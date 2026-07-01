import Foundation

/// WebDAV 音乐源错误。
enum WebDAVMusicError: LocalizedError {
    case missingBaseURL
    case missingPassword
    case http(Int)
    case invalidResponse
    case xml(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "服务器地址无效"
        case .missingPassword:
            return "WebDAV 密码不能为空。"
        case .http(let code):
            return "服务器返回错误：HTTP \(code)"
        case .invalidResponse:
            return "服务器响应无效"
        case .xml(let message):
            return "解析服务器响应失败：\(message)"
        }
    }
}

/// WebDAV 目录浏览项，用于添加服务器时让用户选择音乐目录。
struct WebDAVDirectoryItem: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let isDirectory: Bool

    var id: String { path }
}

/// WebDAV 音乐库客户端；使用 PROPFIND 扫描目录，仅接入音频文件。
final class WebDAVMusicLibraryClient: MusicLibraryClient, @unchecked Sendable {
    let providerType: MusicProviderType = .webDAV
    let profile: ServerProfile

    private let session: URLSession
    private let maxScanDepth = 8
    private var password: String
    private var tracksCache: [FileMusicTrack]?

    init(profile: ServerProfile, password: String = "") {
        self.profile = profile
        self.password = password
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        if profile.ignoreInvalidCertificate && profile.scheme == .https {
            self.session = URLSession(configuration: config, delegate: WebDAVPermissiveCertDelegate(), delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
    }

    /// 校验 WebDAV 根目录是否可访问。
    func authenticate(password: String) async throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WebDAVMusicError.missingPassword }
        self.password = trimmed
        _ = try await listDirectory(rootURL())
        tracksCache = nil
    }

