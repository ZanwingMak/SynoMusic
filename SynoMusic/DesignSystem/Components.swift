import SwiftUI

// MARK: - 玻璃面板

/// 半透明毛玻璃容器：用于卡片、迷你播放器、底部条。
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = Theme.cornerCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - 主要按钮样式

/// 主要按钮：渐变胶囊 + 按压回弹。
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nocBody.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.accentGradient, in: Capsule(style: .continuous))
            .shadow(color: Theme.accent.opacity(0.25), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 次级按钮：描边胶囊。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nocBody.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 圆形图标按钮

/// 圆形图标按钮：用于播放控制条。
struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.soft()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(prominent ? .white : Color.primary)
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(Theme.accentGradient)
                    } else {
                        Circle().fill(Color.primary.opacity(0.08))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 完整功能徽章

/// 已购买用户的完整功能金色徽章。
struct PremiumAccessBadge: View {
    var showsText: Bool = false

    var body: some View {
        HStack(spacing: showsText ? 10 : 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.82, blue: 0.32),
                                Color(red: 0.96, green: 0.56, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: Color.orange.opacity(0.28), radius: 8, y: 4)
                Image(systemName: "crown.fill")
                    .font(.system(size: showsText ? 16 : 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: showsText ? 34 : 30, height: showsText ? 34 : 30)

            if showsText {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完整功能已解锁".t)
                        .font(.nocBody.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("完整功能".t)
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("完整功能已解锁".t)
    }
}

/// 顶部工具栏里的完整功能图标，使用系统符号避免 toolbar 生成方形底色。
struct PremiumToolbarIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.35),
                            Color(red: 0.98, green: 0.55, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .accessibilityLabel("完整功能已解锁".t)
    }
}

// MARK: - 加载/空态/错误状态

/// 通用加载占位。
struct LoadingState: View {
    var body: some View {
        VStack(spacing: Metrics.m) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.accent)
            Text("正在加载".t)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("正在加载".t)
    }
}

/// 通用空态。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.nocSection)
            Text(message)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metrics.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 未添加服务器时的通用空态，附带跳转添加服务器的主按钮。
struct ServerRequiredEmptyState: View {
    var systemImage: String = "externaldrive.connected.to.line.below"
    var title: String = "请添加您的服务器"
    var message: String = "请添加您的服务器加载 NAS 里的音乐。"
    let action: () -> Void

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title.t)
                .font(.nocSection)
            Text(message.t)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                action()
            } label: {
                Label("添加服务器".t, systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 240)
            .padding(.top, Metrics.s)
        }
        .padding(.horizontal, Metrics.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 需要服务器的入口确认框，确定后进入添加服务器流程。
struct ServerRequiredPromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    /// 给当前视图挂载“需要服务器”的确认弹窗。
    func body(content: Content) -> some View {
        content.alert("需要添加服务器".t, isPresented: $isPresented) {
            Button("取消".t, role: .cancel) { }
            Button("确定".t) {
                Haptics.tap()
                onConfirm()
            }
        } message: {
            Text("请添加您的服务器加载 NAS 里的音乐。".t)
        }
    }
}

extension View {
    /// 展示需要服务器的确认框。
    func serverRequiredPrompt(isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        modifier(ServerRequiredPromptModifier(isPresented: isPresented, onConfirm: onConfirm))
    }
}

/// 通用错误态。
struct ErrorStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(title)
                .font(.nocSection)
            Text(message)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Metrics.xl)
            if let retry {
                RetryButton(action: retry)
                    .frame(maxWidth: 200)
                    .padding(.top, Metrics.s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 带旋转 + 缩放动效的"重试"按钮。
private struct RetryButton: View {
    let action: () -> Void
    @State private var rotation: Double = 0
    @State private var pressed: Bool = false

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                rotation += 360
                pressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                pressed = false
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(rotation))
                Text("重试".t)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .scaleEffect(pressed ? 0.9 : 1)
    }
}

// MARK: - 网络封面

/// 在线封面查询参数，只保留可发送、可缓存的文本字段。
struct CoverLookupQuery: Hashable, Sendable {
    let title: String
    let artist: String
    let album: String

