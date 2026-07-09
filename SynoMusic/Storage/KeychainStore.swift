import Foundation
import Security

/// Keychain 工具：按 ServerProfile.id 存取密码。
enum KeychainStore {
    /// 通用前缀，避免与其他 App 冲突。
    private static let service = "app.nocturne.synology"
    /// 控制后续写入的凭据是否允许通过 iCloud Keychain 同步。
    private static let syncEnabledKey = "syno.icloud.credentials.sync.enabled"

    /// 当前是否把新保存的凭据写为 iCloud Keychain 可同步项。
    static var synchronizesCredentials: Bool {
        UserDefaults.standard.bool(forKey: syncEnabledKey)
    }

    /// 写入密码（已存在则覆盖）。
    static func setPassword(_ password: String, account: String) throws {
        try setPassword(password, account: account, synchronizable: synchronizesCredentials)
    }

    /// 切换 Keychain 同步策略，并把已保存的服务器凭据迁移到新策略。
    static func setCredentialsSyncEnabled(_ enabled: Bool, accounts: [String]) throws {
        let cached = accounts.compactMap { account -> (String, String)? in
            guard let password = password(account: account), !password.isEmpty else { return nil }
            return (account, password)
        }
        UserDefaults.standard.set(enabled, forKey: syncEnabledKey)
        UserDefaults.standard.synchronize()
        for (account, password) in cached {
            try setPassword(password, account: account, synchronizable: enabled)
        }
    }

    /// 按指定同步策略写入密码；同步项不能使用 ThisDeviceOnly 访问级别。
    private static func setPassword(_ password: String, account: String, synchronizable: Bool) throws {
        let data = Data(password.utf8)
        // 先删，再增；避免 errSecDuplicateItem。
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        removePassword(account: account)

        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = synchronizable

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// 读取密码；不存在时返回 nil。
    static func password(account: String) -> String? {
        password(account: account, synchronizable: nil)
            ?? password(account: account, synchronizable: kSecAttrSynchronizableAny)
    }

    /// 读取指定同步范围的密码；nil 表示使用系统默认匹配。
    private static func password(account: String, synchronizable: Any?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let synchronizable {
            query[kSecAttrSynchronizable as String] = synchronizable
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 删除某账号的密码。
    static func removePassword(account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }
}
