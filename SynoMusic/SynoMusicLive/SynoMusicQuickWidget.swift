import AppIntents
import SwiftUI
import WidgetKit

/// SynoMusic 桌面小组件可选样式。
enum SynoMusicWidgetStyle: String, AppEnum {
    case smartMixes
    case downloads
    case vinyl
    case recent
    case widgets

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "SynoMusic Widget Style")
    }

    static var caseDisplayRepresentations: [SynoMusicWidgetStyle: DisplayRepresentation] {
        [
            .smartMixes: DisplayRepresentation(title: "Smart Mixes"),
            .downloads: DisplayRepresentation(title: "Downloads"),
            .vinyl: DisplayRepresentation(title: "Vinyl Player"),
            .recent: DisplayRepresentation(title: "Recently Played"),
            .widgets: DisplayRepresentation(title: "Widget Manager")
        ]
    }

    /// 小组件标题本地化 key。
    var titleKey: String {
        switch self {
        case .smartMixes: return "智能歌单"
        case .downloads: return "下载管理"
        case .vinyl: return "黑胶唱片"
        case .recent: return "最近播放"
        case .widgets: return "小组件管理"
        }
    }

    /// 小组件副标题本地化 key。
    var subtitleKey: String {
        switch self {
        case .smartMixes: return "每日推荐"
        case .downloads: return "离线音乐"
        case .vinyl: return "播放入口"
        case .recent: return "继续聆听"
        case .widgets: return "编辑样式"
        }
    }

    /// 对应的 SF Symbol。
    var icon: String {
        switch self {
        case .smartMixes: return "wand.and.stars"
        case .downloads: return "arrow.down.circle"
        case .vinyl: return "record.circle"
        case .recent: return "clock.arrow.circlepath"
        case .widgets: return "rectangle.3.group"
        }
    }

    /// 点击小组件后打开的深链。
    var deepLink: URL {
        switch self {
        case .smartMixes:
            return URL(string: "synomusic://smart-mixes")!
        case .downloads:
            return URL(string: "synomusic://downloads")!
        case .widgets:
            return URL(string: "synomusic://widgets")!
        case .vinyl, .recent:
            return URL(string: "synomusic://smart-mixes")!
        }
    }

    /// 主题渐变颜色。
    var colors: [Color] {
        switch self {
        case .smartMixes:
            return [Color(red: 0.96, green: 0.33, blue: 0.60), Color(red: 0.98, green: 0.56, blue: 0.22), Color(red: 0.45, green: 0.26, blue: 0.92)]
        case .downloads:
            return [Color(red: 0.08, green: 0.50, blue: 0.78), Color(red: 0.22, green: 0.78, blue: 0.70)]
        case .vinyl:
            return [Color(red: 0.08, green: 0.07, blue: 0.07), Color(red: 0.40, green: 0.25, blue: 0.13)]
        case .recent:
            return [Color(red: 0.14, green: 0.31, blue: 0.70), Color(red: 0.52, green: 0.20, blue: 0.82)]
        case .widgets:
            return [Color(red: 0.15, green: 0.16, blue: 0.24), Color(red: 0.44, green: 0.30, blue: 0.86)]
        }
    }
}

/// 小组件编辑面板里的配置项。
struct SynoMusicWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "SynoMusic Widget"
    static let description = IntentDescription("Choose what this SynoMusic widget shows.")

    @Parameter(title: "Content", default: .smartMixes)
    var style: SynoMusicWidgetStyle
}

