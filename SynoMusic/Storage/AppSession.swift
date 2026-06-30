import Foundation

/// 应用会话：保存当前已登录的音乐库客户端。
/// 退出/切换服务器时会被替换。
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var client: SynologyClient?
    @Published private(set) var musicClient: (any MusicLibraryClient)?
    @Published private(set) var isRestoringStartupSession: Bool = true
    /// 正在自动登录的档案 ID；启动 silent login 期间由 RootView 设置，
    /// LoginFlowView 据此高亮该行并显示 ProgressView。
    @Published var autoLoginProfileID: UUID?

    var isLoggedIn: Bool { musicClient != nil }

    /// 当前会话是否为 Synology Audio Station。
    var isSynologySession: Bool {
        musicClient?.providerType == .synologyAudioStation
    }

    /// 注入已登录 Synology 客户端，并同步创建统一音乐库适配器。
    func sign(in client: SynologyClient) {
        self.client = client
        self.musicClient = SynologyMusicLibraryClient(client: client)
        isRestoringStartupSession = false
        autoLoginProfileID = nil
    }

    /// 注入统一音乐库客户端；非 Synology 后端后续会走这个入口。
    func sign(in musicClient: any MusicLibraryClient) {
        self.musicClient = musicClient
        self.client = musicClient.legacySynologyClient
        isRestoringStartupSession = false
        autoLoginProfileID = nil
    }

    /// 注销并丢弃客户端。
    func signOut() async {
        await musicClient?.logout()
        client = nil
        musicClient = nil
        isRestoringStartupSession = false
        autoLoginProfileID = nil
    }

    /// 更新启动恢复状态，供首页在自动登录完成前显示加载态。
    func setRestoringStartupSession(_ isRestoring: Bool) {
        isRestoringStartupSession = isRestoring
    }
}
