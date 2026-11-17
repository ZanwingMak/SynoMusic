import SwiftUI

/// 宽屏侧栏与紧凑标签共用内容框架，不按设备型号创建另一棵导航树。
struct AdaptiveLibrarySidebar: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Binding var selection: PadSection?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("资料库".t) {
                    entries([.library, .albums, .artists, .songs, .browse, .search])
                }
                Section("我的音乐".t) {
                    entries([.favorites, .playlists, .mixes, .history])
                }
                Section("设置".t) {
                    entries([.settings])
                }
            }
            .listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 5) {
                Label(session.musicClient?.profile.name ?? (reviewMode.isEnabled ? "演示资料库".t : "未连接服务器".t), systemImage: "server.rack")
                    .font(.caption).lineLimit(1)
                Text("全部功能免费开放".t).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.bar)
        }
        .navigationTitle("SynoMusic")
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
    }

    /// 绘制可由触控、键盘及辅助技术统一选择的侧栏项目。
    private func entries(_ items: [PadSection]) -> some View {
        ForEach(items) { item in
            Button { selection = item } label: { Label(item.title.t, systemImage: item.icon) }
                .buttonStyle(.plain).tag(item)
        }
    }

}

extension View {
    /// 使用稳定的全屏播放器容器，运行中折叠或展开不会切换呈现类型。
    func adaptivePlayerPresentation(isPresented: Binding<Bool>) -> some View {
        fullScreenCover(isPresented: isPresented) {
            FullPlayerView(isPresented: isPresented)
        }
    }
}

/// 侧栏只负责呈现与选择，不改变各功能的权限和资料来源。
enum PadSection: String, Identifiable {
    case library, browse, albums, artists, songs, favorites, playlists, mixes, history, search, settings
    var id: String { rawValue }
    var tab: MainTab {
        switch self { case .library: .library; case .search: .search; case .settings: .settings; default: .browse }
    }
    var title: String {
        switch self {
        case .library: "资料库"
        case .browse: "浏览"
        case .albums: "专辑"
        case .artists: "艺术家"
        case .songs: "全部歌曲"
        case .favorites: "我喜欢的"
        case .playlists: "我的歌单"
        case .mixes: "智能歌单"
        case .history: "历史记录"
        case .search: "搜索"
        case .settings: "设置"
        }
    }
    /// 侧栏的细分类别直接使用已有浏览路由，便于折回手机时继续当前页面。
    var route: BrowseRoute? {
        switch self {
        case .albums: .allAlbums
        case .artists: .allArtists
        case .songs: .allSongs
        case .favorites: .favorites
        case .playlists: .localPlaylists
        case .mixes: .smartMixes
        case .history: .playbackHistory
        default: nil
        }
    }
    var icon: String {
        switch self {
        case .library: "square.stack"
        case .browse: "square.grid.2x2"
        case .albums: "opticaldisc"
        case .artists: "music.mic"
        case .songs: "music.note"
        case .favorites: "heart"
        case .playlists: "music.note.list"
        case .mixes: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .search: "magnifyingglass"
        case .settings: "slider.horizontal.3"
        }
    }
}
