import Foundation

/// Plex 音乐源错误；第一版只支持手动 X-Plex-Token 连接本地服务器。
enum PlexMusicError: LocalizedError {
    case missingBaseURL
    case missingToken
    case noMusicLibrary
    case missingStreamURL
    case http(Int)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "服务器地址无效"
        case .missingToken:
            return "服务器访问令牌不能为空。"
        case .noMusicLibrary:
            return "没有找到可用的音乐库。"
        case .missingStreamURL:
            return "无法获取歌曲播放地址。"
        case .http(let code):
            if code == 401 {
                return "Plex 授权已失效，请重新登录或更新 X-Plex-Token。"
            }
            return "服务器返回错误：HTTP \(code)"
        case .network(let message):
            return message
        case .decoding(let message):
            return "解析服务器响应失败：\(message)"
        }
    }
}

/// Plex 音乐库客户端；使用 Plex Media Server XML 接口并只映射音乐内容。
final class PlexMusicLibraryClient: MusicLibraryClient, AsyncStreamResolvingMusicClient, @unchecked Sendable {
    let providerType: MusicProviderType = .plex
    private(set) var profile: ServerProfile

    private let session: URLSession
    private let deviceID: String
    private var activeConnectionProfile: ServerProfile
    private var accountToken: String?
    private var token: String?
    private var lastConnectionRefreshAt: Date?
    private var partKeyByItemID: [String: String] = [:]
    private var thumbPathByItemID: [String: String] = [:]

    init(profile: ServerProfile, token: String? = nil) {
        self.profile = profile
        self.activeConnectionProfile = profile
        if let token {
            let credential = PlexAccountService.parseCredential(token)
            self.accountToken = credential.accountToken
            self.token = credential.serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.accountToken = nil
            self.token = nil
        }
        self.deviceID = Self.stableDeviceID()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 14
        config.timeoutIntervalForResource = 30
        if Self.shouldUsePermissiveCertificateHandling(profile: profile) {
            self.session = URLSession(configuration: config, delegate: PlexPermissiveCertDelegate(), delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
    }

    /// 校验 token 是否可访问 Plex 音乐库，并解析账号 token 以便后续刷新远程连接地址。
    func authenticate(token: String) async throws {
        let credential = PlexAccountService.parseCredential(token)
        let trimmed = credential.serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlexMusicError.missingToken }
        self.accountToken = credential.accountToken
        self.token = trimmed
        _ = try await loadLibraries()
    }

    /// 获取 Plex 音乐库 section；Plex 音乐库 section 类型为 artist。
    func loadLibraries() async throws -> [MusicLibrary] {
        let container = try await requestXML(path: "library/sections", query: [])
        let musicSections = container.items.filter { item in
            item.attributes["type"] == "artist"
        }
        let libraries = musicSections.compactMap { item -> MusicLibrary? in
            guard let key = item.attributes["key"] else { return nil }
            return MusicLibrary(
                id: key,
                name: item.attributes["title"] ?? "Music",
                providerType: providerType,
                isDefault: key == selectedMusicSectionKey(in: musicSections)
            )
        }
        guard !libraries.isEmpty else { throw PlexMusicError.noMusicLibrary }
        return libraries
    }

    /// 加载首页需要的专辑与艺术家摘要。
    func loadHomeSnapshot() async throws -> LibraryHomeSnapshot {
        let sectionKey = try await defaultMusicSectionKey()
        let recentAlbums = try await listAlbums(sectionKey: sectionKey, limit: 18, offset: 0, sort: "addedAt:desc")
        let albums = try await listAlbums(sectionKey: sectionKey, limit: 60, offset: 0, sort: "titleSort")
        let artists = try await listArtists(sectionKey: sectionKey, limit: 30, offset: 0)
        return LibraryHomeSnapshot(recentAlbums: recentAlbums, albums: albums, artists: artists)
    }

    /// 列出默认音乐库中的歌曲。
    func listSongs(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Song] {
        let sectionKey = try await defaultMusicSectionKey()
        return try await listSongs(sectionKey: sectionKey, limit: limit, offset: offset, sort: normalizedSort(sortBy, direction: sortDirection))
    }

    /// 列出默认音乐库中的专辑。
    func listAlbums(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Album] {
        let sectionKey = try await defaultMusicSectionKey()
        return try await listAlbums(sectionKey: sectionKey, limit: limit, offset: offset, sort: normalizedSort(sortBy, direction: sortDirection))
    }

    /// 列出默认音乐库中的艺术家。
    func listArtists(limit: Int, offset: Int) async throws -> [Artist] {
        let sectionKey = try await defaultMusicSectionKey()
        return try await listArtists(sectionKey: sectionKey, limit: limit, offset: offset)
    }

    /// 列出 Plex 音频播放列表，过滤掉视频和照片播放列表。
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist] {
        let container = try await requestXML(
            path: "playlists",
            query: [URLQueryItem(name: "playlistType", value: "audio")],
            start: offset,
            size: limit
        )
        return container.items
            .filter { item in
                let type = item.attributes["playlistType"] ?? item.attributes["type"]
                return type == nil || type == "audio"
            }
            .map(mapPlaylist)
    }

