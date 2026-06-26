import SwiftUI

/// 浏览导航路由：用 NavigationStack 的 value 类型驱动。
enum BrowseRoute: Hashable {
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case genre(Genre)
    case folder(FolderNode?)
    case allAlbums
    case allArtists
    case allPlaylists
    case allGenres
    case allFolders
    case allSongs
    case radio
    case favorites
    case localPlaylists
    case localPlaylist(UUID)
    case playbackHistory
    case settings
}

extension BrowseRoute {
    /// 路由到目的视图；集中维护，让多个 NavigationStack 共用同一份 destination。
    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .allAlbums: AllAlbumsView()
        case .allArtists: AllArtistsView()
        case .allPlaylists: AllPlaylistsView()
        case .allGenres: AllGenresView()
        case .allFolders: FolderBrowseView(folder: nil)
        case .album(let album): AlbumDetailView(album: album)
        case .artist(let artist): ArtistDetailView(artist: artist)
        case .playlist(let playlist): PlaylistDetailView(playlist: playlist)
        case .genre(let genre): GenreDetailView(genre: genre)
        case .folder(let folder): FolderBrowseView(folder: folder)
        case .radio:
            PremiumFeatureGate(feature: .radio) {
                RadioBrowseView()
            }
        case .favorites: LocalPlaylistDetailView(playlistID: PlaylistStore.favoritesID)
        case .allSongs: AllSongsView()
        case .localPlaylists: LocalPlaylistsView()
        case .localPlaylist(let id): LocalPlaylistDetailView(playlistID: id)
        case .playbackHistory:
            PremiumFeatureGate(feature: .playbackHistory) {
                PlaybackHistoryView()
            }
        case .settings: SettingsView()
        }
    }
}

extension View {
    /// 把 BrowseRoute 的 navigationDestination 挂到当前 NavigationStack。
    /// 任何承载 `NavigationLink(value:)` 的 Tab 都需要 attach 一次。
    func browseRoutes(reserveMiniPlayer: Bool = false) -> some View {
        navigationDestination(for: BrowseRoute.self) { route in
            route.destination
                .reserveMiniPlayer(visible: reserveMiniPlayer)
        }
    }
}
