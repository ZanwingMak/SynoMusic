import SwiftUI

/// 首页使用电视横向封面轨道和真实来源提示，焦点移动保持在安全边距内。
struct TVHomeView: View {
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var playlists: PlaylistStore
    @State private var showConnection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 64) {
                    VStack(alignment: .leading, spacing: 26) {
                        TVHeading(title: "你的音乐，你的空间。".t, subtitle: library.isDemo ? "演示资料库".t : library.client?.profile.name ?? "连接自己的音乐服务器".t)
                        HStack(spacing: 24) {
                            if !library.songs.isEmpty {
                                Button { playback.play(library.songs) } label: { Label("播放全部".t, systemImage: "play.fill") }
                                Button { playback.play(library.songs.shuffled()) } label: { Label("随机播放".t, systemImage: "shuffle") }
                            } else {
                                Button("添加服务器".t) { showConnection = true }
                                Button("体验演示资料库".t) { library.useDemo(playlists: playlists) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).focusSection()
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let album = library.recentAlbums.first {
                        TVArtwork(url: library.client?.albumCoverURL(album: album), title: album.name).frame(width: 300, height: 300).rotationEffect(.degrees(4)).shadow(color: .black.opacity(0.35), radius: 30, y: 18)
                    }
                }
                if library.isLoading { ProgressView("正在加载".t).padding(.vertical, 20) }
                if let error = library.error { TVEmptyState(title: "加载失败".t, message: error, symbol: "wifi.exclamationmark", retry: { Task { await library.refresh() } }) }
                if !library.recentAlbums.isEmpty {
                    Text("最近添加".t).font(.title2.bold())
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 28) { ForEach(library.recentAlbums) { TVAlbumCard(album: $0).frame(width: 258) } }.padding(16)
                    }.scrollClipDisabled().focusSection()
                }
                HStack(spacing: 28) {
                    TVNavigationCard(title: "我喜欢的".t, subtitle: "本地收藏".t, symbol: "heart", route: .favorites)
                    TVNavigationCard(title: "智能歌单".t, subtitle: "每一刻，都有合适的旋律".t, symbol: "sparkles", route: .mixes)
                    TVNavigationCard(title: "历史记录".t, subtitle: "最近播放".t, symbol: "clock.arrow.circlepath", route: .history)
                }.focusSection()
            }.padding(.horizontal, 64).padding(.bottom, 40)
        }.scrollClipDisabled()
        .sheet(isPresented: $showConnection) { TVServerEditor().tvControls() }
    }
}

/// 专辑卡片保留服务端专辑标识，点击读取该发行的真实曲目。
struct TVAlbumCard: View {
    @EnvironmentObject private var library: TVLibraryStore
    let album: Album
    var body: some View {
        NavigationLink(value: TVRoute.album(album)) {
            VStack(alignment: .leading, spacing: 14) {
                TVArtwork(url: library.client?.albumCoverURL(album: album), title: album.name)
                Text(album.name).font(.system(size: 23, weight: .semibold)).lineLimit(2).frame(height: 56, alignment: .topLeading)
                Text(album.displayArtist).font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(1)
            }.foregroundStyle(.white)
        }.buttonStyle(TVCardStyle())
    }
}

/// 入口卡片在文字、图形和焦点样式上都能辨识，长译文允许换行。
struct TVNavigationCard: View {
    let title: String
    var subtitle = ""
    let symbol: String
    let route: TVRoute
    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(TVStyle.accent)
                Text(title).font(.system(size: 27, weight: .semibold)).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(2) }
            }.frame(maxWidth: .infinity, minHeight: 144, alignment: .leading).padding(12).foregroundStyle(.white)
        }.buttonStyle(TVCardStyle())
    }
}

/// 电视资料库提供专辑墙和明确的类型入口，完整分页结果由共享资料库状态提供。
struct TVBrowseView: View {
    @EnvironmentObject private var library: TVLibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TVHeading(title: "浏览".t, subtitle: library.client?.profile.name ?? (library.isDemo ? "演示资料库".t : "未连接服务器".t))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 26), count: 4), spacing: 26) {
                    TVNavigationCard(title: "所有歌曲".t, symbol: "music.note", route: .songs)
                    TVNavigationCard(title: "艺术家".t, symbol: "music.mic", route: .artists)
                    TVNavigationCard(title: "服务器歌单".t, symbol: "server.rack", route: .serverPlaylists)
                    TVNavigationCard(title: "流派".t, symbol: "guitars", route: .genres)
                    TVNavigationCard(title: "文件夹".t, symbol: "folder", route: .folders)
                    TVNavigationCard(title: "电台".t, symbol: "antenna.radiowaves.left.and.right", route: .radio)
                    TVNavigationCard(title: "播客".t, symbol: "mic", route: .podcasts)
                    TVNavigationCard(title: "智能歌单".t, symbol: "sparkles", route: .mixes)
                }.focusSection()
                Text("全部专辑".t).font(.title2.bold()).padding(.top, 18)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 28)], spacing: 28) { ForEach(library.albums) { TVAlbumCard(album: $0) } }
                if library.albums.isEmpty { TVEmptyState(title: library.isLoading ? "正在加载".t : "无歌曲".t, message: "连接自己的音乐服务器".t) }
            }.padding(.horizontal, 64).padding(.bottom, 40)
        }.scrollClipDisabled()
    }
}

