import Foundation

/// Plex 账号与服务器发现错误。
enum PlexAccountError: LocalizedError {
    case missingCredential
    case missingToken
    case noServer
    case noConnection
    case authorizationPending
    case invalidResponse
    case http(Int)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Plex 账号或密码不能为空。"
        case .missingToken:
            return "没有从 Plex 账号获取到访问令牌，请检查账号安全设置或改用 X-Plex-Token。"
        case .noServer:
            return "没有发现可用的 Plex Media Server。"
        case .noConnection:
            return "发现了 Plex 服务器，但没有可用连接地址。"
        case .authorizationPending:
            return "还没有完成 Plex 浏览器授权，请授权后再继续。"
        case .invalidResponse:
            return "Plex 返回的数据无效。"
        case .http(let code):
            return "Plex 返回错误：HTTP \(code)"
        case .network(let message):
            return message
        case .decoding(let message):
            return "解析 Plex 响应失败：\(message)"
        }
    }
}

/// Plex 账号登录后的基础信息。
struct PlexAccountInfo: Sendable {
    let username: String
    let authToken: String
    let hasPlexPass: Bool
}

/// Plex PIN 授权信息。
struct PlexAuthPin: Identifiable, Sendable {
    let id: Int
    let code: String
    let authURL: URL
    let expiresAt: Date?
}

/// Plex 服务器可用连接地址。
struct PlexServerConnection: Identifiable, Hashable, Sendable {
    let id: String
    let uri: URL
    let scheme: ServerProfile.Scheme
    let host: String
    let port: Int
    let isLocal: Bool
    let isRelay: Bool

    var labelKey: String {
        if isRelay { return "中继连接" }
        return isLocal ? "本地连接" : "远程连接"
    }

    var displayURL: String {
        "\(scheme.rawValue)://\(host):\(port)"
    }
}

/// Plex 账号发现到的 Media Server。
struct PlexDiscoveredServer: Identifiable, Sendable {
    let id: String
    let name: String
    let token: String
    let owned: Bool
    let hasPlexPass: Bool
    let connections: [PlexServerConnection]
}

/// 已验证可访问的 Plex 连接候选。
struct PlexConnectionOption: Identifiable, Sendable {
    let id: String
    let server: PlexDiscoveredServer
    let connection: PlexServerConnection
    let libraries: [MusicLibrary]
    let responseTime: TimeInterval

    var displayTitle: String {
        "\(server.name) · \(connection.labelKey)"
    }
}

/// Plex 账号登录与服务器发现服务。
enum PlexAccountService {
    private static let productName = "SynoMusic"
    private static let appVersion = "1.4.8"

    /// 创建 Plex 浏览器授权 PIN。
    static func createPin() async throws -> PlexAuthPin {
        guard var components = URLComponents(string: "https://plex.tv/api/v2/pins") else {
            throw PlexAccountError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "strong", value: "true")]
        guard let url = components.url else { throw PlexAccountError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 16
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request)

