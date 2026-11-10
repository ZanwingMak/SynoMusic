import SwiftUI

/// 主框架：底部 Tab + 浮动迷你播放器。
struct MainShellView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showFullPlayer: Bool

    @State private var showQueueSheet: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $navigation.selectedTab) {
                NavigationStack {
                    LibraryHomeView()
                        .browseRoutes(reserveMiniPlayer: playback.currentSong != nil)
                }
                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                    .tabItem { Label("资料库".t, systemImage: "rectangle.stack.fill") }
                    .tag(MainTab.library)

                NavigationStack(path: $navigation.browsePath) {
                    BrowseRootView()
                        .browseRoutes(reserveMiniPlayer: playback.currentSong != nil)
                }
                    .tabItem { Label("浏览".t, systemImage: "square.grid.2x2.fill") }
                    .tag(MainTab.browse)

                NavigationStack {
                    SearchView()
                        .browseRoutes(reserveMiniPlayer: playback.currentSong != nil)
                }
                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                    .tabItem { Label("搜索".t, systemImage: "magnifyingglass") }
                    .tag(MainTab.search)

                NavigationStack(path: $navigation.settingsPath) {
                    SettingsView()
                        .navigationDestination(for: SettingsRoute.self) { route in
                            switch route {
                            case .downloads:
                                serverDependentDestination {
                                    DownloadsListView()

                                }
                                .reserveMiniPlayer(visible: playback.currentSong != nil)
                            case .login(let profile):
                                LoginView(profile: profile)
                                    .reserveMiniPlayer(visible: playback.currentSong != nil)
                            case .widgets:
                                WidgetManagerView()

                                .reserveMiniPlayer(visible: playback.currentSong != nil)
                            case .localImports:
                                serverDependentDestination {
                                    LocalImportView()

                                }
                                .reserveMiniPlayer(visible: playback.currentSong != nil)
                            }
                        }
                }
                    .tabItem { Label("设置".t, systemImage: "gearshape.fill") }
                    .tag(MainTab.settings)
            }
            .tint(theme.current.accent(in: colorScheme))

            // 迷你播放器悬浮在 TabBar 之上：用 ZStack 浮，避免被 TabBar 覆盖；
            // 内容让位由页面级 safeAreaInset 处理，深层页面也会保留可滚动空间。
            if playback.currentSong != nil {
                MiniPlayerBar(
                    onTap: { showFullPlayer = true },
                    onQueue: { showQueueSheet = true }
                )
                .padding(.horizontal, Metrics.s)
                .padding(.bottom, Metrics.miniPlayerBottomOffset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
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
                    Button(isEditingQueue ? "完成".t : "编辑".t) {
                        toggleQueueEditing()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成".t) { dismiss() }
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
private struct MiniPlayerReservationHandledKey: EnvironmentKey {
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
