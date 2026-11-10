import SwiftUI
import AVKit
import UIKit

/// 全屏播放器：封面、波形进度条、控制条、歌词面板、队列面板。
struct FullPlayerView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var playbackSettings: PlaybackSettings
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Binding var isPresented: Bool
    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var showSleep = false
    @State private var showAddToPlaylist = false
    @State private var showDeleteConfirm = false
    @State private var ratingPending: Int?
    @State private var showSongInfo = false
    @State private var showSongEdit = false
    @State private var showPlayerMenu: Bool
    @State private var copyToastMessage: String?
    @State private var copyToastTask: Task<Void, Never>?
    @State private var dominantColor: Color = Color(red: 0.18, green: 0.10, blue: 0.25)
    @State private var isSeeking: Bool = false
    @State private var seekDraft: TimeInterval = 0
    @State private var showLyricSettings = false
    @State private var showResearchSheet = false
    @State private var draftLyricFontSize: Double = 18
    @State private var draftLyricAutoScroll: Bool = true
    @State private var draftLyricDelay: Double = 0

    /// 创建全屏播放器，并在调试参数要求时预展开右上角菜单。
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        #if DEBUG
        self._showLyrics = State(initialValue: ProcessInfo.processInfo.arguments.contains("-lyrics"))
        self._showPlayerMenu = State(initialValue: ProcessInfo.processInfo.arguments.contains("-show-player-menu"))
        #else
        self._showPlayerMenu = State(initialValue: false)
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            let visualHeight = min(max(geo.size.height * 0.34, 250), 330)
            let artSide = min(geo.size.width - Metrics.xl * 2, visualHeight)
            ZStack(alignment: .top) {
                background
                VStack(spacing: 0) {
                    topBar
                        .frame(height: 52)
                        .zIndex(10)
                    Spacer(minLength: 8)
                    playbackVisual(artSide: artSide)
                        .frame(height: visualHeight)
                    Spacer(minLength: 10)
                    trackInfo
                        .frame(height: 86, alignment: .center)
                    progressSection
                        .frame(height: 56)
                    controlBar
                        .frame(height: 92)
                    bottomTools
                        .frame(height: 48)
                        .padding(.bottom, max(Metrics.s, geo.safeAreaInsets.bottom))
                }
                .padding(.top, Metrics.l)
                if showPlayerMenu {
                    PlayerTopMenuOverlay(
                        isPresented: $showPlayerMenu,
                        song: playback.currentSong,
                        downloadStatus: playback.currentSong.flatMap { downloads.status(for: $0.id) },
                        onAppendNext: { if let s = playback.currentSong { playback.appendNext(s) } },
                        onAddToPlaylist: { showAddToPlaylist = true },
                        onDownload: { Task { await downloadCurrent() } },
                        onRemoveDownload: { removeCurrentDownload() },
                        onOpenDownloadManager: { openDownloadManager() },
                        onShowInfo: { showSongInfo = true },
                        onShowEdit: { showSongEdit = true },
                        onResearch: { openResearchSheet() },
                        onOpenLyricEditor: { openLyricEditorFromMenu() },
                        currentRating: ratingPending ?? playback.currentSong?.rating,
                        onRate: { stars in Task { await applyRating(stars) } },
                        onDelete: { showDeleteConfirm = true }
                    )
                    .environment(\.showsDownloadActions, shouldShowDownloadActions)
                    .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(300)
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.18), value: theme.currentID)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: showPlayerMenu)
        .tint(theme.current.accent(in: .dark))
        .overlay(alignment: .top) {
            if let msg = playback.statusMessage {
                HStack(spacing: Metrics.s) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.white)
                    Text(msg)
                        .font(.nocCaption)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Spacer(minLength: 4)
                    Button {
                        playback.dismissStatus()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metrics.m)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.75), in: Capsule())
                .padding(.horizontal, Metrics.m)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: playback.statusMessage)
        .overlay(alignment: .center) {
            if let copyToastMessage {
                Text(copyToastMessage)
                    .font(.nocBody.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: Capsule(style: .continuous))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: copyToastMessage)
        .onAppear { syncDebugMenuState() }
        .sheet(isPresented: $showQueue) {
            QueuePanel().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSleep) {
            SleepTimerSheet(isPresented: $showSleep)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddToPlaylist) {
            if let song = playback.currentSong {
                AddToPlaylistSheet(song: song)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("删除文件".t, isPresented: $showDeleteConfirm) {
            Button("删除".t, role: .destructive) { Task { await deleteCurrent() } }
            Button("取消".t, role: .cancel) {}
        } message: {
            Text(deleteAlertMessage)
        }
        .sheet(isPresented: $showSongInfo) {
            if let song = playback.currentSong {
                SongInfoSheet(song: song)
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showSongEdit) {
            if let song = playback.currentSong {
                SongEditSheet(song: song)
                    .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showLyricSettings) {
            LyricSettingsSheet(
                fontSize: $draftLyricFontSize,
                autoScroll: $draftLyricAutoScroll,
                delay: $draftLyricDelay,
                lyrics: playback.lyrics,
                onSave: saveLyricSettings,
                onCancel: cancelLyricSettings,
                onCopyLyrics: copyCurrentLyrics,
                onReset: resetLyricDraft
            )
            .presentationDetents([.medium, .large])
        }

        .sheet(isPresented: $showResearchSheet) {
            if let song = playback.currentSong {
                SongResearchSheet(song: song, coverURL: session.musicClient?.songCoverURL(song: song))
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// 删除确认提示文案，避免内联插值让 SwiftUI 编译器超时。
    private var deleteAlertMessage: String {
        let title = playback.currentSong?.title ?? "该歌曲".t
        return "将通过 File Station 永久删除".t + "「\(title)」" + "对应的文件。该操作不可撤销。".t
    }

    /// DEBUG 下按启动参数打开播放器菜单，便于模拟器截图验收。
    private func syncDebugMenuState() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-show-player-menu") {
            showPlayerMenu = true
        }
        #endif
    }

    /// 调用 setrating 接口。
    private func applyRating(_ stars: Int) async {
        guard let song = playback.currentSong,
              let api = session.client?.audioStation else { return }
        do {
            try await api.setRating(songID: song.id, rating: stars)
            ratingPending = stars
            playback.updateRating(forSongID: song.id, rating: stars)
            playback.setStatus(stars == 0 ? "已清除评分".t : "已设为".t + " \(stars) " + "星".t)
            Haptics.success()
        } catch {
            playback.setStatus("评分失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 通过 File Station 删除当前歌曲文件，然后从队列中移除。
    private func deleteCurrent() async {
        guard let song = playback.currentSong,
              let api = session.client?.audioStation,
              let path = song.path, !path.isEmpty else {
            playback.setStatus("没有可删除的文件路径".t)
            return
        }
        do {
            _ = try await api.deleteFiles(paths: [path])
            playback.setStatus("删除任务已提交".t)
            // 从本地队列移除当前曲并尝试播放下一首
            if let idx = playback.queue.firstIndex(of: song) {
                playback.removeFromQueue(at: idx)
            }
            Haptics.success()
        } catch {
            playback.setStatus("删除失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 下载当前歌曲到本地缓存，并同步设置页下载管理。
    private func downloadCurrent() async {
        guard shouldShowDownloadActions else { return }

        guard let song = playback.currentSong else {
            playback.setStatus("无法下载当前歌曲".t)
            return
        }
        guard session.musicClient != nil || session.client != nil else {
            playback.setStatus("请先连接服务器再下载".t)
            return
        }
        let url: URL?
        do {
            url = try await MusicDownloadResolver.url(
                for: song,
                quality: playback.quality,
                musicClient: session.musicClient,
                legacyClient: session.client
            )
        } catch {
            playback.setStatus("下载失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
            return
        }
        guard let url else {
            playback.setStatus("当前音乐源不支持下载。".t)
            return
        }
        let fileExtension = MusicDownloadResolver.fileExtension(for: song, quality: playback.quality, url: url)
        do {
            playback.setStatus("正在下载".t + "：\(song.title)")
            try await downloads.download(
                song: song,
                streamURL: url,
                fileExtension: fileExtension,
                allowInvalidCertificate: MusicDownloadResolver.allowsInvalidCertificate(
                    musicClient: session.musicClient,
                    legacyClient: session.client
                )
            )
            playback.setStatus("下载完成".t + "：\(song.title)")
            Haptics.success()
        } catch {
            playback.setStatus("下载失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 删除当前歌曲的本地缓存文件。
    private func removeCurrentDownload() {
        guard let song = playback.currentSong else { return }
        downloads.remove(songID: song.id)
        playback.setStatus("已删除下载".t + "：\(song.title)")
        Haptics.success()
    }

    /// 关闭播放器并跳转到设置里的下载管理。
    private func openDownloadManager() {
        guard shouldShowDownloadActions else { return }

        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            navigation.openDownloads()
        }
    }

    /// 是否有任一定时停止策略已激活，决定月亮图标着色。
    private var sleepActive: Bool {
        playback.sleepRemaining != nil || playback.stopAtTrackEnd
    }

    /// 歌词字号预览值；设置面板打开时使用草稿，关闭后回到已保存设置。
    private var lyricPreviewFontSize: Double {
        showLyricSettings ? draftLyricFontSize : playback.lyricFontSize
    }

    /// 歌词自动滚动预览值；保存前不写入播放器设置。
    private var lyricPreviewAutoScroll: Bool {
        showLyricSettings ? draftLyricAutoScroll : playback.lyricAutoScroll
    }

    /// 歌词当前行预览值；调整延迟时即时重算，但取消后不会影响播放引擎。
    private var lyricPreviewCurrentIndex: Int? {
        guard showLyricSettings else { return playback.currentLyricIndex }
        return currentLyricIndex(using: draftLyricDelay)
    }

    // MARK: 子组件

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [dominantColor, Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            FloatingBlobs().opacity(0.5).blur(radius: 80).ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.6), value: dominantColor)
    }

    private var topBar: some View {
        HStack {
            Button { isPresented = false } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放".t).font(.nocLabel).foregroundStyle(.white.opacity(0.6))
                Text(playback.playbackContextTitle ?? playback.currentSong?.album ?? "")
                    .font(.nocLabel.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            TopBarMenu(isPresented: $showPlayerMenu)
        }
        .padding(.horizontal, Metrics.l)
        .onChange(of: playback.currentSong?.id) { _, _ in
            ratingPending = nil
        }
    }
}

/// 全屏播放器右上角的菜单按钮；面板由 FullPlayerView 的全屏 overlay 承载。
private struct TopBarMenu: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                isPresented.toggle()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多".t)
    }
}

/// 播放页顶部菜单面板：全屏透明层负责点击外部关闭，右上角玻璃面板展示操作。
private struct ShowsDownloadActionsKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var showsDownloadActions: Bool {
        get { self[ShowsDownloadActionsKey.self] }
        set { self[ShowsDownloadActionsKey.self] = newValue }
    }
}

private struct PlayerTopMenuOverlay: View {
    @Environment(\.showsDownloadActions) private var showsDownloadActions
    @Binding var isPresented: Bool
    let song: Song?
    let downloadStatus: DownloadStatus?
    let onAppendNext: () -> Void
    let onAddToPlaylist: () -> Void
    let onDownload: () -> Void
    let onRemoveDownload: () -> Void
    let onOpenDownloadManager: () -> Void
    let onShowInfo: () -> Void
    let onShowEdit: () -> Void
    let onResearch: () -> Void
    let onOpenLyricEditor: () -> Void
    let currentRating: Int?
    let onRate: (Int) -> Void
    let onDelete: () -> Void
    @State private var showRating = false

    private let menuWidth: CGFloat = 224

    /// 当前歌曲是否允许删除文件。
    private var canDeleteCurrentSong: Bool {
        guard let song else { return false }
        return !song.isDirectRemoteStream && !(song.path ?? "").isEmpty
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            PlayerGlassMenu {
                menuContent
            }
            .frame(width: menuWidth)
            .padding(.top, Metrics.l + 48)
            .padding(.trailing, Metrics.l)
            .transition(.scale(scale: 0.86, anchor: .topTrailing).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onDisappear { showRating = false }
        .animation(.easeInOut(duration: 0.16), value: showRating)
    }

    /// popover 内的两种面板切换。
    @ViewBuilder
    private var menuContent: some View {
        if showRating {
            ratingPanel
                .transition(.opacity)
        } else {
            actionsPanel
                .transition(.opacity)
        }
    }

    /// 主菜单面板。
    private var actionsPanel: some View {
        VStack(spacing: 0) {
            PlayerMenuRow(icon: "text.line.first.and.arrowtriangle.forward", title: "加入队列".t) {
                perform(onAppendNext)
            }
            PlayerMenuRow(icon: "text.badge.plus", title: "添加到歌单…".t) {
                perform(onAddToPlaylist)
            }
            PlayerMenuRow(icon: "music.note.list", title: "歌词编辑".t) {
                perform(onOpenLyricEditor)
            }
            if showsDownloadActions {
                downloadRow
            }
            PlayerMenuRow(icon: "info.circle", title: "歌曲信息".t) {
                perform(onShowInfo)
            }
            PlayerMenuRow(icon: "square.and.pencil", title: "编辑歌曲信息".t) {
                perform(onShowEdit)
            }
            PlayerMenuRow(icon: "globe", title: "网上搜索".t) {
                perform(onResearch)
            }
            if showsDownloadActions {
                PlayerMenuRow(icon: "tray.and.arrow.down", title: "下载管理".t) {
                    perform(onOpenDownloadManager)
                }
            }
            PlayerMenuRow(icon: "star", title: "评分".t, showsChevron: true) {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.18)) { showRating = true }
            }
            Divider().padding(.vertical, 4)
            PlayerMenuRow(
                icon: "trash",
                title: "删除文件…".t,
                role: .destructive,
                isEnabled: canDeleteCurrentSong
            ) {
                perform(onDelete)
            }
        }
        .padding(.vertical, 6)
    }

    /// 下载菜单行：根据当前缓存状态切换为下载、重新下载或删除下载。
    @ViewBuilder
    private var downloadRow: some View {
        switch downloadStatus {
        case .completed:
            PlayerMenuRow(icon: "trash.circle", title: "删除下载".t, role: .destructive) {
                perform(onRemoveDownload)
            }
        case .downloading, .pending:
            PlayerMenuRow(icon: "arrow.down.circle", title: "正在下载".t, isEnabled: false) {}
        case .failed:
            PlayerMenuRow(icon: "arrow.clockwise.circle", title: "重新下载".t) {
                perform(onDownload)
            }
        case .none:
            PlayerMenuRow(icon: "arrow.down.circle", title: "下载歌曲".t, isEnabled: canDownloadCurrentSong) {
                perform(onDownload)
            }
        }
    }

    /// 判断当前歌曲是否支持本地下载。
    private var canDownloadCurrentSong: Bool {
        guard let song else { return false }
        return !song.isDirectRemoteStream
    }

    /// 评分子面板。
    private var ratingPanel: some View {
        VStack(spacing: 0) {
            PlayerMenuRow(icon: "chevron.left", title: "评分".t) {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.18)) { showRating = false }
            }
            Divider().padding(.vertical, 4)
            PlayerMenuRow(icon: currentRating == 0 ? "star.slash.fill" : "star.slash", title: "清除评分".t) {
                perform { onRate(0) }
            }
            ForEach(1...5, id: \.self) { rating in
                let isSelected = currentRating == rating
                PlayerMenuRow(icon: isSelected ? "star.fill" : "star", title: "\(rating) \("星".t)") {
                    perform { onRate(rating) }
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// 执行动作并关闭菜单。
    private func perform(_ action: @escaping () -> Void) {
        Haptics.tap()
        dismiss()
        action()
    }

    /// 关闭菜单并重置子面板状态。
    private func dismiss() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            isPresented = false
            showRating = false
        }
    }
}

/// 播放器菜单玻璃容器：iOS 26 使用系统 glassEffect，旧系统退回稳定材质。
private struct PlayerGlassMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    content()
                        .background {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .fill(Color.black.opacity(0.18))
                        }
                        .glassEffect(
                            .regular.tint(Color.white.opacity(0.08)).interactive(),
                            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
                        )
                }
            } else {
                content()
                    .background {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 34, style: .continuous)
                                    .fill(Color.black.opacity(0.18))
                            }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)
    }
}

/// 播放器菜单单行：紧凑布局 + 按压反馈。
private struct PlayerMenuRow: View {
    enum Role {
        case normal
        case destructive
    }

    let icon: String?
    let title: String
    var role: Role = .normal
    var showsChevron: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    private let iconColor = Color(red: 0.68, green: 0.48, blue: 1.0)

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(role == .destructive ? .red : iconColor)
                        .frame(width: 20, height: 20)
                }
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(role == .destructive ? Color(red: 1, green: 0.42, blue: 0.38) : .white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PlayerMenuRowButtonStyle())
        .disabled(!isEnabled)
    }
}

/// 播放器菜单行按钮样式：按下时给出缩放与玻璃高光反馈。
private struct PlayerMenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.14) : Color.clear)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension FullPlayerView {
    /// 播放器中部视觉区域；封面和歌词共用同一个固定槽位，避免切换时挤压控件。
    @ViewBuilder
    private func playbackVisual(artSide: CGFloat) -> some View {
        ZStack {
            if showLyrics {
                LyricsPanel(
                    lines: playback.lyrics,
                    currentIndex: lyricPreviewCurrentIndex,
                    isLoading: playback.isFetchingLyrics,
                    fontSize: lyricPreviewFontSize,
                    autoScroll: lyricPreviewAutoScroll,
                    onSeek: { playback.seek(to: $0) }
                )
                    .transition(.opacity)
            } else {
                switch playbackSettings.playerArtworkStyle {
                case .cover:
                    CoverHero(
                        song: playback.currentSong,
                        side: artSide,
                        isPlaying: playback.isPlaying && !playback.isBuffering
                    )
                        .transition(.opacity)
                case .vinyl:
                    VinylHero(
                        song: playback.currentSong,
                        side: artSide,
                        isPlaying: playback.isPlaying && !playback.isBuffering
                    )
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.28)) { showLyrics.toggle() }
        }
    }

