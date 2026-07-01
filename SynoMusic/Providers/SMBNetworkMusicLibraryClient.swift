import Foundation
import SMBClient

/// 手动 SMB 音乐源错误。
enum SMBNetworkMusicError: LocalizedError {
    case missingHost
    case missingShare
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .missingHost:
            return "SMB 地址不能为空。"
        case .missingShare:
            return "没有发现可用的 SMB 共享。"
        case .invalidPath:
            return "SMB 路径格式无效。"
        }
    }
}

/// 手动 SMB 音乐库客户端；通过 SMB2 登录、扫描目录，并在播放前缓存文件。
final class SMBNetworkMusicLibraryClient: MusicLibraryClient, AsyncStreamResolvingMusicClient, @unchecked Sendable {
    let providerType: MusicProviderType = .smb
    let profile: ServerProfile

    private var client: SMBClient?
    private var password: String
    private let maxScanDepth = 8
    private var tracksCache: [FileMusicTrack]?

    init(profile: ServerProfile, password: String = "") {
        self.profile = profile
        self.password = password
    }

    /// 使用手动填写的 SMB 主机、端口和账号密码建立连接。
    func authenticate(password: String) async throws {
        guard !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SMBNetworkMusicError.missingHost
        }
        self.password = password
        let smb = SMBClient(host: profile.host, port: profile.port)
        try await smb.login(
            username: profile.username.nilIfBlank,
            password: password.nilIfBlank
        )
        client = smb
        tracksCache = nil
        _ = try await loadTracks(force: true)
    }

    /// 返回当前 SMB 配置对应的音乐库。
    func loadLibraries() async throws -> [MusicLibrary] {
        let roots = try await scanRoots()
        return roots.map { root in
            MusicLibrary(
                id: root.displayPath,
                name: root.displayPath,
                providerType: providerType,
                isDefault: root == roots.first
            )
        }
    }

    /// 加载首页摘要数据。
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

    /// 列出 SMB 音乐文件。
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

    /// SMB 手动源暂不读取远端播放列表文件。
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist] {
        []
    }

    /// SMB 手动源暂不读取远端播放列表歌曲。
    func playlistSongs(playlist: Playlist) async throws -> [Song] {
        []
    }

    /// 在本地 SMB 索引中搜索歌曲、艺人和专辑。
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

    /// 从 SMB 索引中随机取歌。
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

    /// SMB 不解析封面，继续使用默认封面和线上封面搜索兜底。
    func albumCoverURL(album: Album) -> URL? {
        nil
    }

    /// SMB 不解析封面，继续使用默认封面和线上封面搜索兜底。
    func songCoverURL(song: Song) -> URL? {
        nil
    }

    /// SMB 需要异步缓存，不能直接返回稳定直播 URL。
    func streamURL(song: Song, quality: AudioQuality) -> URL? {
        nil
    }

    /// 下载 SMB 文件到本地缓存，并返回 AVPlayer 可播放的文件 URL。
    func preparedStreamURL(song: Song, quality: AudioQuality) async throws -> URL? {
        let remoteID = FileMusicLibraryIndex.remoteID(from: song.id, providerType: providerType, profile: profile)
        let remoteFile = try parseRemoteFile(remoteID)
        let fileURL = try cacheURL(for: remoteID, extensionName: remoteFile.pathURL.pathExtension)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        let accessor = try requireClient().treeAccessor(share: remoteFile.share)
        let reader = try await accessor.fileReader(path: remoteFile.path)
        try await reader.download(to: fileURL, overwrite: true)
        try await reader.close()
        return fileURL
    }

    /// SMB 手动源不提供统一歌词接口。
    func lyrics(for song: Song) async throws -> [LyricLine] {
        []
    }

    /// 退出 SMB 会话并清理索引缓存。
    func logout() async {
        tracksCache = nil
        _ = try? await client?.logoff()
        client = nil
    }

    /// 懒加载并缓存 SMB 扫描索引。
    private func loadTracks(force: Bool = false) async throws -> [FileMusicTrack] {
        if !force, let tracksCache { return tracksCache }
        var tracks: [FileMusicTrack] = []
        for root in try await scanRoots() {
            tracks.append(contentsOf: try await scan(root: root, depth: 0))
        }
        tracksCache = tracks
        return tracks
    }

    /// 生成需要扫描的 SMB share 和子目录。
    private func scanRoots() async throws -> [SMBRoot] {
        let configured = (profile.musicLibraryID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return [try SMBRoot(configuredPath: configured)]
        }
        let shares = try await requireClient().listShares()
            .filter { $0.type.contains(.diskTree) && !$0.type.contains(.special) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !shares.isEmpty else { throw SMBNetworkMusicError.missingShare }
        return shares.map { SMBRoot(share: $0.name, path: "") }
    }

    /// 递归扫描一个 SMB 根目录。
    private func scan(root: SMBRoot, depth: Int) async throws -> [FileMusicTrack] {
        guard depth <= maxScanDepth else { return [] }
        let accessor = try requireClient().treeAccessor(share: root.share)
        let entries = try await accessor.listDirectory(path: root.path)
            .filter { $0.name != "." && $0.name != ".." && !$0.isHidden }
        var tracks: [FileMusicTrack] = []
        for entry in entries {
            let childPath = root.childPath(entry.name)
            if entry.isDirectory {
                tracks.append(contentsOf: try await scan(root: SMBRoot(share: root.share, path: childPath), depth: depth + 1))
            } else if FileMusicLibraryIndex.isAudioFile(URL(fileURLWithPath: childPath)) {
                tracks.append(makeTrack(entry: entry, root: root, path: childPath))
            }
        }
        return tracks
    }

    /// 把 SMB 文件条目映射为通用文件索引项。
    private func makeTrack(entry: File, root: SMBRoot, path: String) -> FileMusicTrack {
        let fileURL = URL(fileURLWithPath: "/" + root.share + "/" + path)
        let rootURL = URL(fileURLWithPath: "/" + root.share + "/" + root.path)
        let meta = FileMusicLibraryIndex.metadata(from: fileURL, relativeTo: rootURL)
        let remoteID = makeRemoteID(share: root.share, path: path)
        return FileMusicTrack(
            remoteID: remoteID,
            title: meta.title,
            album: meta.album,
            artist: meta.artist,
            duration: 0,
            codec: fileURL.pathExtension.lowercased(),
            filesize: Int64(entry.size),
            path: remoteID,
            modifiedAt: entry.lastWriteTime
        )
    }

    /// 生成可解析的 SMB 远端文件 ID。
    private func makeRemoteID(share: String, path: String) -> String {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = profile.host
        components.port = profile.port
        components.path = "/" + ([share] + path.split(separator: "/").map(String.init)).joined(separator: "/")
        return components.url?.absoluteString ?? "\(share)/\(path)"
    }

    /// 解析远端文件 ID 为 share 和相对路径。
    private func parseRemoteFile(_ remoteID: String) throws -> SMBRemoteFile {
        guard let components = URLComponents(string: remoteID) else { throw SMBNetworkMusicError.invalidPath }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let share = parts.first else { throw SMBNetworkMusicError.invalidPath }
        let path = parts.dropFirst().joined(separator: "/")
        guard !path.isEmpty else { throw SMBNetworkMusicError.invalidPath }
        return SMBRemoteFile(share: share, path: path)
    }

    /// 返回本地缓存文件路径，并确保缓存目录存在。
    private func cacheURL(for remoteID: String, extensionName: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("SMBStreams", isDirectory: true)
        .appendingPathComponent(profile.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = Data(remoteID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let safeName = String(encoded.prefix(96))
        return directory.appendingPathComponent(safeName).appendingPathExtension(extensionName.isEmpty ? "audio" : extensionName)
    }

    /// 返回已登录的 SMBClient。
    private func requireClient() throws -> SMBClient {
        guard let client else { throw SMBNetworkMusicError.missingHost }
        return client
    }
}

/// SMB 扫描根目录。
private struct SMBRoot: Equatable {
    let share: String
    let path: String

    var displayPath: String {
        path.isEmpty ? "/\(share)" : "/\(share)/\(path)"
    }

    init(share: String, path: String) {
        self.share = share
        self.path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    init(configuredPath: String) throws {
        let parts = configuredPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let share = parts.first else { throw SMBNetworkMusicError.invalidPath }
        self.share = share
        self.path = parts.dropFirst().joined(separator: "/")
    }

    /// 生成子路径。
    func childPath(_ name: String) -> String {
        path.isEmpty ? name : "\(path)/\(name)"
    }
}

/// SMB 远端文件位置。
private struct SMBRemoteFile {
    let share: String
    let path: String

    var pathURL: URL {
        URL(fileURLWithPath: path)
    }
}

private extension String {
    /// 空白字符串转 nil，便于 SMBClient 兼容匿名或 guest 登录。
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
