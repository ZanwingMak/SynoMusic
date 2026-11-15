import SwiftUI

/// 电台与播客使用公开服务，搜索结果、订阅与加载错误各自保留状态。
struct TVOnlineView: View {
    @StateObject private var subscriptions = PodcastSubscriptionStore.shared
    let podcasts: Bool
    @State private var keyword = ""
    @State private var stations: [RadioStation] = []
    @State private var shows: [PodcastShow] = []
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                TVHeading(title: (podcasts ? "播客" : "电台").t)
                HStack(spacing: 28) {
                    TextField((podcasts ? "搜索播客" : "搜索电台").t, text: $keyword).onSubmit { Task { await load() } }
                    Button("搜索".t) { Task { await load() } }.disabled(busy)
                }
                if busy { ProgressView("正在加载".t) }
                else if let error { TVEmptyState(title: "加载失败".t, message: error, retry: { Task { await load() } }) }
                else if podcasts {
                    if !subscriptions.shows.isEmpty && keyword.isEmpty {
                        Text("我的订阅".t).font(.title2.bold())
                        showGrid(subscriptions.shows)
                    }
                    Text("播客".t).font(.title2.bold())
                    showGrid(shows)
                } else { TVSongList(songs: stations.map { $0.asSong() }) }
                if !busy && error == nil && (podcasts ? shows.isEmpty : stations.isEmpty) { Text("没有找到结果".t).foregroundStyle(.secondary) }
            }.padding(.horizontal, 64).padding(.bottom, 40)
        }.task { await load() }
    }

    /// 长按节目卡片可订阅，点击则进入实际 RSS 单集列表。
    private func showGrid(_ items: [PodcastShow]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 28)], spacing: 28) {
            ForEach(items) { show in
                NavigationLink(value: TVRoute.episodes(show)) {
                    VStack(alignment: .leading, spacing: 16) {
                        AsyncImage(url: show.artworkURL) { $0.resizable().scaledToFit() } placeholder: { Image(systemName: "mic").resizable().scaledToFit().padding(60).background(TVStyle.surface) }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(show.title).font(.system(size: 24, weight: .semibold)).lineLimit(2)
                        Text(show.author).font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(1)
                        if subscriptions.contains(show) { Label("已订阅".t, systemImage: "checkmark").font(.system(size: 18)).foregroundStyle(TVStyle.accent) }
                    }.foregroundStyle(.white)
                }.buttonStyle(TVCardStyle()).contextMenu { Button((subscriptions.contains(show) ? "取消订阅" : "订阅").t) { subscriptions.toggle(show) } }
            }
        }
    }

    /// 网络请求以搜索代次隔离，关闭页面会取消等待中的请求。
    private func load() async {
        let request = UUID(); generation = request; busy = true; error = nil
        do {
            if podcasts {
                let result = keyword.isEmpty ? try await PodcastAPI.shared.topPodcasts(options: PodcastSearchOptions(countryCode: Locale.current.region?.identifier ?? "US", languageCode: nil, genreID: nil)) : try await PodcastAPI.shared.search(keyword)
                if generation == request { shows = result }
            } else {
                let result = keyword.isEmpty ? try await RadioAPI.shared.topStations() : try await RadioAPI.shared.search(keyword)
                if generation == request { stations = result }
            }
        } catch { if generation == request && !Task.isCancelled { self.error = error.localizedDescription } }
        if generation == request { busy = false }
    }
}
