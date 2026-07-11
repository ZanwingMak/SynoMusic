import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 重复模式。
enum RepeatMode: String, CaseIterable {
    case off, all, one
}

/// 音质设置。
enum AudioQuality: String, CaseIterable, Identifiable {
    case original     // raw 流，不转码
    case high         // 320 kbps mp3
    case standard     // 128 kbps mp3

    var id: String { rawValue }

    /// 用于内置多语言查表的中文标题 key。
    var titleKey: String {
        switch self {
        case .original: return "原始音质"
        case .high: return "高品质 320kbps"
        case .standard: return "标准 128kbps"
        }
    }

    var title: String {
        titleKey
    }

    /// 对应 streamURL 的 format 参数。
    var streamFormat: String {
        switch self {
        case .original: return "raw"
        case .high: return "mp3"
        case .standard: return "mp3"
        }
    }
}

/// 一次队列替换前的快照，用于在浏览页回看之前的播放上下文。
struct PlaybackQueueSnapshot: Identifiable, Hashable, Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    let songs: [Song]
    let currentSongID: String?

    init(id: UUID = UUID(), createdAt: Date = Date(), title: String, songs: [Song], currentSongID: String?) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.songs = songs
        self.currentSongID = currentSongID
    }
}

/// 可同步的播放历史快照；按当前服务器作用域保存最近播放和队列历史。
struct PlaybackHistorySnapshot: Codable, Hashable {
    let scopeID: String
    let playedHistory: [Song]
    let queueHistory: [PlaybackQueueSnapshot]
}

/// 全局播放引擎：单例式注入到 SwiftUI 环境，掌管队列、时间、Now Playing、远程命令。
@MainActor
final class PlaybackEngine: ObservableObject {
    // MARK: 公开状态

    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int = -1
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isBuffering: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffling: Bool = false
    @Published var quality: AudioQuality = .original {
        didSet {
            if transcodeOverride == nil {
                effectiveQuality = quality
            }
        }
    }
    @Published private(set) var effectiveQuality: AudioQuality = .original
    @Published private(set) var playbackContextTitle: String?
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var currentLyricIndex: Int? = nil
    @Published private(set) var isFetchingLyrics: Bool = false
    @Published private(set) var lyricFontSize: Double = UserDefaults.standard.double(forKey: "syno.lyrics.fontSize").clamped(to: 16...28, defaultValue: 18)
    @Published private(set) var lyricAutoScroll: Bool = UserDefaults.standard.object(forKey: "syno.lyrics.autoScroll") as? Bool ?? true
    @Published private(set) var lyricDelay: Double = UserDefaults.standard.double(forKey: "syno.lyrics.delay").clamped(to: -3...3, defaultValue: 0)
    /// 用户可见的瞬时状态消息（错误、Demo 提示等）；nil 表示无消息。
    @Published private(set) var statusMessage: String?
    /// 睡眠定时剩余秒数；nil 表示未启用。
    @Published private(set) var sleepRemaining: TimeInterval?
    /// 是否在"本曲结束后停止"模式。
    @Published private(set) var stopAtTrackEnd: Bool = false
    /// 最近播放过的歌曲，按最近时间倒序。
    @Published private(set) var playedHistory: [Song] = []
    /// 被新播放列表替换掉的队列历史，按最近时间倒序。
    @Published private(set) var queueHistory: [PlaybackQueueSnapshot] = []

    /// 当前歌曲。
    var currentSong: Song? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    /// 当前 API 客户端，由外部注入。
    weak var apiClient: SynologyClient?
    /// 当前统一音乐库客户端；新后端播放会优先走这里。
    weak var musicClient: (any MusicLibraryClient)?
    /// 本地歌单仓库；用于锁屏 like 命令触发喜欢/取消。
    weak var playlistStore: PlaylistStore?
    /// 下载管理器；播放时优先使用已缓存的本地文件。
    weak var downloadManager: DownloadManager?
    /// 播放偏好（后台播放 / 锁屏 / AirPlay）；由 App 注入。
    private var settings: PlaybackSettings?
    private var bgObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?

    // MARK: 私有

    private var player: AVQueuePlayer = AVQueuePlayer()
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    /// 当前曲目的 status 订阅；切歌时取消。
    private var statusCancel: AnyCancellable?
    /// 播放器状态订阅；用于把外部暂停 / 恢复同步回 UI。
    private var playbackStateCancel: AnyCancellable?
    private var bag = Set<AnyCancellable>()
    private var originalQueue: [Song] = []   // 用于关闭随机时还原
    private var demoTicker: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?
    /// 当前播放项的加载标识；切歌时用于丢弃旧异步回调。
    private var activeLoadID = UUID()
    /// 当前 seek 请求版本；切歌和新 seek 会让旧回调失效。
    private var seekRevision: UInt64 = 0
    /// 正在等待 AVPlayer 完成的 seek；期间忽略旧 timeObserver，避免进度条闪回。
    private var pendingSeekRevision: UInt64?
    /// 加载提示至少停留的时间，避免缓存命中时 Toast 一闪而过。
    private let loadingStatusMinimumDuration: TimeInterval = 2.4
    /// 当前加载提示文本，用来区分可自动延迟清理的 loading Toast。
    private var loadingStatusMessage: String?
    /// 当前状态提示开始显示的时间，用于计算 loading Toast 的最短展示时间。
    private var statusVisibleSince: Date?
    private var sleepTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    /// 当前曲目临时使用的转码偏好（fallback 用），不修改用户全局设置。
    private var transcodeOverride: AudioQuality?
    /// 当前曲目是否已尝试过 raw→mp3 兜底重试，避免无限循环。
    private var fallbackTried: Bool = false
    private let onlineLyricsClient = OnlineLyricsClient()
    private var onlineLyricsCache: [String: [LyricLine]] = [:]
    /// 已下载的锁屏封面缓存，减少切回同一首歌时灵动岛封面延迟。
    private var nowPlayingArtworkCache: [String: UIImage] = [:]
    private let playedHistoryKey = "syno.playback.history.songs"
    private let queueHistoryKey = "syno.playback.history.queues"
    private var historyScopeKey = "global"
    private let lyricFontSizeKey = "syno.lyrics.fontSize"
    private let lyricAutoScrollKey = "syno.lyrics.autoScroll"
    private let lyricDelayKey = "syno.lyrics.delay"
    private let maxPlayedHistoryCount = 200
    private let maxQueueHistoryCount = 50

