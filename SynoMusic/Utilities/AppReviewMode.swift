import Foundation

/// App Store 审核模式：指定审核账号登录后使用本地 mock 数据，不访问真实 NAS。
@MainActor
final class AppReviewMode: ObservableObject {
    static let reviewUsername = "synomusic_test"
    static let reviewPassword = "synomusic_test"
    static let shellIdentity = "app-review-mode"

    @Published private(set) var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: storageKey)
        }
    }

    private let storageKey = "syno.appReviewMode.enabled"

    /// 从 UserDefaults 恢复审核模式状态。
    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: storageKey)
    }

    /// 判断输入的账号密码是否为审核账号。
    static func matches(username: String, password: String) -> Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines) == reviewUsername
            && password == reviewPassword
    }

    /// 启用审核模式，后续页面使用 mock 数据并隐藏不适合审核的在线入口。
    func activate() {
        isEnabled = true
    }

    /// 关闭审核模式，恢复正常登录流程。
    func deactivate() {
        isEnabled = false
    }
}
