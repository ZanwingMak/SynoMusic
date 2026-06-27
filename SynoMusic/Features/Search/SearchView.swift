import SwiftUI

/// 搜索：实时搜索歌曲，列表展示，点击播放。
struct SearchView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var reviewMode: AppReviewMode
    @EnvironmentObject private var navigation: AppNavigationState

    @State private var keyword: String = ""
    @State private var results: [Song] = []
    @State private var history: [String] = SearchHistory.load()
    @State private var task: Task<Void, Never>? = nil
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if session.client == nil && !reviewMode.isEnabled {
                ServerRequiredEmptyState(systemImage: "magnifyingglass") {
                    navigation.openAddServer()
                }
            } else if keyword.isEmpty {
                historyView
            } else if isLoading {
                LoadingState()
            } else if let err = error {
                ErrorStateView(title: "搜索失败".t, message: err) { triggerSearch() }
            } else if results.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "无结果".t, message: "试试别的关键词。".t)
            } else {
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { idx, song in
                        Button {
                            Haptics.tap()
                            playback.play(queue: results, startAt: idx, honoringShuffle: false, contextTitle: "搜索".t)
                            SearchHistory.add(keyword)
                            history = SearchHistory.load()
                        } label: {
                            SearchResultRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("搜索".t)
        .searchable(text: $keyword, prompt: "歌曲、艺术家或专辑".t)
        .onChange(of: keyword) { _, newValue in
            task?.cancel()
            guard !newValue.isEmpty else { results = []; return }
            task = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)  // 防抖
                if Task.isCancelled { return }
                await runSearch(newValue)
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            if history.isEmpty {
                EmptyStateView(systemImage: "sparkles", title: "想听点什么？".t, message: "在上方输入歌曲、艺术家或专辑名。".t)
            } else {
                HStack {
                    Text("最近搜索".t).font(.nocSection)
                    Spacer()
                    Button("清除".t) {
                        SearchHistory.clear()
                        history = []
                    }
                    .font(.nocLabel)
                    .foregroundStyle(Theme.accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.s) {
                        ForEach(history, id: \.self) { item in
                            Button(item) { keyword = item }
                                .font(.nocLabel)
                                .padding(.horizontal, Metrics.m)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(Metrics.l)
    }

    /// 重新触发当前关键词搜索。
    private func triggerSearch() {
        Task { await runSearch(keyword) }
    }

    /// 执行歌曲搜索；审核模式在内置歌曲里做本地匹配。
    private func runSearch(_ k: String) async {
        if reviewMode.isEnabled {
            let trimmed = k.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { results = []; return }
            let lower = trimmed.lowercased()
            results = DemoMode.songs.filter { song in
                [song.title, song.artist ?? "", song.album ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(lower)
            }
            return
        }
        guard let api = session.client?.audioStation else { return }
        let trimmed = k.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            self.results = try await api.searchSongs(keyword: trimmed)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct SearchResultRow: View {
    @EnvironmentObject private var session: AppSession
    let song: Song
    var body: some View {
        HStack(spacing: Metrics.m) {
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
                    .lineLimit(1)
                Text([song.artist, song.album].compactMap { $0 }.joined(separator: " · "))
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

/// 简单的搜索历史持久化。
enum SearchHistory {
    private static let key = "noc.searchHistory"
    private static let maxCount = 12

    /// 读取搜索历史。
    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
    /// 追加一条搜索历史，并保持最大数量。
    static func add(_ keyword: String) {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        var list = load().filter { $0 != k }
        list.insert(k, at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        UserDefaults.standard.set(list, forKey: key)
    }
    /// 清空搜索历史。
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
