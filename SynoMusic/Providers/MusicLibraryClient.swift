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