    /// 播放进度区域；固定时间标签高度，避免时长变化影响控制按钮位置。
    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekDraft : playback.currentTime },
                    set: { seekDraft = $0 }
                ),
                in: 0...max(playback.duration, 0.01),
                onEditingChanged: handleSeekEditingChanged
            )
            .tint(.white)
            HStack {
                Text(format(isSeeking ? seekDraft : playback.currentTime))
                Spacer()
                Text(format(max(0, playback.duration - (isSeeking ? seekDraft : playback.currentTime))).withMinus)
            }
            .font(.nocLabel.monospacedDigit())
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.horizontal, Metrics.l)
    }

    private var trackInfo: some View {
        HStack(alignment: .center, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 6) {
                MarqueeTitleText(text: playback.currentSong?.title ?? "")
                HStack(spacing: 8) {
                    Text(playback.currentSong?.artist ?? "")
                        .font(.nocBody)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    qualityBadge
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    copyToPasteboard(playback.currentSong?.title ?? "")
                } label: {
                    Label("复制歌曲名".t, systemImage: "doc.on.doc")
                }
                if let artist = playback.currentSong?.artist, !artist.isEmpty {
                    Button {
                        copyToPasteboard(artist)
                    } label: {
                        Label("复制作者".t, systemImage: "person.text.rectangle")
                    }
                }
            }
            Spacer()
            if let song = playback.currentSong {
                HStack(spacing: 14) {
                    Button {
                        showAddToPlaylist = true
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("加入歌单".t)

                    Button {
                        Haptics.soft()
                        playlists.toggleFavorite(song)
                    } label: {
                        Image(systemName: playlists.isFavorite(song) ? "heart.fill" : "heart")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(playlists.isFavorite(song) ? Color(red: 1, green: 0.32, blue: 0.45) : .white.opacity(0.75))
                            .scaleEffect(playlists.isFavorite(song) ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: playlists.isFavorite(song))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playlists.isFavorite(song) ? "取消喜欢".t : "喜欢".t)
                }
                .frame(width: 82, alignment: .trailing)
            }
        }
        .padding(.horizontal, Metrics.l)
    }

    /// 当前播放音质徽标。
    private var qualityBadge: some View {
        Text(playback.effectiveQuality.titleKey.t)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.12), in: Capsule(style: .continuous))
            .lineLimit(1)
    }

    private var controlBar: some View {
        HStack(spacing: 36) {
            CircleIconButton(systemName: "backward.fill", size: 52) { playback.previous() }
            Button {
                Haptics.soft()
                playback.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            CircleIconButton(systemName: "forward.fill", size: 52) { playback.next() }
        }
    }

    private var bottomTools: some View {
        HStack(spacing: 0) {
            bottomToolButton {
                playback.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(playback.isShuffling ? Theme.accent : .white.opacity(0.75))
            }
            bottomToolButton {
                showSleep = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(sleepActive ? Theme.accent : .white.opacity(0.85))
                    if sleepActive {
                        Circle().fill(Color.green).frame(width: 7, height: 7).offset(x: 4, y: -3)
                    }
                }
            }
            bottomToolButton {
                withAnimation(.easeInOut(duration: 0.2)) { showLyrics.toggle() }
            } label: {
                Image(systemName: showLyrics ? "music.note" : "quote.bubble.fill")
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
            }
            if shouldShowDownloadActions {
                bottomToolButton {
                    handleBottomDownloadTap()
                } label: {
                    downloadToolIcon
                }
            }
            AirPlayButton()
                .frame(width: 36, height: 36)
                .frame(maxWidth: .infinity)
            bottomToolButton {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.white.opacity(0.85))
            }
            bottomToolButton {
                playback.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIcon)
                    .foregroundStyle(playback.repeatMode == .off ? .white.opacity(0.75) : Theme.accent)
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .padding(.horizontal, Metrics.xl)
    }

    /// 当前歌曲的下载状态。
    private var currentDownloadStatus: DownloadStatus? {
        playback.currentSong.flatMap { downloads.status(for: $0.id) }
    }

    /// 底部下载按钮图标，区分未下载、下载中和已下载。
    @ViewBuilder
    private var downloadToolIcon: some View {
        switch currentDownloadStatus {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
        case .downloading, .pending:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.accent)
                .frame(width: 22, height: 22)
        case .failed:
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(Color.orange)
        case .none:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    /// 点击底部下载按钮：未下载/失败时下载，下载中或已下载时进入下载管理。
    private func handleBottomDownloadTap() {
        switch currentDownloadStatus {
        case .downloading, .pending, .completed:
            openDownloadManager()
        case .failed, .none:
            Task { await downloadCurrent() }
        }
    }

    /// 判断当前界面是否可以展示下载相关操作。
    private var shouldShowDownloadActions: Bool {
        (session.musicClient != nil || session.client != nil) && !reviewMode.isEnabled
    }

    /// 底部工具栏的等宽按钮容器，保证图标切换时其它按钮不横向跳动。
    private func bottomToolButton<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Content
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label()
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var repeatIcon: String {
        switch playback.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let total = max(0, Int(s))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 按指定延迟重算当前歌词行，用于设置面板打开期间的实时预览。
    private func currentLyricIndex(using delay: Double) -> Int? {
        guard !playback.lyrics.isEmpty else { return nil }
        let lyricClock = playback.currentTime + delay
        var lo = 0
        var hi = playback.lyrics.count - 1
        var found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if playback.lyrics[mid].timestamp <= lyricClock {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    /// 打开歌词设置前复制当前已保存值，之后的调整只影响本次预览。
    private func openLyricSettings() {
        Haptics.tap()
        draftLyricFontSize = playback.lyricFontSize
        draftLyricAutoScroll = playback.lyricAutoScroll
        draftLyricDelay = playback.lyricDelay
        showLyricSettings = true
    }

    /// 从右上角菜单进入歌词编辑；先切到歌词页，确保实时预览能被看到。
    private func openLyricEditorFromMenu() {

        if !showLyrics {
            withAnimation(.easeInOut(duration: 0.24)) {
                showLyrics = true
            }
        }
        openLyricSettings()
    }

    /// 打开歌曲与歌手的在线资料工具。
    private func openResearchSheet() {

        showResearchSheet = true
    }

    /// 保存歌词设置草稿，并写入播放引擎和本地偏好。
    private func saveLyricSettings() {
        let fontDelta = draftLyricFontSize - playback.lyricFontSize
        if abs(fontDelta) > 0.001 {
            playback.adjustLyricFontSize(by: fontDelta)
        }
        playback.setLyricAutoScroll(draftLyricAutoScroll)
        playback.setLyricDelay(draftLyricDelay)
        Haptics.success()
        showLyricSettings = false
    }

    /// 取消歌词设置草稿；因为草稿未写入播放引擎，关闭后会恢复已保存效果。
    private func cancelLyricSettings() {
        Haptics.tap()
        showLyricSettings = false
    }

    /// 复制当前歌曲歌词文本。
    private func copyCurrentLyrics() {
        let text = playback.lyrics.map(\.text).joined(separator: "\n")
        guard !text.isEmpty else {
            playback.setStatus("暂无歌词".t)
            Haptics.warning()
            return
        }
        UIPasteboard.general.string = text
        playback.setStatus("歌词已复制".t)
        Haptics.success()
    }

    /// 把歌词设置草稿恢复到推荐值。
    private func resetLyricDraft() {
        draftLyricFontSize = 18
        draftLyricAutoScroll = true
        draftLyricDelay = 0
        Haptics.tap()
    }

    /// Slider 拖动中只更新本地预览，松手后再执行一次真实 seek，避免连续 seek 卡顿。
    private func handleSeekEditingChanged(_ editing: Bool) {
        if editing {
            isSeeking = true
            seekDraft = playback.currentTime
        } else {
            let target = seekDraft
            isSeeking = false
            playback.seek(to: target)
        }
    }

    /// 复制非空文本到剪贴板并提示用户。
    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copyToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.16)) {
            copyToastMessage = "已复制".t
        }
        copyToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.16)) {
                    copyToastMessage = nil
                }
            }
        }
        Haptics.success()
    }
}