    /// 从标题、歌手和专辑名构建在线封面查询。
    init(title: String, artist: String?, album: String?) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = (album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从歌曲模型提取在线封面查询字段。
    init(song: Song) {
        self.init(title: song.title, artist: song.artist, album: song.album)
    }

    /// 用于 SwiftUI task 刷新的稳定 key。
    var cacheKey: String {
        [title, artist, album].joined(separator: "|").lowercased()
    }

    /// iTunes 搜索关键字。
    var searchTerm: String {
        [title, artist, album].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 是否为审核截图或 mock 数据的占位内容。
    var isDemoPlaceholder: Bool {
        let values = [title, artist, album].filter { !$0.isEmpty }
        return !values.isEmpty && values.allSatisfy { $0.lowercased() == "demo" }
    }
}

/// 在线封面查询缓存，避免列表和播放器重复请求同一首歌。
actor OnlineCoverLookupCache {
    static let shared = OnlineCoverLookupCache()

    private var cache: [CoverLookupQuery: URL?] = [:]

    /// 查询封面 URL；命中缓存时直接返回。
    func url(for query: CoverLookupQuery?) async -> URL? {
        guard let query, !query.searchTerm.isEmpty, !query.isDemoPlaceholder else { return nil }
        if let cached = cache[query] { return cached }
        let result = await Self.fetchArtworkURL(for: query)
        cache[query] = result
        return result
    }

    /// 调用 iTunes Search API 查找最接近的音乐封面。
    private static func fetchArtworkURL(for query: CoverLookupQuery) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query.searchTerm),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components?.url else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        guard let raw = response.results.first?.artworkUrl100 else { return nil }
        return URL(string: raw.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            ?? URL(string: raw)
    }

    private struct Response: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let artworkUrl100: String?
    }
}

/// 远程加载的封面图：失败/未加载时显示渐变占位。
struct CoverArt: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var fallbackSeed: String = ""
    var lookup: CoverLookupQuery? = nil
    @State private var primaryFailed: Bool = false
    @State private var onlineFallbackURL: URL?

    var body: some View {
        Group {
            if let url, !primaryFailed {
                remoteImage(url: url, marksPrimaryFailure: true)
            } else if let onlineFallbackURL {
                remoteImage(url: onlineFallbackURL, marksPrimaryFailure: false)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: lookupTaskID) { await loadOnlineFallbackIfNeeded() }
        .onChange(of: url) { _, _ in resetLoadingState() }
        .onChange(of: lookup) { _, _ in resetLoadingState() }
    }

    /// 用种子生成稳定渐变，避免占位看起来千篇一律。
    private var placeholderGradient: some View {
        let hue = abs(Double(fallbackSeed.hashValue % 1000)) / 1000.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.45, brightness: 0.85),
                Color(hue: (hue + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 封面占位图。
    private var placeholder: some View {
        placeholderGradient
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
    }

    /// 远程图片视图；主封面失败时切换到在线兜底查询。
    private func remoteImage(url: URL, marksPrimaryFailure: Bool) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.35))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
                    .onAppear {
                        if marksPrimaryFailure {
                            primaryFailed = true
                        }
                    }
            default:
                placeholder
            }
        }
    }

    /// 在线兜底查询的刷新 key。
    private var lookupTaskID: String {
        [
            lookup?.cacheKey ?? "",
            url?.absoluteString ?? "",
            primaryFailed.description
        ].joined(separator: "|")
    }

    /// 原封面不可用时，从在线缓存查询封面。
    private func loadOnlineFallbackIfNeeded() async {
        guard onlineFallbackURL == nil else { return }
        guard url == nil || primaryFailed else { return }
        guard let found = await OnlineCoverLookupCache.shared.url(for: lookup) else { return }
        await MainActor.run {
            onlineFallbackURL = found
        }
    }

    /// 输入歌曲或封面 URL 变化时重置加载状态。
    private func resetLoadingState() {
        primaryFailed = false
        onlineFallbackURL = nil
    }
}
