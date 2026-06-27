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
    @State private var selectedCountry = PodcastCountry.systemDefault
    @State private var selectedLanguage = PodcastLanguage.all
    @State private var selectedCategory = PodcastCategory.all

    private let api = PodcastAPI.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                infoBanner
                presetSection
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
            await loadPreset()
        }
        .onChange(of: selectedCountry) { _, _ in
            Task { await loadPreset() }
        }
        .onChange(of: selectedLanguage) { _, _ in
            Task { await loadPreset() }
        }
        .onChange(of: selectedCategory) { _, _ in
            Task { await loadPreset() }
        }
        .reserveMiniPlayer(visible: playback.currentSong != nil)
    }

    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mic.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("预设探索".t)
                    .font(.nocSection)
                Text("Apple Podcasts 热门榜与公开 RSS。".t)
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PodcastFilterRow(title: "内容分类".t, options: PodcastCategory.items, selection: $selectedCategory)
            PodcastFilterRow(title: "国家或地区".t, options: PodcastCountry.items, selection: $selectedCountry)
            PodcastFilterRow(title: "语言筛选".t, options: PodcastLanguage.items, selection: $selectedLanguage)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                EmptyStateView(systemImage: "mic.circle", title: "没找到播客".t, message: "当前筛选没有找到播客。".t)
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

    /// 根据当前预设加载热门榜；语言筛选存在时用关键词搜索近似匹配。
    private func loadPreset() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            await search(keyword, titleOnly: true)
            return
        }
        isSearching = true
        error = nil
        do {
            if selectedLanguage.code == nil {
                results = try await api.topPodcasts(options: searchOptions)
            } else {
                results = try await api.search(defaultPresetKeyword, options: searchOptions)
            }
        } catch {
            do {
                results = try await api.search(defaultPresetKeyword, options: searchOptions)
            } catch {
                self.error = error.localizedDescription
            }
        }
        isSearching = false
    }

    /// 搜索在线播客资源，并可静默作为默认热门内容加载。
    private func search(_ rawQuery: String, titleOnly: Bool = false) async {
        let keyword = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            await loadPreset()
            return
        }
        isSearching = true
        error = nil
        if !titleOnly {
            Haptics.tap()
        }
        do {
            results = try await api.search(keyword, options: searchOptions)
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    /// 当前播客筛选项转换成 API 参数。
    private var searchOptions: PodcastSearchOptions {
        PodcastSearchOptions(
            countryCode: selectedCountry.code,
            languageCode: selectedLanguage.code,
            genreID: selectedCategory.genreID
        )
    }

    /// 空搜索时用于语言筛选的默认关键词。
    private var defaultPresetKeyword: String {
        let value = [selectedCategory.searchTerm, selectedLanguage.searchHint]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return value.isEmpty ? "podcast" : value
    }
}

private protocol PodcastFilterOption: Identifiable, Hashable {
    var titleKey: String { get }
}

private struct PodcastCategory: PodcastFilterOption {
    let id: String
    let titleKey: String
    let genreID: Int?
    let searchTerm: String

    static let all = PodcastCategory(id: "all", titleKey: "全部分类", genreID: nil, searchTerm: "podcast")
    static let items: [PodcastCategory] = [
        .all,
        PodcastCategory(id: "music", titleKey: "音乐", genreID: 1310, searchTerm: "music podcast"),
        PodcastCategory(id: "news", titleKey: "新闻", genreID: 1489, searchTerm: "news podcast"),
        PodcastCategory(id: "technology", titleKey: "科技", genreID: 1318, searchTerm: "technology podcast"),
        PodcastCategory(id: "comedy", titleKey: "喜剧", genreID: 1303, searchTerm: "comedy podcast"),
        PodcastCategory(id: "education", titleKey: "教育", genreID: 1304, searchTerm: "education podcast"),
        PodcastCategory(id: "business", titleKey: "商业", genreID: 1321, searchTerm: "business podcast"),
        PodcastCategory(id: "health", titleKey: "健康", genreID: 1512, searchTerm: "health podcast"),
        PodcastCategory(id: "sports", titleKey: "体育", genreID: 1545, searchTerm: "sports podcast"),
        PodcastCategory(id: "stories", titleKey: "故事", genreID: 1488, searchTerm: "story podcast"),
        PodcastCategory(id: "culture", titleKey: "社会文化", genreID: 1324, searchTerm: "culture podcast")
    ]
}

private struct PodcastCountry: PodcastFilterOption {
    let id: String
    let titleKey: String
    let code: String

    static let systemDefault = PodcastCountry(id: "current", titleKey: "系统地区", code: Locale.current.region?.identifier ?? "US")
    static let items: [PodcastCountry] = [
        .systemDefault,
        PodcastCountry(id: "us", titleKey: "美国", code: "US"),
        PodcastCountry(id: "cn", titleKey: "中国大陆", code: "CN"),
        PodcastCountry(id: "gb", titleKey: "英国", code: "GB"),
        PodcastCountry(id: "jp", titleKey: "日本", code: "JP"),
        PodcastCountry(id: "kr", titleKey: "韩国", code: "KR"),
        PodcastCountry(id: "tw", titleKey: "台湾", code: "TW"),
        PodcastCountry(id: "hk", titleKey: "香港", code: "HK")
    ]
}

private struct PodcastLanguage: PodcastFilterOption {
    let id: String
    let titleKey: String
    let code: String?
    let searchHint: String

    static let all = PodcastLanguage(id: "all", titleKey: "不限语言", code: nil, searchHint: "")
    static let items: [PodcastLanguage] = [
        .all,
        PodcastLanguage(id: "zh-hans", titleKey: "简体中文", code: "zh_cn", searchHint: "中文"),
        PodcastLanguage(id: "zh-hant", titleKey: "繁体中文", code: "zh_tw", searchHint: "中文"),
        PodcastLanguage(id: "en", titleKey: "英语", code: "en_us", searchHint: "english"),
        PodcastLanguage(id: "ja", titleKey: "日语", code: "ja_jp", searchHint: "japanese"),
        PodcastLanguage(id: "ko", titleKey: "韩语", code: "ko_kr", searchHint: "korean")
    ]
}

private struct PodcastFilterRow<Option: PodcastFilterOption>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.nocLabel)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        Button {
                            Haptics.tap()
                            selection = option
                        } label: {
                            Text(option.titleKey.t)
                                .font(.nocLabel.weight(.semibold))
                                .foregroundStyle(selection == option ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selection == option ? Theme.accent : Color.primary.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
                    EmptyStateView(systemImage: "mic.circle", title: "没有可播放的节目".t, message: "换个播客或稍后重试。".t)
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
                    Image(systemName: "mic.fill")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(10, size * 0.22), style: .continuous))
    }
}