private extension String {
    /// 显示剩余时长时加负号。
    var withMinus: String { "-" + self }
}

// MARK: 封面英雄区

private struct CoverHero: View {
    @EnvironmentObject private var session: AppSession
    let song: Song?
    let side: CGFloat
    let isPlaying: Bool

    var body: some View {
        CoverArt(
            url: song.flatMap { session.musicClient?.songCoverURL(song: $0) },
            cornerRadius: Theme.cornerHero,
            fallbackSeed: song?.id ?? "",
            lookup: song.map(CoverLookupQuery.init(song:))
        )
        .frame(width: side, height: side)
        .scaleEffect(isPlaying ? 1.0 : 0.94)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isPlaying)
    }
}

private struct MarqueeTitleText: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            let shouldScroll = text.count > 18
            let estimatedWidth = CGFloat(text.count) * 13
            let travel = max(estimatedWidth - proxy.size.width + 44, 0)
            TimelineView(.animation(paused: !shouldScroll || travel <= 0)) { timeline in
                let offset = marqueeOffset(date: timeline.date, travel: travel)
                HStack(spacing: 44) {
                    titleText
                    if shouldScroll {
                        titleText
                    }
                }
                .offset(x: -offset)
            }
        }
        .frame(height: 34)
        .clipped()
        .accessibilityLabel(text)
    }

    private var titleText: some View {
        Text(text)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 按时间计算跑马灯偏移，开头和结尾都保留短暂停顿。
    private func marqueeOffset(date: Date, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        let hold: TimeInterval = 1.1
        let moving: TimeInterval = max(4.0, TimeInterval(travel / 28))
        let cycle = hold * 2 + moving
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        if elapsed < hold { return 0 }
        if elapsed > hold + moving { return travel }
        return CGFloat((elapsed - hold) / moving) * travel
    }
}

