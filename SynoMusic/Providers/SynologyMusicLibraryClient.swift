import Foundation

/// Synology Audio Station 的统一音乐库适配器。
final class SynologyMusicLibraryClient: MusicLibraryClient, @unchecked Sendable {
    let client: SynologyClient

    init(client: SynologyClient) {
        self.client = client
    }

    var providerType: MusicProviderType {
        .synologyAudioStation
    }

    var profile: ServerProfile {
        client.profile
    }

    var legacySynologyClient: SynologyClient? {
        client
    }

    /// Audio Station 默认只有 shared/all 这类逻辑库，先映射成一个默认音乐库。
    func loadLibraries() async throws -> [MusicLibrary] {
        [
            MusicLibrary(
                id: "synology:shared",
                name: "Audio Station",
                providerType: providerType,
                isDefault: true
            )
        ]
    }

    /// 并发加载首页需要的最近专辑、专辑墙和艺术家。
    func loadHomeSnapshot() async throws -> LibraryHomeSnapshot {
        async let recent = client.audioStation.listAlbums(limit: 18, sortBy: "recently_added", sortDirection: "DESC")
        async let all = client.audioStation.listAlbums(limit: 60, sortBy: "name", sortDirection: "ASC")
        async let artists = client.audioStation.listArtists(limit: 30)
        return try await LibraryHomeSnapshot(
            recentAlbums: recent,
            albums: all,
            artists: artists
        )
    }

    /// 列出歌曲，参数保持为通用分页和排序形态。
    func listSongs(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Song] {
        try await client.audioStation.listSongs(
            limit: limit,
            offset: offset,
            sortBy: sortBy,
            sortDirection: sortDirection
        )
    }

    /// 列出专辑，参数保持为通用分页和排序形态。
    func listAlbums(limit: Int, offset: Int, sortBy: String, sortDirection: String) async throws -> [Album] {
        try await client.audioStation.listAlbums(
            limit: limit,
            offset: offset,
            sortBy: sortBy,
            sortDirection: sortDirection
        )
    }

    /// 列出艺术家。
    func listArtists(limit: Int, offset: Int) async throws -> [Artist] {
        try await client.audioStation.listArtists(limit: limit, offset: offset)
    }

    /// 使用 Audio Station 原生参数查询艺人的专辑。
    func artistAlbums(artist: Artist) async throws -> [Album] {
        try await client.audioStation.listAlbums(limit: 500, artist: artist.name)
    }

    /// 列出播放列表。
    func listPlaylists(limit: Int, offset: Int) async throws -> [Playlist] {
        try await client.audioStation.listPlaylists(limit: limit, offset: offset)
    }

    /// 列出 Audio Station 播放列表内的歌曲。
    func playlistSongs(playlist: Playlist) async throws -> [Song] {
        try await client.audioStation.playlistSongs(id: playlist.id)
    }

    /// 搜索歌曲标题。
    func searchSongs(keyword: String, limit: Int, offset: Int) async throws -> [Song] {
        try await client.audioStation.searchSongs(keyword: keyword, limit: limit, offset: offset)
    }

    /// 从全库随机抓取歌曲。
    func randomSongs(count: Int) async throws -> [Song] {
        try await client.audioStation.randomSongs(count: count)
    }

    /// 列出指定专辑内的歌曲。
    func albumSongs(album: Album) async throws -> [Song] {
        try await client.audioStation.listSongs(album: album.name, albumArtist: album.artist, sortBy: "track")
    }

    /// 返回专辑封面 URL。
    func albumCoverURL(album: Album) -> URL? {
        client.audioStation.albumCoverURL(album: album.name, albumArtist: album.artist)
    }

    /// 返回歌曲封面 URL。
    func songCoverURL(song: Song) -> URL? {
        client.audioStation.songCoverURL(songID: song.id)
    }

    /// 返回歌曲播放 URL。
    func streamURL(song: Song, quality: AudioQuality) -> URL? {
        client.audioStation.streamURL(songID: song.id, format: quality.streamFormat)
    }

    /// 返回服务器内置歌词。
    func lyrics(for song: Song) async throws -> [LyricLine] {
        try await client.audioStation.getLyrics(songID: song.id)
    }

    /// 退出 Audio Station 会话。
    func logout() async {
        await client.logout()
    }
}
