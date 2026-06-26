import SwiftUI

/// 加入歌单 sheet：列出所有本地歌单 + 多选切换 + 顶部「新建歌单」入口。
/// 多选确认后批量加入歌曲到所有勾选的歌单。
struct AddToPlaylistSheet: View {
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var purchase: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    let song: Song

    @State private var selected: Set<UUID> = []
    @State private var showCreate: Bool = false
    @State private var newName: String = ""
    @State private var newColor: Int = 1
    @State private var paywallFeature: PremiumFeature?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        startCreatingPlaylist()
                    } label: {
                        HStack(spacing: Metrics.m) {
                            ZStack {
                                Circle()
                                    .fill(Theme.accent.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text("新建歌单…".t)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("选择歌单".t) {
                    ForEach(playlists.playlists) { p in
                        Button {
                            toggle(p.id)
                        } label: {
                            HStack(spacing: Metrics.m) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(PlaylistPalette.gradient(for: p.colorIndex))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: p.isBuiltin ? "heart.fill" : "music.note.list")
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(p.name).font(.nocBody.weight(.medium))
                                        if p.contains(song.id) {
                                            Text("已包含".t)
                                                .font(.caption2)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.gray.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text("\(p.songCount) " + "首".t).font(.nocLabel).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(selected.contains(p.id) ? Theme.accent : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("加入歌单".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入".t) { apply() }.disabled(selected.isEmpty)
                }
            }
            .onAppear {
                // 预选已包含该歌曲的歌单，方便用户感知；点击则反转
                selected = Set(playlists.playlists(containing: song.id))
            }
            .sheet(isPresented: $showCreate) {
                createPlaylistSheet
                    .presentationDetents([.medium])
            }
            .sheet(item: $paywallFeature) { feature in
                PaywallView(feature: feature)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var createPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section("名称".t) {
                    TextField("歌单名".t, text: $newName)
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
                                            .foregroundStyle(.white).font(.headline)
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
                    Button("取消".t) { showCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建并选择".t) {
                        guard canCreatePlaylist else {
                            paywallFeature = .localPlaylists
                            return
                        }
                        let p = playlists.create(name: newName, colorIndex: newColor)
                        selected.insert(p.id)
                        newName = ""
                        newColor = 1
                        showCreate = false
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// 打开新建歌单弹窗，免费版达到上限时展示付费墙。
    private func startCreatingPlaylist() {
        guard canCreatePlaylist else {
            Haptics.tap()
            paywallFeature = .localPlaylists
            return
        }
        showCreate = true
    }

    /// 判断当前购买状态下是否还能创建本地歌单。
    private var canCreatePlaylist: Bool {
        purchase.canUse(.localPlaylists) || playlists.userPlaylists.count < PurchaseLimits.maxFreeUserPlaylists
    }

    /// 切换一个歌单的选中状态。
    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        Haptics.tap()
    }

    /// 把歌曲加入已选歌单并关闭弹窗。
    private func apply() {
        playlists.add(song, to: selected)
        Haptics.success()
        dismiss()
    }
}