private struct VinylHero: View {
    @EnvironmentObject private var session: AppSession
    let song: Song?
    let side: CGFloat
    let isPlaying: Bool
    @State private var storedRotation: Double = 0
    @State private var spinStartDate: Date?
    private let degreesPerSecond: Double = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            ZStack {
                vinylDisc
                    .rotationEffect(.degrees(displayRotation(at: timeline.date)))
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.42), radius: 34, y: 18)
        }
        .onAppear { syncSpinState(isPlaying: isPlaying, now: Date()) }
        .onChange(of: isPlaying) { _, playing in
            syncSpinState(isPlaying: playing, now: Date())
        }
        .onChange(of: song?.id) { _, _ in
            storedRotation = 0
            spinStartDate = isPlaying ? Date() : nil
        }
    }

    /// 黑胶唱片主体。
    private var vinylDisc: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.05, green: 0.05, blue: 0.055),
                            Color(red: 0.01, green: 0.01, blue: 0.012),
                            Color.black
                        ],
                        center: .center,
                        startRadius: side * 0.12,
                        endRadius: side * 0.56
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .padding(side * 0.045)
            ForEach(0..<15, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(index.isMultiple(of: 3) ? 0.055 : 0.026), lineWidth: 0.8)
                    .padding(CGFloat(index) * side * 0.022 + side * 0.075)
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.16), Color.clear],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: side * 0.58
                    )
                )
                .blendMode(.screen)
            CoverArt(
                url: song.flatMap { session.musicClient?.songCoverURL(song: $0) },
                cornerRadius: side * 0.27,
                fallbackSeed: song?.id ?? "",
                lookup: song.map(CoverLookupQuery.init(song:))
            )
            .frame(width: side * 0.54, height: side * 0.54)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1.5))
            Circle()
                .fill(Color.black.opacity(0.72))
                .frame(width: side * 0.05, height: side * 0.05)
                .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
        }
    }

    /// 根据当前时间计算唱片角度，暂停时返回冻结角度。
    private func displayRotation(at date: Date) -> Double {
        guard isPlaying, let spinStartDate else { return storedRotation }
        let elapsed = date.timeIntervalSince(spinStartDate)
        return (storedRotation + elapsed * degreesPerSecond).truncatingRemainder(dividingBy: 360)
    }

    /// 同步播放/暂停状态，保证黑胶动画不会被旧的 repeat 动画拖着跑。
    private func syncSpinState(isPlaying: Bool, now: Date) {
        if isPlaying {
            if spinStartDate == nil {
                spinStartDate = now
            }
        } else if let start = spinStartDate {
            storedRotation = (storedRotation + now.timeIntervalSince(start) * degreesPerSecond)
                .truncatingRemainder(dividingBy: 360)
            spinStartDate = nil
        }
    }
}

