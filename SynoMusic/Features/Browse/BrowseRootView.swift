import SwiftUI

/// 浏览入口：分类卡片。
struct BrowseRootView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var reviewMode: AppReviewMode
    @EnvironmentObject private var navigation: AppNavigationState
    @State private var showServerPrompt = false
    @State private var paywallFeature: PremiumFeature?

    private var categories: [(label: String, icon: String, route: BrowseRoute, gradient: [Color])] {
        let all: [(label: String, icon: String, route: BrowseRoute, gradient: [Color])] = [
        ("所有歌曲".t, "music.note", .allSongs, [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.25, green: 0.25, blue: 0.65)]),
        ("智能歌单".t, "wand.and.stars", .smartMixes, [Color(red: 0.95, green: 0.68, blue: 0.22), Color(red: 0.88, green: 0.28, blue: 0.48)]),
        ("电台".t, "antenna.radiowaves.left.and.right", .radio, [Color(red: 0.95, green: 0.42, blue: 0.5), Color(red: 0.55, green: 0.2, blue: 0.85)]),
        ("播客".t, "mic.circle.fill", .podcasts, [Color(red: 0.95, green: 0.35, blue: 0.72), Color(red: 0.48, green: 0.28, blue: 0.88)]),
        ("我的歌单".t, "music.note.list", .localPlaylists, [Color(red: 0.95, green: 0.6, blue: 0.3), Color(red: 0.85, green: 0.3, blue: 0.3)]),
        ("我喜欢的".t, "heart.fill", .favorites, [Color(red: 0.99, green: 0.4, blue: 0.55), Color(red: 0.85, green: 0.15, blue: 0.45)]),
        ("专辑".t, "square.stack.fill", .allAlbums, [Color(red: 0.95, green: 0.42, blue: 0.65), Color(red: 0.7, green: 0.3, blue: 0.9)]),
        ("艺术家".t, "person.2.fill", .allArtists, [Color(red: 0.4, green: 0.5, blue: 0.95), Color(red: 0.2, green: 0.3, blue: 0.7)]),
        ("服务器歌单".t, "server.rack", .allPlaylists, [Color(red: 0.4, green: 0.85, blue: 0.7), Color(red: 0.1, green: 0.55, blue: 0.55)]),
        ("历史记录".t, "clock.arrow.circlepath", .playbackHistory, [Color(red: 0.35, green: 0.7, blue: 0.95), Color(red: 0.15, green: 0.35, blue: 0.75)]),
        ("流派".t, "guitars.fill", .allGenres, [Color(red: 0.3, green: 0.8, blue: 0.7), Color(red: 0.1, green: 0.5, blue: 0.5)]),
        ("文件夹".t, "folder.fill", .allFolders, [Color(red: 0.6, green: 0.6, blue: 0.6), Color(red: 0.35, green: 0.35, blue: 0.4)])
        ]
        guard shouldHideServerDependentEntries else { return all }
        return all.filter { $0.route != .radio && $0.route != .podcasts }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Metrics.m) {
                ForEach(categories, id: \.label) { cat in
                    categoryEntry(cat)
                }
            }
            .padding(Metrics.l)
        }
        .reserveMiniPlayer(visible: playback.currentSong != nil)
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("浏览".t)
        .serverRequiredPrompt(isPresented: $showServerPrompt) {
            navigation.openAddServer()
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// 根据当前会话状态绘制浏览入口；需要服务器时先弹确认框。
    @ViewBuilder
    private func categoryEntry(_ cat: (label: String, icon: String, route: BrowseRoute, gradient: [Color])) -> some View {
        if let feature = cat.route.premiumFeature, !purchase.canUse(feature) {
            Button {
                showPaywall(for: feature)
            } label: {
                CategoryTile(label: cat.label, icon: cat.icon, gradient: cat.gradient)
            }
            .buttonStyle(.plain)
        } else if cat.route.requiresServer && session.client == nil && !reviewMode.isEnabled {
            Button {
                Haptics.tap()
                showServerPrompt = true
            } label: {
                CategoryTile(label: cat.label, icon: cat.icon, gradient: cat.gradient)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: cat.route) {
                CategoryTile(label: cat.label, icon: cat.icon, gradient: cat.gradient)
            }
            .buttonStyle(.plain)
        }
    }

    /// 打开指定功能的付费墙，并提供轻触反馈。
    private func showPaywall(for feature: PremiumFeature) {
        Haptics.tap()
        paywallFeature = feature
    }

    /// 判断是否隐藏依赖真实服务器或外部在线资源的入口。
    private var shouldHideServerDependentEntries: Bool {
        reviewMode.isEnabled || session.client == nil
    }
}

private struct CategoryTile: View {
    let label: String
    let icon: String
    let gradient: [Color]
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon)
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: 90, y: 32)
            VStack(alignment: .leading) {
                Spacer()
                Text(label)
                    .font(.nocSection)
                    .foregroundStyle(.white)
                    .padding(Metrics.m)
            }
        }
        .aspectRatio(1.3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))
        .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 12, y: 6)
    }
}
