import SwiftUI

/// 资料库首页：欢迎语 + 最近添加的专辑墙 + 推荐艺术家。
struct LibraryHomeView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var reviewMode: AppReviewMode
    @EnvironmentObject private var navigation: AppNavigationState
    @StateObject private var vm = LibraryHomeViewModel()
    @State private var paywallFeature: PremiumFeature?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                Header()
                QuickActions()
                if session.isRestoringStartupSession && !reviewMode.isEnabled {
                    LoadingState()
                        .frame(minHeight: 300)
                } else if session.musicClient == nil && !reviewMode.isEnabled {
                    ServerRequiredEmptyState {
                        navigation.openAddServer()
                    }
                    .frame(minHeight: 300)
                } else if vm.isLoading && vm.recentAlbums.isEmpty {
                    LoadingState().frame(height: 280)
                } else if let err = vm.error {
                    ErrorStateView(title: "加载失败".t, message: err) { Task { await vm.load(musicClient: session.musicClient, useMockData: reviewMode.isEnabled) } }
                        .frame(height: 280)
                } else {
                    if !vm.recentAlbums.isEmpty {
                        SectionTitle("最近添加".t)
                        FeaturedAlbumScroller(albums: vm.recentAlbums)
                    }
                    if !vm.albums.isEmpty {
                        SectionTitle("全部专辑".t)
                        AlbumGrid(albums: vm.albums)
                    }
                    if !vm.artists.isEmpty {
                        SectionTitle("艺术家".t)
                        ArtistRail(artists: vm.artists)
                    }
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.top, Metrics.s)
        }
        .refreshable { await vm.load(musicClient: session.musicClient, force: true, useMockData: reviewMode.isEnabled) }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("SynoMusic")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                purchaseButton
                toolbarLink(value: BrowseRoute.localPlaylists, systemImage: "music.note.list", label: "我的歌单".t)
                toolbarLink(value: BrowseRoute.settings, systemImage: "gearshape", label: "设置".t)
            }
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task(id: homeLoadIdentity) {
            await vm.load(musicClient: session.musicClient, force: true, useMockData: reviewMode.isEnabled)
        }
    }

    /// 首页加载身份；音乐源、服务器或音乐库变化都需要重新加载。
    private var homeLoadIdentity: String {
        guard let profile = session.musicClient?.profile else {
            return reviewMode.isEnabled ? "review" : "none"
        }
        return [
            profile.providerType.rawValue,
            profile.id.uuidString,
            profile.musicLibraryID ?? ""
        ].joined(separator: ":")
    }

    /// 首页右上角的购买与订阅入口。
    private var purchaseButton: some View {
        Button {
            Haptics.tap()
            paywallFeature = .allAccess
        } label: {
            if purchase.hasFullAccess {
                PremiumToolbarIcon()
            } else {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityLabel(purchase.hasFullAccess ? "完整功能已解锁".t : "购买与订阅".t)
        .buttonStyle(.plain)
    }

    /// 带轻触反馈的导航栏图标入口。
    private func toolbarLink(value: BrowseRoute, systemImage: String, label: String) -> some View {
        NavigationLink(value: value) {
            Image(systemName: systemImage)
                .accessibilityLabel(label)
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}

// MARK: 子组件

private struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeGreeting().t)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
            Text(headline().t)
                .font(.system(.title, design: .rounded).weight(.bold))
        }
        .padding(.top, Metrics.s)
    }

    /// 根据当前日期稳定挑选一句首页主文案，避免每次刷新跳动。
    private func headline() -> String {
        let lines = [
            "听听今天该听的",
            "今天想听点什么？",
            "让音乐接管这一刻",
            "从一首歌开始",
            "把喜欢的声音找回来",
            "适合安静听歌的时刻"
        ]
        return pick(from: lines, salt: 17)
    }

    /// 从候选文案中按日期和小时挑一个稳定值。
    private func pick(from values: [String], salt: Int) -> String {
        guard !values.isEmpty else { return "" }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let hour = Calendar.current.component(.hour, from: Date())
        return values[(day + hour + salt) % values.count]
    }

    /// 当前时段的问候语，增加更多变化但保持同一时段语义。
    private func timeGreeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11:
            return pick(from: ["早安", "早上好，先放一首喜欢的", "新的早晨，新的播放队列"], salt: 3)
        case 11..<14:
            return pick(from: ["中午好", "午间换个节奏", "让午休多一点声音"], salt: 5)
        case 14..<18:
            return pick(from: ["下午好", "下午适合慢慢听", "给下午一点律动"], salt: 7)
        case 18..<23:
            return pick(from: ["晚上好", "夜色刚好，音乐也刚好", "今晚从哪首开始？"], salt: 11)
        default:
            return pick(from: ["夜深了", "深夜适合小声播放", "晚点了，听点温柔的"], salt: 13)
        }
    }
}

