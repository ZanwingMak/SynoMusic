import Foundation

/// 音乐服务器类型；后续多后端能力统一从这里分流。
enum MusicProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case synologyAudioStation
    case jellyfin
    case emby
    case plex
    case webDAV
    case smb

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .synologyAudioStation: return "Synology Audio Station"
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        case .plex: return "Plex"
        case .webDAV: return "WebDAV"
        case .smb: return "SMB"
        }
    }
}

/// 服务器档案：保存 NAS / 自建音乐服务连接配置；密码单独存 Keychain。
struct ServerProfile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var providerType: MusicProviderType
    var name: String          // 用户备注名，如 "家里的 DS"
    var scheme: Scheme        // http / https
    var host: String          // IP / DDNS / QuickConnect ID
    var port: Int             // 默认 5000 / 5001
    var username: String
    var ignoreInvalidCertificate: Bool
    var lastConnectedAt: Date?
    /// 是否通过 QuickConnect ID 创建；开启后编辑器只展示 ID 字段，host/port/scheme 由解析器填。
    var isQuickConnect: Bool
    /// 用户填写的 QuickConnect ID（保留显示）。
    var quickConnectID: String
    /// 远端服务中选定的音乐库 ID；为空时使用服务端第一个音乐库。
    var musicLibraryID: String?
    /// 远端服务中选定的音乐库名称；用于 UI 显示和排查配置。
    var musicLibraryName: String?
    /// Plex Media Server 的 machine identifier；用于远程连接地址变化后重新发现同一台服务器。
    var plexMachineIdentifier: String?

    enum Scheme: String, Codable, CaseIterable, Identifiable, Sendable {
        case http, https
        var id: String { rawValue }
    }

    /// 拼装 baseURL。
    var baseURL: URL? {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = host
        components.port = port
        return components.url
    }

    /// 用于 UI 上展示的连接串。
    var displayURL: String {
        if isQuickConnect, !quickConnectID.isEmpty {
            return "QC: \(quickConnectID)"
        }
        return "\(scheme.rawValue)://\(host):\(port)"
    }

    /// 展示 QuickConnect 已解析出的真实设备地址；直连档案与 displayURL 一致。
    var resolvedDisplayURL: String {
        guard isQuickConnect else { return displayURL }
        guard !host.isEmpty, host != quickConnectID else { return "未获取" }
        return "\(scheme.rawValue)://\(host):\(port)"
    }

    init(
        id: UUID = UUID(),
        providerType: MusicProviderType = .synologyAudioStation,
        name: String = "",
        scheme: Scheme = .http,
        host: String,
        port: Int = 5000,
        username: String,
        ignoreInvalidCertificate: Bool = false,
        lastConnectedAt: Date? = nil,
        isQuickConnect: Bool = false,
        quickConnectID: String = "",
        musicLibraryID: String? = nil,
        musicLibraryName: String? = nil,
        plexMachineIdentifier: String? = nil
    ) {
        self.id = id
        self.providerType = providerType
        self.name = name.isEmpty ? host : name
        self.scheme = scheme
        self.host = host
        self.port = port
        self.username = username
        self.ignoreInvalidCertificate = ignoreInvalidCertificate
        self.lastConnectedAt = lastConnectedAt
        self.isQuickConnect = isQuickConnect
        self.quickConnectID = quickConnectID
        self.musicLibraryID = musicLibraryID
        self.musicLibraryName = musicLibraryName
        self.plexMachineIdentifier = plexMachineIdentifier
    }

    // 旧版本档案兼容解码（没有 providerType / isQuickConnect / quickConnectID 字段）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.providerType = try c.decodeIfPresent(MusicProviderType.self, forKey: .providerType) ?? .synologyAudioStation
        self.name = try c.decode(String.self, forKey: .name)
        self.scheme = try c.decode(Scheme.self, forKey: .scheme)
        self.host = try c.decode(String.self, forKey: .host)
        self.port = try c.decode(Int.self, forKey: .port)
        self.username = try c.decode(String.self, forKey: .username)
        self.ignoreInvalidCertificate = try c.decode(Bool.self, forKey: .ignoreInvalidCertificate)
        self.lastConnectedAt = try c.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        self.isQuickConnect = try c.decodeIfPresent(Bool.self, forKey: .isQuickConnect) ?? false
        self.quickConnectID = try c.decodeIfPresent(String.self, forKey: .quickConnectID) ?? ""
        self.musicLibraryID = try c.decodeIfPresent(String.self, forKey: .musicLibraryID)
        self.musicLibraryName = try c.decodeIfPresent(String.self, forKey: .musicLibraryName)
        self.plexMachineIdentifier = try c.decodeIfPresent(String.self, forKey: .plexMachineIdentifier)
    }
}
