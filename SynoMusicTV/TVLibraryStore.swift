import Foundation
import Combine

/// 电视资料库复用手机的协议适配器和安全凭据存储，媒体缓存可被 tvOS 回收。
@MainActor
final class TVLibraryStore: ObservableObject {
    @Published private(set) var client: (any MusicLibraryClient)?
    @Published private(set) var albums: [Album] = []
    @Published private(set) var recentAlbums: [Album] = []
    @Published private(set) var artists: [Artist] = []
    @Published private(set) var songs: [Song] = []
    @Published private(set) var libraries: [MusicLibrary] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isDemo = false
    @Published var error: String?
    private var generation = UUID()

    /// 登录成功后才保存配置和密码，过期的异步请求不会覆盖后来选择的音乐源。
    func connect(_ profile: ServerProfile, password: String, otp: String = "", servers: ServerStore, playlists: PlaylistStore) async {
        let request = UUID(); generation = request; isLoading = true; error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let credential = password.isEmpty ? servers.password(for: profile) ?? "" : password
            let result = try await MusicProviderLoginHelper.login(profile: profile, password: credential, otp: otp.isEmpty ? nil : otp)
            guard generation == request else { await result.musicClient.logout(); return }
            if !credential.isEmpty { try servers.savePassword(credential, for: result.profile) }
            servers.upsert(result.profile); servers.setActive(result.profile)
            client = result.musicClient; isDemo = false
            playlists.setActiveScope(for: result.profile)
            albums = []; artists = []; songs = []; recentAlbums = []
            libraries = try await result.musicClient.loadLibraries()
            await load(request: request)
        } catch { if generation == request { self.error = error.localizedDescription } }
    }

    /// 刷新所选音乐源，同时保留已有内容供短暂网络错误时继续浏览。
    func refresh() async {
        guard !isDemo, client != nil else { return }
        let request = UUID(); generation = request; isLoading = true; error = nil
        await load(request: request)
        if generation == request { isLoading = false }
    }

    /// 移除当前服务器时一并清理会话和可浏览资料，不让旧连接在后台继续生效。
    func disconnect() async {
        generation = UUID(); let previous = client; client = nil; isDemo = false
        albums = []; recentAlbums = []; artists = []; songs = []; libraries = []; error = nil; isLoading = false
        await previous?.logout()
    }

    /// 分页读取完整歌曲列表，避免只把前几百首歌曲当成完整曲库。
    private func load(request: UUID) async {
        guard let client else { return }
        do {
            let snapshot = try await client.loadHomeSnapshot()
            guard generation == request else { return }
            recentAlbums = snapshot.recentAlbums; albums = snapshot.albums; artists = snapshot.artists
            var allSongs: [Song] = [], seen = Set<String>(), offset = 0
            while !Task.isCancelled {
                let page = try await client.listSongs(limit: 500, offset: offset, sortBy: "title", sortDirection: "ASC")
                guard generation == request else { return }
                let added = page.filter { seen.insert($0.id).inserted }
                allSongs += added; songs = allSongs
                if page.count < 500 || added.isEmpty { break }
                offset += page.count
            }
            var allAlbums: [Album] = [], albumIDs = Set<String>()
            offset = 0
            while !Task.isCancelled {
                let page = try await client.listAlbums(limit: 500, offset: offset, sortBy: "name", sortDirection: "ASC")
                guard generation == request else { return }
                let added = page.filter { albumIDs.insert($0.id).inserted }; allAlbums += added
                if page.count < 500 || added.isEmpty { break }; offset += page.count
            }
            albums = allAlbums
            var allArtists: [Artist] = [], artistIDs = Set<String>()
            offset = 0
            while !Task.isCancelled {
                let page = try await client.listArtists(limit: 500, offset: offset)
                guard generation == request else { return }
                let added = page.filter { artistIDs.insert($0.id).inserted }; allArtists += added
                if page.count < 500 || added.isEmpty { break }; offset += page.count
            }
            artists = allArtists
        } catch { if generation == request { self.error = error.localizedDescription } }
    }

    /// 没有真实服务器时仍可明确体验原创演示资料；所有用户都可进入和离开。
    func useDemo(playlists: PlaylistStore) {
        generation = UUID(); client = nil; isDemo = true; isLoading = false; error = nil
        songs = DemoMode.albums.flatMap { album in DemoMode.songs.prefix(3).enumerated().map { index, template in
            Song(id: "tv-demo-\(album.id)-\(index)", title: template.title, album: album.name, artist: album.displayArtist, albumArtist: album.artist, genre: "Ambient", composer: nil, trackNumber: index + 1, discNumber: 1, year: 2026, duration: 30, bitrate: nil, codec: "WAV", filesize: nil, path: nil, rating: template.rating)
        } }
        albums = Self.allAlbums(from: songs); recentAlbums = Array(albums.prefix(8)); artists = Array(DemoMode.artists.prefix(4))
        playlists.setActiveScope(for: DemoMode.serverProfiles.first)
    }

    /// 读取专辑的实际歌曲顺序，演示资料只返回有明确归属的示例歌曲。
    func albumSongs(_ album: Album) async throws -> [Song] {
        if isDemo { return songs.filter { $0.album == album.name } }
        guard let client else { return [] }
        return try await client.albumSongs(album: album)
    }

    /// 从实际曲目聚合完整专辑，包含合辑的专辑艺人信息。
    private static func allAlbums(from songs: [Song]) -> [Album] {
        Dictionary(grouping: songs, by: { [$0.album ?? "", $0.albumArtist ?? $0.artist ?? ""].joined(separator: "\u{1f}") }).map { key, tracks in
            let first = tracks[0]
            return Album(id: key, name: first.album ?? first.title, artist: first.albumArtist ?? first.artist ?? "", displayArtist: first.albumArtist ?? first.artist ?? "", year: first.year, songCount: tracks.count)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
