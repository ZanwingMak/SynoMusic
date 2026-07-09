import Foundation

/// 一首歌的用户本地数据：备注 + 自定义颜色标签。
/// 与服务端 ID3 标签分离，因 Audio Station 没有写元数据的 API。
struct SongUserData: Codable, Hashable {
    var note: String = ""
    var customTitle: String = ""
    var customArtist: String = ""
    var customAlbum: String = ""
}

/// 本地用户数据仓库：按 songID 索引。
@MainActor
final class SongUserDataStore: ObservableObject {
    static let shared = SongUserDataStore()
    @Published private(set) var entries: [String: SongUserData] = [:]
    private let key = "syno.songUserData"

    init() { load() }

    func data(for songID: String) -> SongUserData {
        entries[songID] ?? SongUserData()
    }

    func update(_ songID: String, with data: SongUserData) {
        entries[songID] = data
        save()
    }

    /// 用云端快照替换本地歌曲自定义资料。
    func replaceEntries(_ newEntries: [String: SongUserData]) {
        entries = newEntries
        save()
    }

    private func load() {
        guard let raw = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([String: SongUserData].self, from: raw) else { return }
        entries = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.synchronize()
        }
    }
}
