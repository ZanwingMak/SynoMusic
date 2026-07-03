import Foundation

/// 用户可选择的音乐库；不同后端会映射成同一套 UI 模型。
struct MusicLibrary: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let providerType: MusicProviderType
    let isDefault: Bool
}

/// 资料库首页需要的最小数据快照。
struct LibraryHomeSnapshot: Sendable {
    let recentAlbums: [Album]
    let albums: [Album]
    let artists: [Artist]
}

/// 所有音乐服务适配器的统一入口；只暴露音乐能力，不承载视频或媒体服务器职责。
protocol MusicLibraryClient: AnyObject, Sendable {
    var providerType: MusicProviderType { get }
    var profile: ServerProfile { get }
    var legacySynologyClient: SynologyClient? { get }

    func loadLibraries() async throws -> [MusicLibrary]
    func loadHomeSnapshot() async throws -> LibraryHomeSnapshot
    func listSongs(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Song]
    func listAlbums(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Album]
    func listArtists(limit: Int, offset: Int) async throws -> [Artist]
    func artistAlbums(artist: Artist) async throws -> [Album]
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist]
    func playlistSongs(playlist: Playlist) async throws -> [Song]
    func searchSongs(keyword: String, limit: Int, offset: Int) async throws -> [Song]
    func randomSongs(count: Int) async throws -> [Song]
    func albumSongs(album: Album) async throws -> [Song]
    func albumCoverURL(album: Album) -> URL?
    func songCoverURL(song: Song) -> URL?
    func streamURL(song: Song, quality: AudioQuality) -> URL?
    func lyrics(for song: Song) async throws -> [LyricLine]
    func logout() async
}

/// 需要异步准备播放 URL 的音乐源，例如 SMB 需要先缓存远端文件再交给 AVPlayer。
protocol AsyncStreamResolvingMusicClient: AnyObject, Sendable {
    func preparedStreamURL(song: Song, quality: AudioQuality) async throws -> URL?
}

extension MusicLibraryClient {
    var legacySynologyClient: SynologyClient? { nil }

    /// 通用艺人专辑查询兜底：没有服务端专用接口时，从专辑列表中过滤艺人名称。
    func artistAlbums(artist: Artist) async throws -> [Album] {
        let albums = try await listAlbums(limit: 1000, offset: 0, sortBy: "name", sortDirection: "ASC")
        let name = artist.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return albums }
        return albums.filter { album in
            album.artist.lowercased().contains(name)
                || album.displayArtist.lowercased().contains(name)
        }
    }
}

/// 音乐下载 URL 解析器：把不同音乐源的播放地址统一转换为可保存的 URL。
enum MusicDownloadResolver {
    /// 为歌曲解析可下载 URL；异步音乐源会先准备本地缓存，旧 Synology 路径作为兼容兜底。
    static func url(
        for song: Song,
        quality: AudioQuality,
        musicClient: MusicLibraryClient?,
        legacyClient: SynologyClient?
    ) async throws -> URL? {
        if song.id.hasPrefix("local:"), let path = song.path, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if song.isDirectRemoteStream {
            return nil
        }
        if let asyncClient = musicClient as? AsyncStreamResolvingMusicClient {
            return try await asyncClient.preparedStreamURL(song: song, quality: quality)
        }
        if let url = musicClient?.streamURL(song: song, quality: quality) {
            return url
        }
        return legacyClient?.audioStation.streamURL(songID: song.id, format: quality.streamFormat)
    }

    /// 根据音质、歌曲编码和 URL 推断下载文件扩展名。
    static func fileExtension(for song: Song, quality: AudioQuality, url: URL?) -> String {
        if quality == .original, let codec = song.codec?.trimmingCharacters(in: .whitespacesAndNewlines), !codec.isEmpty {
            return codec
        }
        if let ext = url?.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines), !ext.isEmpty {
            return ext
        }
        return "mp3"
    }

    /// 判断当前音乐源下载请求是否允许用户配置的自签名证书。
    static func allowsInvalidCertificate(musicClient: MusicLibraryClient?, legacyClient: SynologyClient?) -> Bool {
        musicClient?.profile.ignoreInvalidCertificate == true
            || legacyClient?.profile.ignoreInvalidCertificate == true
    }
}
