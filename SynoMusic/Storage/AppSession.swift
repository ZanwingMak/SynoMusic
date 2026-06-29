import Foundation

/// 应用会话：保存当前已登录的 SynologyClient。
/// 退出/切换服务器时会被替换。
@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var client: SynologyClient?
    @Published private(set) var isRestoringStartupSession: Bool = true
    /// 正在自动登录的档案 ID；启动 silent login 期间由 RootView 设置，
    /// LoginFlowView 据此高亮该行并显示 ProgressView。
    @Published var autoLoginProfileID: UUID?

    var isLoggedIn: Bool { client != nil }

    /// 注入已登录客户端。
    func sign(in client: SynologyClient) {
        self.client = client
        isRestoringStartupSession = false
        autoLoginProfileID = nil
    }

    /// 注销并丢弃客户端。
    func signOut() async {
        await client?.logout()
        client = nil
        isRestoringStartupSession = false
        autoLoginProfileID = nil
    }

    /// 更新启动恢复状态，供首页在自动登录完成前显示加载态。
    func setRestoringStartupSession(_ isRestoring: Bool) {
        isRestoringStartupSession = isRestoring
    }
}