    /// 列出 Plex 播放列表内的歌曲。
    func playlistSongs(playlist: Playlist) async throws -> [Song] {
        let playlistID = remoteID(from: playlist.id)
        let container = try await requestXML(path: "playlists/\(playlistID)/items", query: [], start: 0, size: 1000)
        return container.items.map(mapSong)
    }

    /// 在默认音乐库中搜索歌曲。
    func searchSongs(keyword: String, limit: Int, offset: Int) async throws -> [Song] {
        let sectionKey = try await defaultMusicSectionKey()
        let container = try await requestXML(
            path: "library/sections/\(sectionKey)/search",
            query: [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "query", value: keyword)
            ],
            start: offset,
            size: limit
        )
        return container.items.map(mapSong)
    }

    /// 随机抓取默认音乐库中的歌曲。
    func randomSongs(count: Int) async throws -> [Song] {
        let sectionKey = try await defaultMusicSectionKey()
        return try await listSongs(sectionKey: sectionKey, limit: max(count, 50), offset: 0, sort: "random")
            .shuffled()
            .prefix(count)
            .map { $0 }
    }

    /// 列出指定 Plex 专辑下的歌曲。
    func albumSongs(album: Album) async throws -> [Song] {
        let albumID = remoteID(from: album.id)
        let container = try await requestXML(path: "library/metadata/\(albumID)/children", query: [], start: 0, size: 1000)
        return container.items.map(mapSong)
    }

    /// 使用 Plex 原生 artist children 接口列出艺人专辑。
    func artistAlbums(artist: Artist) async throws -> [Album] {
        let artistID = remoteID(from: artist.id)
        let container = try await requestXML(path: "library/metadata/\(artistID)/children", query: [], start: 0, size: 1000)
        return container.items.map(mapAlbum)
    }

    /// 返回专辑封面 URL。
    func albumCoverURL(album: Album) -> URL? {
        imageURL(itemID: remoteID(from: album.id))
    }

    /// 返回歌曲封面 URL。
    func songCoverURL(song: Song) -> URL? {
        imageURL(itemID: remoteID(from: song.id))
    }

    /// 返回 Plex 歌曲直连播放地址；第一版不同音质档位均使用服务器原始音频流。
    func streamURL(song: Song, quality: AudioQuality) -> URL? {
        let itemID = remoteID(from: song.id)
        let partKey = cachedPartKey(for: itemID) ?? song.path
        guard let partKey, !partKey.isEmpty else { return nil }
        return makeURL(path: partKey, query: [], includeTokenQuery: true)
    }

    /// 播放前轻量刷新 Plex 连接，避免公网 IP 或 plex.direct 地址变化后旧播放 URL 失效。
    func preparedStreamURL(song: Song, quality: AudioQuality) async throws -> URL? {
        try? await refreshConnectionIfStale()
        return streamURL(song: song, quality: quality)
    }

    /// Plex 内置歌词差异较大，第一版交给现有在线歌词兜底。
    func lyrics(for song: Song) async throws -> [LyricLine] {
        []
    }

    /// 清理本地 token 与缓存，不主动修改 Plex 服务端状态。
    func logout() async {
        token = nil
        partKeyByItemID.removeAll()
        thumbPathByItemID.removeAll()
    }

    /// 读取默认音乐 section key。
    private func defaultMusicSectionKey() async throws -> String {
        let libraries = try await loadLibraries()
        if let preferred = profile.musicLibraryID,
           libraries.contains(where: { $0.id == preferred }) {
            return preferred
        }
        guard let key = libraries.first?.id else {
            throw PlexMusicError.noMusicLibrary
        }
        return key
    }

    /// 返回当前 profile 应该使用的音乐库 section key。
    private func selectedMusicSectionKey(in musicSections: [PlexXMLItem]) -> String? {
        if let preferred = profile.musicLibraryID,
           musicSections.contains(where: { $0.attributes["key"] == preferred }) {
            return preferred
        }
        return musicSections.first?.attributes["key"]
    }

    /// 查询 Plex 音乐歌曲列表并映射成通用模型。
    private func listSongs(sectionKey: String, limit: Int, offset: Int, sort: String) async throws -> [Song] {
        let container = try await requestXML(
            path: "library/sections/\(sectionKey)/all",
            query: [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "sort", value: sort)
            ],
            start: offset,
            size: limit
        )
        return container.items.map(mapSong)
    }

    /// 查询 Plex 音乐专辑列表并映射成通用模型。
    private func listAlbums(sectionKey: String, limit: Int, offset: Int, sort: String) async throws -> [Album] {
        let container = try await requestXML(
            path: "library/sections/\(sectionKey)/all",
            query: [
                URLQueryItem(name: "type", value: "9"),
                URLQueryItem(name: "sort", value: sort)
            ],
            start: offset,
            size: limit
        )
        return container.items.map(mapAlbum)
    }

    /// 查询 Plex 音乐艺术家列表并映射成通用模型。
    private func listArtists(sectionKey: String, limit: Int, offset: Int) async throws -> [Artist] {
        let container = try await requestXML(
            path: "library/sections/\(sectionKey)/all",
            query: [
                URLQueryItem(name: "type", value: "8"),
                URLQueryItem(name: "sort", value: "titleSort")
            ],
            start: offset,
            size: limit
        )
        return container.items.map(mapArtist)
    }

    /// 把 App 内排序字段转换为 Plex sort 参数。
    private func normalizedSort(_ sortBy: String, direction: String) -> String {
        if sortBy == "recently_added" { return "addedAt:desc" }
        if sortBy == "random" { return "random" }
        let suffix = direction.uppercased() == "DESC" ? ":desc" : ""
        switch sortBy {
        case "track":
            return "indexSort\(suffix)"
        case "name":
            fallthrough
        default:
            return "titleSort\(suffix)"
        }
    }

    /// 映射 Plex Track 到通用 Song，并缓存播放 part key 与封面路径。
    private func mapSong(_ item: PlexXMLItem) -> Song {
        let itemID = item.attributes["ratingKey"] ?? item.attributes["key"] ?? UUID().uuidString
        let media = item.mediaAttributes
        let part = item.partAttributes
        let partKey = part?["key"]
        let fileName = fileTitle(from: part?["file"])
        let thumb = item.attributes["thumb"] ?? item.attributes["parentThumb"] ?? item.attributes["grandparentThumb"]
        cache(itemID: itemID, partKey: partKey, thumbPath: thumb)

        return Song(
            id: globalID(itemID),
            title: bestText(item.attributes["title"], fallback: fileName, unknown: "未知歌曲"),
            album: bestOptionalText(item.attributes["parentTitle"]),
            artist: bestOptionalText(item.attributes["grandparentTitle"] ?? item.attributes["originalTitle"]),
            albumArtist: bestOptionalText(item.attributes["grandparentTitle"]),
            genre: nil,
            composer: nil,
            trackNumber: Int(item.attributes["index"] ?? ""),
            discNumber: Int(item.attributes["parentIndex"] ?? ""),
            year: Int(item.attributes["year"] ?? ""),
            duration: duration(from: item.attributes["duration"] ?? media?["duration"]),
            bitrate: bitrate(from: media?["bitrate"]),
            codec: media?["audioCodec"] ?? media?["container"] ?? part?["container"],
            filesize: part?["size"].flatMap(Int64.init),
            path: partKey,
            rating: nil
        )
    }

    /// 映射 Plex Album 到通用 Album，并缓存封面路径。
    private func mapAlbum(_ item: PlexXMLItem) -> Album {
        let itemID = item.attributes["ratingKey"] ?? item.attributes["key"] ?? UUID().uuidString
        let artist = bestText(
            item.attributes["parentTitle"],
            fallback: item.attributes["parentTitleSort"],
            unknown: "未知艺术家"
        )
        cache(itemID: itemID, partKey: nil, thumbPath: item.attributes["thumb"] ?? item.attributes["parentThumb"])
        return Album(
            id: globalID(itemID),
            name: bestText(item.attributes["title"], fallback: nil, unknown: "未知专辑"),
            artist: artist,
            displayArtist: artist,
            year: Int(item.attributes["year"] ?? ""),
            songCount: Int(item.attributes["leafCount"] ?? item.attributes["childCount"] ?? "")
        )
    }

    /// 映射 Plex Artist 到通用 Artist。
    private func mapArtist(_ item: PlexXMLItem) -> Artist {
        let itemID = item.attributes["ratingKey"] ?? item.attributes["key"] ?? item.attributes["title"] ?? UUID().uuidString
        cache(itemID: itemID, partKey: nil, thumbPath: item.attributes["thumb"])
        return Artist(
            id: globalID(itemID),
            name: bestText(item.attributes["title"], fallback: nil, unknown: "未知艺术家"),
            albumCount: Int(item.attributes["childCount"] ?? "")
        )
    }

    /// 映射 Plex Playlist 到通用 Playlist。
    private func mapPlaylist(_ item: PlexXMLItem) -> Playlist {
        let itemID = item.attributes["ratingKey"] ?? item.attributes["key"] ?? UUID().uuidString
        cache(itemID: itemID, partKey: nil, thumbPath: item.attributes["thumb"])
        return Playlist(
            id: globalID(itemID),
            name: bestText(item.attributes["title"], fallback: nil, unknown: "播放列表"),
            library: providerType.rawValue,
            songCount: Int(item.attributes["leafCount"] ?? item.attributes["viewedLeafCount"] ?? ""),
            isSmart: item.attributes["smart"] == "1",
            owner: item.attributes["composite"] ?? item.attributes["username"]
        )
    }

    /// 缓存 Plex item 的播放地址和封面路径，供同步 URL 方法使用。
    private func cache(itemID: String, partKey: String?, thumbPath: String?) {
        if let partKey, !partKey.isEmpty {
            partKeyByItemID[itemID] = partKey
        }
        if let thumbPath, !thumbPath.isEmpty {
            thumbPathByItemID[itemID] = thumbPath
        }
    }

    /// 读取缓存中的 Plex part key。
    private func cachedPartKey(for itemID: String) -> String? {
        partKeyByItemID[itemID]
    }

    /// 读取缓存中的 Plex 封面路径。
    private func cachedThumbPath(for itemID: String) -> String? {
        thumbPathByItemID[itemID]
    }

    /// 生成封面 URL；没有缓存时使用 metadata thumb 兜底。
    private func imageURL(itemID: String) -> URL? {
        let path = cachedThumbPath(for: itemID) ?? "library/metadata/\(itemID)/thumb"
        return makeURL(path: path, query: [], includeTokenQuery: true)
    }

    /// 给远端 ID 加上 provider 与服务器前缀，避免不同服务之间 ID 冲突。
    private func globalID(_ remoteID: String) -> String {
        "\(providerType.rawValue):\(profile.id.uuidString):\(remoteID)"
    }

    /// 从通用 ID 中还原 Plex 远端 ID。
    private func remoteID(from id: String) -> String {
        let prefix = "\(providerType.rawValue):\(profile.id.uuidString):"
        guard id.hasPrefix(prefix) else { return id }
        return String(id.dropFirst(prefix.count))
    }

    /// 把 Plex 毫秒时长转换为秒。
    private func duration(from value: String?) -> TimeInterval {
        guard let value, let milliseconds = Double(value) else { return 0 }
        return milliseconds / 1000
    }

    /// 把 Plex bitrate 规范成 bps。
    private func bitrate(from value: String?) -> Int? {
        guard let value, let raw = Int(value) else { return nil }
        return raw < 10_000 ? raw * 1000 : raw
    }

    /// 从 Plex 文件路径中提取可读文件名，作为乱码标题的兜底。
    private func fileTitle(from path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let trimmed = name.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 返回可展示文本；当 Plex 元数据全是问号时使用兜底文本。
    private func bestText(_ primary: String?, fallback: String?, unknown: String) -> String {
        if let text = bestOptionalText(primary) { return text }
        if let text = bestOptionalText(fallback) { return text }
        return unknown
    }

    /// 返回可选可展示文本；过滤空白和明显的问号占位符。
    private func bestOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isQuestionPlaceholder(trimmed) else { return nil }
        return trimmed
    }

    /// 判断字符串是否基本由问号和分隔符构成。
    private func isQuestionPlaceholder(_ value: String) -> Bool {
        let visible = value.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !visible.isEmpty else { return false }
        let questionCount = visible.filter { $0 == "?" || $0 == "？" }.count
        let allowedCount = visible.filter { scalar in
            scalar == "?" || scalar == "？" || scalar == "." || scalar == "-" || scalar == "_" || scalar == "·"
        }.count
        return questionCount > 0 && allowedCount == visible.count
    }

    /// 发起 Plex XML 请求并解析 MediaContainer。
    private func requestXML(
        path: String,
        query: [URLQueryItem],
        start: Int? = nil,
        size: Int? = nil
    ) async throws -> PlexMediaContainer {
        guard token?.isEmpty == false else { throw PlexMusicError.missingToken }

        do {
            return try await performXMLRequest(
                path: path,
                query: query,
                start: start,
                size: size,
                using: activeConnectionProfile
            )
        } catch {
            guard shouldRetryAfterRefreshingConnection(error) else { throw error }
            return try await refreshConnectionAndRetry(
                path: path,
                query: query,
                start: start,
                size: size,
                originalError: error
            )
        }
    }

    /// 使用指定连接地址发起 Plex XML 请求并解析结果。
    private func performXMLRequest(
        path: String,
        query: [URLQueryItem],
        start: Int?,
        size: Int?,
        using requestProfile: ServerProfile
    ) async throws -> PlexMediaContainer {
        guard let url = makeURL(path: path, query: query, includeTokenQuery: true, profile: requestProfile) else {
            throw PlexMusicError.missingBaseURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 14
        applyHeaders(to: &request)
        if let start {
            request.setValue(String(start), forHTTPHeaderField: "X-Plex-Container-Start")
        }
        if let size {
            request.setValue(String(size), forHTTPHeaderField: "X-Plex-Container-Size")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw PlexMusicError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw PlexMusicError.network("服务器响应无效") }
        guard (200..<300).contains(http.statusCode) else { throw PlexMusicError.http(http.statusCode) }

        do {
            return try PlexXMLItemParser.parse(data)
        } catch {
            throw PlexMusicError.decoding(error.localizedDescription)
        }
    }

    /// 判断当前错误是否适合通过刷新 Plex 连接地址后重试。
    private func shouldRetryAfterRefreshingConnection(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        guard accountToken?.isEmpty == false || token?.isEmpty == false else { return false }
        guard profile.plexMachineIdentifier?.isEmpty == false || !profile.host.isEmpty else { return false }
        if case PlexMusicError.network = error { return true }
        if case PlexMusicError.http = error { return true }
        return false
    }

    /// 拉取最新 Plex 服务器连接列表，并按当前连接类型优先重试。
    private func refreshConnectionAndRetry(
        path: String,
        query: [URLQueryItem],
        start: Int?,
        size: Int?,
        originalError: Error
    ) async throws -> PlexMediaContainer {
        let candidates: [ServerProfile]
        do {
            candidates = try await refreshedConnectionProfiles()
        } catch {
            throw originalError
        }
        var lastError: Error = originalError
        for candidate in candidates {
            do {
                let container = try await performXMLRequest(
                    path: path,
                    query: query,
                    start: start,
                    size: size,
                    using: candidate
                )
                applyActiveConnection(candidate)
                return container
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    /// 需要时刷新连接地址；播放前使用，避免长期缓存旧的 plex.direct 地址。
    private func refreshConnectionIfStale() async throws {
        if let lastConnectionRefreshAt,
           Date().timeIntervalSince(lastConnectionRefreshAt) < 600 {
            return
        }
        let candidates = try await refreshedConnectionProfiles()
        guard let first = candidates.first else { return }
        applyActiveConnection(first)
    }

    /// 从 Plex 账号资源列表中生成当前服务器的最新连接候选。
    private func refreshedConnectionProfiles() async throws -> [ServerProfile] {
        let refreshToken = accountToken?.nilIfBlank ?? token?.nilIfBlank
        guard let refreshToken else { return [] }
        let server = try await PlexAccountService.refreshedServer(for: profile, accountToken: refreshToken)
        if !server.token.isEmpty {
            token = server.token
        }
        return preferredConnections(server.connections).map { connection in
            var updated = profile
            updated.scheme = connection.scheme
            updated.host = connection.host
            updated.port = connection.port
            updated.name = profile.name.isEmpty ? server.name : profile.name
            updated.username = profile.username
            updated.plexMachineIdentifier = server.id
            return updated
        }
    }

    /// 将已验证可用的连接设为当前连接，同时更新 profile 供外部保存。
    private func applyActiveConnection(_ updated: ServerProfile) {
        activeConnectionProfile = updated
        profile = updated
        lastConnectionRefreshAt = Date()
    }

    /// 按用户上次选择的连接类型排序：本地、远程直连和 Relay 各自尽量保持原选择。
    private func preferredConnections(_ connections: [PlexServerConnection]) -> [PlexServerConnection] {
        let current = activeConnectionProfile
        return connections.sorted { lhs, rhs in
            let left = connectionScore(lhs, current: current)
            let right = connectionScore(rhs, current: current)
            if left != right { return left < right }
            return lhs.displayURL < rhs.displayURL
        }
    }

    /// 计算连接候选与当前连接的接近程度，分数越低越优先。
    private func connectionScore(_ connection: PlexServerConnection, current: ServerProfile) -> Int {
        var score = 0
        if connection.host != current.host { score += 20 }
        if connection.port != current.port { score += 4 }
        if connection.scheme != current.scheme { score += 2 }
        if current.host.contains("plex.direct") && !connection.host.contains("plex.direct") { score += 8 }
        if !current.host.contains("plex.direct") && connection.host.contains("plex.direct") { score += 3 }
        if connection.isRelay { score += 6 }
        if !connection.isLocal && !current.host.contains("plex.direct") { score += 2 }
        return score
    }

    /// 构造 Plex API 或资源 URL。
    private func makeURL(path: String, query: [URLQueryItem], includeTokenQuery: Bool) -> URL? {
        makeURL(path: path, query: query, includeTokenQuery: includeTokenQuery, profile: activeConnectionProfile)
    }

    /// 使用指定 profile 构造 Plex API 或资源 URL。
    private func makeURL(
        path: String,
        query: [URLQueryItem],
        includeTokenQuery: Bool,
        profile requestProfile: ServerProfile
    ) -> URL? {
        guard var url = requestProfile.baseURL else { return nil }
        path
            .split(separator: "/", omittingEmptySubsequences: true)
            .forEach { url.appendPathComponent(String($0)) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = query
        if includeTokenQuery, let token, !token.isEmpty {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    /// 设置 Plex 客户端识别与 token 请求头。
    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("SynoMusic", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("1.5.4", forHTTPHeaderField: "X-Plex-Version")
        request.setValue(deviceID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("iOS", forHTTPHeaderField: "X-Plex-Platform")
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
    }

    /// 判断 Plex 是否需要宽松证书处理；Plex Media Server 的 HTTPS 地址常使用自签名或与当前地址不匹配的证书。
    private static func shouldUsePermissiveCertificateHandling(profile: ServerProfile) -> Bool {
        profile.providerType == .plex
    }

    /// 返回稳定设备 ID，避免每次启动都在 Plex 侧识别为新客户端。
    private static func stableDeviceID() -> String {
        let key = "syno.plex.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

/// Plex XML 响应中的 MediaContainer。
private struct PlexMediaContainer: Sendable {
    let attributes: [String: String]
    let items: [PlexXMLItem]
}

/// Plex XML 响应中的 Directory / Track / Playlist 条目。
private struct PlexXMLItem: Sendable {
    let elementName: String
    var attributes: [String: String]
    var mediaAttributes: [String: String]?
    var partAttributes: [String: String]?
}

/// Plex XML 解析器；只收集音乐列表需要的属性，不解析正文。
private final class PlexXMLItemParser: NSObject, XMLParserDelegate {
    private var containerAttributes: [String: String] = [:]
    private var items: [PlexXMLItem] = []
    private var currentItem: PlexXMLItem?

    /// 解析 XML Data 并返回条目容器。
    static func parse(_ data: Data) throws -> PlexMediaContainer {
        let delegate = PlexXMLItemParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? PlexMusicError.decoding("XML 解析失败")
        }
        return PlexMediaContainer(attributes: delegate.containerAttributes, items: delegate.items)
    }

    /// 读取开始标签上的属性。
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "MediaContainer":
            containerAttributes = attributeDict
        case "Directory", "Track", "Playlist":
            currentItem = PlexXMLItem(elementName: elementName, attributes: attributeDict)
        case "Media":
            currentItem?.mediaAttributes = attributeDict
        case "Part":
            currentItem?.partAttributes = attributeDict
        default:
            break
        }
    }

    /// 在可映射条目结束时提交当前条目。
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard Self.collectableElements.contains(elementName),
              let item = currentItem,
              item.elementName == elementName else { return }
        items.append(item)
        currentItem = nil
    }

    private static let collectableElements: Set<String> = ["Directory", "Track", "Playlist"]
}

/// 允许用户显式开启的 Plex 自签名证书连接。
private final class PlexPermissiveCertDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    /// 处理 session 级证书挑战。
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        complete(challenge, completionHandler: completionHandler)
    }

    /// 处理 task 级证书挑战。
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        complete(challenge, completionHandler: completionHandler)
    }

    /// 信任用户已在配置里允许的服务器证书。
    private func complete(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
