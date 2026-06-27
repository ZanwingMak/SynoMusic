import SwiftUI

/// 播客入口：搜索 Apple Podcasts 在线资源并管理本地订阅。
struct PodcastBrowseView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @StateObject private var store = PodcastSubscriptionStore()
    @State private var query = ""
    @State private var results: [PodcastShow] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var hasLoadedDefault = false

    private let api = PodcastAPI.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                infoBanner
                subscriptionsSection
                searchResultsSection
            }
            .padding(.horizontal, Metrics.l)
            .padding(.top, Metrics.s)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("播客".t)
        .searchable(text: $query, prompt: "搜索播客".t)
        .onSubmit(of: .search) {
            Task { await search(query) }
        }
        .task {
            guard !hasLoadedDefault else { return }
            hasLoadedDefault = true
            await search("music", titleOnly: true)
        }
        .reserveMiniPlayer(visible: playback.currentSong != nil)
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "podcasts")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("网上搜索".t)
                    .font(.nocSection)
                Text("播客资源来自 Apple Podcasts 搜索与公开 RSS。".t)
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var subscriptionsSection: some View {
        if !store.shows.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Text("已订阅播客".t)
                    .font(.nocSection)
                ForEach(store.shows) { show in
                    PodcastShowRow(show: show, isSubscribed: true) {
                        store.toggle(show)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(resultsTitle)
                .font(.nocSection)
            if isSearching && results.isEmpty {
                LoadingState().frame(height: 220)
            } else if let error {
                ErrorStateView(title: "加载失败".t, message: error) { Task { await search(query) } }
                    .frame(height: 220)
            } else if results.isEmpty {
                EmptyStateView(systemImage: "podcasts", title: "没找到播客".t, message: "输入关键词搜索 Apple Podcasts 资源。".t)
                    .frame(height: 220)
            } else {
                ForEach(results) { show in
                    PodcastShowRow(show: show, isSubscribed: store.contains(show)) {
                        store.toggle(show)
                    }
                }
            }
        }
    }

    private var resultsTitle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "热门播客".t : "搜索结果".t
    }

    /// 搜索在线播客资源，并可静默作为默认热门内容加载。
    private func search(_ rawQuery: String, titleOnly: Bool = false) async {
        let keyword = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isSearching = true
        error = nil
        if !titleOnly {
            Haptics.tap()
        }
        do {
            results = try await api.search(keyword)
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }
}

private struct PodcastShowRow: View {
    let show: PodcastShow
    let isSubscribed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Metrics.m) {
            NavigationLink(value: BrowseRoute.podcastShow(show)) {
                HStack(spacing: Metrics.m) {
                    PodcastArtwork(url: show.artworkURL, size: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(show.title)
                            .font(.nocBody.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(show.author.isEmpty ? "播客".t : show.author)
                            .font(.nocLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let genre = show.genre, !genre.isEmpty {
                            Text(genre)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: {
                Haptics.tap()
                onToggle()
            }) {
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSubscribed ? Color.green : Theme.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSubscribed ? "取消订阅".t : "订阅".t)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 播客节目详情：加载 RSS 单集并播放。
struct PodcastShowDetailView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @StateObject private var store = PodcastSubscriptionStore()
    let show: PodcastShow

    @State private var episodes: [PodcastEpisode] = []
    @State private var isLoading = false
    @State private var error: String?

    private let api = PodcastAPI.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                header
                if isLoading && episodes.isEmpty {
                    LoadingState().frame(height: 220)
                } else if let error {
                    ErrorStateView(title: "加载节目失败".t, message: error) { Task { await loadEpisodes() } }
                        .frame(height: 220)
                } else if episodes.isEmpty {
                    EmptyStateView(systemImage: "podcasts", title: "没有可播放的节目".t, message: "换个播客或稍后重试。".t)
                        .frame(height: 220)
                } else {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        Text("播客单集".t)
                            .font(.nocSection)
                        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                            PodcastEpisodeRow(episode: episode) {
                                playEpisode(at: index)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.top, Metrics.s)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                Haptics.tap()
                store.toggle(show)
            } label: {
                Label(store.contains(show) ? "取消订阅".t : "订阅".t,
                      systemImage: store.contains(show) ? "checkmark.circle.fill" : "plus.circle")
            }
        }
        .task { await loadEpisodes() }
        .reserveMiniPlayer(visible: playback.currentSong != nil)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            PodcastArtwork(url: show.artworkURL, size: 88)
            VStack(alignment: .leading, spacing: 6) {
                Text(show.title)
                    .font(.nocTitle)
                    .lineLimit(2)
                if !show.author.isEmpty {
                    Text(show.author)
                        .font(.nocBody)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let genre = show.genre, !genre.isEmpty {
                    Text(genre)
                        .font(.nocLabel.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 加载当前播客 RSS 单集列表。
    private func loadEpisodes() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            episodes = try await api.episodes(for: show)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 播放选中的播客单集，并将同节目其它单集加入队列。
    private func playEpisode(at index: Int) {
        let songs = episodes.map { $0.asSong(in: show) }
        guard songs.indices.contains(index) else { return }
        Haptics.soft()
        playback.play(queue: songs, startAt: index, honoringShuffle: false, contextTitle: show.title)
    }
}

private struct PodcastEpisodeRow: View {
    let episode: PodcastEpisode
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Metrics.m) {
                PodcastArtwork(url: episode.artworkURL, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.nocBody.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !episode.summary.isEmpty {
                        Text(episode.summary)
                            .font(.nocLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(metaText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var metaText: String {
        var parts: [String] = []
        if let publishedAt = episode.publishedAt {
            parts.append(publishedAt.formatted(date: .abbreviated, time: .omitted))
        }
        if let duration = episode.duration, duration > 0 {
            parts.append(formatDuration(duration))
        }
        return parts.isEmpty ? "播客单集".t : parts.joined(separator: " · ")
    }

    /// 格式化播客单集时长。
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded())
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}

private struct PodcastArtwork: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Theme.accentGradient
                    Image(systemName: "podcasts")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(10, size * 0.22), style: .continuous))
    }
}
