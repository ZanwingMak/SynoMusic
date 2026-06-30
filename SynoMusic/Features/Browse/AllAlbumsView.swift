import SwiftUI

/// 全部专辑：网格视图 + 排序切换。
struct AllAlbumsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reviewMode: AppReviewMode
    @State private var albums: [Album] = []
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var sortBy: SortOption = .name
    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Metrics.m),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Metrics.m)
    ]

    enum SortOption: String, CaseIterable, Identifiable {
        case name, recently_added, artist, year
        var id: String { rawValue }
        /// 返回中文 key；调用处使用 `.t` 翻译。
        var labelKey: String {
            switch self {
            case .name: return "按名称"
            case .recently_added: return "最近添加"
            case .artist: return "按艺术家"
            case .year: return "按年代"
            }
        }
    }

    var body: some View {
        Group {
            if isLoading && albums.isEmpty {
                LoadingState()
            } else if let err = error {
                ErrorStateView(title: "加载失败".t, message: err) { Task { await load() } }
            } else if albums.isEmpty {
                EmptyStateView(systemImage: "square.stack", title: "空空如也".t, message: "Audio Station 中没有专辑。".t)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Metrics.l) {
                        ForEach(albums) { album in
                            NavigationLink(value: BrowseRoute.album(album)) {
                                AlbumCell(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Metrics.l)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("专辑".t)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序".t, selection: $sortBy) {
                        ForEach(SortOption.allCases) { o in
                            Text(o.labelKey.t).tag(o)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .onChange(of: sortBy) { _, _ in Task { await load(force: true) } }
        .task { await load() }
    }

    /// 加载专辑列表；审核模式使用本地假数据。
    private func load(force: Bool = false) async {
        if reviewMode.isEnabled {
            albums = DemoMode.albums
            return
        }
        guard let musicClient = session.musicClient else { return }
        if !force && !albums.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            self.albums = try await musicClient.listAlbums(
                limit: 500,
                offset: 0,
                sortBy: sortBy.rawValue,
                sortDirection: sortBy == .recently_added ? "DESC" : "ASC"
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
