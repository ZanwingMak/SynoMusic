import AVFoundation
import MediaPlayer
import Combine

/// 电视原生音频引擎：切页不重建播放器，遥控器与系统媒体命令使用同一状态。
@MainActor
final class TVPlayback: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsLoading = false
    @Published private(set) var history: [Song] = []
    @Published var error: String?
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var quality = AudioQuality(rawValue: UserDefaults.standard.string(forKey: "tv.quality") ?? "") ?? .original
    @Published var speed: Float = 1
    @Published var onlineLyrics = UserDefaults.standard.object(forKey: "tv.onlineLyrics") as? Bool ?? true
    @Published private(set) var sleepMinutes = 0
    var client: (any MusicLibraryClient)?
    var isDemo = false
    private let player = AVPlayer()
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var request = UUID()
    private var itemGeneration = UUID()
    private var playTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var historyKey = "tv.history"
    private var wantsPlayback = false

    var song: Song? { queue.indices.contains(index) ? queue[index] : nil }
    var currentLyric: Int? { lyrics.lastIndex { $0.timestamp >= 0 && $0.timestamp <= position } }

    /// 注册实际播放器时钟与状态，系统中断结束后保持暂停，由用户决定何时继续。
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                let total = self.player.currentItem?.duration.seconds ?? 0
                if total.isFinite && total > 0 { self.duration = total }
            }
        }
        statusObserver = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing, waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            Task { @MainActor in self?.isPlaying = playing; self?.isBuffering = waiting; self?.updateNowPlaying() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.pause() } }
        configureRemoteCommands()
    }

    /// 更换服务器时清理旧队列及系统媒体信息，播放记录按账号隔离。
    func setSource(_ client: (any MusicLibraryClient)?, demo: Bool) {
        if let old = self.client, let client, old === client, demo == isDemo { return }
        if self.client == nil && client == nil && demo == isDemo { return }
        stop(); self.client = client; isDemo = demo
        historyKey = "tv.history." + (client?.profile.id.uuidString ?? (demo ? "demo" : "none"))
        history = UserDefaults.standard.data(forKey: historyKey).flatMap { try? JSONDecoder().decode([Song].self, from: $0) } ?? []
    }

    /// 从明确的集合开始播放，所有异步 URL 和歌词请求均绑定本次歌曲代次。
    func play(_ songs: [Song], at start: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs; load(at: min(max(0, start), songs.count - 1))
    }

    /// 解析真实播放地址，SMB/Plex 等异步媒体源复用手机已有的准备流程。
    func load(at nextIndex: Int, transcoding: Bool = false) {
        guard queue.indices.contains(nextIndex) else { return }
        request = UUID(); let generation = request; itemGeneration = generation
        playTask?.cancel(); lyricTask?.cancel(); player.pause(); player.replaceCurrentItem(with: nil)
        index = nextIndex; position = 0; duration = song?.duration ?? 0; lyrics = []; lyricsLoading = false; error = nil; isBuffering = true; wantsPlayback = true
        guard let song else { return }
        let streamQuality = transcoding ? AudioQuality.high : quality
        playTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url: URL?
                if self.isDemo { url = Bundle.main.url(forResource: "DemoAudio", withExtension: "wav") }
                else if song.isDirectRemoteStream { url = song.path.flatMap(URL.init(string:)) }
                else if let resolver = self.client as? AsyncStreamResolvingMusicClient { url = try await resolver.preparedStreamURL(song: song, quality: streamQuality) }
                else { url = self.client?.streamURL(song: song, quality: streamQuality) }
                guard generation == self.request, !Task.isCancelled else { return }
                guard let url else { throw URLError(.badURL) }
                let item = AVPlayerItem(url: url)
                self.itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    let message = item.error?.localizedDescription ?? "Playback failed"
                    Task { @MainActor in
                        guard let self, self.itemGeneration == generation else { return }
                        if !transcoding && streamQuality == .original && self.wantsPlayback && [.synologyAudioStation, .jellyfin, .emby].contains(self.client?.providerType) {
                            self.load(at: self.index, transcoding: true)
                        } else { self.error = message; self.isBuffering = false; self.pause() }
                    }
                }
                if let endObserver = self.endObserver { NotificationCenter.default.removeObserver(endObserver) }
                self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in Task { @MainActor in self?.advance(automatic: true) } }
                self.player.replaceCurrentItem(with: item); self.player.playImmediately(atRate: self.speed)
                self.history = [song] + self.history.filter { $0.id != song.id }; self.history = Array(self.history.prefix(80))
                if let data = try? JSONEncoder().encode(self.history) { UserDefaults.standard.set(data, forKey: self.historyKey) }
                self.updateNowPlaying(); self.fetchLyrics(song: song, generation: generation)
            } catch { if generation == self.request { self.error = error.localizedDescription; self.isBuffering = false } }
        }
    }

    /// 用户暂停也会取消正在等待的起播请求，避免稍后突然自行播放。
    func pause() { wantsPlayback = false; request = UUID(); playTask?.cancel(); player.pause(); isPlaying = false; isBuffering = false; updateNowPlaying() }

    /// 恢复或暂停当前音频；尚未准备 URL 的歌曲从当前索引重新准备。
    func toggle() {
        if isPlaying || isBuffering { pause() }
        else if player.currentItem != nil { wantsPlayback = true; player.playImmediately(atRate: speed) }
        else if song != nil { load(at: index) }
    }

    /// 清理媒体对象和系统状态，避免切换来源后仍展示旧歌曲。
    func stop() { pause(); itemGeneration = UUID(); lyricTask?.cancel(); lyricsLoading = false; player.replaceCurrentItem(with: nil); queue = []; position = 0; duration = 0; lyrics = []; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }

    /// 遥控器的下一首与自然结束分别处理单曲循环和列表边界。
    func advance(automatic: Bool = false) {
        guard !queue.isEmpty else { return }
        if automatic && repeatMode == .one { load(at: index); return }
        if shuffle && queue.count > 1 { load(at: queue.indices.filter { $0 != index }.randomElement() ?? index); return }
        if index + 1 < queue.count { load(at: index + 1) }
        else if repeatMode == .all { load(at: 0) } else { pause() }
    }

    /// 已播放超过三秒时回到曲首，否则返回上一首。
    func previous() { if position > 3 { seek(0) } else if index > 0 { load(at: index - 1) } }

    /// 跳转仅限可定位音频，电台直播不提供无效进度操作。
    func seek(_ value: Double) {
        guard value.isFinite, song?.id.hasPrefix("radio:") != true else { return }
        let target = max(0, min(value, max(duration, 0)))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)); position = target; updateNowPlaying()
    }

    /// 设置实际播放速度并同步给系统媒体中心。
    func setSpeed(_ rate: Float) { speed = min(2, max(0.5, rate)); if isPlaying { player.rate = speed }; updateNowPlaying() }

    /// 单次定时结束后暂停，不自动开启下一次计时。
    func sleep(after minutes: Int) {
        sleepTask?.cancel(); sleepMinutes = max(0, minutes)
        guard sleepMinutes > 0 else { return }
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(minutes * 60)); self?.sleepMinutes = 0; self?.pause() }
            catch {}
        }
    }

    /// 追加歌曲保留当前音频对象和位置。
    func enqueue(_ song: Song, next: Bool = false) { queue.insert(song, at: next ? min(index + 1, queue.count) : queue.count) }

    /// 清空最近播放只影响本机记录，不删除音乐文件和收藏。
    func clearHistory() { history = []; UserDefaults.standard.removeObject(forKey: historyKey) }

    /// 移除队列条目，当前曲目被移除时显式切换到剩余的下一首。
    func remove(at row: Int) {
        guard queue.indices.contains(row) else { return }
        let playing = isPlaying; queue.remove(at: row)
        if queue.isEmpty { stop() }
        else if row == index { load(at: min(row, queue.count - 1)); if !playing { pause() } }
        else if row < index { index -= 1 }
    }

    /// 歌词只应用到对应的曲目；在线补全使用无凭据的独立客户端。
    private func fetchLyrics(song: Song, generation: UUID) {
        lyricsLoading = true
        lyricTask = Task { [weak self] in
            guard let self else { return }
            var lines = self.isDemo ? DemoMode.lyrics : (try? await self.client?.lyrics(for: song)) ?? []
            if lines.isEmpty && self.onlineLyrics && !self.isDemo && !song.isDirectRemoteStream { lines = (try? await OnlineLyricsClient().fetch(for: song)) ?? [] }
            guard self.song?.id == song.id, !Task.isCancelled else { return }
            self.lyrics = lines; self.lyricsLoading = false
        }
    }

    /// 向系统报告真实播放状态，进度跳转和速度变化后同步更新。
    private func updateNowPlaying() {
        guard let song else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: song.title, MPMediaItemPropertyArtist: song.artist ?? "", MPMediaItemPropertyAlbumTitle: song.album ?? "", MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0]
    }

    /// Siri Remote 和系统媒体中心的指令进入与界面完全相同的播放动作。
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.advance() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }; let position = event.positionTime; Task { @MainActor in self?.seek(position) }; return .success }
    }
}
