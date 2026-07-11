import SwiftUI

/// 本地播客订阅存储，使用 UserDefaults 持久化 feed 列表。
@MainActor
final class PodcastSubscriptionStore: ObservableObject {
    static let shared = PodcastSubscriptionStore()

    @Published private(set) var shows: [PodcastShow] = []

    private let key = "syno.podcast.subscriptions"

    init() {
        load()
    }

    /// 判断节目是否已订阅。
    func contains(_ show: PodcastShow) -> Bool {
        shows.contains { $0.id == show.id }
    }

    /// 订阅或取消订阅指定节目。
    func toggle(_ show: PodcastShow) {
        if contains(show) {
            shows.removeAll { $0.id == show.id }
        } else {
            shows.insert(show, at: 0)
        }
        persist()
    }

    /// 用云端快照替换本地播客订阅列表。
    func replaceShows(_ newShows: [PodcastShow]) {
        shows = newShows
        persist()
    }

    /// 从 UserDefaults 恢复订阅列表。
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PodcastShow].self, from: data) else {
            shows = []
            return
        }
        shows = decoded
    }

    /// 保存订阅列表到 UserDefaults。
    private func persist() {
        guard let data = try? JSONEncoder().encode(shows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
