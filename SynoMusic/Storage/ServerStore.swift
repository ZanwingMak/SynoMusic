import Foundation

/// 服务器档案仓库：用 UserDefaults 持久化档案列表，密码走 Keychain。
@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published var activeProfileID: UUID?

    private let defaults: UserDefaults
    private let key = "noc.serverProfiles"
    private let activeKey = "noc.activeProfileID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        #if DEBUG
        if DemoMode.isEnabled, profiles.isEmpty {
            self.profiles = DemoMode.serverProfiles
            self.activeProfileID = profiles.first?.id
        }
        #endif
    }

    var activeProfile: ServerProfile? {
        guard let id = activeProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == id })
    }

    /// 默认档案：与 activeProfile 同义；用于启动自动登录的语义入口。
    var defaultProfile: ServerProfile? { activeProfile }

    /// 新增或更新档案。
    func upsert(_ profile: ServerProfile) {
        objectWillChange.send()
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    /// 删除档案（同时清除 Keychain 密码）。
    func remove(_ profile: ServerProfile) {
        KeychainStore.removePassword(account: profile.id.uuidString)
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id { activeProfileID = profiles.first?.id }
        save()
    }

    /// 设置当前活动档案。
    func setActive(_ profile: ServerProfile) {
        activeProfileID = profile.id
        defaults.set(profile.id.uuidString, forKey: activeKey)
    }

    /// 用云端快照替换本地非敏感服务器配置；密码仍保留在本机 Keychain。
    func replaceProfiles(_ newProfiles: [ServerProfile], activeProfileID newActiveID: UUID?) {
        profiles = newProfiles
        if let newActiveID, profiles.contains(where: { $0.id == newActiveID }) {
            activeProfileID = newActiveID
        } else {
            activeProfileID = profiles.first?.id
        }
        save()
    }

    /// 保存密码。
    func savePassword(_ password: String, for profile: ServerProfile) throws {
        try KeychainStore.setPassword(password, account: profile.id.uuidString)
    }

    /// 读取密码。
    func password(for profile: ServerProfile) -> String? {
        KeychainStore.password(account: profile.id.uuidString)
    }

    // MARK: 持久化

    private func load() {
        if let data = defaults.data(forKey: key),
           let list = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            self.profiles = list
        }
        if let s = defaults.string(forKey: activeKey), let id = UUID(uuidString: s) {
            self.activeProfileID = id
        } else {
            self.activeProfileID = profiles.first?.id
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: key)
        }
        // 显式 synchronize：simulator 通过 simctl terminate 关进程时，UserDefaults
        // 的异步写回可能丢失。这里同步落盘，保证下次启动能读到。
        defaults.synchronize()
    }
}
