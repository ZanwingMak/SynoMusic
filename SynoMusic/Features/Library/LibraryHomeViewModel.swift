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

    /// 拉取首页数据；审核/Demo 使用 mock 数据，真实会话并发抓取以提升首屏速度。
    func load(client: SynologyClient?, force: Bool = false, useMockData: Bool = false) async {
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
        guard let client else { return }
        if loaded && !force { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        do {
            async let recent = client.audioStation.listAlbums(limit: 18, sortBy: "recently_added", sortDirection: "DESC")
            async let all = client.audioStation.listAlbums(limit: 60, sortBy: "name", sortDirection: "ASC")
            async let arts = client.audioStation.listArtists(limit: 30)

            let (r, a, ar) = try await (recent, all, arts)
            self.recentAlbums = r
            self.albums = a
            self.artists = ar
            self.loaded = true
        } catch SynologyError.cancelled {
            // 刷新过程中旧请求被系统取消属于正常路径，不展示错误态。
        } catch is CancellationError {
            // Swift 并发取消同样不应该污染首页。
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
