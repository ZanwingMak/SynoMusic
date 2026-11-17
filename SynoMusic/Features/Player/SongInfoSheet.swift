import SwiftUI

/// 查看歌曲信息：所有可用字段以只读形式展示。
struct SongInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let song: Song

    var body: some View {
        NavigationStack {
            Form {
                Section("基本".t) {
                    info("标题".t, song.title)
                    info("艺术家".t, song.artist ?? "—")
                    info("专辑".t, song.album ?? "—")
                    info("专辑艺术家".t, song.albumArtist ?? "—")
                    if let y = song.year, y > 0 { info("年代".t, String(y)) }
                    if let g = song.genre { info("流派".t, g) }
                    if let c = song.composer { info("作曲".t, c) }
                    if let t = song.trackNumber { info("曲目".t, "\(t)") }
                    if let d = song.discNumber { info("碟号".t, "\(d)") }
                }
                Section("音频".t) {
                    info("时长".t, formatDuration(song.duration))
                    if let codec = song.codec { info("编码".t, codec.uppercased()) }
                    if let br = song.bitrate, br > 0 { info("比特率".t, "\(br / 1000) kbps") }
                    if let fs = song.filesize, fs > 0 { info("文件大小".t, fs.humanSize) }
                    if let r = song.rating { info("评分".t, "★ \(r) / 5") }
                }
                if let path = song.path, !path.isEmpty {
                    Section("位置".t) {
                        info("路径".t, path)
                    }
                }
                Section {
                    Text("说明：Audio Station 没有官方编辑 ID3 元数据的 API。如需修改标题/艺术家等服务端字段，请在 NAS 上直接修改源文件后重新扫描媒体库。本地仍可通过「编辑歌曲信息」加入自己的备注与显示覆盖。".t)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("歌曲信息".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Label("完成".t, systemImage: "checkmark") }
                }
            }
        }
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = max(0, Int(s))
        let h = total / 3600
        let m = (total % 3600) / 60
        let sec = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

/// 编辑歌曲的本地信息：备注 + 本地显示覆盖（标题/艺术家/专辑）。
struct SongEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = SongUserDataStore.shared
    let song: Song

    @State private var note: String = ""
    @State private var customTitle: String = ""
    @State private var customArtist: String = ""
    @State private var customAlbum: String = ""
    @State private var showConfirm: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Audio Station 没有 ID3 标签写入接口，下面的字段只在本机生效（用于在 SynoMusic 内覆盖显示）。在 NAS 上修改实际元数据请使用 File Station + 媒体扫描。".t)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("本地覆盖".t) {
                    LabeledRow("标题".t, text: $customTitle)
                    LabeledRow("艺术家".t, text: $customArtist)
                    LabeledRow("专辑".t, text: $customAlbum)
                }
                Section("个人备注".t) {
                    TextField("写点什么…".t, text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("编辑歌曲信息".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("取消".t, systemImage: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { showConfirm = true } label: { Label("保存".t, systemImage: "checkmark") }
                }
            }
            .alert("保存修改？".t, isPresented: $showConfirm) {
                Button("确认保存".t) {
                    let data = SongUserData(
                        note: note,
                        customTitle: customTitle.trimmingCharacters(in: .whitespaces),
                        customArtist: customArtist.trimmingCharacters(in: .whitespaces),
                        customAlbum: customAlbum.trimmingCharacters(in: .whitespaces)
                    )
                    store.update(song.id, with: data)
                    Haptics.success()
                    dismiss()
                }
                Button("取消".t, role: .cancel) {}
            } message: {
                Text("将把上方的本地覆盖与备注写入本机存储，不会影响 NAS 上的源文件。".t)
            }
            .onAppear {
                let d = store.data(for: song.id)
                note = d.note
                customTitle = d.customTitle
                customArtist = d.customArtist
                customAlbum = d.customAlbum
            }
        }
    }
}

private struct LabeledRow: View {
    let label: String
    @Binding var text: String
    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            ClearableTextField(title: label, text: $text)
        }
    }
}
