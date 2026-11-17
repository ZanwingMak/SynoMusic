import SwiftUI

/// 由系统栏附件或页面安全区承载的迷你播放器。
struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var usesSystemContainer = false
    var onTap: () -> Void
    var onQueue: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.xs) {
                Button { Haptics.tap(); onTap() } label: {
                    HStack(spacing: Metrics.s) {
                        CoverArt(
                            url: playback.currentSong.flatMap { session.musicClient?.songCoverURL(song: $0) },
                            cornerRadius: 8,
                            fallbackSeed: playback.currentSong?.id ?? "",
                            lookup: playback.currentSong.map(CoverLookupQuery.init(song:))
                        )
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playback.currentSong?.title ?? "")
                                .font(.nocBody.weight(.semibold)).lineLimit(1)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text(playback.currentSong?.artist ?? "")
                                    .font(.nocLabel).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 系统栏附件高度固定；完整标题可通过旁白或展开播放器读取。
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("正在播放".t + "：" + (playback.currentSong?.title ?? ""))
                control(playback.isPlaying ? "pause.fill" : "play.fill", label: playback.isPlaying ? "暂停" : "播放", action: playback.togglePlayPause)
                control("forward.fill", label: "下一首", action: playback.next)
                if let onQueue {
                    control("list.bullet", label: "队列") { Haptics.tap(); onQueue() }
                }
            }
            .padding(.horizontal, Metrics.s)
            .padding(.vertical, usesSystemContainer ? 0 : Metrics.xs)
            progressBar
        }
        .buttonStyle(.plain)
        .background {
            if !usesSystemContainer {
                RoundedRectangle(cornerRadius: 18).fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: usesSystemContainer ? 0 : 18))
    }

    /// 各播放操作拥有独立且至少 44pt 的触控区域，避免触发外层展开操作。
    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label.t)
    }

    /// 自绘进度条：左侧渐变 + 右侧灰底，避免 ProgressView linear 圆角溢出问题。
    private var progressBar: some View {
        GeometryReader { geo in
            let total = max(playback.duration, 0.01)
            let value = min(max(playback.currentTime, 0), total)
            let ratio = total > 0 ? value / total : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                Rectangle()
                    .fill(Theme.accentGradient)
                    .frame(width: geo.size.width * ratio)
                    .animation(.linear(duration: 0.5), value: value)
            }
        }
        .frame(height: 2.5)
    }
}