        let data = try await requestData(request)
        do {
            let response = try JSONDecoder().decode(PlexPinResponse.self, from: data)
            guard let authURL = makePinAuthURL(code: response.code) else {
                throw PlexAccountError.invalidResponse
            }
            return PlexAuthPin(
                id: response.id,
                code: response.code,
                authURL: authURL,
                expiresAt: response.expiresAtDate
            )
        } catch let error as PlexAccountError {
            throw error
        } catch {
            throw PlexAccountError.decoding(error.localizedDescription)
        }
    }

    /// 检查 Plex PIN 是否已授权；未授权时返回 nil。
    static func checkPin(_ pin: PlexAuthPin) async throws -> PlexAccountInfo? {
        guard let url = URL(string: "https://plex.tv/api/v2/pins/\(pin.id)") else {
            throw PlexAccountError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request)

        let data = try await requestData(request)
        do {
            let response = try JSONDecoder().decode(PlexPinResponse.self, from: data)
            guard let token = response.authToken?.nilIfBlank else { return nil }
            return try await fetchAccountInfo(token: token)
        } catch {
            throw PlexAccountError.decoding(error.localizedDescription)
        }
    }

    /// 使用 Plex 账号密码登录并读取账号访问令牌。
    static func signIn(username: String, password: String) async throws -> PlexAccountInfo {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !trimmedPassword.isEmpty else {
            throw PlexAccountError.missingCredential
        }

        guard let url = URL(string: "https://plex.tv/users/sign_in.json") else {
            throw PlexAccountError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 16
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let basic = Data("\(trimmedUser):\(trimmedPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")

        let data = try await requestData(request)
        do {
            let response = try JSONDecoder().decode(PlexSignInResponse.self, from: data)
            guard let token = response.user.authToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty else {
                throw PlexAccountError.missingToken
            }
            return PlexAccountInfo(
                username: response.user.displayName(fallback: trimmedUser),
                authToken: token,
                hasPlexPass: response.user.hasPlexPass
            )
        } catch let error as PlexAccountError {
            throw error
        } catch {
            throw PlexAccountError.decoding(error.localizedDescription)
        }
    }

    /// 使用 token 读取 Plex 账号基础信息。
    static func fetchAccountInfo(token: String) async throws -> PlexAccountInfo {
        guard var components = URLComponents(string: "https://plex.tv/users/account.json") else {
            throw PlexAccountError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        guard let url = components.url else { throw PlexAccountError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(to: &request, token: token)

        do {
            let data = try await requestData(request)
            let response = try JSONDecoder().decode(PlexAccountResponse.self, from: data)
            return PlexAccountInfo(
                username: response.user.displayName(fallback: "Plex"),
                authToken: token,
                hasPlexPass: response.user.hasPlexPass
            )
        } catch {
            return PlexAccountInfo(username: "Plex", authToken: token, hasPlexPass: false)
        }
    }

    /// 使用账号 token 拉取可访问的 Plex Media Server 资源。
    static func fetchServers(account: PlexAccountInfo) async throws -> [PlexDiscoveredServer] {
        guard var components = URLComponents(string: "https://plex.tv/api/resources") else {
            throw PlexAccountError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "includeHttps", value: "1"),
            URLQueryItem(name: "includeRelay", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: account.authToken)
        ]
        guard let url = components.url else { throw PlexAccountError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 16
        applyHeaders(to: &request, token: account.authToken)

        let data = try await requestData(request)
        let devices: [PlexResourceDevice]
        do {
            devices = try PlexResourcesParser.parse(data)
        } catch {
            throw PlexAccountError.decoding(error.localizedDescription)
        }

        let servers = devices.compactMap { device -> PlexDiscoveredServer? in
            guard device.isServer else { return nil }
            let connections = device.connections
                .compactMap(makeConnection)
                .sorted(by: sortConnection)
            guard !connections.isEmpty else { return nil }
            let serverToken = device.accessToken.isEmpty ? account.authToken : device.accessToken
            return PlexDiscoveredServer(
                id: device.clientIdentifier,
                name: device.name.isEmpty ? "Plex Media Server" : device.name,
                token: serverToken,
                owned: device.owned,
                hasPlexPass: account.hasPlexPass,
                connections: connections
            )
        }
        guard !servers.isEmpty else { throw PlexAccountError.noServer }
        return servers
    }

    /// 根据用户选择的 Plex 连接生成 App 内服务器配置。
    static func makeProfile(
        from base: ServerProfile,
        account: PlexAccountInfo,
        server: PlexDiscoveredServer,
        connection: PlexServerConnection,
        library: MusicLibrary? = nil
    ) -> ServerProfile {
        ServerProfile(
            id: base.id,
            providerType: .plex,
            name: base.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? server.name : base.name,
            scheme: connection.scheme,
            host: connection.host,
            port: connection.port,
            username: account.username,
            ignoreInvalidCertificate: base.ignoreInvalidCertificate,
            lastConnectedAt: nil,
            isQuickConnect: false,
            quickConnectID: "",
            musicLibraryID: library?.id,
            musicLibraryName: library?.name
        )
    }

    /// 生成 Plex 浏览器授权地址。
    private static func makePinAuthURL(code: String) -> URL? {
        let values = [
            "clientID": stableDeviceID(),
            "code": code,
            "context[device][product]": productName,
            "context[device][platform]": "iOS",
            "forwardUrl": "https://app.plex.tv/desktop"
        ]
        let fragment = values
            .map { key, value in
                "\(escape(key))=\(escape(value))"
            }
            .joined(separator: "&")
        return URL(string: "https://app.plex.tv/auth#?\(fragment)")
    }

    /// 百分号转义 Plex 授权 URL 参数。
    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    /// 把 Plex 资源中的连接节点转成可保存的连接地址。
    private static func makeConnection(_ resource: PlexResourceConnection) -> PlexServerConnection? {
        guard let url = URL(string: resource.uri),
              let schemeRaw = url.scheme,
              let scheme = ServerProfile.Scheme(rawValue: schemeRaw),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        let port = url.port ?? (scheme == .https ? 443 : 80)
        return PlexServerConnection(
            id: "\(resource.uri)-\(resource.local)-\(resource.relay)",
            uri: url,
            scheme: scheme,
            host: host,
            port: port,
            isLocal: resource.local,
            isRelay: resource.relay
        )
    }

    /// Plex 连接排序：本地优先，其次远程直连，最后才是 Relay。
    private static func sortConnection(_ lhs: PlexServerConnection, _ rhs: PlexServerConnection) -> Bool {
        let leftScore = (lhs.isRelay ? 2 : 0) + (lhs.isLocal ? 0 : 1)
        let rightScore = (rhs.isRelay ? 2 : 0) + (rhs.isLocal ? 0 : 1)
        if leftScore != rightScore { return leftScore < rightScore }
        return lhs.displayURL < rhs.displayURL
    }

    /// 排序已经验证可用的 Plex 连接候选。
    static func sortOptions(_ lhs: PlexConnectionOption, _ rhs: PlexConnectionOption) -> Bool {
        let leftScore = (lhs.connection.isRelay ? 2 : 0) + (lhs.connection.isLocal ? 0 : 1)
        let rightScore = (rhs.connection.isRelay ? 2 : 0) + (rhs.connection.isLocal ? 0 : 1)
        if leftScore != rightScore { return leftScore < rightScore }
        if lhs.responseTime != rhs.responseTime { return lhs.responseTime < rhs.responseTime }
        return lhs.connection.displayURL < rhs.connection.displayURL
    }

    /// 发送 HTTP 请求并校验 Plex 返回状态码。
    private static func requestData(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw PlexAccountError.network("请求已取消")
        } catch {
            throw PlexAccountError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw PlexAccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw PlexAccountError.http(http.statusCode) }
        return data
    }

    /// 给 Plex 请求附加客户端识别头。
    private static func applyHeaders(to request: inout URLRequest, token: String? = nil) {
        request.setValue(productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(appVersion, forHTTPHeaderField: "X-Plex-Version")
        request.setValue(stableDeviceID(), forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
    }

    /// 返回稳定设备 ID，避免 Plex 每次都把 App 当成新客户端。
    private static func stableDeviceID() -> String {
        let key = "syno.plex.account.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

/// Plex 登录 JSON 根节点。
private struct PlexSignInResponse: Decodable {
    let user: PlexSignInUser
}

/// Plex 账号信息 JSON；兼容有 user 包裹或直接返回用户字段的格式。
private struct PlexAccountResponse: Decodable {
    let user: PlexSignInUser

    /// 兼容 Plex 不同账号接口的 JSON 根结构。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let user = try container.decodeIfPresent(PlexSignInUser.self, forKey: .user) {
            self.user = user
        } else {
            self.user = try PlexSignInUser(from: decoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case user
    }
}

/// Plex PIN 授权 JSON。
private struct PlexPinResponse: Decodable {
    let id: Int
    let code: String
    let authToken: String?
    let expiresAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case code
        case authToken
        case expiresAt
    }

    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        return ISO8601DateFormatter().date(from: expiresAt)
    }
}

/// Plex 登录 JSON 用户节点；兼容不同历史字段名。
private struct PlexSignInUser: Decodable {
    let username: String?
    let title: String?
    let email: String?
    let authToken: String?
    let subscription: PlexSubscription?
    let roles: [String]?
    let entitlements: [String]?

    private enum CodingKeys: String, CodingKey {
        case username
        case title
        case email
        case authToken
        case authenticationToken = "authentication_token"
        case authTokenSnake = "auth_token"
        case subscription
        case roles
        case entitlements
    }

    /// 兼容 Plex 新旧 token 字段名。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        authToken = try container.decodeIfPresent(String.self, forKey: .authToken)
            ?? container.decodeIfPresent(String.self, forKey: .authenticationToken)
            ?? container.decodeIfPresent(String.self, forKey: .authTokenSnake)
        subscription = try container.decodeIfPresent(PlexSubscription.self, forKey: .subscription)
        roles = try container.decodeIfPresent([String].self, forKey: .roles)
        entitlements = try container.decodeIfPresent([String].self, forKey: .entitlements)
    }

    /// 生成展示用户名。
    func displayName(fallback: String) -> String {
        username?.nilIfBlank ?? title?.nilIfBlank ?? email?.nilIfBlank ?? fallback
    }

    var hasPlexPass: Bool {
        if subscription?.active == true { return true }
        let joined = ((roles ?? []) + (entitlements ?? [])).joined(separator: ",").lowercased()
        return joined.contains("plexpass") || joined.contains("plex_pass")
    }
}

/// Plex 订阅节点。
private struct PlexSubscription: Decodable {
    let active: Bool?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case active
        case status
    }
}

/// Plex 资源中的服务器节点。
private struct PlexResourceDevice {
    let name: String
    let product: String
    let provides: String
    let clientIdentifier: String
    let accessToken: String
    let owned: Bool
    var connections: [PlexResourceConnection]

    var isServer: Bool {
        product == "Plex Media Server" || provides.split(separator: ",").contains("server")
    }
}

/// Plex 资源中的连接节点。
private struct PlexResourceConnection {
    let uri: String
    let local: Bool
    let relay: Bool
}

/// Plex 资源 XML 解析器。
private final class PlexResourcesParser: NSObject, XMLParserDelegate {
    private var devices: [PlexResourceDevice] = []
    private var currentDevice: PlexResourceDevice?

    /// 解析 resources XML。
    static func parse(_ data: Data) throws -> [PlexResourceDevice] {
        let delegate = PlexResourcesParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? PlexAccountError.decoding("XML 解析失败")
        }
        return delegate.devices
    }

    /// 读取 Device / Connection 开始标签属性。
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "Device":
            currentDevice = PlexResourceDevice(
                name: attributeDict["name"] ?? "",
                product: attributeDict["product"] ?? "",
                provides: attributeDict["provides"] ?? "",
                clientIdentifier: attributeDict["clientIdentifier"] ?? UUID().uuidString,
                accessToken: attributeDict["accessToken"] ?? "",
                owned: Self.boolValue(attributeDict["owned"]),
                connections: []
            )
        case "Connection":
            guard currentDevice != nil,
                  let uri = attributeDict["uri"],
                  !uri.isEmpty else { return }
            currentDevice?.connections.append(
                PlexResourceConnection(
                    uri: uri,
                    local: Self.boolValue(attributeDict["local"]),
                    relay: Self.boolValue(attributeDict["relay"])
                )
            )
        default:
            break
        }
    }

    /// 在 Device 结束时提交当前服务器节点。
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "Device", let device = currentDevice else { return }
        devices.append(device)
        currentDevice = nil
    }

    /// 兼容 Plex XML 中的 1/0、true/false 布尔值。
    private static func boolValue(_ raw: String?) -> Bool {
        guard let raw = raw?.lowercased() else { return false }
        return raw == "1" || raw == "true"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
