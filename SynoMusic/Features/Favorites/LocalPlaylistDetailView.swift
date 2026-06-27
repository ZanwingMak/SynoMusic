import SwiftUI

/// 本地歌单详情：复用为「我喜欢的」与任意用户自建歌单。
/// 支持播放/随机、批量编辑（多选删除/播放）、清空、重命名（用户自建）、删除（用户自建）。
struct LocalPlaylistDetailView: View {
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var playback: PlaybackEngine

    let playlistID: UUID

    @State private var isEditing: Bool = false
    @State private var selected: Set<String> = []
    @State private var showRename: Bool = false
    @State private var renameText: String = ""
    @State private var showDeleteConfirm: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// 从 store 拿到的当前歌单（可能为 nil，例如歌单已被删除）。
    private var playlist: LocalPlaylist? {
        playlists.playlist(playlistID)
    }

    private var snapshots: [Song] {
        playlist?.snapshots ?? []
    }

    /// 内置歌单走本地化，用户自建歌单保持原始名称。
    private var playlistDisplayName: String {
        guard let playlist else { return "" }
        return playlist.isBuiltin ? playlist.name.t : playlist.name
    }

    var body: some View {
        Group {
            if playlist == nil {
                EmptyStateView(systemImage: "questionmark.circle", title: "歌单不存在".t, message: "该歌单已被删除。".t)
            } else if snapshots.isEmpty {
                EmptyStateView(
                    systemImage: playlist?.isBuiltin == true ? "heart" : "music.note.list",
                    title: "暂无歌曲".t,
                    message: playlist?.isBuiltin == true ? "在播放器或歌曲菜单点击 ❤️ 添加。".t : "在歌曲菜单选择「添加到歌单」加入。".t
                )
            } else {
                List {
                    if !isEditing { actionsRow.listRowSeparator(.hidden) }
                    ForEach(snapshots) { song in
                        FavoriteRow(
                            song: song,
                            isEditing: isEditing,
                            isSelected: selected.contains(song.id),
                            isCurrent: playback.currentSong?.id == song.id,
                            isPlaying: playback.isPlaying
                        ) {
                            tap(song)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                playlists.remove(song.id, from: playlistID)
                            } label: { Label("移除".t, systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(navTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { trailingMenu }
        }
        .safeAreaInset(edge: .bottom) { if isEditing { editBar } }
        .alert(
            "重命名歌单".t,
            isPresented: $showRename
        ) {
            TextField("名称".t, text: $renameText)
            Button("保存".t) {
                playlists.rename(playlistID, to: renameText)
                Haptics.success()
            }
            Button("取消".t, role: .cancel) {}
        }
        .alert("删除歌单".t, isPresented: $showDeleteConfirm) {
            Button("删除".t, role: .destructive) {
                playlists.delete(playlistID)
                dismiss()
            }
            Button("取消".t, role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isEditing)
    }

    // MARK: 子组件

    private var navTitle: String {
        if isEditing { return "已选".t + " \(selected.count) " + "首".t }
        return playlistDisplayName
    }

    /// 删除歌单 alert 的提示文案；抽出避免内联插值让编译器超时。
    private var deleteMessage: String {
        let name = playlistDisplayName
        return "将永久删除".t + "「\(name)」。" + "歌曲文件本身不会被删除。".t
    }

    @ViewBuilder
    private var trailingMenu: some View {
        if isEditing {
            Button("完成".t) { exitEdit() }
        } else if !snapshots.isEmpty {
            Menu {
                Button { enterEdit() } label: { Label("批量编辑".t, systemImage: "checklist") }
                if let p = playlist, !p.isBuiltin {
                    Button {
                        renameText = p.name
                        showRename = true
                    } label: { Label("重命名".t, systemImage: "pencil") }
                }
                Button(role: .destructive) {
                    playlists.clear(playlistID)
                } label: { Label("清空全部歌曲".t, systemImage: "trash") }
                if let p = playlist, !p.isBuiltin {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Label("删除歌单".t, systemImage: "minus.circle") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: Metrics.m) {
            Button {
                playback.isShuffling = false
                playback.play(queue: snapshots, startAt: 0, honoringShuffle: false, contextTitle: playlistDisplayName)
            } label: { Label("播放".t, systemImage: "play.fill") }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                playback.isShuffling = true
                playback.play(queue: snapshots.shuffled(), startAt: 0, honoringShuffle: false, contextTitle: playlistDisplayName)
            } label: { Label("随机".t, systemImage: "shuffle") }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.vertical, Metrics.s)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private var editBar: some View {
        HStack(spacing: Metrics.s) {
            Button {
                if selected.count == snapshots.count {
                    selected.removeAll()
                } else {
                    selected = Set(snapshots.map(\.id))
                }
                Haptics.tap()
            } label: {
                Label(selected.count == snapshots.count ? "全不选".t : "全选".t,
                      systemImage: selected.count == snapshots.count ? "checkmark.square" : "square")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button { playSelected() } label: { Label("播放选中".t, systemImage: "play.fill") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected.isEmpty)

            Button(role: .destructive) { removeSelected() } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(selected.isEmpty ? Color.gray.opacity(0.4) : Color.red))
            }
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .background(.ultraThinMaterial)
    }

    // MARK: 行为

    private func tap(_ song: Song) {
        if isEditing {
            if selected.contains(song.id) { selected.remove(song.id) }
            else { selected.insert(song.id) }
            Haptics.tap()
        } else if let idx = snapshots.firstIndex(of: song) {
            playback.play(queue: snapshots, startAt: idx, honoringShuffle: false, contextTitle: playlistDisplayName)
        }
    }
    private func enterEdit() { isEditing = true; selected.removeAll(); Haptics.tap() }
    private func exitEdit() { isEditing = false; selected.removeAll(); Haptics.tap() }
    private func playSelected() {
        let songs = snapshots.filter { selected.contains($0.id) }
        guard !songs.isEmpty else { return }
        playback.play(queue: songs, startAt: 0, honoringShuffle: false, contextTitle: playlistDisplayName)
        exitEdit()
    }
    private func removeSelected() {
        playlists.remove(ids: selected, from: playlistID)
        Haptics.success()
        selected.removeAll()
        if snapshots.isEmpty { exitEdit() }
    }
}

/// 收藏列表用的行；当编辑模式下左侧多出圆形勾选标记。
struct FavoriteRow: View {
    @EnvironmentObject private var session: AppSession
    let song: Song
    let isEditing: Bool
    let isSelected: Bool
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Metrics.m) {
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Theme.accent : .secondary)
                }
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
                if isCurrent && !isEditing {
                    EqualizerIcon(isAnimating: isPlaying)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}
