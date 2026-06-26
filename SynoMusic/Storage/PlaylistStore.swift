import Foundation
import SwiftUI

/// 本地歌单：包含「我喜欢的」内置 + 用户自定义。
/// 与 Synology 服务器侧的 Audio Station Playlist 区分；本地歌单仅在本机存储。
struct LocalPlaylist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// 取自预设色板（0..7），UI 据此渲染封面渐变。
    var colorIndex: Int
    var songIDs: [String]
    /// 同步存一份歌曲快照，离线也能展示标题/艺术家。
    var snapshots: [Song]
    /// 内置歌单（如「我喜欢的」）不能删除/重命名。
    var isBuiltin: Bool
    var createdAt: Date
    var updatedAt: Date

    var songCount: Int { songIDs.count }
    func contains(_ songID: String) -> Bool { songIDs.contains(songID) }
}

/// 本地歌单仓库。
@MainActor
final class PlaylistStore: ObservableObject {

    /// 「我喜欢的」固定 UUID，方便跨版本/迁移定位。
    static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Published private(set) var playlists: [LocalPlaylist] = []

    private let key = "noc.localPlaylists"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        migrateLegacyFavorites()
        ensureFavorites()
    }

    /// 「我喜欢的」内置歌单。
    var favoritesPlaylist: LocalPlaylist {
        playlists.first(where: { $0.id == Self.favoritesID })
            ?? LocalPlaylist(
                id: Self.favoritesID,
                name: "我喜欢的",
                colorIndex: 0,
                songIDs: [],
                snapshots: [],
                isBuiltin: true,
                createdAt: Date(),
                updatedAt: Date()
            )
    }

    /// 用户自定义歌单（不含内置）。
    var userPlaylists: [LocalPlaylist] {
        playlists.filter { !$0.isBuiltin }
    }

    func playlist(_ id: UUID) -> LocalPlaylist? {
        playlists.first(where: { $0.id == id })
    }

    // MARK: 创建 / 重命名 / 删除

    @discardableResult
    func create(name: String, colorIndex: Int = 1) -> LocalPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let p = LocalPlaylist(
            id: UUID(),
            name: trimmed.isEmpty ? "新歌单" : trimmed,
            colorIndex: max(0, min(colorIndex, 7)),
            songIDs: [],
            snapshots: [],
            isBuiltin: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        playlists.append(p)
        save()
        return p
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }),
              !playlists[idx].isBuiltin else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        playlists[idx].name = trimmed
        playlists[idx].updatedAt = Date()
        save()
    }

    func setColor(_ id: UUID, colorIndex: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].colorIndex = max(0, min(colorIndex, 7))
        playlists[idx].updatedAt = Date()
        save()
    }

    func delete(_ id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }),
              !playlists[idx].isBuiltin else { return }
        playlists.remove(at: idx)
        save()
    }

    /// 清空一个歌单的全部歌曲（内置可清空，但歌单本身保留）。
    func clear(_ id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].songIDs.removeAll()
        playlists[idx].snapshots.removeAll()
        playlists[idx].updatedAt = Date()
        save()
    }

    // MARK: 添加 / 移除歌曲

    /// 把一首歌加入若干歌单（已存在则跳过）。
    func add(_ song: Song, to playlistIDs: Set<UUID>) {
        guard !playlistIDs.isEmpty else { return }
        for id in playlistIDs {
            guard let idx = playlists.firstIndex(where: { $0.id == id }) else { continue }
            if !playlists[idx].songIDs.contains(song.id) {
                playlists[idx].songIDs.append(song.id)
                playlists[idx].snapshots.append(song)
                playlists[idx].updatedAt = Date()
            }
        }
        save()
    }

    func remove(_ songID: String, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].songIDs.removeAll { $0 == songID }
        playlists[idx].snapshots.removeAll { $0.id == songID }
        playlists[idx].updatedAt = Date()
        save()
    }

    func remove(ids: Set<String>, from playlistID: UUID) {
        guard !ids.isEmpty,
              let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].songIDs.removeAll { ids.contains($0) }
        playlists[idx].snapshots.removeAll { ids.contains($0.id) }
        playlists[idx].updatedAt = Date()
        save()
    }

    func contains(songID: String, in playlistID: UUID) -> Bool {
        playlists.first(where: { $0.id == playlistID })?.contains(songID) ?? false
    }

    /// 一首歌当前被加入了哪些歌单。
    func playlists(containing songID: String) -> [UUID] {
        playlists.filter { $0.contains(songID) }.map(\.id)
    }

    /// 用云端快照替换本地歌单，并补齐内置「我喜欢的」歌单。
    func replacePlaylists(_ newPlaylists: [LocalPlaylist]) {
        playlists = newPlaylists
        ensureFavorites()
        save()
    }

    // MARK: 「喜欢」语义快捷方法

    func isFavorite(_ song: Song) -> Bool {
        favoritesPlaylist.contains(song.id)
    }

    func toggleFavorite(_ song: Song) {
        if isFavorite(song) {
            remove(song.id, from: Self.favoritesID)
        } else {
            add(song, to: [Self.favoritesID])
        }
    }

    // MARK: 持久化 + 迁移

    private func load() {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([LocalPlaylist].self, from: data) else { return }
        playlists = list
    }

    /// 旧 FavoritesStore 数据迁移到内置「我喜欢的」歌单。
    private func migrateLegacyFavorites() {
        let oldIDsKey = "noc.favorites.ids"
        let oldSnapKey = "noc.favorites.snapshots"
        let oldIDs = defaults.stringArray(forKey: oldIDsKey)
        guard let ids = oldIDs, !ids.isEmpty else { return }
        var oldSnaps: [Song] = []
        if let data = defaults.data(forKey: oldSnapKey),
           let list = try? JSONDecoder().decode([Song].self, from: data) {
            oldSnaps = list
        }
        // 注入到内置歌单中
        if let idx = playlists.firstIndex(where: { $0.id == Self.favoritesID }) {
            for sid in ids where !playlists[idx].songIDs.contains(sid) {
                playlists[idx].songIDs.append(sid)
                if let snap = oldSnaps.first(where: { $0.id == sid }) {
                    playlists[idx].snapshots.append(snap)
                }
            }
        } else {
            playlists.insert(LocalPlaylist(
                id: Self.favoritesID,
                name: "我喜欢的",
                colorIndex: 0,
                songIDs: ids,
                snapshots: oldSnaps,
                isBuiltin: true,
                createdAt: Date(),
                updatedAt: Date()
            ), at: 0)
        }
        defaults.removeObject(forKey: oldIDsKey)
        defaults.removeObject(forKey: oldSnapKey)
        save()
    }

    private func ensureFavorites() {
        if !playlists.contains(where: { $0.id == Self.favoritesID }) {
            playlists.insert(LocalPlaylist(
                id: Self.favoritesID,
                name: "我喜欢的",
                colorIndex: 0,
                songIDs: [],
                snapshots: [],
                isBuiltin: true,
                createdAt: Date(),
                updatedAt: Date()
            ), at: 0)
            save()
        }
    }

    private func save() {
        objectWillChange.send()
        if let data = try? JSONEncoder().encode(playlists) {
            defaults.set(data, forKey: key)
            defaults.synchronize()
        }
    }
}