/// 桌面小组件：提供可编辑的 SynoMusic 快捷入口。
struct SynoMusicQuickWidget: Widget {
    private let kind = "SynoMusicQuickWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SynoMusicWidgetIntent.self, provider: SynoMusicQuickTimelineProvider()) { entry in
            SynoMusicQuickWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetL10n.text("SynoMusic 小组件"))
        .description(WidgetL10n.text("长按小组件可切换样式"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// 小组件时间线条目。
private struct SynoMusicQuickEntry: TimelineEntry {
    let date: Date
    let style: SynoMusicWidgetStyle
}

/// 小组件静态时间线提供者。
private struct SynoMusicQuickTimelineProvider: AppIntentTimelineProvider {
    /// 占位内容。
    func placeholder(in context: Context) -> SynoMusicQuickEntry {
        SynoMusicQuickEntry(date: Date(), style: .smartMixes)
    }

    /// 小组件图库预览内容。
    func snapshot(for configuration: SynoMusicWidgetIntent, in context: Context) async -> SynoMusicQuickEntry {
        SynoMusicQuickEntry(date: Date(), style: configuration.style)
    }

    /// 小组件无需频繁刷新，提供静态时间线。
    func timeline(for configuration: SynoMusicWidgetIntent, in context: Context) async -> Timeline<SynoMusicQuickEntry> {
        Timeline(entries: [SynoMusicQuickEntry(date: Date(), style: configuration.style)], policy: .never)
    }
}

/// 小组件视图。
private struct SynoMusicQuickWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SynoMusicQuickEntry

    var body: some View {
        Link(destination: entry.style.deepLink) {
            Group {
                if family == .systemSmall {
                    smallWidget
                } else {
                    mediumWidget
                }
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    /// 小号小组件：突出当前选择的一个入口。
    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                appMark
                Spacer()
                Image(systemName: entry.style.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            Spacer(minLength: 0)
            stylePreview
                .frame(height: 42)
            Text(WidgetL10n.text(entry.style.titleKey))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(WidgetL10n.text(entry.style.subtitleKey))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
        }
        .padding(16)
    }

    /// 中号小组件：展示当前样式和两个常用快捷入口。
    private var mediumWidget: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                appMark
                Spacer(minLength: 0)
                Text(WidgetL10n.text(entry.style.titleKey))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(WidgetL10n.text(entry.style.subtitleKey))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    shortcutPill(title: "播放", icon: "play.fill")
                    shortcutPill(title: "管理", icon: "rectangle.3.group")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stylePreview
                .frame(width: 118, height: 106)
        }
        .padding(16)
    }

    /// 小组件背景。
    private var widgetBackground: some View {
        LinearGradient(colors: entry.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 130, height: 130)
                    .offset(x: 48, y: -54)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: 110, height: 110)
                    .offset(x: -50, y: 56)
            }
    }

    /// 小组件品牌标识。
    private var appMark: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("SynoMusic")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    /// 当前样式的预览插画。
    @ViewBuilder
    private var stylePreview: some View {
        switch entry.style {
        case .vinyl:
            vinylPreview
        case .recent:
            recentPreview
        case .widgets:
            widgetGridPreview
        case .downloads:
            downloadPreview
        case .smartMixes:
            smartMixPreview
        }
    }

    /// 黑胶唱片样式预览。
    private var vinylPreview: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(0.95), .black.opacity(0.72), .white.opacity(0.12)],
                        center: .center,
                        startRadius: 6,
                        endRadius: 58
                    )
                )
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .stroke(.white.opacity(index.isMultiple(of: 2) ? 0.08 : 0.04), lineWidth: 1)
                    .padding(CGFloat(index) * 6 + 7)
            }
            Circle()
                .fill(LinearGradient(colors: [.pink.opacity(0.92), .purple.opacity(0.90)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
            Image(systemName: "music.note")
                .foregroundStyle(.white)
                .font(.system(size: 16, weight: .bold))
        }
    }

    /// 最近播放样式预览。
    private var recentPreview: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(index == 0 ? 0.92 : 0.34))
                    .overlay {
                        Image(systemName: index == 0 ? "play.fill" : "music.note")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(index == 0 ? .black.opacity(0.65) : .white)
                    }
            }
        }
    }

    /// 小组件管理样式预览。
    private var widgetGridPreview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(["wand.and.stars", "arrow.down.circle", "record.circle", "gearshape"], id: \.self) { icon in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .overlay {
                        Image(systemName: icon)
                            .foregroundStyle(.white)
                            .font(.system(size: 16, weight: .bold))
                    }
            }
        }
    }

    /// 下载样式预览。
    private var downloadPreview: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Capsule()
                .fill(.white.opacity(0.22))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: 62)
                }
                .frame(height: 7)
        }
        .padding(14)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 智能歌单样式预览。
    private var smartMixPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(.white.opacity(0.90)).frame(width: 82, height: 8)
                Capsule().fill(.white.opacity(0.42)).frame(width: 58, height: 6)
            }
        }
        .padding(14)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 中号小组件底部快捷胶囊。
    private func shortcutPill(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(WidgetL10n.text(title))
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(0.18), in: Capsule())
    }
}

