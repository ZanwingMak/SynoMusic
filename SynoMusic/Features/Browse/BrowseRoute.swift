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
    case smartMixes
    case radio
    case podcasts
    case podcastShow(PodcastShow)
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
        case .allAlbums:
            ServerRequiredGate { AllAlbumsView() }
        case .allArtists:
            ServerRequiredGate { AllArtistsView() }
        case .allPlaylists:
            ServerRequiredGate { AllPlaylistsView() }
        case .allGenres:
            ServerRequiredGate { AllGenresView() }
        case .allFolders:
            ServerRequiredGate { FolderBrowseView(folder: nil) }
        case .album(let album):
            ServerRequiredGate { AlbumDetailView(album: album) }
        case .artist(let artist):
            ServerRequiredGate { ArtistDetailView(artist: artist) }
        case .playlist(let playlist):
            ServerRequiredGate { PlaylistDetailView(playlist: playlist) }
        case .genre(let genre):
            ServerRequiredGate { GenreDetailView(genre: genre) }
        case .folder(let folder):
            ServerRequiredGate { FolderBrowseView(folder: folder) }
        case .radio:
            ServerDependentOnlineGate {
                PremiumFeatureGate(feature: .radio) {
                    RadioBrowseView()
                }
            }
        case .podcasts:
            ServerDependentOnlineGate {
                PremiumFeatureGate(feature: .podcasts) {
                    PodcastBrowseView()
                }
            }
        case .podcastShow(let show):
            ServerDependentOnlineGate {
                PremiumFeatureGate(feature: .podcasts) {
                    PodcastShowDetailView(show: show)
                }
            }
        case .favorites: LocalPlaylistDetailView(playlistID: PlaylistStore.favoritesID)
        case .allSongs:
            ServerRequiredGate { AllSongsView() }
        case .smartMixes:
            PremiumFeatureGate(feature: .smartMixes) {
                SmartMixesView()
            }
        case .localPlaylists: LocalPlaylistsView()
        case .localPlaylist(let id): LocalPlaylistDetailView(playlistID: id)
        case .playbackHistory:
            PremiumFeatureGate(feature: .playbackHistory) {
                PlaybackHistoryView()
            }
        case .settings: SettingsView()
        }
    }

    /// 是否属于必须连接 NAS 才能读取的媒体库页面。
    var requiresServer: Bool {
        switch self {
        case .album, .artist, .playlist, .genre, .folder,
             .allAlbums, .allArtists, .allPlaylists, .allGenres, .allFolders, .allSongs:
            return true
        default:
            return false
        }
    }

    /// 当前路由对应的付费功能；入口页用它提前拦截并展示付费墙。
    var premiumFeature: PremiumFeature? {
        switch self {
        case .radio:
            return .radio
        case .podcasts, .podcastShow:
            return .podcasts
        case .smartMixes:
            return .smartMixes
        case .playbackHistory:
            return .playbackHistory
        default:
            return nil
        }
    }

    /// 当前阶段仍依赖 Audio Station 专有 API 的页面。
    var isSynologyOnly: Bool {
        switch self {
        case .genre, .folder, .allGenres, .allFolders, .smartMixes:
            return true
        default:
            return false
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

/// 对需要 NAS 的页面做统一空态保护。
private struct ServerRequiredGate<Content: View>: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var reviewMode: AppReviewMode
    @ViewBuilder var content: () -> Content

    var body: some View {
        if session.musicClient == nil && !reviewMode.isEnabled {
            ServerRequiredEmptyState {
                navigation.openAddServer()
            }
        } else {
            content()
        }
    }
}

/// 对需要真实服务器会话且不能在审核模式展示的在线页面做统一保护。
private struct ServerDependentOnlineGate<Content: View>: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var reviewMode: AppReviewMode
    @ViewBuilder var content: () -> Content

    var body: some View {
        if session.musicClient == nil || reviewMode.isEnabled {
            ServerRequiredEmptyState {
                navigation.openAddServer()
            }
        } else {
            content()
        }
    }
}
