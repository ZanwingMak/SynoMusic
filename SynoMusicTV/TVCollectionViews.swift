import SwiftUI

/// 我的音乐聚合本地收藏、歌单和播放历史，数据随音乐源隔离保存。
struct TVCollectionView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                TVHeading(title: "我的音乐".t, subtitle: "喜欢的音乐，都在这里".t)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3), spacing: 28) {
                    TVNavigationCard(title: "我喜欢的".t, symbol: "heart", route: .favorites)
                    TVNavigationCard(title: "我的歌单".t, symbol: "music.note.list", route: .playlists)
                    TVNavigationCard(title: "历史记录".t, symbol: "clock.arrow.circlepath", route: .history)
                    TVNavigationCard(title: "智能歌单".t, symbol: "sparkles", route: .mixes)
                }
            }.padding(.horizontal, 64).padding(.bottom, 40)
        }
    }
}

/// 所有详情共用加载与失败恢复，远端结果以路由为身份，返回时由系统恢复焦点。
struct TVDestination: View {
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var playlists: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    let route: TVRoute
    @State private var tracks: [Song] = []
    @State private var remotes: [Playlist] = []
    @State private var busy = false
    @State private var error: String?
    @State private var editingName = false
    @State private var name = ""
    @State private var deletePlaylist = false
    @State private var folderNodes: [FolderNode] = []

    var body: some View {
        Group {
            if route == .radio { TVOnlineView(podcasts: false) }
            else if route == .podcasts { TVOnlineView(podcasts: true) }
            else { detail }
        }
        .task(id: route) { await load() }
        .navigationTitle(title)
        .toolbar(.hidden, for: .navigationBar)
        .background(TVStyle.background.ignoresSafeArea())
        .sheet(isPresented: $editingName) { playlistNameEditor.tvControls() }
        .confirmationDialog("删除歌单".t, isPresented: $deletePlaylist, titleVisibility: .visible) {
            if case .playlist(let id) = route { Button("删除".t, role: .destructive) { playlists.delete(id); dismiss() } }
            Button("取消".t, role: .cancel) {}
        } message: { Text("只移除本机歌单，原始音乐文件会保留。".t) }
    }

    private var title: String {
        switch route {
        case .album(let album): album.name
        case .artists: "艺术家".t
        case .artist(let artist): artist.name
        case .songs: "所有歌曲".t
        case .favorites: "我喜欢的".t
        case .history: "历史记录".t
        case .mixes: "智能歌单".t
        case .mix(let id): Self.mixTitle(id).t
        case .playlists: "我的歌单".t
        case .playlist(let id): playlists.playlist(id)?.name ?? "我的歌单".t
        case .serverPlaylists: "服务器歌单".t
        case .remotePlaylist(let playlist): playlist.name
        case .genres: "流派".t
        case .genre(let genre): genre
        case .folders: "文件夹".t
        case .folder(let path): path
        case .nasFolder(let node): node.title
        case .episodes(let show): show.title
        case .radio: "电台".t
        case .podcasts: "播客".t
        }
    }

