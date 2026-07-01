import Foundation

/// 系统文件夹音乐源错误；SMB 通过 iOS 文件 App 暴露的安全书签接入。
enum FolderMusicError: LocalizedError {
    case missingBookmark
    case invalidBookmark
    case unreadableFolder

    var errorDescription: String? {
        switch self {
        case .missingBookmark:
            return "请先选择 SMB 共享文件夹。"
        case .invalidBookmark:
            return "文件夹授权已失效，请重新选择 SMB 共享文件夹。"
        case .unreadableFolder:
            return "无法读取该文件夹。"
        }
    }
}

/// SMB / 文件 App 文件夹音乐库客户端；仅扫描用户授权的文件夹。
final class FolderMusicLibraryClient: MusicLibraryClient, @unchecked Sendable {
    let providerType: MusicProviderType = .smb
    let profile: ServerProfile

    private var bookmark: String
    private var rootURL: URL?
    private var isSecurityScoped = false
    private var tracksCache: [FileMusicTrack]?

    init(profile: ServerProfile, bookmark: String = "") {
        self.profile = profile
        self.bookmark = bookmark
    }

    /// 校验并恢复用户授权的 SMB 文件夹。
    func authenticate(bookmark: String) async throws {
        let trimmed = bookmark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderMusicError.missingBookmark }
        self.bookmark = trimmed
        stopAccessingRoot()
        rootURL = try Self.resolveBookmark(trimmed)
        isSecurityScoped = rootURL?.startAccessingSecurityScopedResource() == true
        _ = try await loadTracks(force: true)
    }

    /// 返回授权文件夹作为一个音乐库。
    func loadLibraries() async throws -> [MusicLibrary] {
        [
            MusicLibrary(
                id: profile.musicLibraryID ?? profile.id.uuidString,
                name: profile.musicLibraryName ?? profile.host,
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
            recentAlbums: Array(albums.prefix(24)),
            albums: albums,
            artists: Array(artists.prefix(30))
        )
    }

    /// 列出 SMB 文件夹中的歌曲。
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

    /// SMB 文件夹第一版不读取播放列表文件。
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist] {
        []
    }

    /// SMB 文件夹第一版没有远端播放列表歌曲。
    func playlistSongs(playlist: Playlist) async throws -> [Song] {
        []
    }

    /// 在本地文件夹索引中搜索歌曲、艺人和专辑。
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

    /// 从 SMB 文件夹索引中随机取歌。
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

    /// 文件夹源不解析内嵌封面，交给默认封面和线上封面搜索兜底。
    func albumCoverURL(album: Album) -> URL? {
        nil
    }

    /// 文件夹源不解析内嵌封面，交给默认封面和线上封面搜索兜底。
    func songCoverURL(song: Song) -> URL? {
        nil
    }

    /// 返回文件提供器 URL，供 AVPlayer 直接播放。
    func streamURL(song: Song, quality: AudioQuality) -> URL? {
        let remoteID = FileMusicLibraryIndex.remoteID(from: song.id, providerType: providerType, profile: profile)
        return URL(string: remoteID)
    }

    /// SMB 文件夹不提供统一歌词接口。
    func lyrics(for song: Song) async throws -> [LyricLine] {
        []
    }

    /// 停止访问安全书签并清理缓存。
    func logout() async {
        tracksCache = nil
        stopAccessingRoot()
    }

    /// 创建可持久化的安全书签字符串。
    static func makeBookmark(for url: URL) throws -> String {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return data.base64EncodedString()
    }

    /// 从安全书签字符串恢复文件夹 URL。
    static func resolveBookmark(_ encoded: String) throws -> URL {
        guard let data = Data(base64Encoded: encoded) else { throw FolderMusicError.invalidBookmark }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw FolderMusicError.invalidBookmark }
        return url
    }

    /// 懒加载并缓存文件夹索引。
    private func loadTracks(force: Bool = false) async throws -> [FileMusicTrack] {
        if !force, let tracksCache { return tracksCache }
        guard let root = rootURL ?? (try? Self.resolveBookmark(bookmark)) else {
            throw FolderMusicError.missingBookmark
        }
        if rootURL == nil {
            rootURL = root
            isSecurityScoped = rootURL?.startAccessingSecurityScopedResource() == true
        }
        let tracks = try scan(root: root)
        tracksCache = tracks
        return tracks
    }

    /// 扫描授权目录下的音频文件。
    private func scan(root: URL) throws -> [FileMusicTrack] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FolderMusicError.unreadableFolder
        }

        var tracks: [FileMusicTrack] = []
        for case let url as URL in enumerator where FileMusicLibraryIndex.isAudioFile(url) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let meta = FileMusicLibraryIndex.metadata(from: url, relativeTo: root)
            tracks.append(
                FileMusicTrack(
                    remoteID: url.absoluteString,
                    title: meta.title,
                    album: meta.album,
                    artist: meta.artist,
                    duration: 0,
                    codec: url.pathExtension.lowercased(),
                    filesize: values?.fileSize.map(Int64.init),
                    path: url.absoluteString,
                    modifiedAt: values?.contentModificationDate
                )
            )
        }
        return tracks
    }

    /// 停止访问当前安全书签。
    private func stopAccessingRoot() {
        if isSecurityScoped {
            rootURL?.stopAccessingSecurityScopedResource()
        }
        isSecurityScoped = false
        rootURL = nil
    }
}
