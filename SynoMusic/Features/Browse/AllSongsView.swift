import SwiftUI

/// 所有歌曲：分页加载 + 排序切换 + 行内菜单（播放/加入队列/添加到歌单/喜欢）。
struct AllSongsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var playlists: PlaylistStore

    @State private var songs: [Song] = []
    @State private var isLoadingPage: Bool = false
    @State private var isInitialLoading: Bool = false
    @State private var error: String?
    @State private var sortBy: SortOption = .name
    @State private var reachedEnd: Bool = false
    @State private var pickerSong: Song?

    private let pageSize: Int = 200

    enum SortOption: String, CaseIterable, Identifiable {
        case name, artist, album, recently_added
        var id: String { rawValue }
        /// 返回中文 key；调用处使用 `.t` 翻译。
        var labelKey: String {
            switch self {
            case .name: return "按名称"
            case .artist: return "按艺术家"
            case .album: return "按专辑"
            case .recently_added: return "最近添加"
            }
        }
    }

    var body: some View {
        Group {
            if isInitialLoading && songs.isEmpty {
                LoadingState()
            } else if let err = error, songs.isEmpty {
                ErrorStateView(title: "加载失败".t, message: err) { Task { await reload() } }
            } else if songs.isEmpty {
                EmptyStateView(systemImage: "music.note", title: "没有歌曲".t, message: "Audio Station 中没有歌曲。".t)
            } else {
                List {
                    actionsRow.listRowSeparator(.hidden)
                    ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                        SongTrackRow(song: song, index: idx + 1, isCurrent: playback.currentSong?.id == song.id, isPlaying: playback.isPlaying) {
                            playback.play(queue: songs, startAt: idx, honoringShuffle: false, contextTitle: "所有歌曲".t)
                        }
                        .contextMenu { menu(for: song) }
                        .swipeActions(edge: .trailing) {
                            Button { playback.appendNext(song) } label: { Label("接下来".t, systemImage: "text.line.first.and.arrowtriangle.forward") }
                                .tint(.blue)
                            Button {
                                if playlists.isFavorite(song) { playlists.toggleFavorite(song) }
                                else { playlists.toggleFavorite(song); Haptics.success() }
                            } label: {
                                Label(playlists.isFavorite(song) ? "取消喜欢".t : "喜欢".t,
                                      systemImage: playlists.isFavorite(song) ? "heart.slash" : "heart")
                            }
                            .tint(playlists.isFavorite(song) ? .gray : .pink)
                            Button { pickerSong = song } label: { Label("加入歌单".t, systemImage: "text.badge.plus") }
                                .tint(Theme.accent)
                        }
                        .onAppear {
                            // 接近底部时拉下一页
                            if !reachedEnd, !isLoadingPage, idx == songs.count - 30 {
                                Task { await loadMore() }
                            }
                        }
                    }
                    if isLoadingPage {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("所有歌曲".t)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序".t, selection: $sortBy) {
                        ForEach(SortOption.allCases) { o in Text(o.labelKey.t).tag(o) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
        .onChange(of: sortBy) { _, _ in Task { await reload() } }
        .task { if songs.isEmpty { await reload() } }
        .sheet(item: $pickerSong) { song in
            AddToPlaylistSheet(song: song)
                .presentationDetents([.medium, .large])
        }
    }

    private var actionsRow: some View {
        HStack(spacing: Metrics.m) {
            Button {
                playback.isShuffling = false
                playback.play(queue: songs, startAt: 0, honoringShuffle: false, contextTitle: "所有歌曲".t)
            } label: { Label("播放".t, systemImage: "play.fill") }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                playback.isShuffling = true
                playback.play(queue: songs.shuffled(), startAt: 0, honoringShuffle: false, contextTitle: "所有歌曲".t)
            } label: { Label("随机".t, systemImage: "shuffle") }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.vertical, Metrics.s)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    @ViewBuilder
    private func menu(for song: Song) -> some View {
        Button { playback.appendNext(song) } label: { Label("接下来播放".t, systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button {
            if playback.queue.isEmpty { playback.play(queue: [song], honoringShuffle: false, contextTitle: "所有歌曲".t) } else { playback.appendNext(song) }
        } label: { Label("加入队列".t, systemImage: "list.bullet") }
        Button { pickerSong = song } label: { Label("添加到歌单…".t, systemImage: "text.badge.plus") }
        Button {
            playlists.toggleFavorite(song)
            Haptics.tap()
        } label: {
            Label(playlists.isFavorite(song) ? "取消喜欢".t : "喜欢".t,
                  systemImage: playlists.isFavorite(song) ? "heart.slash" : "heart")
        }
    }

    private func reload() async {
        guard let api = session.client?.audioStation else { return }
        isInitialLoading = true
        defer { isInitialLoading = false }
        error = nil
        songs = []
        reachedEnd = false
        do {
            let page = try await api.listSongs(
                limit: pageSize,
                offset: 0,
                sortBy: sortBy.rawValue,
                sortDirection: sortBy == .recently_added ? "DESC" : "ASC"
            )
            songs = page
            if page.count < pageSize { reachedEnd = true }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let api = session.client?.audioStation,
              !reachedEnd, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let page = try await api.listSongs(
                limit: pageSize,
                offset: songs.count,
                sortBy: sortBy.rawValue,
                sortDirection: sortBy == .recently_added ? "DESC" : "ASC"
            )
            songs.append(contentsOf: page)
            if page.count < pageSize { reachedEnd = true }
        } catch {
            playback.setStatus("加载更多失败".t + "：\(error.localizedDescription)")
        }
    }
}

/// 通用音轨行：复用于「所有歌曲」「歌单详情」等场景。
struct SongTrackRow: View {
    @EnvironmentObject private var session: AppSession
    let song: Song
    let index: Int?
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); onTap() }) {
            HStack(spacing: Metrics.m) {
                CoverArt(
                    url: session.client?.audioStation.songCoverURL(songID: song.id),
                    cornerRadius: 6,
                    fallbackSeed: song.id,
                    lookup: CoverLookupQuery(song: song)
                )
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.nocBody.weight(.medium))
                        .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        .lineLimit(1)
                    Text([song.artist, song.album].compactMap { $0 }.joined(separator: " · "))
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    EqualizerIcon(isAnimating: isPlaying)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.accent)
                } else if song.duration > 0 {
                    Text(formatDuration(song.duration))
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