// MARK: 歌词面板

private struct LyricsPanel: View {
    let lines: [LyricLine]
    let currentIndex: Int?
    let isLoading: Bool
    let fontSize: Double
    let autoScroll: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        Group {
            if isLoading && lines.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.75))
                    Text("正在查找歌词".t)
                        .font(.nocBody)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("暂无歌词".t).font(.nocBody).foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                                Button {
                                    Haptics.tap()
                                    onSeek(line.timestamp)
                                } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(.system(size: fontSize, weight: idx == currentIndex ? .semibold : .regular, design: .rounded))
                                        .foregroundStyle(idx == currentIndex ? .white : .white.opacity(0.5))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, idx == currentIndex ? 8 : 4)
                                        .background {
                                            if idx == currentIndex {
                                                Capsule(style: .continuous)
                                                    .fill(Color.white.opacity(0.12))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .id(idx)
                                .animation(.easeInOut(duration: 0.25), value: currentIndex)
                            }
                        }
                        .padding(.horizontal, Metrics.l)
                        .padding(.top, 20)
                        .padding(.bottom, 72)
                    }
                    .onAppear {
                        if autoScroll { scrollToCurrent(proxy) }
                    }
                    .onChange(of: currentIndex) { _, idx in
                        guard autoScroll, idx != nil else { return }
                        scrollToCurrent(proxy)
                    }
                    .onChange(of: autoScroll) { _, enabled in
                        if enabled { scrollToCurrent(proxy) }
                    }
                }
            }
        }
    }

    /// 把当前歌词行滚动到中间。
    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let currentIndex else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(currentIndex, anchor: .center)
        }
    }
}