/// 搜索提交和清除分别处理，输入法组词时不会发送请求或抢夺焦点。
struct TVSearchView: View {
    @EnvironmentObject private var library: TVLibraryStore
    @State private var keyword = ""
    @State private var results: [Song] = []
    @State private var busy = false
    @State private var searched = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TVHeading(title: "搜索".t, subtitle: "搜索音乐库".t)
                HStack(spacing: 24) {
                    TextField("搜索歌曲、艺术家、专辑".t, text: $keyword).onSubmit { Task { await search() } }
                    Button("搜索".t) { Task { await search() } }.disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                    if !keyword.isEmpty { Button("清除".t) { generation = UUID(); keyword = ""; results = []; error = nil; busy = false; searched = false } }
                }
                if busy { ProgressView("正在加载".t) }
                if let error { TVEmptyState(title: "加载失败".t, message: error, retry: { Task { await search() } }) }
                else if !results.isEmpty { TVSongList(songs: results) }
                else if searched && !busy { TVEmptyState(title: "没有找到匹配的歌曲。".t, message: "输入关键词，查找你的音乐。".t, symbol: "magnifyingglass") }
                else { TVEmptyState(title: "搜索音乐库".t, message: "输入关键词，查找你的音乐。".t, symbol: "magnifyingglass") }
            }.padding(.horizontal, 64).padding(.bottom, 40)
        }
    }

    /// 保留搜索代次，前一次请求不会覆盖后来输入的查询结果。
    private func search() async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines); guard !query.isEmpty else { return }
        let request = UUID(); generation = request; busy = true; error = nil; searched = true; results = []
        do {
            let found: [Song]
            if let client = library.client { found = try await client.searchSongs(keyword: query, limit: 500, offset: 0) }
            else { found = library.songs.filter { [$0.title, $0.artist ?? "", $0.album ?? ""].contains { $0.localizedCaseInsensitiveContains(query) } } }
            guard request == generation else { return }; results = found
        } catch { if request == generation { self.error = error.localizedDescription } }
        if request == generation { busy = false }
    }
}

/// 每首歌曲有独立播放入口和长按菜单，焦点高亮不会改变正在播放的歌曲。
struct TVSongList: View {
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    let songs: [Song]
    var playlistID: UUID? = nil
    @State private var addingSong: Song?
    @State private var infoSong: Song?
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                Button { playback.play(songs, at: index) } label: {
                    HStack(spacing: 22) {
                        Text("\(index + 1)").font(.system(size: 19).monospacedDigit()).foregroundStyle(.secondary).frame(width: 42)
                        TVArtwork(url: library.client?.songCoverURL(song: song), title: song.album ?? song.title).frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(song.title).font(.system(size: 24, weight: .semibold)).lineLimit(2)
                            Text(song.artist ?? "").font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(song.album ?? "").font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 360, alignment: .leading)
                        if playlists.isFavorite(song.id) { Image(systemName: "heart.fill").foregroundStyle(TVStyle.accent) }
                        if playback.song?.id == song.id { Image(systemName: "waveform").foregroundStyle(TVStyle.accent) }
                        Text(song.id.hasPrefix("radio:") ? "直播".t : Self.time(song.duration)).font(.system(size: 19).monospacedDigit()).frame(width: 82, alignment: .trailing)
                    }.foregroundStyle(.white)
                }
                .buttonStyle(TVCardStyle())
                .contextMenu {
                    Button(playlists.isFavorite(song.id) ? "取消喜欢".t : "喜欢".t) { playlists.toggleFavorite(song) }
                    Button("接下来播放".t) { playback.enqueue(song, next: true) }
                    Button("加入队列".t) { playback.enqueue(song) }
                    Button("添加到歌单…".t) { addingSong = song }
                    Button("歌曲信息".t) { infoSong = song }
                    if let playlistID { Button("从歌单移除".t) { playlists.remove(song.id, from: playlistID) } }
                }
                .accessibilityHint("长按查看歌曲操作".t)
            }
        }
        .sheet(item: $addingSong) { TVAddToPlaylistView(song: $0).tvControls() }
        .sheet(item: $infoSong) { TVSongInfoView(song: $0).tvControls() }
    }

    /// 远距离阅读使用稳定的分钟秒格式，未知长度不伪造播放时长。
    static func time(_ value: Double) -> String { guard value.isFinite, value >= 0 else { return "–:––" }; return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
