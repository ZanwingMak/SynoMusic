import SwiftUI

/// 电台浏览：标签筛选 + 国家筛选 + 关键词搜索 + 热门。
struct RadioBrowseView: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @State private var stations: [RadioStation] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var mode: Mode = .top
    @State private var query: String = ""
    private let api = RadioAPI.shared

    /// 常用快捷过滤项。
    private static let countries: [(code: String, label: String)] = [
        ("CN", "中国大陆".t), ("HK", "香港".t), ("TW", "台湾".t),
        ("JP", "日本".t), ("KR", "韩国".t),
        ("US", "美国".t), ("GB", "英国".t), ("FR", "法国".t), ("DE", "德国".t),
        ("BR", "巴西".t), ("IN", "印度".t), ("AU", "澳大利亚".t)
    ]
    private static let tags: [String] = [
        "pop", "rock", "jazz", "classical", "news",
        "ambient", "electronic", "hip hop", "country", "chinese"
    ]

    enum Mode: Equatable, Hashable {
        case top
        case country(String, String) // code, label
        case tag(String)
        case search(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                pillRow

                if isLoading && stations.isEmpty {
                    LoadingState().frame(height: 240)
                } else if let err = error {
                    ErrorStateView(title: "加载失败".t, message: err) { Task { await load() } }
                        .frame(height: 240)
                } else if stations.isEmpty {
                    EmptyStateView(systemImage: "antenna.radiowaves.left.and.right",
                                   title: "没找到电台".t,
                                   message: "换个关键词或切换分类。".t)
                        .frame(height: 240)
                } else {
                    VStack(spacing: Metrics.s) {
                        ForEach(stations) { station in
                            RadioRow(station: station) { tap(station) }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.top, Metrics.s)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("电台".t)
        .searchable(text: $query, prompt: "搜索电台".t)
        .onSubmit(of: .search) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            mode = .search(query)
            Task { await load() }
        }
        .task {
            await api.resolveMirror()
            await load()
        }
    }

    // MARK: 子组件

    private var pillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.s) {
                pill("热门".t, isActive: mode == .top) {
                    mode = .top; Task { await load() }
                }
                ForEach(Self.countries, id: \.code) { item in
                    let active = mode == .country(item.code, item.label)
                    pill(item.label, isActive: active) {
                        mode = .country(item.code, item.label); Task { await load() }
                    }
                }
                ForEach(Self.tags, id: \.self) { t in
                    let active = mode == .tag(t)
                    pill(t.capitalized, isActive: active) {
                        mode = .tag(t); Task { await load() }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func pill(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.tap()
            // 立刻清空旧结果，触发 LoadingState；防止"切了但看起来没变化"的错觉。
            stations = []
            isLoading = true
            error = nil
            action()
        }) {
            Text(label)
                .font(.nocLabel.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isActive ? Theme.accent : Color.primary.opacity(0.06), in: Capsule())
                .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func tap(_ station: RadioStation) {
        Haptics.soft()
        playback.play(queue: [station.asSong()], startAt: 0, honoringShuffle: false, contextTitle: "电台".t)
        Task { await api.reportClick(station.stationuuid) }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        error = nil
        do {
            switch mode {
            case .top:
                stations = try await api.topStations()
            case .country(let code, _):
                stations = try await api.stations(countryCode: code)
            case .tag(let tag):
                stations = try await api.stations(tag: tag)
            case .search(let kw):
                stations = try await api.search(kw)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct RadioRow: View {
    let station: RadioStation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Metrics.m) {
                AsyncImage(url: station.faviconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.accentGradient)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name)
                        .font(.nocBody.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let c = station.country, !c.isEmpty {
                            Text(c).font(.nocLabel).foregroundStyle(.secondary)
                        }
                        if let b = station.bitrate, b > 0 {
                            Text("· \(b) kbps").font(.nocLabel).foregroundStyle(.tertiary)
                        }
                    }
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
