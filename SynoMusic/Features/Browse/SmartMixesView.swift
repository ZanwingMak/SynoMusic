import SwiftUI

/// 智能歌单：把播放历史、下载缓存和服务器曲库组合成可一键播放的集合。
struct SmartMixesView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var reviewMode: AppReviewMode

    @State private var loadingMixID: String?
    @State private var errorMessage: String?
    @State private var showServerPrompt = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Metrics.m) {
                mixCard(
                    id: "recent",
                    title: "最近常听",
                    subtitle: "从播放历史继续听。",
                    icon: "clock.arrow.circlepath",
                    gradient: [.blue, .purple]
                ) {
                    playRecentHistory()
                }
                mixCard(
                    id: "random",
                    title: "随机探索",
                    subtitle: "从曲库随机挑选歌曲。",
                    icon: "shuffle",
                    gradient: [.pink, .orange]
                ) {
                    await playRandomSongs()
                }
                mixCard(
                    id: "rated",
                    title: "高评分歌曲",
                    subtitle: "优先播放 4 星及以上歌曲。",
                    icon: "star.fill",
                    gradient: [.yellow, .orange]
                ) {
                    await playHighlyRatedSongs()
                }
                mixCard(
                    id: "added",
                    title: "最近添加精选",
                    subtitle: "播放最近加入曲库的音乐。",
                    icon: "sparkles",
                    gradient: [.teal, .green]
                ) {
                    await playRecentAdditions()
                }
                mixCard(
                    id: "downloaded",
                    title: "已下载歌曲",
                    subtitle: "离线缓存也能直接播放。",
                    icon: "arrow.down.circle.fill",
                    gradient: [.indigo, .cyan]
                ) {
                    playDownloadedSongs()
                }
            }
            .padding(Metrics.l)

            if let errorMessage {
                Text(errorMessage)
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Metrics.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("智能歌单".t)
        .serverRequiredPrompt(isPresented: $showServerPrompt) {
            navigation.openAddServer()
        }
    }

    /// 绘制一个智能歌单入口卡片。
    private func mixCard(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        gradient: [Color],
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await runMix(id: id, action: action) }
        } label: {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: icon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.2))
                    .offset(x: 72, y: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Spacer()
                    if loadingMixID == id {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    Text(title.t)
                        .font(.nocSection)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle.t)
                        .font(.nocLabel)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
                .padding(16)
            }
            .aspectRatio(1.06, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))
            .shadow(color: (gradient.first ?? .clear).opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(loadingMixID != nil)
    }

    /// 包装异步歌单动作，统一处理 loading、错误和触觉反馈。
    private func runMix(id: String, action: @escaping () async -> Void) async {
        guard loadingMixID == nil else { return }
        loadingMixID = id
        errorMessage = nil
        Haptics.tap()
        await action()
        loadingMixID = nil
    }

    /// 播放最近历史里的歌曲。
    private func playRecentHistory() {
        let songs = Array(playback.playedHistory.prefix(80))
        playSongs(songs, title: "最近常听")
    }

    /// 从服务器随机抓取歌曲并播放。
    private func playRandomSongs() async {
        if reviewMode.isEnabled {
            playSongs(DemoMode.songs.shuffled(), title: "随机探索")
            return
        }
        guard requireServerOrPrompt() else { return }
        guard let api = session.client?.audioStation else {
            return
        }
        do {
            let songs = try await api.randomSongs(count: 80)
            playSongs(songs, title: "随机探索")
        } catch {
            showError(error)
        }
    }

    /// 拉取较大范围歌曲后筛选高评分歌曲播放。
    private func playHighlyRatedSongs() async {
        if reviewMode.isEnabled {
            let rated = DemoMode.songs.filter { ($0.rating ?? 0) >= 4 }
            playSongs(rated.isEmpty ? DemoMode.songs : rated, title: "高评分歌曲")
            return
        }
        guard requireServerOrPrompt() else { return }
        guard let api = session.client?.audioStation else {
            return
        }
        do {
            let pool = try await api.listSongs(limit: 500, sortBy: "title", sortDirection: "ASC")
            let rated = pool.filter { ($0.rating ?? 0) >= 4 }
            playSongs(Array((rated.isEmpty ? pool : rated).prefix(100)), title: "高评分歌曲")
        } catch {
            showError(error)
        }
    }

    /// 播放最近添加的服务器歌曲。
    private func playRecentAdditions() async {
        if reviewMode.isEnabled {
            playSongs(DemoMode.songs, title: "最近添加精选")
            return
        }
        guard requireServerOrPrompt() else { return }
        guard let api = session.client?.audioStation else {
            return
        }
        do {
            let songs = try await api.listSongs(limit: 120, sortBy: "recently_added", sortDirection: "DESC")
            playSongs(songs, title: "最近添加精选")
        } catch {
            showError(error)
        }
    }

    /// 播放已下载歌曲的本地快照。
    private func playDownloadedSongs() {
        playSongs(downloads.completedSongSnapshots, title: "已下载歌曲")
    }

    /// 使用统一上下文播放智能歌单。
    private func playSongs(_ songs: [Song], title: String) {
        guard !songs.isEmpty else {
            errorMessage = "暂时没有可播放的歌曲。".t
            Haptics.warning()
            return
        }
        playback.play(queue: songs, startAt: 0, honoringShuffle: false, contextTitle: title.t)
        Haptics.success()
    }

    /// 把错误转换为界面提示。
    private func showError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Haptics.warning()
    }

    /// 没有服务器时弹出确认框；已连接时允许继续执行。
    private func requireServerOrPrompt() -> Bool {
        guard session.client == nil && !reviewMode.isEnabled else { return true }
        showServerPrompt = true
        loadingMixID = nil
        Haptics.warning()
        return false
    }
}