/// 8 个预设歌单封面色板。
enum PlaylistPalette {
    static let colors: [[Color]] = [
        [Color(red: 0.99, green: 0.4, blue: 0.55), Color(red: 0.85, green: 0.15, blue: 0.45)], // 喜欢红
        [Color(red: 0.95, green: 0.42, blue: 0.65), Color(red: 0.55, green: 0.20, blue: 0.95)], // 紫粉
        [Color(red: 0.4, green: 0.5, blue: 0.95), Color(red: 0.2, green: 0.3, blue: 0.7)],     // 海蓝
        [Color(red: 0.3, green: 0.8, blue: 0.7), Color(red: 0.1, green: 0.5, blue: 0.5)],      // 青绿
        [Color(red: 0.95, green: 0.6, blue: 0.3), Color(red: 0.85, green: 0.3, blue: 0.3)],    // 橙红
        [Color(red: 0.9, green: 0.85, blue: 0.4), Color(red: 0.6, green: 0.5, blue: 0.1)],     // 暖黄
        [Color(red: 0.6, green: 0.6, blue: 0.6), Color(red: 0.35, green: 0.35, blue: 0.4)],    // 灰
        [Color(red: 0.5, green: 0.95, blue: 0.6), Color(red: 0.2, green: 0.7, blue: 0.4)]      // 鲜绿
    ]
    static func gradient(for index: Int) -> LinearGradient {
        let i = max(0, min(index, colors.count - 1))
        return LinearGradient(colors: colors[i], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// 兼容：保留 FavoritesStore 类型别名给迁移期未替换的引用，但后续都用 PlaylistStore。
typealias FavoritesStore = PlaylistStore

extension PlaylistStore {
    /// FavoritesStore 时代的 API：返回内置喜欢歌单的快照。
    var snapshots: [Song] { favoritesPlaylist.snapshots }
    var songIDs: Set<String> { Set(favoritesPlaylist.songIDs) }
    func toggle(_ song: Song) { toggleFavorite(song) }
    func isFavorite(_ id: String) -> Bool { favoritesPlaylist.contains(id) }
    func clear() { clear(Self.favoritesID) }
    func remove(ids: Set<String>) { remove(ids: ids, from: Self.favoritesID) }
}