/// 歌词设置面板：先编辑草稿，保存后才应用到播放引擎。
private struct LyricSettingsSheet: View {
    @Binding var fontSize: Double
    @Binding var autoScroll: Bool
    @Binding var delay: Double
    let lyrics: [LyricLine]
    let onSave: () -> Void
    let onCancel: () -> Void
    let onCopyLyrics: () -> Void
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    lyricSettingCard(
                        title: "字体大小".t,
                        value: "\(Int(fontSize))",
                        onDecrease: { fontSize = max(16, fontSize - 1) },
                        onIncrease: { fontSize = min(28, fontSize + 1) }
                    ) {
                        Slider(value: $fontSize, in: 16...28, step: 1)
                    }

                    lyricSettingCard(
                        title: "歌词延迟".t,
                        value: formattedDelay,
                        onDecrease: { delay = roundedDelay(delay - 0.1) },
                        onIncrease: { delay = roundedDelay(delay + 0.1) }
                    ) {
                        Slider(value: $delay, in: -3...3, step: 0.1)
                    }

                    HStack(spacing: 12) {
                        Text("跟随进度滚动".t)
                            .font(.nocBody.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Toggle("", isOn: $autoScroll)
                            .labelsHidden()
                            .tint(Theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    lyricToolsCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .navigationTitle("歌词设置".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消".t) { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存".t) { onSave() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// 歌词工具卡片：复制歌词和重置显示设置。
    private var lyricToolsCard: some View {
        VStack(spacing: 0) {
            Button {
                onCopyLyrics()
            } label: {
                lyricToolRow(icon: "doc.on.doc", title: "复制歌词", subtitle: lyrics.isEmpty ? "暂无歌词".t : "\(lyrics.count) " + "行歌词".t)
            }
            .buttonStyle(.plain)
            .disabled(lyrics.isEmpty)

            Divider().overlay(.white.opacity(0.08))

            Button {
                onReset()
            } label: {
                lyricToolRow(icon: "arrow.counterclockwise", title: "重置歌词设置", subtitle: "恢复推荐显示效果".t)
            }
            .buttonStyle(.plain)
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// 歌词工具中的单行按钮。
    private func lyricToolRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.t)
                    .font(.nocBody.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    /// 当前歌词延迟的展示文本。
    private var formattedDelay: String {
        String(format: "%+.1fs", delay)
    }

    /// 歌词设置卡片：标题、数值、步进按钮和滑杆放在同一块里，避免重复标签。
    private func lyricSettingCard<SliderContent: View>(
        title: String,
        value: String,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        @ViewBuilder slider: () -> SliderContent
    ) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.nocBody.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .trailing)
                HStack(spacing: 0) {
                    lyricStepButton(systemName: "minus", action: onDecrease)
                    Divider().frame(height: 18)
                    lyricStepButton(systemName: "plus", action: onIncrease)
                }
                .frame(height: 34)
                .background(.white.opacity(0.08), in: Capsule(style: .continuous))
            }

            slider()
                .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// 歌词设置里的小步进按钮。
    private func lyricStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// 把歌词延迟限制在范围内并保留一位小数，避免浮点误差显示。
    private func roundedDelay(_ value: Double) -> Double {
        let clamped = min(3, max(-3, value))
        return (clamped * 10).rounded() / 10
    }
}

// MARK: 在线资料工具

private struct SongResearchSheet: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let song: Song
    let coverURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("歌曲与歌手".t) {
                    researchRow("Google", icon: "magnifyingglass", url: googleURL(for: songQuery))
                    researchRow("百度".t, icon: "magnifyingglass", url: baiduURL(for: songQuery))
                    researchRow("维基百科".t, icon: "book", url: wikipediaURL(for: artistQuery))
                    researchRow("萌娘百科".t, icon: "sparkles", url: moegirlURL(for: artistQuery))
                }
                Section("封面".t) {
                    researchRow("Google 图片".t, icon: "photo.on.rectangle", url: googleImageURL(for: coverQuery))
                    researchRow("百度图片".t, icon: "photo", url: baiduImageURL(for: coverQuery))
                    if let coverURL {
                        Button {
                            UIPasteboard.general.string = coverURL.absoluteString
                            Haptics.success()
                        } label: {
                            Label("复制当前封面链接".t, systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .navigationTitle("在线资料工具".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".t) { dismiss() }
                }
            }
        }
    }

    /// 当前歌曲搜索关键词。
    private var songQuery: String {
        [song.title, song.artist ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 当前歌手搜索关键词。
    private var artistQuery: String {
        let artist = song.artist ?? song.albumArtist ?? song.title
        return artist.isEmpty ? song.title : artist
    }

    /// 当前封面搜索关键词。
    private var coverQuery: String {
        [song.album ?? song.title, song.artist ?? "", "album cover"].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 单个搜索入口行。
    private func researchRow(_ title: String, icon: String, url: URL?) -> some View {
        Button {
            guard let url else { return }
            openURL(url)
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(url == nil)
    }

    /// Google 搜索 URL。
    private func googleURL(for query: String) -> URL? {
        searchURL(base: "https://www.google.com/search", queryName: "q", query: query)
    }

    /// 百度搜索 URL。
    private func baiduURL(for query: String) -> URL? {
        searchURL(base: "https://www.baidu.com/s", queryName: "wd", query: query)
    }

    /// 维基百科搜索 URL。
    private func wikipediaURL(for query: String) -> URL? {
        searchURL(base: "https://www.wikipedia.org/search-redirect.php", queryName: "search", query: query)
    }

    /// 萌娘百科搜索 URL。
    private func moegirlURL(for query: String) -> URL? {
        searchURL(base: "https://zh.moegirl.org.cn/index.php", queryName: "search", query: query)
    }

    /// Google 图片搜索 URL。
    private func googleImageURL(for query: String) -> URL? {
        searchURL(base: "https://www.google.com/search", queryName: "q", query: query, extra: [URLQueryItem(name: "tbm", value: "isch")])
    }

    /// 百度图片搜索 URL。
    private func baiduImageURL(for query: String) -> URL? {
        searchURL(base: "https://image.baidu.com/search/index", queryName: "tn", query: "baiduimage", extra: [URLQueryItem(name: "word", value: query)])
    }

    /// 根据 base 和 query 参数构造搜索 URL。
    private func searchURL(base: String, queryName: String, query: String, extra: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = [URLQueryItem(name: queryName, value: query)] + extra
        return components.url
    }
}

// MARK: 队列面板

private struct QueuePanel: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    /// 当前队列列表是否处于编辑模式。
    private var isEditingQueue: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        NavigationStack {
            List {
                Section(playback.isShuffling ? "随机播放队列".t : "播放队列".t) {
                    ForEach(Array(playback.queue.enumerated()), id: \.element.id) { idx, song in
                        Button {
                            Haptics.tap()
                            playback.playItem(at: idx)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title).font(.nocBody)
                                        .foregroundStyle(idx == playback.currentIndex ? Theme.accent : .primary)
                                    Text(song.artist ?? "").font(.nocLabel).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if idx == playback.currentIndex {
                                    EqualizerIcon(isAnimating: playback.isPlaying)
                                        .frame(width: 18, height: 18)
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { from, to in
                        playback.moveInQueue(from: from, to: to)
                    }
                    .onDelete { idx in
                        if let i = idx.first { playback.removeFromQueue(at: i) }
                    }
                }
            }
            .navigationTitle("队列".t)
            .navigationBarTitleDisplayMode(.inline)
            .tint(theme.current.accent(in: .dark))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditingQueue ? "完成".t : "编辑".t) {
                        toggleQueueEditing()
                    }
                }
            }
        }
    }

    /// 切换队列的编辑状态；避免额外动画叠加系统列表编辑动画造成卡顿。
    private func toggleQueueEditing() {
        editMode?.wrappedValue = isEditingQueue ? .inactive : .active
    }
}

// MARK: AirPlay 按钮包装

private struct AirPlayButton: UIViewRepresentable {
    /// 创建系统 AirPlay 路由选择器，并使用当前强调色作为激活态颜色。
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.accent)
        return v
    }

    /// SwiftUI 刷新时同步强调色，避免切换主题后 AirPlay 激活态仍保留旧颜色。
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(Theme.accent)
    }
}

// MARK: 背景光斑

private struct FloatingBlobs: View {
    @State private var t: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.5))
                    .frame(width: geo.size.width * 0.9)
                    .offset(x: -80 + sin(t) * 40, y: -180 + cos(t * 0.7) * 60)
                Circle()
                    .fill(Color.pink.opacity(0.5))
                    .frame(width: geo.size.width * 0.7)
                    .offset(x: 100 + cos(t * 0.5) * 60, y: 260 + sin(t * 0.6) * 80)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: true)) {
                t = .pi * 2
            }
        }
    }
}
