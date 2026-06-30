import Foundation

/// Jellyfin / Emby 兼容接口错误。
enum MediaBrowserError: LocalizedError {
    case unsupportedProvider
    case missingBaseURL
    case notAuthenticated
    case noMusicLibrary
    case http(Int)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "该音乐源正在接入中，当前版本暂不可连接。"
        case .missingBaseURL:
            return "服务器地址无效"
        case .notAuthenticated:
            return "登录状态无效，请重新登录。"
        case .noMusicLibrary:
            return "没有找到可用的音乐库。"
        case .http(let code):
            return "服务器返回错误：HTTP \(code)"
        case .network(let message):
            return message
        case .decoding(let message):
            return "解析服务器响应失败：\(message)"
        }
    }
}

/// Jellyfin / Emby 共用的音乐库客户端；只查询音乐相关条目。
final class MediaBrowserMusicLibraryClient: MusicLibraryClient, @unchecked Sendable {
    let providerType: MusicProviderType
    let profile: ServerProfile

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let deviceID: String
    private var token: String?
    private var userID: String?
    private var serverID: String?

    init(
        providerType: MusicProviderType,
        profile: ServerProfile,
        token: String? = nil,
        userID: String? = nil,
        serverID: String? = nil
    ) {
        self.providerType = providerType
        self.profile = profile
        self.token = token
        self.userID = userID
        self.serverID = serverID
        self.deviceID = Self.stableDeviceID()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 14
        config.timeoutIntervalForResource = 30
        if profile.ignoreInvalidCertificate && profile.scheme == .https {
            self.session = URLSession(configuration: config, delegate: MediaBrowserPermissiveCertDelegate(), delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
    }

    /// 使用用户名密码登录 Jellyfin / Emby，并保存本次会话 token。
    func authenticate(password: String) async throws {
        guard providerType == .jellyfin || providerType == .emby else {
            throw MediaBrowserError.unsupportedProvider
        }

        do {
            let auth = try await authenticateWithJSON(password: password)
            apply(auth)
        } catch {
            guard providerType == .emby else { throw error }
            let auth = try await authenticateWithForm(password: password)
            apply(auth)
        }
        guard token != nil, userID != nil else {
            throw MediaBrowserError.notAuthenticated
        }
    }

    /// 获取音乐库列表，只返回 CollectionType 为 music 的库。
    func loadLibraries() async throws -> [MusicLibrary] {
        guard let userID else { throw MediaBrowserError.notAuthenticated }
        let payload: MBItemList = try await request(path: "Users/\(userID)/Views", query: [])
        let musicItems = payload.Items.filter { item in
            item.CollectionType == "music"
        }
        let libraries = musicItems.map { item in
            MusicLibrary(id: item.Id, name: item.Name ?? "Music", providerType: providerType, isDefault: item.Id == musicItems.first?.Id)
        }
        guard !libraries.isEmpty else { throw MediaBrowserError.noMusicLibrary }
        return libraries
    }

    /// 加载首页需要的专辑与艺术家摘要。
    func loadHomeSnapshot() async throws -> LibraryHomeSnapshot {
        let rootID = try await defaultMusicLibraryID()
        async let recent = listAlbums(parentID: rootID, limit: 18, offset: 0, sortBy: "DateCreated", sortDirection: "Descending")
        async let all = listAlbums(parentID: rootID, limit: 60, offset: 0, sortBy: "SortName", sortDirection: "Ascending")
        async let artists = listArtists(parentID: rootID, limit: 30, offset: 0)
        return try await LibraryHomeSnapshot(recentAlbums: recent, albums: all, artists: artists)
    }

    /// 列出当前默认音乐库中的歌曲。
    func listSongs(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Song] {
        let rootID = try await defaultMusicLibraryID()
        return try await listSongs(parentID: rootID, limit: limit, offset: offset, sortBy: sortBy, sortDirection: sortDirection)
    }

    /// 列出当前默认音乐库中的专辑。
    func listAlbums(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Album] {
        let rootID = try await defaultMusicLibraryID()
        return try await listAlbums(parentID: rootID, limit: limit, offset: offset, sortBy: sortBy, sortDirection: sortDirection)
    }

    /// 列出当前默认音乐库中的艺术家。
    func listArtists(limit: Int, offset: Int) async throws -> [Artist] {
        let rootID = try await defaultMusicLibraryID()
        return try await listArtists(parentID: rootID, limit: limit, offset: offset)
    }

    /// 列出当前默认音乐库中的音频播放列表。
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist] {
        let rootID = try await defaultMusicLibraryID()
        let items = try await listItems(
            parentID: rootID,
            includeItemTypes: "Playlist",
            mediaTypes: "Audio",
            limit: limit,
            offset: offset,
            sortBy: "SortName",
            sortDirection: "Ascending"
        )
        return items.map(mapPlaylist)
    }

    /// 列出 Jellyfin / Emby 播放列表内的音频歌曲。
    func playlistSongs(playlist: Playlist) async throws -> [Song] {
        let playlistID = remoteID(from: playlist.id)
        return try await listSongs(parentID: playlistID, limit: 1000, offset: 0, sortBy: "SortName", sortDirection: "Ascending")
    }

    /// 搜索当前默认音乐库中的歌曲。
    func searchSongs(keyword: String, limit: Int, offset: Int) async throws -> [Song] {
        let rootID = try await defaultMusicLibraryID()
        let items = try await listItems(
            parentID: rootID,
            includeItemTypes: "Audio",
            mediaTypes: "Audio",
            limit: limit,
            offset: offset,
            sortBy: "SortName",
            sortDirection: "Ascending",
            extra: [URLQueryItem(name: "SearchTerm", value: keyword)]
        )
        return items.map(mapSong)
    }

    /// 随机抓取当前默认音乐库中的歌曲。
    func randomSongs(count: Int) async throws -> [Song] {
        let rootID = try await defaultMusicLibraryID()
        let items = try await listItems(
            parentID: rootID,
            includeItemTypes: "Audio",
            mediaTypes: "Audio",
            limit: max(count * 4, 200),
            offset: 0,
            sortBy: "Random",
            sortDirection: "Ascending"
        )
        return Array(items.map(mapSong).shuffled().prefix(count))
    }

    /// 列出指定专辑中的歌曲。
    func albumSongs(album: Album) async throws -> [Song] {
        let albumID = remoteID(from: album.id)
        return try await listSongs(parentID: albumID, limit: 1000, offset: 0, sortBy: "ParentIndexNumber,IndexNumber,SortName", sortDirection: "Ascending")
    }

    /// 返回专辑封面 URL。
    func albumCoverURL(album: Album) -> URL? {
        imageURL(itemID: remoteID(from: album.id))
    }

    /// 返回歌曲封面 URL。
    func songCoverURL(song: Song) -> URL? {
        imageURL(itemID: remoteID(from: song.id))
    }

    /// 返回歌曲播放 URL；原始音质直连，压缩音质请求服务器转码。
    func streamURL(song: Song, quality: AudioQuality) -> URL? {
        let id = remoteID(from: song.id)
        switch quality {
        case .original:
            return makeURL(
                path: "Audio/\(id)/stream",
                query: [URLQueryItem(name: "static", value: "true")],
                includeTokenQuery: true
            )
        case .high, .standard:
            let bitrate = quality == .high ? "320000" : "128000"
            return makeURL(
                path: "Audio/\(id)/universal",
                query: [
                    URLQueryItem(name: "UserId", value: userID),
                    URLQueryItem(name: "DeviceId", value: deviceID),
                    URLQueryItem(name: "MaxStreamingBitrate", value: bitrate),
                    URLQueryItem(name: "Container", value: "mp3,aac,m4a,flac,wav,ogg"),
                    URLQueryItem(name: "AudioCodec", value: "mp3"),
                    URLQueryItem(name: "TranscodingContainer", value: "mp3"),
                    URLQueryItem(name: "PlaySessionId", value: UUID().uuidString)
                ],
                includeTokenQuery: true
            )
        }
    }

    /// Jellyfin / Emby 歌词 API 差异较多，第一版交给在线歌词兜底。
    func lyrics(for song: Song) async throws -> [LyricLine] {
        []
    }

    /// 当前版本只清理本地会话，不主动调用服务端登出。
    func logout() async {
        token = nil
        userID = nil
        serverID = nil
    }

    /// 用 JSON 请求体执行用户认证。
    private func authenticateWithJSON(password: String) async throws -> MBAuthResponse {
        let body = try JSONEncoder().encode(MBAuthRequest(Username: profile.username, Pw: password))
        return try await request(
            path: "Users/AuthenticateByName",
            query: [],
            method: "POST",
            body: body,
            contentType: "application/json",
            authenticated: false
        )
    }

    /// 用表单请求体兜底 Emby 认证，兼容部分服务端配置。
    private func authenticateWithForm(password: String) async throws -> MBAuthResponse {
        let username = profile.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profile.username
        let pw = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        let body = Data("Username=\(username)&Pw=\(pw)".utf8)
        return try await request(
            path: "Users/AuthenticateByName",
            query: [],
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded",
            authenticated: false
        )
    }

    /// 保存认证响应中的 token 和用户 ID。
    private func apply(_ auth: MBAuthResponse) {
        token = auth.AccessToken
        userID = auth.User?.Id ?? auth.SessionInfo?.UserId
        serverID = auth.ServerId ?? auth.User?.ServerId
    }

    /// 读取默认音乐库 ID。
    private func defaultMusicLibraryID() async throws -> String {
        guard let id = try await loadLibraries().first?.id else {
            throw MediaBrowserError.noMusicLibrary
        }
        return id
    }

    /// 按父级、类型和排序查询 Items。
    private func listItems(
        parentID: String?,
        includeItemTypes: String,
        mediaTypes: String? = nil,
        limit: Int,
        offset: Int,
        sortBy: String,
        sortDirection: String,
        extra: [URLQueryItem] = []
    ) async throws -> [MBItem] {
        guard let userID else { throw MediaBrowserError.notAuthenticated }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: includeItemTypes),
            URLQueryItem(name: "StartIndex", value: String(offset)),
            URLQueryItem(name: "Limit", value: String(limit)),
            URLQueryItem(name: "SortBy", value: sortBy),
            URLQueryItem(name: "SortOrder", value: sortDirection),
            URLQueryItem(name: "Fields", value: "BasicSyncInfo,Genres,MediaSources,Path,ProviderIds,SortName")
        ]
        if let parentID {
            query.append(URLQueryItem(name: "ParentId", value: parentID))
        }
        if let mediaTypes {
            query.append(URLQueryItem(name: "MediaTypes", value: mediaTypes))
        }
        query.append(contentsOf: extra)
        let payload: MBItemList = try await request(path: "Users/\(userID)/Items", query: query)
        return payload.Items
    }

    /// 查询歌曲 Items 并映射到通用模型。
    private func listSongs(parentID: String?, limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Song] {
        let items = try await listItems(
            parentID: parentID,
            includeItemTypes: "Audio",
            mediaTypes: "Audio",
            limit: limit,
            offset: offset,
            sortBy: normalizedSort(sortBy),
            sortDirection: normalizedDirection(sortDirection)
        )
        return items.map(mapSong)
    }

    /// 查询专辑 Items 并映射到通用模型。
    private func listAlbums(parentID: String?, limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Album] {
        let items = try await listItems(
            parentID: parentID,
            includeItemTypes: "MusicAlbum",
            limit: limit,
            offset: offset,
            sortBy: normalizedSort(sortBy),
            sortDirection: normalizedDirection(sortDirection)
        )
        return items.map(mapAlbum)
    }

    /// 查询艺术家 Items 并映射到通用模型。
    private func listArtists(parentID: String?, limit: Int, offset: Int) async throws -> [Artist] {
        let items = try await listItems(
            parentID: parentID,
            includeItemTypes: "MusicArtist",
            limit: limit,
            offset: offset,
            sortBy: "SortName",
            sortDirection: "Ascending"
        )
        return items.map(mapArtist)
    }

    /// 把 Jellyfin / Emby 排序字段归一到 MediaBrowser 命名。
    private func normalizedSort(_ sortBy: String) -> String {
        switch sortBy {
        case "name", "track": return "SortName"
        case "recently_added": return "DateCreated"
        case "random": return "Random"
        default: return sortBy
        }
    }

    /// 把 ASC/DESC 归一到 MediaBrowser 命名。
    private func normalizedDirection(_ direction: String) -> String {
        direction.uppercased() == "DESC" ? "Descending" : "Ascending"
    }

    /// 映射 Audio item 到通用 Song。
    private func mapSong(_ item: MBItem) -> Song {
        Song(
            id: globalID(item.Id),
            title: item.Name ?? "未知歌曲",
            album: item.Album,
            artist: item.Artists?.joined(separator: ", ") ?? item.ArtistItems?.map(\.Name).joined(separator: ", "),
            albumArtist: item.AlbumArtist ?? item.AlbumArtists?.map(\.Name).joined(separator: ", "),
            genre: item.Genres?.first,
            composer: nil,
            trackNumber: item.IndexNumber,
            discNumber: item.ParentIndexNumber,
            year: item.ProductionYear,
            duration: TimeInterval(item.RunTimeTicks ?? 0) / 10_000_000,
            bitrate: item.Bitrate,
            codec: item.Container,
            filesize: item.Size,
            path: item.Path,
            rating: nil
        )
    }

    /// 映射 MusicAlbum item 到通用 Album。
    private func mapAlbum(_ item: MBItem) -> Album {
        let artist = item.AlbumArtist
            ?? item.AlbumArtists?.map(\.Name).joined(separator: ", ")
            ?? item.ArtistItems?.map(\.Name).joined(separator: ", ")
            ?? "未知艺术家"
        return Album(
            id: globalID(item.Id),
            name: item.Name ?? "未知专辑",
            artist: artist,
            displayArtist: artist,
            year: item.ProductionYear,
            songCount: item.ChildCount
        )
    }

    /// 映射 MusicArtist item 到通用 Artist。
    private func mapArtist(_ item: MBItem) -> Artist {
        Artist(id: globalID(item.Id), name: item.Name ?? "未知艺术家", albumCount: item.ChildCount)
    }

    /// 映射 Playlist item 到通用 Playlist。
    private func mapPlaylist(_ item: MBItem) -> Playlist {
        Playlist(
            id: globalID(item.Id),
            name: item.Name ?? "播放列表",
            library: providerType.rawValue,
            songCount: item.ChildCount,
            isSmart: false,
            owner: nil
        )
    }

    /// 生成封面 URL。
    private func imageURL(itemID: String) -> URL? {
        makeURL(path: "Items/\(itemID)/Images/Primary", query: [], includeTokenQuery: true)
    }

    /// 给远端 item ID 加上 provider 和服务器前缀，避免不同服务之间 ID 冲突。
    private func globalID(_ remoteID: String) -> String {
        "\(providerType.rawValue):\(profile.id.uuidString):\(remoteID)"
    }

    /// 从全局 ID 还原远端 item ID。
    private func remoteID(from id: String) -> String {
        let prefix = "\(providerType.rawValue):\(profile.id.uuidString):"
        guard id.hasPrefix(prefix) else { return id }
        return String(id.dropFirst(prefix.count))
    }

    /// 发起 JSON 请求并解码响应。
    private func request<Payload: Decodable>(
        path: String,
        query: [URLQueryItem],
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        authenticated: Bool = true
    ) async throws -> Payload {
        guard let url = makeURL(path: path, query: query, includeTokenQuery: false) else {
            throw MediaBrowserError.missingBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 14
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request, authenticated: authenticated)
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw MediaBrowserError.network("请求已取消")
        } catch {
            throw MediaBrowserError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw MediaBrowserError.network("服务器响应无效") }
        guard (200..<300).contains(http.statusCode) else { throw MediaBrowserError.http(http.statusCode) }

        do {
            return try decoder.decode(Payload.self, from: data)
        } catch {
            throw MediaBrowserError.decoding(error.localizedDescription)
        }
    }

    /// 构造 API URL，Emby 默认使用 `/emby` 前缀。
    private func makeURL(path: String, query: [URLQueryItem], includeTokenQuery: Bool) -> URL? {
        guard var url = profile.baseURL else { return nil }
        if providerType == .emby {
            url.appendPathComponent("emby")
        }
        path.split(separator: "/").forEach { component in
            url.appendPathComponent(String(component))
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = query
        if includeTokenQuery, let token {
            items.append(URLQueryItem(name: "api_key", value: token))
        }
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    /// 设置 MediaBrowser 认证头。
    private func applyHeaders(to request: inout URLRequest, authenticated: Bool) {
        request.setValue(clientHeader(includeToken: false), forHTTPHeaderField: "X-Emby-Authorization")
        guard authenticated, let token else { return }
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(clientHeader(includeToken: true), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
    }

    /// 构造 Jellyfin / Emby 识别客户端所需的 MediaBrowser header。
    private func clientHeader(includeToken: Bool) -> String {
        var segments = [
            "MediaBrowser Client=\"SynoMusic\"",
            "Device=\"iOS\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"1.5.2\""
        ]
        if includeToken, let token {
            segments.append("Token=\"\(token)\"")
        }
        return segments.joined(separator: ", ")
    }

    /// 返回稳定设备 ID，避免每次启动都在服务端生成新设备。
    private static func stableDeviceID() -> String {
        let key = "syno.mediabrowser.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

/// 允许用户显式开启的自签名证书连接。
private final class MediaBrowserPermissiveCertDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
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

private struct MBAuthRequest: Encodable {
    let Username: String
    let Pw: String
}

private struct MBAuthResponse: Decodable {
    let User: MBUser?
    let SessionInfo: MBSession?
    let AccessToken: String?
    let ServerId: String?
}

private struct MBUser: Decodable {
    let Id: String?
    let Name: String?
    let ServerId: String?
}

private struct MBSession: Decodable {
    let Id: String?
    let UserId: String?
}

private struct MBItemList: Decodable {
    let Items: [MBItem]
    let TotalRecordCount: Int?
}

private struct MBNameID: Decodable {
    let Name: String
    let Id: String?
}

private struct MBItem: Decodable {
    let Id: String
    let Name: String?
    let itemType: String?
    let MediaType: String?
    let CollectionType: String?
    let Album: String?
    let AlbumId: String?
    let AlbumArtist: String?
    let Artists: [String]?
    let ArtistItems: [MBNameID]?
    let AlbumArtists: [MBNameID]?
    let Genres: [String]?
    let RunTimeTicks: Int64?
    let IndexNumber: Int?
    let ParentIndexNumber: Int?
    let ProductionYear: Int?
    let ChildCount: Int?
    let Container: String?
    let Size: Int64?
    let Path: String?
    let Bitrate: Int?
    let ImageTags: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case Id
        case Name
        case itemType = "Type"
        case MediaType
        case CollectionType
        case Album
        case AlbumId
        case AlbumArtist
        case Artists
        case ArtistItems
        case AlbumArtists
        case Genres
        case RunTimeTicks
        case IndexNumber
        case ParentIndexNumber
        case ProductionYear
        case ChildCount
        case Container
        case Size
        case Path
        case Bitrate
        case ImageTags
    }
}
