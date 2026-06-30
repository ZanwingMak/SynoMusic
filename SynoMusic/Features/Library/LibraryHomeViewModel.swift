import Foundation

/// 资料库首页的数据装载器。
@MainActor
final class LibraryHomeViewModel: ObservableObject {
    @Published var recentAlbums: [Album] = []
    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private var loaded: Bool = false

    /// 拉取首页数据；审核/Demo 使用 mock 数据，真实会话通过统一音乐源客户端加载。
    func load(musicClient: (any MusicLibraryClient)?, force: Bool = false, useMockData: Bool = false) async {
        #if DEBUG
        if DemoMode.isEnabled {
            self.recentAlbums = Array(DemoMode.albums.prefix(8))
            self.albums = DemoMode.albums
            self.artists = DemoMode.artists
            self.loaded = true
            return
        }
        #endif
        if useMockData {
            self.recentAlbums = Array(DemoMode.albums.prefix(8))
            self.albums = DemoMode.albums
            self.artists = DemoMode.artists
            self.loaded = true
            return
        }
        guard let musicClient else { return }
        if loaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            let snapshot = try await musicClient.loadHomeSnapshot()
            self.recentAlbums = snapshot.recentAlbums
            self.albums = snapshot.albums
            self.artists = snapshot.artists
            self.loaded = true
        } catch SynologyError.cancelled {
            // 刷新过程中旧请求被系统取消属于正常路径，不展示错误态。
        } catch is CancellationError {
            // Swift 并发取消同样不应该污染首页。
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 兼容旧调用点：把 SynologyClient 包装成统一音乐源客户端。
    func load(client: SynologyClient?, force: Bool = false, useMockData: Bool = false) async {
        let musicClient = client.map(SynologyMusicLibraryClient.init(client:))
        await load(musicClient: musicClient, force: force, useMockData: useMockData)
    }
}
