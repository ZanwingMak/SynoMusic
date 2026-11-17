import SwiftUI
import UIKit

/// 自适应主框架：同一导航树支持手机、宽屏与运行中的折叠变化。
struct MainShellView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var showFullPlayer: Bool

    @State private var showQueueSheet: Bool = false
    @State private var sidebarSection: PadSection? = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var compactColumn: NavigationSplitViewColumn = .detail

    var body: some View {
        GeometryReader { geometry in
            let showsSidebar = horizontalSizeClass == .regular && geometry.size.width >= 740
            playerTabs(hidesTabBar: showsSidebar)
                .onChange(of: showsSidebar, initial: true) { _, expanded in
                    columnVisibility = expanded ? .all : .automatic
                }
        }
        .environment(\.miniPlayerReservationHandled, true)
        .onChange(of: navigation.selectedTab) { _, tab in syncSidebar(with: tab) }
        .onAppear {
            syncSidebar(with: navigation.selectedTab)
            playback.apiClient = session.client
            playback.musicClient = session.musicClient
            playback.setHistoryScope(for: session.musicClient?.profile)
            playback.playlistStore = playlists
            playlists.setActiveScope(for: session.musicClient?.profile)
        }
        .onChange(of: session.client) { _, newClient in
            playback.apiClient = newClient
            playback.musicClient = session.musicClient
        }
        .onReceive(session.$musicClient) { newClient in
            playback.apiClient = newClient?.legacySynologyClient
            playback.musicClient = newClient
            playback.setHistoryScope(for: newClient?.profile)
            playlists.setActiveScope(for: newClient?.profile)
        }
        .onChange(of: session.isLoggedIn) { _, _ in
            playback.musicClient = session.musicClient
            playback.setHistoryScope(for: session.musicClient?.profile)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: playback.currentSong)
        .animation(.easeInOut(duration: 0.18), value: theme.currentID)
        .sheet(isPresented: $showQueueSheet) {
            QueueSheet().presentationDetents([.medium, .large])
        }
    }

    /// 将播放条交给系统 Tab 容器定位，使竖向栏和安全区变化不再依赖固定底部高度。
    @ViewBuilder private func playerTabs(hidesTabBar: Bool) -> some View {
        if #available(iOS 26.1, *) {
            tabs(hidesTabBar: hidesTabBar).tabViewBottomAccessory(isEnabled: playback.currentSong != nil) {
                miniPlayer
            }
        } else if #available(iOS 26.0, *) {
            tabs(hidesTabBar: hidesTabBar).tabViewBottomAccessory {
                if playback.currentSong != nil { miniPlayer }
            }
        } else {
            tabs(hidesTabBar: hidesTabBar)
        }
    }

    /// 各标签的导航树保持同一身份；标签容器放在最外层，保留系统工具栏和搜索栏。
    private func tabs(hidesTabBar: Bool) -> some View {
        TabView(selection: $navigation.selectedTab) {
            navigationColumns(showsSidebar: hidesTabBar) {
                NavigationStack(path: $navigation.libraryPath) {
                    LibraryHomeView()
                        .browseRoutes(reserveMiniPlayer: playback.currentSong != nil)
                }
            }
            .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            .tabItem { Label("资料库".t, systemImage: "rectangle.stack.fill") }
            .tag(MainTab.library)

            navigationColumns(showsSidebar: hidesTabBar) {
                NavigationStack(path: $navigation.browsePath) {
                    BrowseRootView()
                        .browseRoutes(reserveMiniPlayer: playback.currentSong != nil)
                }
            }
            .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            .tabItem { Label("浏览".t, systemImage: "square.grid.2x2.fill") }
            .tag(MainTab.browse)

            navigationColumns(showsSidebar: hidesTabBar) {
                NavigationStack(path: $navigation.searchPath) {
                    SearchView()
                        .browseRoutes(reserveMiniPlayer: playback.currentSong != nil)
                }
            }
            .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            .tabItem { Label("搜索".t, systemImage: "magnifyingglass") }
            .tag(MainTab.search)

            navigationColumns(showsSidebar: hidesTabBar) {
                NavigationStack(path: $navigation.settingsPath) {
                    SettingsView()
                        .navigationDestination(for: SettingsRoute.self) { route in
                            switch route {
                            case .downloads:
                                serverDependentDestination { DownloadsListView() }
                                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                            case .login(let profile):
                                LoginView(profile: profile)
                                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                            case .widgets:
                                WidgetManagerView()
                                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                            case .localImports:
                                serverDependentDestination { LocalImportView() }
                                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                            }
                        }
                }
            }
            .toolbar(hidesTabBar ? .hidden : .automatic, for: .tabBar)
            .tabItem { Label("设置".t, systemImage: "gearshape.fill") }
            .tag(MainTab.settings)
        }
        .tint(theme.current.accent(in: colorScheme))
    }

    /// 在每个稳定标签内使用系统分栏，避免外层分栏吞掉子页面的导航与搜索工具栏。
    private func navigationColumns<Content: View>(showsSidebar: Bool, @ViewBuilder content: () -> Content) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            AdaptiveLibrarySidebar(selection: sidebarSelection(isExpanded: showsSidebar))
        } detail: {
            content()
                .modifier(LegacyPlayerInset(onExpand: { showFullPlayer = true }, onQueue: { showQueueSheet = true }))
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// 展开、播放与队列按钮独立响应，系统负责播放器附件的实际位置。
    private var miniPlayer: some View {
        MiniPlayerBar(usesSystemContainer: true, onTap: { showFullPlayer = true }, onQueue: { showQueueSheet = true })
    }

    /// 宽屏侧栏复用手机标签和现有路由，不再更换整个内容框架。
    private func sidebarSelection(isExpanded: Bool) -> Binding<PadSection?> {
        Binding(get: { sidebarSection }, set: { section in
            guard let section else { return }
            sidebarSection = section
            compactColumn = .detail
            if !isExpanded { columnVisibility = .detailOnly }
            navigation.selectedTab = section.tab
            if let route = section.route {
                navigation.browsePath = NavigationPath([route])
            } else if section == .browse {
                navigation.browsePath = NavigationPath()
            }
        })
    }

    /// 同步快捷操作请求，同时保留浏览分类对应的侧栏选中项。
    private func syncSidebar(with tab: MainTab) {
        guard sidebarSection?.tab != tab else { return }
        switch tab {
        case .library: sidebarSection = .library
        case .browse: sidebarSection = .browse
        case .search: sidebarSection = .search
        case .settings: sidebarSection = .settings
        }
    }

    /// 真实服务器会话可用时展示内容，否则给出通用连接提示。
    @ViewBuilder
    private func serverDependentDestination<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if session.musicClient == nil || reviewMode.isEnabled {
            ServerRequiredEmptyState {
                navigation.openAddServer()
            }
        } else {
            content()
        }
    }
}