/// 资料库首页顶部的快捷卡片横向滑动区。
private struct QuickActions: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var reviewMode: AppReviewMode
    @EnvironmentObject private var navigation: AppNavigationState
    @State private var isShuffling = false
    @State private var showServerPrompt = false
    @State private var paywallFeature: PremiumFeature?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.m) {
                Button { handleShuffleTap() } label: {
                    ActionCard(
                        title: "随机歌单".t,
                        subtitle: isShuffling ? "正在抓取…".t : "从全库抽 100 首".t,
                        icon: "shuffle",
                        gradient: [Color(red: 0.95, green: 0.42, blue: 0.65), Color(red: 0.55, green: 0.20, blue: 0.95)]
                    )
                }
                .buttonStyle(.plain)

                if session.musicClient == nil || session.isSynologySession || reviewMode.isEnabled {
                    routeCard(
                        route: .smartMixes,
                        title: "智能歌单".t,
                        subtitle: "自动整理".t,
                        icon: "wand.and.stars",
                        gradient: [Color(red: 0.95, green: 0.68, blue: 0.22), Color(red: 0.88, green: 0.28, blue: 0.48)]
                    )
                }

                NavigationLink(value: BrowseRoute.favorites) {
                    ActionCard(
                        title: "我喜欢的".t,
                        subtitle: "本地收藏".t,
                        icon: "heart.fill",
                        gradient: [Color(red: 0.99, green: 0.4, blue: 0.55), Color(red: 0.85, green: 0.15, blue: 0.45)]
                    )
                }
                .buttonStyle(.plain)

                routeCard(
                    route: .allSongs,
                    title: "所有歌曲".t,
                    subtitle: "整库浏览".t,
                    icon: "music.note",
                    gradient: [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.25, green: 0.25, blue: 0.65)]
                )

                if shouldShowServerDependentEntries {
                    routeCard(
                        route: .radio,
                        title: "电台".t,
                        subtitle: "全球电台".t,
                        icon: "antenna.radiowaves.left.and.right",
                        gradient: [Color(red: 0.4, green: 0.85, blue: 0.7), Color(red: 0.1, green: 0.55, blue: 0.55)]
                    )

                    routeCard(
                        route: .podcasts,
                        title: "播客".t,
                        subtitle: "网上搜索".t,
                        icon: "mic.circle.fill",
                        gradient: [Color(red: 0.95, green: 0.35, blue: 0.72), Color(red: 0.48, green: 0.28, blue: 0.88)]
                    )
                }

                routeCard(
                    route: .allAlbums,
                    title: "全部专辑".t,
                    subtitle: "整库浏览".t,
                    icon: "square.stack.fill",
                    gradient: [Color(red: 0.95, green: 0.6, blue: 0.3), Color(red: 0.85, green: 0.3, blue: 0.3)]
                )
            }
        }
        .scrollClipDisabled()
        .serverRequiredPrompt(isPresented: $showServerPrompt) {
            navigation.openAddServer()
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// 点击随机播放时先检查是否已连接服务器。
    private func handleShuffleTap() {
        guard session.musicClient != nil || reviewMode.isEnabled else {
            Haptics.tap()
            showServerPrompt = true
            return
        }
        Task { await randomShuffleAll() }
    }

    /// 绘制快捷入口；付费功能优先弹付费墙，需要服务器的页面再弹添加服务器确认框。
    @ViewBuilder
    private func routeCard(route: BrowseRoute, title: String, subtitle: String, icon: String, gradient: [Color]) -> some View {
        if let feature = route.premiumFeature, !purchase.canUse(feature) {
            Button {
                showPaywall(for: feature)
            } label: {
                ActionCard(title: title, subtitle: subtitle, icon: icon, gradient: gradient)
            }
            .buttonStyle(.plain)
        } else if route.requiresServer && session.musicClient == nil && !reviewMode.isEnabled {
            Button {
                Haptics.tap()
                showServerPrompt = true
            } label: {
                ActionCard(title: title, subtitle: subtitle, icon: icon, gradient: gradient)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: route) {
                ActionCard(title: title, subtitle: subtitle, icon: icon, gradient: gradient)
            }
            .buttonStyle(.plain)
        }
    }

    /// 打开指定功能的付费墙，并提供轻触反馈。
    private func showPaywall(for feature: PremiumFeature) {
        Haptics.tap()
        paywallFeature = feature
    }

    /// 判断是否显示依赖真实服务器或外部在线资源的快捷入口。
    private var shouldShowServerDependentEntries: Bool {
        session.musicClient != nil && !reviewMode.isEnabled
    }

    /// 从服务器随机抓取歌曲，审核模式或未连接由入口提前处理。
    private func randomShuffleAll() async {
        if reviewMode.isEnabled {
            playback.play(queue: DemoMode.songs.shuffled(), startAt: 0, honoringShuffle: false, contextTitle: "随机100首".t)
            return
        }
        guard let musicClient = session.musicClient else {
            playback.setStatus("请先连接服务器再随机播放".t)
            return
        }
        isShuffling = true
        defer { isShuffling = false }
        do {
            let songs = try await musicClient.randomSongs(count: 100)
            guard !songs.isEmpty else {
                playback.setStatus("没有可播放的歌曲".t)
                return
            }
            playback.play(queue: songs, startAt: 0, honoringShuffle: false, contextTitle: "随机100首".t)
        } catch {
            playback.setStatus("随机抓取失败".t + "：\(error.localizedDescription)")
        }
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon)
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.white.opacity(0.18))
                .offset(x: 54, y: 18)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(title).font(.nocSection).foregroundStyle(.white)
                Text(subtitle).font(.nocLabel).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            .padding(Metrics.m)
        }
        .frame(width: 146, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerCard, style: .continuous))
        .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 12, y: 6)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.nocSection)
            .padding(.top, Metrics.s)
    }
}

