import SwiftUI

/// 「我的歌单」入口：列出本地全部歌单（含我喜欢的 + 用户自建），支持新建/删除/重命名。
struct LocalPlaylistsView: View {
    @EnvironmentObject private var playlists: PlaylistStore
    @State private var showCreate: Bool = false
    @State private var newName: String = ""
    @State private var newColor: Int = 1

    var body: some View {
        List {
            Section {
                Button {
                    startCreatingPlaylist()
                } label: {
                    HStack(spacing: Metrics.m) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 54, height: 54)
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text("新建歌单".t)
                            .font(.nocBody.weight(.medium))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(playlists.visiblePlaylists) { p in
                    NavigationLink(value: BrowseRoute.localPlaylist(p.id)) {
                        PlaylistRow(playlist: p)
                    }
                    .swipeActions(edge: .trailing) {
                        if !p.isBuiltin {
                            Button(role: .destructive) {
                                playlists.delete(p.id)
                            } label: { Label("删除".t, systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("我的歌单".t)
        .sheet(isPresented: $showCreate) {
            createSheet.presentationDetents([.medium])
        }

    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("名称".t) {
                    TextField("歌单名".t, text: $newName)
                        .textInputAutocapitalization(.sentences)
                }
                Section("封面颜色".t) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<PlaylistPalette.colors.count, id: \.self) { i in
                                ZStack {
                                    Circle()
                                        .fill(PlaylistPalette.gradient(for: i))
                                        .frame(width: 44, height: 44)
                                    if newColor == i {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.headline)
                                    }
                                }
                                .onTapGesture { newColor = i; Haptics.tap() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("新建歌单".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { reset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建".t) {

                        playlists.create(name: newName, colorIndex: newColor)
                        Haptics.success()
                        reset()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// 打开新建歌单弹窗，不限制歌单数量。
    private func startCreatingPlaylist() {

        showCreate = true
    }

    /// 重置新建歌单表单。
    private func reset() {
        showCreate = false
        newName = ""
        newColor = 1
    }
}

/// 歌单行：渐变方块封面 + 名称 + 歌曲数。
struct PlaylistRow: View {
    let playlist: LocalPlaylist

    /// 内置歌单走本地化，用户自建歌单保持原始名称。
    private var displayName: String {
        playlist.isBuiltin ? playlist.name.t : playlist.name
    }

    var body: some View {
        HStack(spacing: Metrics.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PlaylistPalette.gradient(for: playlist.colorIndex))
                    .frame(width: 54, height: 54)
                Image(systemName: playlist.isBuiltin ? "heart.fill" : "music.note.list")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName).font(.nocBody.weight(.semibold))
                    if playlist.isBuiltin {
                        Text("内置".t)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text("\(playlist.songCount) " + "首".t)
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
