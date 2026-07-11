import Foundation

/// 服务器档案仓库：用 UserDefaults 持久化档案列表，密码走 Keychain。
@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var profiles: [ServerProfile] = []
    @Published var activeProfileID: UUID?
    @Published private(set) var updatedAt: Date = .distantPast

    private let defaults: UserDefaults
    private let key = "noc.serverProfiles"
    private let activeKey = "noc.activeProfileID"
    private let updatedAtKey = "noc.serverProfiles.updatedAt"

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
        markModified()
        save()
    }

    /// 删除档案（同时清除 Keychain 密码）。
    func remove(_ profile: ServerProfile) {
        KeychainStore.removePassword(account: profile.id.uuidString)
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id { activeProfileID = profiles.first?.id }
        markModified()
        save()
    }

    /// 设置当前活动档案。
    func setActive(_ profile: ServerProfile) {
        activeProfileID = profile.id
        markModified()
        save()
    }

    /// 用云端快照替换本地非敏感服务器配置；密码仍保留在本机 Keychain。
    func replaceProfiles(_ newProfiles: [ServerProfile], activeProfileID newActiveID: UUID?, modifiedAt: Date = Date()) {
        profiles = newProfiles
        if let newActiveID, profiles.contains(where: { $0.id == newActiveID }) {
            activeProfileID = newActiveID
        } else {
            activeProfileID = profiles.first?.id
        }
        updatedAt = modifiedAt
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
        let savedUpdatedAt = defaults.double(forKey: updatedAtKey)
        if savedUpdatedAt > 0 {
            self.updatedAt = Date(timeIntervalSince1970: savedUpdatedAt)
        } else {
            self.updatedAt = profiles.isEmpty ? .distantPast : Date()
        }
        if let s = defaults.string(forKey: activeKey), let id = UUID(uuidString: s) {
            self.activeProfileID = id
        } else {
            self.activeProfileID = profiles.first?.id
        }
    }

    /// 标记服务器配置在本机发生过修改，用于 iCloud 同步冲突判断。
    private func markModified(_ date: Date = Date()) {
        updatedAt = date
    }

    /// 持久化当前默认服务器 ID，避免云同步恢复后丢失默认选择。
    private func saveActiveProfileID() {
        if let activeProfileID {
            defaults.set(activeProfileID.uuidString, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: key)
        }
        saveActiveProfileID()
        defaults.set(updatedAt.timeIntervalSince1970, forKey: updatedAtKey)
        // 显式 synchronize：simulator 通过 simctl terminate 关进程时，UserDefaults
        // 的异步写回可能丢失。这里同步落盘，保证下次启动能读到。
        defaults.synchronize()
    }
}