    /// 读取指定 WebDAV 路径下的目录和音频文件，供配置页浏览选择。
    func browseDirectory(path: String) async throws -> [WebDAVDirectoryItem] {
        let directoryURL = url(forWebDAVPath: path)
        return try await listDirectory(directoryURL)
            .filter { !sameWebDAVPath($0.url, directoryURL) }
            .filter { $0.isDirectory || FileMusicLibraryIndex.isAudioFile($0.url) }
            .map { entry in
                WebDAVDirectoryItem(
                    path: webDAVPath(from: entry.url),
                    name: FileMusicLibraryIndex.cleanName(entry.url.lastPathComponent, unknown: entry.isDirectory ? "未命名目录" : "未知歌曲"),
                    isDirectory: entry.isDirectory
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// 返回 WebDAV 根目录作为一个音乐库。
    func loadLibraries() async throws -> [MusicLibrary] {
        [
            MusicLibrary(
                id: rootPath(),
                name: profile.musicLibraryName ?? profile.musicLibraryID ?? "WebDAV",
                providerType: providerType,
                isDefault: true
            )
        ]
    }

    /// 加载首页需要的专辑与艺人摘要。
    func loadHomeSnapshot() async throws -> LibraryHomeSnapshot {
        let tracks = try await loadTracks()
        let albums = FileMusicLibraryIndex.albums(from: tracks, providerType: providerType, profile: profile)
        let artists = FileMusicLibraryIndex.artists(from: tracks, providerType: providerType, profile: profile)
        return LibraryHomeSnapshot(
            recentAlbums: Array(albums.prefix(18)),
            albums: Array(albums.prefix(60)),
            artists: Array(artists.prefix(30))
        )
    }

    /// 列出 WebDAV 音乐文件。
    func listSongs(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Song] {
        let songs = FileMusicLibraryIndex.sortedSongs(
            from: try await loadTracks(),
            providerType: providerType,
            profile: profile,
            sortBy: sortBy,
            sortDirection: sortDirection
        )
        return FileMusicLibraryIndex.page(songs, limit: limit, offset: offset)
    }

    /// 列出根据目录聚合出的专辑。
    func listAlbums(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Album] {
        let albums = FileMusicLibraryIndex.albums(from: try await loadTracks(), providerType: providerType, profile: profile)
        return FileMusicLibraryIndex.page(albums, limit: limit, offset: offset)
    }

    /// 列出根据目录聚合出的艺人。
    func listArtists(limit: Int, offset: Int) async throws -> [Artist] {
        let artists = FileMusicLibraryIndex.artists(from: try await loadTracks(), providerType: providerType, profile: profile)
        return FileMusicLibraryIndex.page(artists, limit: limit, offset: offset)
    }

    /// WebDAV 第一版不读取服务端播放列表。
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist] {
        []
    }

    /// WebDAV 第一版没有远端播放列表歌曲。
    func playlistSongs(playlist: Playlist) async throws -> [Song] {
        []
    }

    /// 在本地索引里搜索歌曲、艺人和专辑。
    func searchSongs(keyword: String, limit: Int, offset: Int) async throws -> [Song] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let filtered = try await loadTracks().filter { track in
            track.title.lowercased().contains(q)
                || (track.album ?? "").lowercased().contains(q)
                || (track.artist ?? "").lowercased().contains(q)
        }
        let songs = filtered.map { FileMusicLibraryIndex.song(from: $0, providerType: providerType, profile: profile) }
        return FileMusicLibraryIndex.page(songs, limit: limit, offset: offset)
    }

    /// 从 WebDAV 索引中随机取歌。
    func randomSongs(count: Int) async throws -> [Song] {
        Array(try await loadTracks().shuffled().prefix(count))
            .map { FileMusicLibraryIndex.song(from: $0, providerType: providerType, profile: profile) }
    }

    /// 返回指定专辑下的歌曲。
    func albumSongs(album: Album) async throws -> [Song] {
        let key = FileMusicLibraryIndex.remoteID(from: album.id, providerType: providerType, profile: profile)
            .replacingOccurrences(of: "album:", with: "")
        let filtered = try await loadTracks().filter { "\($0.album ?? "未知专辑")|\($0.artist ?? "未知艺术家")" == key }
        return filtered.map { FileMusicLibraryIndex.song(from: $0, providerType: providerType, profile: profile) }
    }

    /// WebDAV 不强制约定封面位置，交给默认封面和线上封面搜索兜底。
    func albumCoverURL(album: Album) -> URL? {
        nil
    }

    /// WebDAV 不强制约定封面位置，交给默认封面和线上封面搜索兜底。
    func songCoverURL(song: Song) -> URL? {
        nil
    }

    /// 返回带 Basic Auth userinfo 的 WebDAV 直连播放 URL。
    func streamURL(song: Song, quality: AudioQuality) -> URL? {
        let remoteID = FileMusicLibraryIndex.remoteID(from: song.id, providerType: providerType, profile: profile)
        guard let url = URL(string: remoteID) else { return nil }
        return authenticatedURL(url)
    }

    /// WebDAV 不提供统一歌词接口。
    func lyrics(for song: Song) async throws -> [LyricLine] {
        []
    }

    /// 清空 WebDAV 本地索引缓存。
    func logout() async {
        tracksCache = nil
        password = ""
    }

    /// 懒加载并缓存 WebDAV 文件索引。
    private func loadTracks() async throws -> [FileMusicTrack] {
        if let tracksCache { return tracksCache }
        let tracks = try await scanDirectory(rootURL(), depth: 0)
        tracksCache = tracks
        return tracks
    }

    /// 递归扫描 WebDAV 目录并提取音频文件。
    private func scanDirectory(_ directoryURL: URL, depth: Int) async throws -> [FileMusicTrack] {
        guard depth <= maxScanDepth else { return [] }
        let entries = try await listDirectory(directoryURL)
        var tracks: [FileMusicTrack] = []
        for entry in entries where !sameWebDAVPath(entry.url, directoryURL) {
            if entry.isDirectory {
                tracks.append(contentsOf: try await scanDirectory(entry.url, depth: depth + 1))
            } else if FileMusicLibraryIndex.isAudioFile(entry.url) {
                tracks.append(makeTrack(from: entry))
            }
        }
        return tracks
    }

    /// 使用 PROPFIND Depth:1 读取目录内容。
    private func listDirectory(_ directoryURL: URL) async throws -> [WebDAVEntry] {
        var request = URLRequest(url: directoryURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        applyBasicAuth(to: &request)
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
            <d:getcontentlength/>
            <d:getlastmodified/>
          </d:prop>
        </d:propfind>
        """.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw WebDAVMusicError.invalidResponse
        }
        guard let http = response as? HTTPURLResponse else { throw WebDAVMusicError.invalidResponse }
        guard http.statusCode == 207 || (200..<300).contains(http.statusCode) else {
            throw WebDAVMusicError.http(http.statusCode)
        }
        do {
            return try WebDAVResponseParser.parse(data, baseURL: directoryURL)
        } catch {
            throw WebDAVMusicError.xml(error.localizedDescription)
        }
    }

    /// 从 WebDAV 条目生成文件索引项。
    private func makeTrack(from entry: WebDAVEntry) -> FileMusicTrack {
        let meta = FileMusicLibraryIndex.metadata(from: entry.url, relativeTo: rootURL())
        return FileMusicTrack(
            remoteID: entry.url.absoluteString,
            title: meta.title,
            album: meta.album,
            artist: meta.artist,
            duration: 0,
            codec: entry.url.pathExtension.lowercased(),
            filesize: entry.contentLength,
            path: entry.url.absoluteString,
            modifiedAt: entry.modifiedAt
        )
    }

    /// 返回 WebDAV 根路径，默认使用服务端根目录。
    private func rootPath() -> String {
        let raw = profile.musicLibraryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/"
        guard !raw.isEmpty else { return "/" }
        return raw.hasPrefix("/") ? raw : "/" + raw
    }

    /// 构造 WebDAV 根 URL。
    private func rootURL() -> URL {
        url(forWebDAVPath: rootPath())
    }

    /// 根据 WebDAV 路径构造请求 URL。
    private func url(forWebDAVPath path: String) -> URL {
        guard var url = profile.baseURL else { return URL(string: "http://127.0.0.1/")! }
        path.split(separator: "/", omittingEmptySubsequences: true).forEach { component in
            url.appendPathComponent(String(component))
        }
        return url
    }

    /// 把绝对 URL 还原为 WebDAV 路径。
    private func webDAVPath(from url: URL) -> String {
        let decoded = url.path.removingPercentEncoding ?? url.path
        guard !decoded.isEmpty else { return "/" }
        return decoded.hasPrefix("/") ? decoded : "/" + decoded
    }

    /// 给 URLRequest 添加 Basic Auth。
    private func applyBasicAuth(to request: inout URLRequest) {
        guard !profile.username.isEmpty || !password.isEmpty else { return }
        let raw = "\(profile.username):\(password)"
        request.setValue("Basic \(Data(raw.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
    }

    /// 给 AVPlayer 可直接访问的 URL 添加 userinfo。
    private func authenticatedURL(_ url: URL) -> URL {
        guard !profile.username.isEmpty || !password.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.user = profile.username
        components.password = password
        return components.url ?? url
    }

    /// 比较 WebDAV URL 路径，忽略末尾斜杠。
    private func sameWebDAVPath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == rhs.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// WebDAV PROPFIND 返回的条目。
private struct WebDAVEntry: Sendable {
    let url: URL
    let isDirectory: Bool
    let contentLength: Int64?
    let modifiedAt: Date?
}

/// WebDAV XML 解析器，只提取音乐扫描需要的字段。
private final class WebDAVResponseParser: NSObject, XMLParserDelegate {
    private var entries: [WebDAVEntry] = []
    private var baseURL: URL!
    private var href: String = ""
    private var isDirectory = false
    private var contentLength: Int64?
    private var modifiedAt: Date?
    private var currentElement: String?
    private var currentText: String = ""

    /// 解析 WebDAV Multi-Status XML。
    static func parse(_ data: Data, baseURL: URL) throws -> [WebDAVEntry] {
        let delegate = WebDAVResponseParser()
        delegate.baseURL = baseURL
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? WebDAVMusicError.xml("XML 解析失败")
        }
        return delegate.entries
    }

    /// 读取开始元素并重置临时字段。
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        if name == "response" {
            href = ""
            isDirectory = false
            contentLength = nil
            modifiedAt = nil
        } else if name == "collection" {
            isDirectory = true
        } else if Self.textElements.contains(name) {
            currentElement = name
            currentText = ""
        }
    }

    /// 累积文本节点内容。
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentElement != nil else { return }
        currentText += string
    }

    /// 在元素结束时提交字段或完整 response。
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalized(elementName)
        if name == currentElement {
            assign(text: currentText.trimmingCharacters(in: .whitespacesAndNewlines), to: name)
            currentElement = nil
            currentText = ""
        } else if name == "response", let url = resolveHref(href) {
            entries.append(WebDAVEntry(url: url, isDirectory: isDirectory, contentLength: contentLength, modifiedAt: modifiedAt))
        }
    }

    /// 把 XML 字段写入当前 response。
    private func assign(text: String, to element: String) {
        switch element {
        case "href":
            href = text
        case "getcontentlength":
            contentLength = Int64(text)
        case "getlastmodified":
            modifiedAt = Self.rfc1123.date(from: text)
        default:
            break
        }
    }

    /// 解析 WebDAV href 为绝对 URL。
    private func resolveHref(_ href: String) -> URL? {
        guard !href.isEmpty else { return nil }
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        let decoded = href.removingPercentEncoding ?? href
        if decoded.hasPrefix("/") {
            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
            components.path = decoded
            components.query = nil
            components.fragment = nil
            return components.url
        }
        var url = baseURL!
        decoded.split(separator: "/", omittingEmptySubsequences: true).forEach { component in
            url.appendPathComponent(String(component))
        }
        return url
    }

    /// 去掉命名空间前缀。
    private func normalized(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private static let textElements: Set<String> = ["href", "getcontentlength", "getlastmodified"]
    private static let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

/// 允许用户显式开启的 WebDAV 自签名证书连接。
private final class WebDAVPermissiveCertDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
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
