import SwiftUI
import WidgetKit

/// 桌面小组件：提供智能歌单和下载管理快捷入口。
struct SynoMusicQuickWidget: Widget {
    private let kind = "SynoMusicQuickWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SynoMusicQuickTimelineProvider()) { entry in
            SynoMusicQuickWidgetView(entry: entry)
        }
        .configurationDisplayName("SynoMusic")
        .description("Quick access to SynoMusic widgets and premium tools.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// 小组件时间线条目。
private struct SynoMusicQuickEntry: TimelineEntry {
    let date: Date
}

/// 小组件静态时间线提供者。
private struct SynoMusicQuickTimelineProvider: TimelineProvider {
    /// 占位内容。
    func placeholder(in context: Context) -> SynoMusicQuickEntry {
        SynoMusicQuickEntry(date: Date())
    }

    /// 小组件图库预览内容。
    func getSnapshot(in context: Context, completion: @escaping (SynoMusicQuickEntry) -> Void) {
        completion(SynoMusicQuickEntry(date: Date()))
    }

    /// 小组件无需频繁刷新，提供静态时间线。
    func getTimeline(in context: Context, completion: @escaping (Timeline<SynoMusicQuickEntry>) -> Void) {
        completion(Timeline(entries: [SynoMusicQuickEntry(date: Date())], policy: .never))
    }
}

/// 小组件视图。
private struct SynoMusicQuickWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SynoMusicQuickEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                smallWidget
            } else {
                mediumWidget
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    /// 小号小组件：突出一个快速入口，同时保留管理入口。
    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                appMark
                Spacer()
                widgetIconLink(icon: "gearshape.fill", url: "synomusic://widgets")
            }
            Spacer(minLength: 0)
            Text("Smart Mixes")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("Auto curated")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
            HStack(spacing: 8) {
                widgetIconLink(icon: "wand.and.stars", url: "synomusic://smart-mixes")
                widgetIconLink(icon: "arrow.down.circle", url: "synomusic://downloads")
            }
        }
        .padding(16)
    }

    /// 中号小组件：展示特色功能、下载和管理入口。
    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                appMark
                Spacer()
                widgetLink(title: "Manage", icon: "rectangle.3.group", url: "synomusic://widgets")
            }
            HStack(spacing: 10) {
                featureTile(title: "Smart Mixes", subtitle: "Daily picks", icon: "wand.and.stars", url: "synomusic://smart-mixes")
                featureTile(title: "Downloads", subtitle: "Offline queue", icon: "arrow.down.circle", url: "synomusic://downloads")
                featureTile(title: "Widgets", subtitle: "Manage", icon: "rectangle.3.group", url: "synomusic://widgets")
            }
        }
        .padding(16)
    }

    /// 小组件背景。
    private var widgetBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.32, blue: 0.58),
                Color(red: 0.95, green: 0.54, blue: 0.20),
                Color(red: 0.43, green: 0.24, blue: 0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 120, height: 120)
                .offset(x: 120, y: -50)
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

    /// 中号小组件里的功能卡片。
    private func featureTile(title: String, subtitle: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                Spacer(minLength: 0)
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(10)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// 小组件中的深链按钮。
    private func widgetLink(title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.18), in: Capsule())
        }
    }

    /// 只有图标的深链按钮。
    private func widgetIconLink(icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}
