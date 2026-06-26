import SwiftUI

/// 资料库首页：欢迎语 + 最近添加的专辑墙 + 推荐艺术家。
struct LibraryHomeView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var purchase: PurchaseStore
    @StateObject private var vm = LibraryHomeViewModel()
    @State private var paywallFeature: PremiumFeature?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                Header()
                QuickActions()
                if vm.isLoading && vm.recentAlbums.isEmpty {
                    LoadingState().frame(height: 280)
                } else if let err = vm.error {
                    ErrorStateView(title: "加载失败".t, message: err) { Task { await vm.load(client: session.client) } }
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
        .refreshable { await vm.load(client: session.client, force: true) }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("SynoMusic")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                purchaseButton
                toolbarLink(value: BrowseRoute.localPlaylists, systemImage: "music.note.list", label: "我的歌单".t)
                toolbarLink(value: BrowseRoute.radio, systemImage: "antenna.radiowaves.left.and.right", label: "电台".t)
                toolbarLink(value: BrowseRoute.settings, systemImage: "gearshape", label: "设置".t)
            }
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await vm.load(client: session.client) }
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
            Text(timeGreeting())
                .font(.nocCaption)
                .foregroundStyle(.secondary)
            Text("听听今天该听的".t)
                .font(.system(.title, design: .rounded).weight(.bold))
        }
        .padding(.top, Metrics.s)
    }
    private func timeGreeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "早安".t
        case 11..<14: return "中午好".t
        case 14..<18: return "下午好".t
        case 18..<23: return "晚上好".t
        default: return "夜深了".t
        }
    }
}

/// 资料库首页顶部的快捷卡片横向滑动区。
private struct QuickActions: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @State private var isShuffling = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.m) {
                Button { Task { await randomShuffleAll() } } label: {
                    ActionCard(
                        title: "随机歌单".t,
                        subtitle: isShuffling ? "正在抓取…".t : "从全库抽 100 首".t,
                        icon: "shuffle",
                        gradient: [Color(red: 0.95, green: 0.42, blue: 0.65), Color(red: 0.55, green: 0.20, blue: 0.95)]
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: BrowseRoute.smartMixes) {
                    ActionCard(
                        title: "智能歌单".t,
                        subtitle: "自动整理".t,
                        icon: "wand.and.stars",
                        gradient: [Color(red: 0.95, green: 0.68, blue: 0.22), Color(red: 0.88, green: 0.28, blue: 0.48)]
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: BrowseRoute.favorites) {
                    ActionCard(
                        title: "我喜欢的".t,
                        subtitle: "本地收藏".t,
                        icon: "heart.fill",
                        gradient: [Color(red: 0.99, green: 0.4, blue: 0.55), Color(red: 0.85, green: 0.15, blue: 0.45)]
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: BrowseRoute.allSongs) {
                    ActionCard(
                        title: "所有歌曲".t,
                        subtitle: "整库浏览".t,
                        icon: "music.note",
                        gradient: [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.25, green: 0.25, blue: 0.65)]
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: BrowseRoute.radio) {
                    ActionCard(
                        title: "电台".t,
                        subtitle: "全球电台".t,
                        icon: "antenna.radiowaves.left.and.right",
                        gradient: [Color(red: 0.4, green: 0.85, blue: 0.7), Color(red: 0.1, green: 0.55, blue: 0.55)]
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: BrowseRoute.allAlbums) {
                    ActionCard(
                        title: "全部专辑".t,
                        subtitle: "整库浏览".t,
                        icon: "square.stack.fill",
                        gradient: [Color(red: 0.95, green: 0.6, blue: 0.3), Color(red: 0.85, green: 0.3, blue: 0.3)]
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .scrollClipDisabled()
    }

    private func randomShuffleAll() async {
        guard let api = session.client?.audioStation else {
            playback.setStatus("请先连接服务器再随机播放".t)
            return
        }
        isShuffling = true
        defer { isShuffling = false }
        do {
            let songs = try await api.randomSongs(count: 100)
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
                url: session.client?.audioStation.albumCoverURL(album: album.name, albumArtist: album.artist),
                cornerRadius: 14,
                fallbackSeed: album.id
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
            url: session.client?.audioStation.albumCoverURL(album: album.name, albumArtist: album.artist),
            cornerRadius: 10,
            fallbackSeed: album.id
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