    /// 限流：避免 timeObserver 每 0.5s 都调 LA update（系统对 LA 更新频率有上限）。
    private var lastActivityUpdate: Date = .distantPast
    /// 是否正处于 Demo 模拟（apiClient 为 nil 但用户仍点歌的场景）。
    private var isDemoPlayback: Bool = false
    /// 音频会话被系统中断前是否处于播放状态，用于中断结束后恢复。
    private var shouldResumeAfterInterruption: Bool = false

    init() {
        loadHistories()
        setupAudioSession()
        setupAudioSessionInterruptionObserver()
        setupAppLifecycleObservers()
        setupPlaybackStateObserver()
        setupRemoteCommands()
        setupTimeObserver()
        setupEndObserver()
    }

    // 不实现 deinit：PlaybackEngine 是 App 生命周期单例，观察者随进程退出自然释放；
    // Swift 6 严格并发禁止 nonisolated deinit 访问 main-actor 状态。

    // MARK: 公开操作

    /// 替换队列并从指定下标开始播放；可选择是否沿用当前随机播放开关来重排队列。
    func play(queue songs: [Song], startAt index: Int = 0, honoringShuffle: Bool = true, contextTitle: String? = nil) {
        guard !songs.isEmpty else { return }
        recordQueueSnapshotIfNeeded(replacingWith: songs)
        self.originalQueue = songs
        var ordered = songs
        let shouldShuffle = honoringShuffle && isShuffling
        if shouldShuffle { ordered = shuffledKeepingHead(songs, head: index) }
        self.queue = ordered
        self.currentIndex = shouldShuffle ? 0 : (ordered.indices.contains(index) ? index : 0)
        // 新曲：清空临时转码状态
        transcodeOverride = nil
        fallbackTried = false
        effectiveQuality = quality
        playbackContextTitle = cleanContextTitle(contextTitle) ?? currentSong?.album
        loadCurrent(autoPlay: true)
    }

    /// 添加单曲到队尾（"接下来播放"）。
    func appendNext(_ song: Song) {
        if queue.isEmpty {
            play(queue: [song], honoringShuffle: false)
        } else if queue.contains(where: { $0.id == song.id }) {
            setStatus("已在队列中".t + "：\(song.title)")
        } else {
            queue.insert(song, at: min(currentIndex + 1, queue.count))
            setStatus("已加入队列".t + "：\(song.title)")
        }
    }

    /// 切换播放/暂停。
    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    /// 用户主动暂停播放，并清掉待自动恢复标记。
    func pause() {
        shouldResumeAfterInterruption = false
        guard shouldFadeAudio, player.timeControlStatus == .playing else {
            fadeTask?.cancel()
            player.pause()
            setPlayingState(false)
            return
        }
        fadeOutAndPause()
        setPlayingState(false)
    }

    /// 用户主动恢复播放；必要时重新激活音频会话。
    func resume() {
        shouldResumeAfterInterruption = false
        activateAudioSessionIfNeeded()
        if isDemoPlayback {
            setPlayingState(true)
            startDemoTicker()
            return
        }
        // 若从未加载，尝试加载当前。
        if player.currentItem == nil { loadCurrent(autoPlay: true); return }
        prepareFadeInIfNeeded()
        player.play()
        fadeInIfNeeded()
        setPlayingState(true)
    }

