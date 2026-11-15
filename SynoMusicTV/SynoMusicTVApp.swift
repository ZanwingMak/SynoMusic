import SwiftUI

/// Apple TV 使用独立场景和原生焦点界面，共享服务器协议、媒体模型与收藏仓库。
@main
struct SynoMusicTVApp: App {
    @StateObject private var library = TVLibraryStore()
    @StateObject private var playback = TVPlayback()
    @StateObject private var servers = ServerStore()
    @StateObject private var playlists = PlaylistStore()
    @StateObject private var language = LanguageManager.shared

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(library).environmentObject(playback)
                .environmentObject(servers).environmentObject(playlists).environmentObject(language)
                .preferredColorScheme(.dark).tint(TVStyle.accent)
                .buttonStyle(TVControlStyle())
        }
    }
}

extension String {
    /// 电视与手机使用同一份翻译，不在各屏幕维护重复的语言判断。
    @MainActor var t: String { LanguageManager.shared.t(self) }
}

/// 电视的字号和材质针对远距离阅读，不沿用手机触控尺寸。
enum TVStyle {
    static let accent = Color(red: 0.86, green: 0.64, blue: 0.46)
    static let background = Color(red: 0.075, green: 0.085, blue: 0.08)
    static let surface = Color.white.opacity(0.055)
}

/// 路由保存真实媒体标识，遥控器返回由系统 NavigationStack 处理。
enum TVRoute: Hashable {
    case album(Album), artists, artist(Artist), songs, favorites, history, mixes, mix(String)
    case playlists, playlist(UUID), serverPlaylists, remotePlaylist(Playlist)
    case genres, genre(String), folders, folder(String), nasFolder(FolderNode), radio, podcasts, episodes(PodcastShow)
}

/// 五个顶级入口由系统 TV TabView 承载，避免自制导航造成焦点陷阱。
struct TVRootView: View {
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var servers: ServerStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var language: LanguageManager
    @State private var path: [TVRoute] = []
    @State private var showPlayer = false

    var body: some View {
        NavigationStack(path: $path) {
            TabView {
                TVHomeView().tabItem { Label("资料库".t, systemImage: "square.stack") }
                TVBrowseView().tabItem { Label("浏览".t, systemImage: "square.grid.2x2") }
                TVCollectionView().tabItem { Label("我的音乐".t, systemImage: "heart") }
                TVSearchView().tabItem { Label("搜索".t, systemImage: "magnifyingglass") }
                TVSettingsView().tabItem { Label("设置".t, systemImage: "slider.horizontal.3") }
            }
            .id(language.current.rawValue)
            .navigationDestination(for: TVRoute.self) { TVDestination(route: $0) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playback.song != nil { TVPlaybackDock { showPlayer = true }.padding(.horizontal, 64).padding(.bottom, 20) }
            }
            .background(TVStyle.background.ignoresSafeArea())
        }
        .fullScreenCover(isPresented: $showPlayer) { TVNowPlayingView { showPlayer = false }.tvControls() }
        .onPlayPauseCommand { playback.toggle() }
        .onReceive(library.$client) { client in playback.setSource(client, demo: client == nil && library.isDemo) }
        .onChange(of: library.isDemo) { _, demo in playback.setSource(library.client, demo: demo) }
        .task {
            guard library.client == nil && !library.isDemo else { return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                library.useDemo(playlists: playlists)
                playback.setSource(nil, demo: true)
                if ProcessInfo.processInfo.arguments.contains("-player") { playback.play(library.songs); showPlayer = true }
                return
            }
            #endif
            if let profile = servers.defaultProfile, servers.password(for: profile) != nil {
                await library.connect(profile, password: "", servers: servers, playlists: playlists)
            }
        }
    }
}

/// 原生按钮的焦点状态明确可见；减少动态效果时停用缩放过渡。
struct TVCardStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 焦点同时通过边框、明度和尺寸表达，不仅依赖颜色。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(18)
            .background(focused ? Color.white.opacity(0.16) : TVStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(focused ? TVStyle.accent : .white.opacity(0.06), lineWidth: focused ? 3 : 1) }
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.98 : focused ? 1.025 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focused)
    }
}

/// 普通操作使用明确的文本对比，避免 TV 系统填色样式与强调色叠加后丢失标签。
struct TVControlStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 聚焦时变为亮底深字，非聚焦时保留浅字描边；不只用颜色表示焦点。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(focused ? TVStyle.background : .white)
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(focused ? .white : .white.opacity(0.08), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(focused ? 1 : 0.15), lineWidth: focused ? 3 : 1) }
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.97 : focused ? 1.04 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
    }
}

/// 真实封面请求失败时使用中性音乐符号，原创演示封面只用于明确的演示资料。
struct TVArtwork: View {
    @EnvironmentObject private var library: TVLibraryStore
    var url: URL?
    let title: String
    var body: some View {
        Group {
            if library.isDemo { DemoArtworkView(title: title, seed: title) }
            else {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                    ZStack { LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "music.note").font(.system(size: 48)).foregroundStyle(.white.opacity(0.4)) }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// 大屏标题保留足够行高，并始终标明当前资料来源。
struct TVHeading: View {
    let title: String
    var subtitle = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SYNO / MUSIC").font(.system(size: 17, weight: .medium)).tracking(4).foregroundStyle(TVStyle.accent)
            Text(title).font(.system(size: 54, weight: .bold)).lineLimit(2)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 24)).foregroundStyle(.secondary).lineLimit(3) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
    }
}

/// 连接、加载、失败和空结果各有明确状态，不用空白屏代替反馈。
struct TVEmptyState: View {
    let title: String
    let message: String
    var symbol = "music.note"
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: symbol).font(.system(size: 64, weight: .light)).foregroundStyle(TVStyle.accent)
            Text(title).font(.title2.bold())
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 860)
            if let retry { Button("重试".t, action: retry) }
        }.frame(maxWidth: .infinity, minHeight: 400).padding(40)
    }
}

/// 全站播放条只使用独立按钮，不把播放和展开动作嵌套在同一点击区。
private struct TVPlaybackDock: View {
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var library: TVLibraryStore
    let onExpand: () -> Void
    var body: some View {
        HStack(spacing: 22) {
            Button(action: onExpand) {
                HStack(spacing: 18) {
                    TVArtwork(url: playback.song.flatMap { library.client?.songCoverURL(song: $0) }, title: playback.song?.album ?? "").frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(playback.song?.title ?? "").font(.system(size: 24, weight: .semibold)).lineLimit(1)
                        Text(playback.song?.artist ?? "").font(.system(size: 19)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.title3)
                }.padding(8)
            }.buttonStyle(TVCardStyle()).accessibilityLabel("正在播放".t)
            Button(action: playback.toggle) { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel((playback.isPlaying ? "暂停" : "播放").t)
            Button { playback.advance() } label: { Image(systemName: "forward.fill").frame(width: 44, height: 44) }.accessibilityLabel("下一首".t)
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}


extension View {
    /// 模态页面显式继承电视的按钮与深色外观，避免系统填色掩盖按钮文字。
    func tvControls() -> some View {
        buttonStyle(TVControlStyle()).tint(TVStyle.accent).preferredColorScheme(.dark)
    }
}
