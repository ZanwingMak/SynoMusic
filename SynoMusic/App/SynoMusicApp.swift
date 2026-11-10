import SwiftUI

/// 应用入口：装配根环境对象并展示首屏。
@main
struct SynoMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// 服务器仓库：管理已配置的群晖服务器列表与凭证。
    @StateObject private var serverStore = ServerStore()
    /// 播放引擎：全局共享，保证迷你播放器在跨页面时状态一致。
    @StateObject private var playback = PlaybackEngine()
    /// 当前会话：保存登录后的 Synology 客户端句柄；未登录时为 nil。
    @StateObject private var session = AppSession()
    /// 本地歌单仓库（含「我喜欢的」内置 + 用户自定义）。
    @StateObject private var playlists = PlaylistStore()
    /// 下载管理器：播放器、歌曲菜单和设置页共享同一个缓存索引。
    @StateObject private var downloads = DownloadManager()
    /// 本地导入音乐库。
    @StateObject private var localImports = LocalImportStore()
    /// 主题（accent 色 + 外观偏好）。
    @StateObject private var theme = ThemeManager.shared
    /// 多语言。
    @StateObject private var lm = LanguageManager.shared
    /// 播放偏好（后台播放 / 锁屏 / AirPlay 开关）。
    @StateObject private var playbackSettings = PlaybackSettings()
    /// 播客订阅仓库，用于跨页面和 iCloud 同步共享订阅状态。
    @StateObject private var podcastStore = PodcastSubscriptionStore.shared
    /// 歌曲自定义资料仓库，用于备注和自定义标题等资料同步。
    @StateObject private var songUserDataStore = SongUserDataStore.shared
    /// App 内部导航状态，用于播放器等浮层跳转主框架页面。
    @StateObject private var navigation = AppNavigationState()
    /// StoreKit 购买状态。
    @StateObject private var purchaseStore = PurchaseStore()
    /// iCloud 配置同步状态。
    @StateObject private var cloudSync = CloudSyncStore()
    /// App Store 审核模式：审核账号登录后使用 mock 数据。
    @StateObject private var reviewMode = AppReviewMode()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(serverStore)
                .environmentObject(playback)
                .environmentObject(session)
                .environmentObject(playlists)
                .environmentObject(downloads)
                .environmentObject(localImports)
                .environmentObject(theme)
                .environmentObject(lm)
                .environmentObject(playbackSettings)
                .environmentObject(podcastStore)
                .environmentObject(songUserDataStore)
                .environmentObject(navigation)
                .environmentObject(purchaseStore)
                .environmentObject(cloudSync)
                .environmentObject(reviewMode)
                .onAppear {
                    migrateUnlockedPlayback()
                    playback.applyPlaybackSettings(playbackSettings)
                    playback.downloadManager = downloads
                    cloudSync.configure(
                        serverStore: serverStore,
                        playlistStore: playlists,
                        themeManager: theme,
                        playbackSettings: playbackSettings,
                        podcastStore: podcastStore,
                        songUserDataStore: songUserDataStore,
                        playbackEngine: playback
                    )
                    cloudSync.scheduleAutomaticPull()
                    cloudSync.scheduleOccasionalSync()
                }
                .task {
                    await purchaseStore.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        cloudSync.scheduleAutomaticPull()
                        cloudSync.scheduleOccasionalSync()
                    }
                }
                .onReceive(serverStore.objectWillChange) { _ in
                    cloudSync.scheduleAutomaticPush()
                }
                .onReceive(playlists.objectWillChange) { _ in
                    cloudSync.scheduleAutomaticPush()
                }
                .onReceive(theme.objectWillChange) { _ in
                    cloudSync.scheduleAutomaticPush()
                }
                .onReceive(playbackSettings.objectWillChange) { _ in
                    cloudSync.scheduleAutomaticPush()
                }
                .onReceive(podcastStore.objectWillChange) { _ in
                    cloudSync.scheduleAutomaticPush()
                }
                .onReceive(songUserDataStore.objectWillChange) { _ in
                    cloudSync.scheduleAutomaticPush()
                }

                .tint(theme.current.accent(in: .dark))
                .preferredColorScheme(theme.appearance.colorScheme)
                // 只对语言变化重建整树（翻译值仅在 body 重算时才会刷新）；
                // 主题强调色由 RootView / MainShellView 订阅刷新，避免切换主题就跳回首页。
                .id(lm.current.rawValue)
        }
    }

    /// 升级到全部功能开放后，恢复旧版曾被付费限制关闭的后台播放。
    private func migrateUnlockedPlayback() {
        let key = "syno.unlockedPlaybackMigrated"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        playbackSettings.backgroundPlaybackEnabled = true
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// 字符串便捷翻译入口：`"设置".t` 等价于 `LanguageManager.shared.t("设置")`。
extension String {
    @MainActor var t: String { LanguageManager.shared.t(self) }
}