    /// 停止播放并清空队列，同时重置中断恢复状态。
    func stop() {
        shouldResumeAfterInterruption = false
        player.pause()
        player.removeAllItems()
        fadeTask?.cancel()
        demoTicker?.cancel()
        isDemoPlayback = false
        setPlayingState(false)
        queue = []
        currentIndex = -1
        currentTime = 0
        duration = 0
        playbackContextTitle = nil
        dismissStatus()
        clearNowPlaying()
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task { await LiveActivityCoordinator.shared.endActivity() }
        }
        #endif
    }

    /// 切到下一首；队尾按重复模式决定循环或暂停。
    func next() {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            loadCurrent(autoPlay: true)
        } else if repeatMode == .all {
            currentIndex = 0
            loadCurrent(autoPlay: true)
        } else {
            pause()
        }
    }

    /// 切到上一首；当前曲目已播放超过 3 秒时先回到曲头。
    func previous() {
        guard !queue.isEmpty else { return }
        // 若播放过 3s，回到曲头；否则上一首。
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            loadCurrent(autoPlay: true)
        } else {
            seek(to: 0)
        }
    }

    /// 跳转到指定播放时间，并丢弃切歌前遗留的旧 seek 回调。
    func seek(to time: TimeInterval) {
        let targetSeconds = max(0, min(time, duration > 0 ? duration : time))
        if isDemoPlayback {
            currentTime = targetSeconds
            updateNowPlayingPlaybackState()
            return
        }
        guard player.currentItem != nil else { return }
        seekRevision &+= 1
        let revision = seekRevision
        pendingSeekRevision = revision
        let songID = currentSong?.id
        currentTime = targetSeconds
        updateCurrentLyric()
        updateNowPlayingPlaybackState()
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: target) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.seekRevision == revision, self.currentSong?.id == songID else { return }
                self.pendingSeekRevision = nil
                self.currentTime = targetSeconds
                self.updateCurrentLyric()
                self.updateNowPlayingPlaybackState()
            }
        }
    }

    /// 调整歌词字号并持久化到本地。
    func adjustLyricFontSize(by delta: Double) {
        lyricFontSize = (lyricFontSize + delta).clamped(to: 16...28, defaultValue: 18)
        UserDefaults.standard.set(lyricFontSize, forKey: lyricFontSizeKey)
    }

    /// 设置歌词是否跟随播放进度自动滚动。
    func setLyricAutoScroll(_ enabled: Bool) {
        lyricAutoScroll = enabled
        UserDefaults.standard.set(enabled, forKey: lyricAutoScrollKey)
    }

    /// 设置歌词时间偏移，正数代表歌词提前显示。
    func setLyricDelay(_ delay: Double) {
        lyricDelay = delay.clamped(to: -3...3, defaultValue: 0)
        UserDefaults.standard.set(lyricDelay, forKey: lyricDelayKey)
        updateCurrentLyric()
    }

    func toggleShuffle() {
        isShuffling.toggle()
        if isShuffling, !queue.isEmpty {
            queue = shuffledKeepingHead(queue, head: currentIndex)
            currentIndex = 0
        } else if !isShuffling, !originalQueue.isEmpty, let cur = currentSong {
            queue = originalQueue
            currentIndex = queue.firstIndex(of: cur) ?? 0
        }
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// 选定队列中的一项播放。
    func playItem(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        loadCurrent(autoPlay: true)
    }

    /// 从队列移除一项。
    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        if index == currentIndex {
            queue.remove(at: index)
            if queue.isEmpty { stop() } else {
                if currentIndex >= queue.count { currentIndex = queue.count - 1 }
                loadCurrent(autoPlay: true)
            }
        } else {
            if index < currentIndex { currentIndex -= 1 }
            queue.remove(at: index)
        }
    }

    /// 重排队列。
    func moveInQueue(from offsets: IndexSet, to destination: Int) {
        let cur = currentSong
        queue.move(fromOffsets: offsets, toOffset: destination)
        if let cur, let idx = queue.firstIndex(of: cur) { currentIndex = idx }
    }

    /// 清空播放历史和队列历史。
    func clearPlaybackHistory() {
        playedHistory = []
        queueHistory = []
        persistHistories()
    }

    /// 删除一条最近播放记录。
    func removePlayedHistory(songID: String) {
        playedHistory.removeAll { $0.id == songID }
        persistHistories()
    }

    /// 删除一条队列历史记录。
    func removeQueueHistory(id: UUID) {
        queueHistory.removeAll { $0.id == id }
        persistHistories()
    }

    /// 导出当前服务器作用域的播放历史。
    func historySnapshot() -> PlaybackHistorySnapshot {
        PlaybackHistorySnapshot(
            scopeID: historyScopeKey,
            playedHistory: playedHistory,
            queueHistory: queueHistory
        )
    }

    /// 导出精简版播放历史给 iCloud，避免完整队列历史占用过多 CloudKit 配额。
    func cloudHistorySnapshot(maxPlayedCount: Int, maxQueueCount: Int, maxQueueSongs: Int) -> PlaybackHistorySnapshot {
        let compactQueues = queueHistory.prefix(maxQueueCount).map { snapshot in
            PlaybackQueueSnapshot(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                title: snapshot.title,
                songs: Array(snapshot.songs.prefix(maxQueueSongs)),
                currentSongID: snapshot.currentSongID
            )
        }
        return PlaybackHistorySnapshot(
            scopeID: historyScopeKey,
            playedHistory: Array(playedHistory.prefix(maxPlayedCount)),
            queueHistory: compactQueues
        )
    }

    /// 应用云端播放历史；只覆盖当前作用域，避免不同服务器历史串台。
    func applyHistorySnapshot(_ snapshot: PlaybackHistorySnapshot) {
        guard snapshot.scopeID == historyScopeKey else { return }
        playedHistory = Array(snapshot.playedHistory.prefix(maxPlayedHistoryCount))
        queueHistory = Array(snapshot.queueHistory.prefix(maxQueueHistoryCount))
        persistHistories()
    }

    /// 切换播放历史作用域；不同服务器配置会读取各自独立的历史记录。
    func setHistoryScope(for profile: ServerProfile?) {
        let nextKey = historyScopeIdentifier(for: profile)
        guard nextKey != historyScopeKey else { return }
        persistHistories()
        historyScopeKey = nextKey
        loadHistories()
    }

    /// 用最新评分替换队列和历史里的歌曲快照。
    func updateRating(forSongID id: String, rating: Int) {
        let normalized = max(0, min(rating, 5))
        queue = queue.map { song in
            guard song.id == id else { return song }
            return song.withRating(normalized)
        }
        originalQueue = originalQueue.map { song in
            guard song.id == id else { return song }
            return song.withRating(normalized)
        }
        playedHistory = playedHistory.map { song in
            guard song.id == id else { return song }
            return song.withRating(normalized)
        }
        queueHistory = queueHistory.map { snapshot in
            let songs = snapshot.songs.map { song in
                guard song.id == id else { return song }
                return song.withRating(normalized)
            }
            return PlaybackQueueSnapshot(
                id: snapshot.id,
                createdAt: snapshot.createdAt,
                title: snapshot.title,
                songs: songs,
                currentSongID: snapshot.currentSongID
            )
        }
        persistHistories()
    }

    // MARK: 内部加载

    /// 加载当前曲目，并重置与上一首相关的异步状态。
    private func loadCurrent(autoPlay: Bool) {
        guard let song = currentSong else { return }
        recordPlayedSong(song)
        activeLoadID = UUID()
        seekRevision &+= 1
        pendingSeekRevision = nil
        let loadID = activeLoadID
        fadeTask?.cancel()
        demoTicker?.cancel()
        currentTime = 0
        duration = song.duration > 0 ? song.duration : 0
        lyrics = []
        currentLyricIndex = nil
        isBuffering = true
        // 1. 电台/播客：song.id 以 "radio:" / "podcast:" 开头，直接用 song.path 作为 stream URL
        // 2. 已登录：走 Audio Station streamURL
        // 3. 未登录：走 Demo 模拟
        Task { @MainActor in
            let url: URL?
            do {
                url = try await self.resolvePlaybackURL(for: song, autoPlay: autoPlay)
            } catch {
                guard self.activeLoadID == loadID, self.currentSong?.id == song.id else { return }
                self.isBuffering = false
                self.setStatus(error.localizedDescription)
                return
            }
            guard self.activeLoadID == loadID, self.currentSong?.id == song.id else { return }
            guard let url else {
                if self.isDemoPlayback { return }
                self.isBuffering = false
                self.setStatus("无法构造流地址：\(song.title)")
                return
            }
            self.isDemoPlayback = false

            let item = AVPlayerItem(url: url)
            self.player.removeAllItems()
            self.player.insert(item, after: nil)

            self.isBuffering = true
            self.observeStall(for: item)
            self.observeFailure(for: item)

            if autoPlay {
                self.activateAudioSessionIfNeeded()
                self.prepareFadeInIfNeeded()
                self.player.play()
                self.fadeInIfNeeded()
                self.setPlayingState(true)
            } else {
                self.player.volume = 1
                self.setPlayingState(false)
            }
            self.updateNowPlayingMetadata()
            self.refreshLiveActivity()
            await self.refreshDuration(for: item, song: song, loadID: loadID)
            guard self.activeLoadID == loadID, self.currentSong?.id == song.id else { return }
            self.updateNowPlayingPlaybackState()
            await self.fetchLyricsAsync(for: song)
        }
    }

    /// Demo 模拟：UI 上时间线走，但不真正出声。
    private func startDemoPlayback(for song: Song, autoPlay: Bool) {
        isDemoPlayback = true
        demoTicker?.cancel()
        player.pause()
        player.removeAllItems()
        duration = song.duration > 0 ? song.duration : 240
        currentTime = 0
        effectiveQuality = quality
        isBuffering = false
        setPlayingState(autoPlay)
        setStatus("演示模式：尚未连接服务器，未真实播放。", persistent: true)
        updateNowPlayingMetadata()
        if autoPlay { startDemoTicker() }
    }

    /// 统一生成远程音乐播放地址，兼容新 provider 和旧 Synology 路径。
    private func streamURL(for song: Song, quality: AudioQuality) -> URL? {
        if let url = musicClient?.streamURL(song: song, quality: quality) {
            return url
        }
        return apiClient?.audioStation.streamURL(songID: song.id, format: quality.streamFormat)
    }

    /// 准备当前歌曲播放 URL；普通源同步返回，SMB 等源可先异步缓存后返回本地 URL。
    private func resolvePlaybackURL(for song: Song, autoPlay: Bool) async throws -> URL? {
        if let localURL = downloadManager?.localURL(for: song.id) {
            return localURL
        }
        if song.id.hasPrefix("local:"), let path = song.path {
            return URL(fileURLWithPath: path)
        }
        if song.isDirectRemoteStream, let path = song.path {
            return URL(string: path)
        }
        guard musicClient != nil || apiClient != nil else {
            startDemoPlayback(for: song, autoPlay: autoPlay)
            return nil
        }
        let effective = transcodeOverride ?? quality
        effectiveQuality = effective
        if let asyncClient = musicClient as? AsyncStreamResolvingMusicClient {
            return try await asyncClient.preparedStreamURL(song: song, quality: effective)
        }
        return streamURL(for: song, quality: effective)
    }

    /// 统一读取服务器歌词，兼容新 provider 和旧 Synology 路径。
    private func musicLyrics(for song: Song) async throws -> [LyricLine] {
        if let musicClient {
            return try await musicClient.lyrics(for: song)
        }
        guard let api = apiClient?.audioStation else { return [] }
        return try await api.getLyrics(songID: song.id)
    }

    /// 统一生成歌曲封面地址，兼容新 provider 和旧 Synology 路径。
    private func songCoverURL(for song: Song) -> URL? {
        if let url = musicClient?.songCoverURL(song: song) {
            return url
        }
        return apiClient?.audioStation.songCoverURL(songID: song.id)
    }

    private func startDemoTicker() {
        demoTicker?.cancel()
        demoTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    guard let self else { return }
                    guard self.isPlaying, self.isDemoPlayback else { return }
                    let next = min(self.currentTime + 0.5, self.duration)
                    self.currentTime = next
                    self.updateCurrentLyric()
                    self.updateNowPlayingPlaybackState()
                    if next >= self.duration { self.next() }
                }
            }
        }
    }

    // MARK: 定时停止

    /// 在 `interval` 秒后自动暂停；nil 取消。
    func setSleepTimer(_ interval: TimeInterval?) {
        sleepTask?.cancel()
        sleepTask = nil
        stopAtTrackEnd = false
        sleepRemaining = nil
        guard let interval, interval > 0 else {
            // 取消路径：sleepRemaining 已置 nil，直接返回让 UI 立刻刷新
            return
        }
        sleepRemaining = interval
        let deadline = Date().addingTimeInterval(interval)
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // 关键修复：从 sleep 醒来时先确认任务未被取消，避免在 cancel 后
                // 又跑一次 tick 把 sleepRemaining 又写回去，导致用户必须点两次取消。
                if Task.isCancelled { return }
                let remain = deadline.timeIntervalSinceNow
                await MainActor.run {
                    guard let self else { return }
                    if remain <= 0 {
                        self.sleepRemaining = nil
                        self.pause()
                        self.setStatus("已按定时器暂停播放")
                    } else {
                        self.sleepRemaining = remain
                    }
                }
                if remain <= 0 { break }
            }
        }
    }

    /// 标记"播放完当前曲目后停止"。曲目结束时由 endObserver 检查。
    func enableStopAtTrackEnd() {
        sleepTask?.cancel()
        sleepRemaining = nil
        stopAtTrackEnd = true
    }

    /// 设置一条状态消息；`persistent=false` 时 4 秒后自动清除。
    func setStatus(_ message: String?, persistent: Bool = false) {
        statusMessage = message
        statusVisibleSince = message == nil ? nil : Date()
        if message == nil || message != loadingStatusMessage {
            loadingStatusMessage = nil
        }
        statusClearTask?.cancel()
        if let message, !persistent, !message.isEmpty {
            statusClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run {
                    guard self?.statusMessage == message else { return }
                    self?.statusMessage = nil
                    self?.loadingStatusMessage = nil
                    self?.statusVisibleSince = nil
                }
            }
        }
    }

    /// UI 关闭 Toast 时调用。
    func dismissStatus() {
        statusClearTask?.cancel()
        statusMessage = nil
        loadingStatusMessage = nil
        statusVisibleSince = nil
    }

    /// 显示当前歌曲加载中的状态消息，并记录最短可见时间。
    private func setLoadingStatus(title: String) {
        let message = "正在加载".t + ": \(title)"
        loadingStatusMessage = message
        setStatus(message)
    }

    /// 在播放器 ready 后清理加载提示；显示不足最短时长时延迟清理。
    private func dismissLoadingStatusIfNeeded() {
        guard let loadingStatusMessage, statusMessage == loadingStatusMessage else { return }
        let elapsed = statusVisibleSince.map { Date().timeIntervalSince($0) } ?? loadingStatusMinimumDuration
        let remaining = max(0, loadingStatusMinimumDuration - elapsed)
        statusClearTask?.cancel()
        guard remaining > 0 else {
            dismissStatus()
            return
        }
        statusClearTask = Task { [weak self, loadingStatusMessage] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            await MainActor.run {
                guard self?.statusMessage == loadingStatusMessage else { return }
                self?.dismissStatus()
            }
        }
    }

    /// 监听 AVPlayerItem 失败事件，转成可见错误。
    /// 注意：必须用 Combine + `receive(on: .main)` 把回调引回主线程，
    /// 否则 KVO 在非主线程触发 `@MainActor` 隔离检查会让 Swift 6 直接 SIGTRAP。
    private func observeFailure(for item: AVPlayerItem) {
        if let obs = failObserver { NotificationCenter.default.removeObserver(obs) }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                self?.setStatus("播放中断".t + ": \(err?.localizedDescription ?? "未知错误".t)")
            }
        }
        statusCancel?.cancel()
        statusCancel = item.publisher(for: \.status, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.dismissLoadingStatusIfNeeded()
                case .failed:
                    let reason = item?.error?.localizedDescription ?? "未知错误".t
                    // 兜底：原始流失败时，自动用 MP3 转码再试一次（仅 NAS 流，不针对电台）
                    let isNasStream = !(self.currentSong?.isDirectRemoteStream ?? false)
                    let usingRaw = (self.transcodeOverride ?? self.quality).streamFormat == "raw"
                    if isNasStream, usingRaw, !self.fallbackTried {
                        self.fallbackTried = true
                        self.transcodeOverride = .high
                        self.effectiveQuality = .high
                        self.loadCurrent(autoPlay: true)
                    } else {
                        self.setStatus("无法播放".t + ": \(reason)")
                        self.isBuffering = false
                        self.setPlayingState(false)
                    }
                default:
                    break
                }
            }
    }

    /// 读取当前 AVPlayerItem 的真实时长，忽略切歌前返回的旧请求。
    private func refreshDuration(for item: AVPlayerItem, song: Song, loadID: UUID) async {
        do {
            let asset = item.asset
            let d = try await asset.load(.duration)
            guard activeLoadID == loadID, let currentItem = player.currentItem, currentItem === item else { return }
            self.duration = CMTimeGetSeconds(d).isFinite ? CMTimeGetSeconds(d) : (currentSong?.duration ?? 0)
        } catch {
            guard activeLoadID == loadID else { return }
            self.duration = song.duration
        }
        isBuffering = false
    }

    /// 加载当前歌曲歌词：优先使用 NAS 内置歌词，缺失时自动从 LRCLIB 在线查询。
    private func fetchLyricsAsync(for song: Song) async {
        lyrics = []
        currentLyricIndex = nil
        isFetchingLyrics = true
        defer { isFetchingLyrics = false }

        if let nasLines = try? await musicLyrics(for: song),
           !nasLines.isEmpty {
            assignLyrics(nasLines, for: song)
            return
        }

        let key = onlineLyricsCacheKey(for: song)
        if let cached = onlineLyricsCache[key] {
            assignLyrics(cached, for: song)
            return
        }

        do {
            let onlineLines = try await onlineLyricsClient.fetch(for: song)
            onlineLyricsCache[key] = onlineLines
            assignLyrics(onlineLines, for: song)
        } catch {
            assignLyrics([], for: song)
        }
    }

    /// 只给仍然是当前曲目的歌曲赋值歌词，避免快速切歌时旧请求覆盖新歌词。
    private func assignLyrics(_ lines: [LyricLine], for song: Song) {
        guard currentSong?.id == song.id else { return }
        lyrics = lines
        updateCurrentLyric()
    }

    /// 构造在线歌词缓存键。
    private func onlineLyricsCacheKey(for song: Song) -> String {
        [
            song.title,
            song.artist ?? "",
            song.album ?? "",
            String(Int(song.duration.rounded()))
        ].joined(separator: "|").lowercased()
    }

    // MARK: 历史记录

    /// 从 UserDefaults 恢复播放历史，失败时安全回落为空列表。
    private func loadHistories() {
        let decoder = JSONDecoder()
        playedHistory = []
        queueHistory = []
        if let data = UserDefaults.standard.data(forKey: scopedPlayedHistoryKey),
           let songs = try? decoder.decode([Song].self, from: data) {
            playedHistory = songs
        }
        if let data = UserDefaults.standard.data(forKey: scopedQueueHistoryKey),
           let snapshots = try? decoder.decode([PlaybackQueueSnapshot].self, from: data) {
            queueHistory = snapshots
        }
    }

    /// 将播放历史写入 UserDefaults，保持重启后可查看。
    private func persistHistories() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(playedHistory) {
            UserDefaults.standard.set(data, forKey: scopedPlayedHistoryKey)
        }
        if let data = try? encoder.encode(queueHistory) {
            UserDefaults.standard.set(data, forKey: scopedQueueHistoryKey)
        }
    }

    /// 当前服务器作用域下的单曲历史存储键。
    private var scopedPlayedHistoryKey: String {
        "\(playedHistoryKey).\(historyScopeKey)"
    }

    /// 当前服务器作用域下的队列历史存储键。
    private var scopedQueueHistoryKey: String {
        "\(queueHistoryKey).\(historyScopeKey)"
    }

    /// 将服务器配置转换为稳定历史作用域标识。
    private func historyScopeIdentifier(for profile: ServerProfile?) -> String {
        guard let profile else { return "global" }
        return [
            profile.providerType.rawValue,
            profile.id.uuidString,
            profile.musicLibraryID ?? ""
        ].joined(separator: "-")
    }

    /// 记录单曲播放历史；同一首歌只保留最近一次位置。
    private func recordPlayedSong(_ song: Song) {
        playedHistory.removeAll { $0.id == song.id }
        playedHistory.insert(song, at: 0)
        if playedHistory.count > maxPlayedHistoryCount {
            playedHistory = Array(playedHistory.prefix(maxPlayedHistoryCount))
        }
        persistHistories()
    }

    /// 在替换当前队列前保存旧队列，避免用户点另一个专辑后丢失上下文。
    private func recordQueueSnapshotIfNeeded(replacingWith songs: [Song]) {
        guard !queue.isEmpty else { return }
        guard queue.map(\.id) != songs.map(\.id) else { return }
        let title = playbackContextTitle ?? currentSong?.album ?? currentSong?.title ?? "播放队列".t
        let snapshot = PlaybackQueueSnapshot(
            title: title,
            songs: queue,
            currentSongID: currentSong?.id
        )
        queueHistory.removeAll { $0.songs.map(\.id) == snapshot.songs.map(\.id) }
        queueHistory.insert(snapshot, at: 0)
        if queueHistory.count > maxQueueHistoryCount {
            queueHistory = Array(queueHistory.prefix(maxQueueHistoryCount))
        }
        persistHistories()
    }

    // MARK: Audio Session / Remote / Observers

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 没拿到 audio session 不影响 UI 渲染，仅静默
        }
    }

    /// 在需要播放或恢复时激活音频会话；失败时保持 UI 可操作。
    private func activateAudioSessionIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // 音频会话激活失败时，AVPlayer 后续仍会给出状态 / 错误回调。
        }
    }

    /// 监听系统音频中断：其他 App 播放媒体时同步暂停状态，中断结束后按需恢复。
    private func setupAudioSessionInterruptionObserver() {
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                self?.handleAudioSessionInterruption(typeRawValue: rawType)
            }
        }
    }

    /// 处理音频中断开始 / 结束事件，保证 UI 状态和恢复策略与系统音频会话一致。
    private func handleAudioSessionInterruption(typeRawValue: UInt?) {
        guard
            let rawType = typeRawValue,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying || player.timeControlStatus == .playing
            player.pause()
            demoTicker?.cancel()
            isBuffering = false
            setPlayingState(false)
        case .ended:
            let shouldResume = shouldResumeAfterInterruption
            shouldResumeAfterInterruption = false
            guard shouldResume, currentSong != nil else {
                syncPlayingStateFromPlayer()
                return
            }
            resumeAfterAudioSessionInterruption()
        @unknown default:
            syncPlayingStateFromPlayer()
        }
    }

    /// 中断结束后的恢复入口；不依赖用户再次切回 App。
    private func resumeAfterAudioSessionInterruption() {
        activateAudioSessionIfNeeded()
        if isDemoPlayback {
            setPlayingState(true)
            startDemoTicker()
            return
        }
        if player.currentItem == nil {
            loadCurrent(autoPlay: true)
        } else {
            player.play()
            setPlayingState(true)
        }
    }

    /// 监听 App 回到前台，修正被系统改动但未及时回调到 SwiftUI 的播放状态。
    private func setupAppLifecycleObservers() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncPlayingStateFromPlayer()
            }
        }
    }

    /// 监听 AVQueuePlayer 真实状态，修复外部媒体中断后按钮仍显示播放中的问题。
    private func setupPlaybackStateObserver() {
        playbackStateCancel = player.publisher(for: \.timeControlStatus, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                Task { @MainActor in
                    self?.handlePlayerTimeControlStatus(status)
                }
            }
    }

    /// 根据播放器 timeControlStatus 更新缓冲和播放状态。
    private func handlePlayerTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard !isDemoPlayback else { return }
        switch status {
        case .playing:
            isBuffering = false
            setPlayingState(true)
        case .paused:
            isBuffering = false
            setPlayingState(false)
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = true
        @unknown default:
            break
        }
    }

    /// 从播放器当前状态回写 SwiftUI 状态，用于前台恢复和系统事件兜底。
    private func syncPlayingStateFromPlayer() {
        guard !isDemoPlayback else { return }
        switch player.timeControlStatus {
        case .playing:
            setPlayingState(true)
        case .paused:
            setPlayingState(false)
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = true
        @unknown default:
            break
        }
    }

    /// 统一更新播放状态，并同步锁屏信息和 Live Activity。
    private func setPlayingState(_ playing: Bool) {
        guard isPlaying != playing else {
            updateNowPlayingPlaybackState()
            return
        }
        isPlaying = playing
        updateNowPlayingPlaybackState()
        refreshLiveActivity()
    }

    /// 当前是否应该对 AVPlayer 做淡入淡出。
    private var shouldFadeAudio: Bool {
        settings?.crossfadeEnabled == true && (settings?.crossfadeDuration ?? 0) > 0
    }

    /// 播放前把音量准备到淡入起点。
    private func prepareFadeInIfNeeded() {
        guard shouldFadeAudio else {
            player.volume = 1
            return
        }
        fadeTask?.cancel()
        player.volume = 0
    }

    /// 按用户设置把当前播放器音量淡入到 1。
    private func fadeInIfNeeded() {
        guard shouldFadeAudio else { return }
        fadePlayerVolume(to: 1, duration: min(settings?.crossfadeDuration ?? 3, 3))
    }

    /// 淡出后暂停播放器。
    private func fadeOutAndPause() {
        let duration = min(settings?.crossfadeDuration ?? 3, 2)
        fadePlayerVolume(to: 0, duration: duration) { [weak self] in
            self?.player.pause()
            self?.player.volume = 1
        }
    }

    /// 用小步进调整 AVPlayer 音量，避免暂停/播放过于突兀。
    private func fadePlayerVolume(to target: Float, duration: Double, completion: (() -> Void)? = nil) {
        fadeTask?.cancel()
        let start = player.volume
        let steps = max(1, Int(duration / 0.05))
        fadeTask = Task { [weak self] in
            for step in 1...steps {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
                await MainActor.run {
                    guard let self else { return }
                    let progress = Float(step) / Float(steps)
                    self.player.volume = start + (target - start) * progress
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.player.volume = target
                completion?()
            }
        }
    }

    /// 应用播放偏好；启用后立刻按当前开关重新配置 audio session
    /// 并订阅 `didEnterBackgroundNotification` 在「后台播放」关闭时进入后台自动暂停。
    func applyPlaybackSettings(_ settings: PlaybackSettings) {
        self.settings = settings
        settings.applyAudioSession()
        if bgObserver == nil {
            bgObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.settings?.backgroundPlaybackEnabled == false {
                        self.pause()
                    }
                }
            }
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // queue: .main 保证在 main queue 上，但 Swift 6 严格并发要求显式 actor hop。
            Task { @MainActor in
                guard let self else { return }
                guard self.pendingSeekRevision == nil else { return }
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                self.currentTime = max(0, min(seconds, self.duration > 0 ? self.duration : seconds))
                self.updateCurrentLyric()
                self.updateNowPlayingPlaybackState()
            }
        }
    }

    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.stopAtTrackEnd {
                    self.stopAtTrackEnd = false
                    self.pause()
                    self.setStatus("已在本曲结束时停止")
                    return
                }
                if self.repeatMode == .one {
                    self.seek(to: 0)
                    self.resume()
                } else {
                    self.next()
                }
            }
        }
    }

    private func observeStall(for item: AVPlayerItem) {
        if let obs = stallObserver { NotificationCenter.default.removeObserver(obs) }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isBuffering = true }
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let pos = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: pos.positionTime) }
            return .success
        }
        // 锁屏「★」喜欢命令，与本地 FavoritesStore 双向同步
        center.likeCommand.localizedTitle = "喜欢"
        center.likeCommand.localizedShortTitle = "喜欢"
        center.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let song = self?.currentSong else { return }
                self?.playlistStore?.toggleFavorite(song)
                self?.updateNowPlayingMetadata()
            }
            return .success
        }
    }

    private func updateNowPlayingMetadata() {
        guard let song = currentSong else { clearNowPlaying(); return }
        // 同步 like 状态到锁屏 ★
        MPRemoteCommandCenter.shared().likeCommand.isActive = playlistStore?.isFavorite(song) ?? false
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: nowPlayingSubtitle(for: song),
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let cached = nowPlayingArtworkCache[song.id] {
            Self.attachArtwork(cached)
            return
        }

        // 异步抓封面：下载在 @MainActor，但 MPMediaItemArtwork 的 handler 闭包
        // 必须在 nonisolated 上下文里创建——MediaPlayer 会在它自己的 accessQueue
        // 上调用这个闭包，闭包若被绑定到 @MainActor，runtime 会主动 SIGTRAP。
        let coverURL = songCoverURL(for: song)
        let lookup = CoverLookupQuery(song: song)
        if let url = coverURL {
            Task { @MainActor [weak self] in
                guard let self, self.currentSong?.id == song.id else { return }
                if let image = await Self.loadArtworkImage(from: url) {
                    guard self.currentSong?.id == song.id else { return }
                    self.cacheNowPlayingArtwork(image, for: song.id)
                    Self.attachArtwork(image)
                } else if let fallbackURL = await OnlineCoverLookupCache.shared.url(for: lookup),
                          let image = await Self.loadArtworkImage(from: fallbackURL) {
                    guard self.currentSong?.id == song.id else { return }
                    self.cacheNowPlayingArtwork(image, for: song.id)
                    Self.attachArtwork(image)
                }
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self, self.currentSong?.id == song.id else { return }
                guard let fallbackURL = await OnlineCoverLookupCache.shared.url(for: lookup) else { return }
                guard let image = await Self.loadArtworkImage(from: fallbackURL) else { return }
                guard self.currentSong?.id == song.id else { return }
                self.cacheNowPlayingArtwork(image, for: song.id)
                Self.attachArtwork(image)
            }
        }
    }

    /// 缓存锁屏封面，并限制缓存数量避免长期播放后占用过多内存。
    private func cacheNowPlayingArtwork(_ image: UIImage, for songID: String) {
        nowPlayingArtworkCache[songID] = image
        if nowPlayingArtworkCache.count > 120, let first = nowPlayingArtworkCache.keys.first {
            nowPlayingArtworkCache.removeValue(forKey: first)
        }
    }

    /// 构造锁屏播放器副标题：有当前歌词时优先展示歌词，没有歌词时展示歌手。
    private func nowPlayingSubtitle(for song: Song) -> String {
        if let index = currentLyricIndex, lyrics.indices.contains(index) {
            let line = lyrics[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return line }
        }
        return song.artist ?? ""
    }

    /// 下载锁屏封面图片，失败时返回 nil。
    nonisolated private static func loadArtworkImage(from url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    /// nonisolated 静态方法：构造 MPMediaItemArtwork 并合并进 NowPlaying。
    /// 必须 nonisolated，否则它内部生成的 handler 闭包会继承 @MainActor 隔离，
    /// 在 MediaPlayer 的 accessQueue 上回调时触发 swift_task_checkIsolated 崩溃。
    nonisolated private static func attachArtwork(_ image: UIImage) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        current[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
    }

    private func updateNowPlayingPlaybackState() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let song = currentSong {
            info[MPMediaItemPropertyArtist] = nowPlayingSubtitle(for: song)
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateLiveActivityThrottled()
    }

    // MARK: Live Activity

    #if canImport(ActivityKit)
    /// 构造可 Sendable 的 ContentState 后交给 LiveActivityCoordinator actor 持有 Activity。
    @available(iOS 16.2, *)
    private func buildLiveActivityState() -> NowPlayingActivityAttributes.ContentState? {
        guard let song = currentSong else { return nil }
        let cover = songCoverURL(for: song)?.absoluteString
        return NowPlayingActivityAttributes.ContentState(
            title: song.title,
            artist: song.artist ?? "",
            album: song.album,
            isPlaying: isPlaying,
            elapsed: currentTime,
            duration: duration,
            coverURL: cover
        )
    }
    #endif

    /// 限流的 LA 更新：1 秒内最多一次。
    ///
    /// 注意：当前关闭 Live Activity 的"主动启动"——iOS 系统会用
    /// `MPNowPlayingInfoCenter` 自动在锁屏与灵动岛展示当前播放信息。
    /// 启动 Activity.request 会在锁屏出现"第二个播放器"，与系统 widget 重复。
    /// 代码保留以便未来按需启用。
    private func updateLiveActivityThrottled() {
        #if canImport(ActivityKit)
        guard liveActivityEnabled else { return }
        guard #available(iOS 16.2, *) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastActivityUpdate) > 1.0 else { return }
        guard let state = buildLiveActivityState() else { return }
        lastActivityUpdate = now
        Task { await LiveActivityCoordinator.shared.updateOrStart(state) }
        #endif
    }

    /// 通用入口：切歌、暂停/播放时调用。
    private func refreshLiveActivity() {
        #if canImport(ActivityKit)
        guard liveActivityEnabled else {
            // 即便禁用，仍确保任何残留的 LA 被结束
            Task { await LiveActivityCoordinator.shared.endActivity() }
            return
        }
        guard #available(iOS 16.2, *) else { return }
        if let state = buildLiveActivityState() {
            lastActivityUpdate = Date()
            Task { await LiveActivityCoordinator.shared.updateOrStart(state) }
        } else {
            Task { await LiveActivityCoordinator.shared.endActivity() }
        }
        #endif
    }

    /// Live Activity 启动开关。默认 false：使用 iOS 系统的 MPNowPlayingInfo
    /// 在锁屏 / 灵动岛展示，不重复一个我们自家的卡片。
    private let liveActivityEnabled: Bool = false

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func updateCurrentLyric() {
        guard !lyrics.isEmpty else {
            currentLyricIndex = nil; return
        }
        // 二分定位最后一个 timestamp <= currentTime 的行。
        let lyricClock = currentTime + lyricDelay
        var lo = 0, hi = lyrics.count - 1, found: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lyrics[mid].timestamp <= lyricClock {
                found = mid; lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        if currentLyricIndex != found {
            currentLyricIndex = found
            updateNowPlayingPlaybackState()
        }
    }

    /// 保证 head 仍在首位，其余打乱。
    private func shuffledKeepingHead(_ songs: [Song], head: Int) -> [Song] {
        guard songs.indices.contains(head) else { return songs.shuffled() }
        let h = songs[head]
        var rest = songs
        rest.remove(at: head)
        rest.shuffle()
        return [h] + rest
    }

    /// 清理播放上下文标题，空字符串不进入播放器顶部展示。
    private func cleanContextTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Double {
    /// 将数值限制在闭区间内；UserDefaults 首次读取 0 时可给出业务默认值。
    func clamped(to range: ClosedRange<Double>, defaultValue: Double) -> Double {
        let value = self == 0 ? defaultValue : self
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