    /// 收藏和历史直接观察实际仓库，远端集合保留加载时的结果与顺序。
    private var visibleTracks: [Song] {
        switch route {
        case .songs: library.songs
        case .favorites: playlists.favoritesPlaylist.snapshots
        case .history: playback.history
        case .playlist(let id): playlists.playlist(id)?.snapshots ?? []
        case .genre(let name): library.songs.filter { $0.genre == name }
        case .folder(let name): library.songs.filter { Self.folder($0) == name }
        default: tracks
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if case .album(let album) = route {
                    HStack(spacing: 48) {
                        TVArtwork(url: library.client?.albumCoverURL(album: album), title: album.name).frame(width: 260, height: 260)
                        TVHeading(title: album.name, subtitle: album.displayArtist)
                    }.padding(.vertical, 20)
                } else { TVHeading(title: title) }
                if busy { ProgressView("正在加载".t) }
                else if let error { TVEmptyState(title: "加载失败".t, message: error, symbol: "wifi.exclamationmark", retry: { Task { await load() } }) }
                else if route == .playlists { playlistGrid }
                else if route == .mixes { mixGrid }
                else if isNASFolder { nasFolderGrid }
                else if route == .genres || route == .folders { groupingGrid }
                else if route == .serverPlaylists { remoteGrid }
                else if route == .artists { artistIndex }
                else if case .artist(let artist) = route { artistGrid(artist) }
                else {
                    HStack(spacing: 24) {
                        if !visibleTracks.isEmpty {
                            Button { playback.play(visibleTracks) } label: { Label("播放全部".t, systemImage: "play.fill") }
                            Button { playback.play(visibleTracks.shuffled()) } label: { Label("随机播放".t, systemImage: "shuffle") }
                        }
                        if case .playlist(let id) = route, let playlist = playlists.playlist(id), !playlist.isBuiltin {
                            Button("重命名".t) { name = playlist.name; editingName = true }
                            Button("删除歌单".t) { deletePlaylist = true }
                        }
                        if route == .history, !playback.history.isEmpty { Button("清空历史".t) { playback.clearHistory() } }
                    }
                    if visibleTracks.isEmpty { TVEmptyState(title: "无歌曲".t, message: emptyMessage) }
                    else { TVSongList(songs: visibleTracks, playlistID: currentPlaylistID) }
                }
            }.padding(.horizontal, 64).padding(.bottom, 40)
        }.scrollClipDisabled()
    }

    /// 详情中的长按移除操作只作用于正在查看的本地歌单。
    private var currentPlaylistID: UUID? {
        if route == .favorites { return PlaylistStore.favoritesID }
        if case .playlist(let id) = route { return id }
        return nil
    }

    private var isNASFolder: Bool {
        guard library.client?.legacySynologyClient != nil else { return false }
        if route == .folders { return true }
        if case .nasFolder = route { return true }
        return false
    }

    private var nasFolderGrid: some View {
        VStack(alignment: .leading, spacing: 28) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 450), spacing: 28)], spacing: 28) {
                ForEach(folderNodes) { node in TVNavigationCard(title: node.title, symbol: "folder", route: .nasFolder(node)) }
            }
            TVSongList(songs: tracks)
            if folderNodes.isEmpty && tracks.isEmpty { TVEmptyState(title: "空目录".t, message: "这里还没有音频文件。".t, symbol: "folder") }
        }
    }

    /// 空收藏与空规则给出具体原因，不以无关歌曲填充结果。
    private var emptyMessage: String {
        if route == .favorites { return "长按歌曲并选择喜欢，即可在这里找到。".t }
        if case .mix(let id) = route, id == "rated" { return "优先播放 4 星及以上歌曲。".t }
        return "浏览自己的音乐收藏，选择歌曲开始聆听。".t
    }

    private var playlistGrid: some View {
        VStack(alignment: .leading, spacing: 28) {
            Button { name = ""; editingName = true } label: { Label("新建歌单".t, systemImage: "plus") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 450), spacing: 28)], spacing: 28) {
                ForEach(playlists.visiblePlaylists) { playlist in
                    TVNavigationCard(title: playlist.isBuiltin ? "我喜欢的".t : playlist.name, subtitle: "\(playlist.songCount) " + "首歌".t, symbol: playlist.isBuiltin ? "heart" : "music.note.list", route: .playlist(playlist.id))
                }
            }
        }
    }

    private var mixGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3), spacing: 28) {
            ForEach(["recent", "random", "rated", "added", "favorites"], id: \.self) { id in
                TVNavigationCard(title: Self.mixTitle(id).t, symbol: id == "random" ? "shuffle" : id == "rated" ? "star" : id == "favorites" ? "heart" : "sparkles", route: .mix(id))
            }
        }
    }

    private var groupingGrid: some View {
        let folder = route == .folders
        let names = Set(library.songs.compactMap { folder ? Self.folder($0) : $0.genre }.filter { !$0.isEmpty }).sorted()
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 500), spacing: 28)], spacing: 28) {
            ForEach(names, id: \.self) { name in TVNavigationCard(title: name, symbol: folder ? "folder" : "guitars", route: folder ? .folder(name) : .genre(name)) }
            if names.isEmpty { Text("当前音乐源未提供这些资料。".t).foregroundStyle(.secondary) }
        }
    }

    private var remoteGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 500), spacing: 28)], spacing: 28) {
            ForEach(remotes) { playlist in TVNavigationCard(title: playlist.name, subtitle: "\(playlist.songCount ?? 0) " + "首歌".t, symbol: "music.note.list", route: .remotePlaylist(playlist)) }
            if remotes.isEmpty { Text("暂无播放列表".t).foregroundStyle(.secondary) }
        }
    }

    /// 艺术家入口保留原始服务器名称，专辑筛选同时匹配专辑艺人。
    private func artistGrid(_ artist: Artist) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 28)], spacing: 28) {
            ForEach(library.albums.filter { $0.artist == artist.name || $0.displayArtist == artist.name }) { TVAlbumCard(album: $0) }
        }
    }

    private var artistIndex: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 450), spacing: 28)], spacing: 28) {
            ForEach(library.artists) { item in TVNavigationCard(title: item.name, symbol: "music.mic", route: .artist(item)) }
        }
    }

    private var playlistNameEditor: some View {
        VStack(spacing: 30) {
            Text("我的歌单".t).font(.title)
            TextField("名称".t, text: $name)
            HStack(spacing: 30) {
                Button("取消".t) { editingName = false }
                Button("保存".t) {
                    if case .playlist(let id) = route { playlists.rename(id, to: name) } else { _ = playlists.create(name: name) }
                    editingName = false
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(70).frame(maxWidth: 900)
    }

    /// 页面加载使用系统任务取消，离开详情后不会覆盖其他屏幕。
    private func load() async {
        tracks = []; remotes = []; error = nil; busy = true
        defer { busy = false }
        do {
            switch route {
            case .album(let album): tracks = try await library.albumSongs(album)
            case .serverPlaylists: remotes = try await library.client?.listPlaylists(limit: 500, offset: 0) ?? []
            case .remotePlaylist(let playlist): tracks = try await library.client?.playlistSongs(playlist: playlist) ?? []
            case .folders: if isNASFolder { try await loadFolder(parentID: nil) }
            case .nasFolder(let node): try await loadFolder(parentID: node.id)
            case .episodes(let show): tracks = try await PodcastAPI.shared.episodes(for: show).map { $0.asSong(in: show) }
            case .mix(let id):
                switch id {
                case "recent": tracks = playback.history
                case "random": tracks = library.songs.shuffled().prefix(80).map { $0 }
                case "rated": tracks = library.songs.filter { ($0.rating ?? 0) >= 4 }
                case "favorites": tracks = playlists.favoritesPlaylist.snapshots
                case "added": tracks = library.isDemo ? Array(library.songs.reversed().prefix(80)) : try await library.client?.listSongs(limit: 120, offset: 0, sortBy: "recently_added", sortDirection: "DESC") ?? []
                default: break
                }
            default: break
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    /// Audio Station 的文件夹使用真实层级接口，并分页读取当前目录。
    private func loadFolder(parentID: String?) async throws {
        guard let api = library.client?.legacySynologyClient?.audioStation else { return }
        var nodes: [FolderNode] = [], seen = Set<String>(), offset = 0
        while !Task.isCancelled {
            let page = try await api.listFolders(parentID: parentID, limit: 500, offset: offset)
            let added = page.filter { seen.insert($0.id).inserted }; nodes += added
            if page.count < 500 || added.isEmpty { break }; offset += page.count
        }
        folderNodes = nodes.filter { $0.type == "folder" }
        tracks = nodes.filter { $0.type != "folder" }.map { node in
            let id = node.songID ?? node.id
            return library.songs.first { $0.id == id } ?? Song(id: id, title: node.title, album: nil, artist: nil, albumArtist: nil, genre: nil, composer: nil, trackNumber: nil, discNumber: nil, year: nil, duration: 0, bitrate: nil, codec: nil, filesize: nil, path: node.path, rating: nil)
        }
    }

    /// 通用音乐源只按实际文件路径分组，不把专辑名称伪装成服务器目录。
    private static func folder(_ song: Song) -> String? {
        guard let path = song.path, path.contains("/") else { return nil }
        return (path as NSString).deletingLastPathComponent
    }

    /// 精选名称与手机一致，便于在不同设备间找到相同内容。
    private static func mixTitle(_ id: String) -> String {
        ["recent": "最近常听", "random": "随机探索", "rated": "高评分歌曲", "added": "最近添加精选", "favorites": "我喜欢的"][id] ?? "智能歌单"
    }
}

/// 添加歌曲时明确选择目标；新建和已有歌单都立即写入本机存储。
struct TVAddToPlaylistView: View {
    @EnvironmentObject private var playlists: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @State private var name = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                TVHeading(title: "添加到歌单…".t, subtitle: song.title)
                ForEach(playlists.visiblePlaylists) { playlist in
                    Button(playlist.isBuiltin ? "我喜欢的".t : playlist.name) { playlists.add(song, to: [playlist.id]); dismiss() }.disabled(playlist.contains(song.id))
                }
                TextField("新歌单名称".t, text: $name)
                Button("新建并添加".t) { let playlist = playlists.create(name: name); playlists.add(song, to: [playlist.id]); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("取消".t) { dismiss() }
            }.padding(70)
        }
    }
}

/// 信息面板只呈现实际标签，文件位置不包含密码或会话地址。
struct TVSongInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVHeading(title: "歌曲信息".t, subtitle: song.title)
            ForEach(fields, id: \.0) { field in HStack { Text(field.0.t).foregroundStyle(.secondary).frame(width: 220, alignment: .leading); Text(field.1).lineLimit(3) } }
            Button("完成".t) { dismiss() }
        }.padding(70)
    }
    private var fields: [(String, String)] {
        [("艺术家", song.artist ?? ""), ("专辑", song.album ?? ""), ("流派", song.genre ?? ""), ("音质", song.codec?.uppercased() ?? ""), ("时长", TVSongList.time(song.duration)), ("评分", song.rating.map { "\($0)/5" } ?? "")].filter { !$0.1.isEmpty }
    }
}
