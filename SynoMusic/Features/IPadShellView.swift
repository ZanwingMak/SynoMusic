import SwiftUI

/// iPad 的独立主框架：侧栏导航与底部播放条共同占据安全区，详情不再为手机 TabBar 留白。
struct IPadShellView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reviewMode: AppReviewMode
    @State private var section: PadSection? = .library
    @State private var showQueue = false
    @Binding var showFullPlayer: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("资料库".t) {
                    entries([.library, .albums, .artists, .songs, .browse, .search])
                }
                Section("我的音乐".t) {
                    entries([.favorites, .playlists, .mixes, .history])
                }
                Section("设置".t) {
                    entries([.settings])
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SynoMusic")
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(session.musicClient?.profile.name ?? (reviewMode.isEnabled ? "演示资料库".t : "未连接服务器".t), systemImage: "server.rack")
                        .font(.caption).lineLimit(1)
                    Text("全部功能免费开放".t).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } detail: {
            if section == .settings {
                NavigationStack(path: $navigation.settingsPath) {
                    SettingsView()
                        .navigationDestination(for: SettingsRoute.self) { settingsDestination($0) }
                        .browseRoutes()
                }
            } else {
                NavigationStack(path: $navigation.browsePath) {
                    destination
                        .browseRoutes()
                }
                .id(section)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.miniPlayerReservationHandled, true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if playback.currentSong != nil {
                IPadPlayerBar(onExpand: { showFullPlayer = true }, onQueue: { showQueue = true })
            }
        }
        .onAppear { selectExternalTab(navigation.selectedTab) }
        .onChange(of: navigation.selectedTab) { _, tab in selectExternalTab(tab) }
        .sheet(isPresented: $showQueue) { QueueSheet().presentationDetents([.large]) }
    }

    /// 让播放器、快捷操作和深层页面的既有跨页请求在 iPad 上保持有效。
    private func selectExternalTab(_ tab: MainTab) {
        switch tab {
        case .settings: section = .settings
        case .search: section = .search
        case .library: section = .library
        case .browse: if section?.tab != .browse { section = .browse }
        }
    }

    /// 根据侧栏选择复用实际功能页面，保留服务器权限与未连接状态处理。
    @ViewBuilder private var destination: some View {
        switch section ?? .library {
        case .library: LibraryHomeView()
        case .browse: BrowseRootView()
        case .search: SearchView()
        case .albums: BrowseRoute.allAlbums.destination
        case .artists: BrowseRoute.allArtists.destination
        case .songs: BrowseRoute.allSongs.destination
        case .favorites: BrowseRoute.favorites.destination
        case .playlists: BrowseRoute.localPlaylists.destination
        case .mixes: BrowseRoute.smartMixes.destination
        case .history: BrowseRoute.playbackHistory.destination
        case .settings: SettingsView()
        }
    }

    /// 绘制可由触控、键盘及辅助技术统一选择的侧栏项目。
    private func entries(_ items: [PadSection]) -> some View {
        ForEach(items) { item in
            Button { sidebarSelection.wrappedValue = item } label: { Label(item.title.t, systemImage: item.icon) }
                .buttonStyle(.plain).tag(item)
        }
    }

    /// 用户切换侧栏时同步紧凑布局的标签，窗口变窄后仍停留在相同功能区。
    private var sidebarSelection: Binding<PadSection?> {
        Binding(get: { section }, set: { next in
            section = next; navigation.browsePath = NavigationPath()
            navigation.selectedTab = next?.tab ?? .library
        })
    }

    /// 设置的外部直达页面沿用已有路由，不另建一套业务状态。
    @ViewBuilder private func settingsDestination(_ route: SettingsRoute) -> some View {
        switch route {
        case .downloads: DownloadsListView()
        case .localImports: LocalImportView()
        case .widgets: WidgetManagerView()
        case .login(let profile): LoginView(profile: profile)
        }
    }
}

extension View {
    /// iPad 播放器使用真正的全屏空间，iPhone 保留原有可下拉关闭的模态体验。
    @ViewBuilder func adaptivePlayerPresentation(isPresented: Binding<Bool>) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            fullScreenCover(isPresented: isPresented) { FullPlayerView(isPresented: isPresented) }
        } else {
            sheet(isPresented: isPresented) { FullPlayerView(isPresented: isPresented).presentationDragIndicator(.visible) }
        }
    }
}

/// 侧栏只负责呈现与选择，不改变各功能的权限和资料来源。
private enum PadSection: String, Identifiable {
    case library, browse, albums, artists, songs, favorites, playlists, mixes, history, search, settings
    var id: String { rawValue }
    var tab: MainTab {
        switch self { case .library: .library; case .search: .search; case .settings: .settings; default: .browse }
    }
    var title: String {
        switch self {
        case .library: "资料库"
        case .browse: "浏览"
        case .albums: "专辑"
        case .artists: "艺术家"
        case .songs: "全部歌曲"
        case .favorites: "我喜欢的"
        case .playlists: "我的歌单"
        case .mixes: "智能歌单"
        case .history: "历史记录"
        case .search: "搜索"
        case .settings: "设置"
        }
    }
    var icon: String {
        switch self {
        case .library: "square.stack"
        case .browse: "square.grid.2x2"
        case .albums: "opticaldisc"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .favorites: "heart"
        case .playlists: "music.note.list"
        case .mixes: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .search: "magnifyingglass"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// 平板播放条把展开、传输控制和队列分成独立按钮，避免嵌套 Button 的误触。
private struct IPadPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var session: AppSession
    let onExpand: () -> Void
    let onQueue: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onExpand) {
                HStack(spacing: 14) {
                    CoverArt(url: playback.currentSong.flatMap { session.musicClient?.songCoverURL(song: $0) }, cornerRadius: 9, fallbackSeed: playback.currentSong?.id ?? "", lookup: playback.currentSong.map(CoverLookupQuery.init(song:)))
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.currentSong?.title ?? "").font(.headline).lineLimit(1)
                        Text(playback.currentSong?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("正在播放".t)
            HStack(spacing: 16) {
                control("backward.fill", label: "上一首", action: playback.previous)
                control(playback.isPlaying ? "pause.fill" : "play.fill", label: playback.isPlaying ? "暂停" : "播放", action: playback.togglePlayPause)
                control("forward.fill", label: "下一首", action: playback.next)
            }
            Button(action: onQueue) { Image(systemName: "list.bullet").frame(width: 44, height: 44) }
                .accessibilityLabel("队列".t)
            Button(action: onExpand) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                .accessibilityLabel("正在播放".t)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Rectangle().fill(Theme.accent).frame(width: proxy.size.width * min(1, max(0, playback.currentTime / max(playback.duration, 0.01))), height: 2)
            }
            .frame(height: 2).allowsHitTesting(false)
        }
    }

    /// 保证播放按钮具有一致的最小点击范围与辅助阅读标签。
    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title3).frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel(label.t)
    }
}