/// 通用队列面板，被迷你播放器队列按钮触发。
struct QueueSheet: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
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
            .tint(theme.current.accent(in: colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { toggleQueueEditing() } label: {
                        Label(isEditingQueue ? "完成".t : "编辑".t, systemImage: isEditingQueue ? "checkmark" : "pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label("完成".t, systemImage: "checkmark") }
                }
            }
        }
    }

    /// 切换队列的编辑状态；避免额外动画叠加系统列表编辑动画造成卡顿。
    private func toggleQueueEditing() {
        editMode?.wrappedValue = isEditingQueue ? .inactive : .active
    }
}

/// 标记当前视图树已经由外层容器统一处理了迷你播放器底部预留。
struct MiniPlayerReservationHandledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 当前视图树是否已经统一处理迷你播放器底部预留。
    var miniPlayerReservationHandled: Bool {
        get { self[MiniPlayerReservationHandledKey.self] }
        set { self[MiniPlayerReservationHandledKey.self] = newValue }
    }
}

extension View {
    /// 在自己内部的滚动视图底部 reserve 给迷你播放器的空间；
    /// 仅在 `visible == true` 时生效。
    func reserveMiniPlayer(visible: Bool) -> some View {
        modifier(MiniPlayerReservationModifier(visible: visible))
    }
}

/// 兼容旧页面的迷你播放器预留 modifier；外层已统一处理时自动跳过。
private struct MiniPlayerReservationModifier: ViewModifier {
    @Environment(\.miniPlayerReservationHandled) private var isHandledByContainer
    let visible: Bool

    /// 按需添加底部安全区占位，避免内容被浮动迷你播放器遮挡。
    func body(content: Content) -> some View {
        if isHandledByContainer {
            content
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if visible {
                    Color.clear
                        .frame(height: Metrics.miniPlayerReservedHeight)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

/// iOS 17–25 使用页面安全区承载播放条，避免猜测系统标签栏的尺寸。
private struct LegacyPlayerInset: ViewModifier {
    @EnvironmentObject private var playback: PlaybackEngine
    let onExpand: () -> Void
    let onQueue: () -> Void

    /// 旧系统为当前标签预留播放条的真实高度，新系统交由 Tab 附件处理。
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if playback.currentSong != nil {
                    MiniPlayerBar(onTap: onExpand, onQueue: onQueue)
                        .padding(.horizontal, Metrics.s)
                        .padding(.vertical, Metrics.s)
                }
            }
        }
    }
}