private struct FeaturedAlbumScroller: View {
    @EnvironmentObject private var session: AppSession
    let albums: [Album]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.m) {
                ForEach(albums) { album in
                    NavigationLink(value: BrowseRoute.album(album)) {
                        FeaturedAlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}

private struct FeaturedAlbumCard: View {
    @EnvironmentObject private var session: AppSession
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            CoverArt(
                url: session.musicClient?.albumCoverURL(album: album),
                cornerRadius: 14,
                fallbackSeed: album.id,
                lookup: CoverLookupQuery(title: album.name, artist: album.artist, album: album.name)
            )
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.nocBody.weight(.semibold))
                    .lineLimit(1)
                Text(album.displayArtist)
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)
        }
    }
}

private struct AlbumGrid: View {
    let albums: [Album]
    @EnvironmentObject private var session: AppSession
    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Metrics.m),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Metrics.m)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.l) {
            ForEach(albums) { album in
                NavigationLink(value: BrowseRoute.album(album)) {
                    AlbumCell(album: album)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AlbumCell: View {
    @EnvironmentObject private var session: AppSession
    let album: Album
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    albumCover
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(album.name)
                .font(.nocBody.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            Text(album.displayArtist)
                .font(.nocLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 专辑封面固定填满方形容器，避免异步图片按原始尺寸撑开网格。
    private var albumCover: some View {
        CoverArt(
            url: session.musicClient?.albumCoverURL(album: album),
            cornerRadius: 10,
            fallbackSeed: album.id,
            lookup: CoverLookupQuery(title: album.name, artist: album.artist, album: album.name)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct ArtistRail: View {
    let artists: [Artist]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.m) {
                ForEach(artists) { artist in
                    NavigationLink(value: BrowseRoute.artist(artist)) {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(LinearGradient(
                                    colors: gradient(for: artist.name),
                                    startPoint: .top, endPoint: .bottom
                                ))
                                .overlay(
                                    Text(artist.name.prefix(1).uppercased())
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                )
                                .frame(width: 76, height: 76)
                            Text(artist.name)
                                .font(.nocLabel)
                                .lineLimit(1)
                                .frame(width: 80)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
    private func gradient(for name: String) -> [Color] {
        let hue = abs(Double(name.hashValue % 1000)) / 1000.0
        return [
            Color(hue: hue, saturation: 0.6, brightness: 0.9),
            Color(hue: (hue + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.5)
        ]
    }
}