/// Widget 扩展内的轻量本地化，避免依赖主 App 的运行时语言管理器。
private enum WidgetL10n {
    private static let table: [String: [String: String]] = [
        "zh-Hans": [
            "SynoMusic 小组件": "SynoMusic 小组件",
            "长按小组件可切换样式": "长按小组件可切换样式。",
            "智能歌单": "智能歌单",
            "下载管理": "下载管理",
            "黑胶唱片": "黑胶唱片",
            "最近播放": "最近播放",
            "实时歌词": "实时歌词",
            "小组件管理": "小组件管理",
            "每日推荐": "每日推荐",
            "离线音乐": "离线音乐",
            "播放入口": "播放入口",
            "继续聆听": "继续聆听",
            "歌词一览": "歌词一览",
            "编辑样式": "编辑样式",
            "播放": "播放",
            "管理": "管理"
        ],
        "zh-Hant": [
            "SynoMusic 小组件": "SynoMusic 小工具",
            "长按小组件可切换样式": "長按小工具可切換樣式。",
            "智能歌单": "智能歌單",
            "下载管理": "下載管理",
            "黑胶唱片": "黑膠唱片",
            "最近播放": "最近播放",
            "实时歌词": "即時歌詞",
            "小组件管理": "小工具管理",
            "每日推荐": "每日推薦",
            "离线音乐": "離線音樂",
            "播放入口": "播放入口",
            "继续聆听": "繼續聆聽",
            "歌词一览": "歌詞一覽",
            "编辑样式": "編輯樣式",
            "播放": "播放",
            "管理": "管理"
        ],
        "en": [
            "SynoMusic 小组件": "SynoMusic Widget",
            "长按小组件可切换样式": "Long-press the widget to change its style.",
            "智能歌单": "Smart Mixes",
            "下载管理": "Downloads",
            "黑胶唱片": "Vinyl Player",
            "最近播放": "Recently Played",
            "实时歌词": "Live Lyrics",
            "小组件管理": "Widget Manager",
            "每日推荐": "Daily picks",
            "离线音乐": "Offline music",
            "播放入口": "Playback shortcut",
            "继续聆听": "Keep listening",
            "歌词一览": "Lyrics glance",
            "编辑样式": "Edit style",
            "播放": "Play",
            "管理": "Manage"
        ],
        "ja": [
            "SynoMusic 小组件": "SynoMusicウィジェット",
            "长按小组件可切换样式": "ウィジェットを長押ししてスタイルを変更できます。",
            "智能歌单": "スマートミックス",
            "下载管理": "ダウンロード",
            "黑胶唱片": "レコード",
            "最近播放": "最近再生",
            "实时歌词": "リアルタイム歌詞",
            "小组件管理": "ウィジェット管理",
            "每日推荐": "毎日のおすすめ",
            "离线音乐": "オフライン音楽",
            "播放入口": "再生ショートカット",
            "继续聆听": "聴き続ける",
            "歌词一览": "歌詞表示",
            "编辑样式": "スタイル編集",
            "播放": "再生",
            "管理": "管理"
        ],
        "ko": [
            "SynoMusic 小组件": "SynoMusic 위젯",
            "长按小组件可切换样式": "위젯을 길게 눌러 스타일을 바꿀 수 있습니다.",
            "智能歌单": "스마트 믹스",
            "下载管理": "다운로드",
            "黑胶唱片": "바이닐 플레이어",
            "最近播放": "최근 재생",
            "实时歌词": "실시간 가사",
            "小组件管理": "위젯 관리",
            "每日推荐": "일일 추천",
            "离线音乐": "오프라인 음악",
            "播放入口": "재생 바로가기",
            "继续聆听": "계속 듣기",
            "歌词一览": "가사 보기",
            "编辑样式": "스타일 편집",
            "播放": "재생",
            "管理": "관리"
        ],
        "de": [
            "SynoMusic 小组件": "SynoMusic Widget",
            "长按小组件可切换样式": "Halte das Widget gedrückt, um den Stil zu ändern.",
            "智能歌单": "Smart Mixes",
            "下载管理": "Downloads",
            "黑胶唱片": "Vinyl-Player",
            "最近播放": "Zuletzt gespielt",
            "实时歌词": "Live-Lyrics",
            "小组件管理": "Widget-Verwaltung",
            "每日推荐": "Tägliche Tipps",
            "离线音乐": "Offline-Musik",
            "播放入口": "Wiedergabe",
            "继续聆听": "Weiterhören",
            "歌词一览": "Lyrics",
            "编辑样式": "Stil bearbeiten",
            "播放": "Abspielen",
            "管理": "Verwalten"
        ],
        "fr": [
            "SynoMusic 小组件": "Widget SynoMusic",
            "长按小组件可切换样式": "Appuyez longuement sur le widget pour changer de style.",
            "智能歌单": "Smart Mixes",
            "下载管理": "Téléchargements",
            "黑胶唱片": "Lecteur vinyle",
            "最近播放": "Écoutés récemment",
            "实时歌词": "Paroles en direct",
            "小组件管理": "Gestion des widgets",
            "每日推荐": "Suggestions du jour",
            "离线音乐": "Musique hors ligne",
            "播放入口": "Raccourci lecture",
            "继续聆听": "Continuer l’écoute",
            "歌词一览": "Aperçu paroles",
            "编辑样式": "Modifier le style",
            "播放": "Lire",
            "管理": "Gérer"
        ]
    ]

    /// 按系统语言返回 Widget 文案。
    static func text(_ key: String) -> String {
        let code = localeCode()
        return table[code]?[key] ?? table["en"]?[key] ?? key
    }

    /// 将系统 Locale 归一化到当前支持的语言代码。
    private static func localeCode() -> String {
        let locale = Locale.autoupdatingCurrent
        let language = locale.language.languageCode?.identifier ?? "en"
        if language == "zh" {
            let identifier = locale.identifier.lowercased()
            return identifier.contains("hant") || identifier.contains("tw") || identifier.contains("hk") ? "zh-Hant" : "zh-Hans"
        }
        return table.keys.contains(language) ? language : "en"
    }
}
