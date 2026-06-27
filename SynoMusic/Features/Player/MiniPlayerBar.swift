import SwiftUI

/// 浮于 TabBar 之上的迷你播放器。
struct MiniPlayerBar: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var session: AppSession
    var onTap: () -> Void
    var onQueue: (() -> Void)? = nil

    var body: some View {
        Button(action: { Haptics.tap(); onTap() }) {
            GlassPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    HStack(spacing: Metrics.m) {
                        CoverArt(
                            url: playback.currentSong.flatMap { session.client?.audioStation.songCoverURL(songID: $0.id) },
                            cornerRadius: 8,
                            fallbackSeed: playback.currentSong?.id ?? "",
                            lookup: playback.currentSong.map(CoverLookupQuery.init(song:))
                        )
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playback.currentSong?.title ?? "")
                                .font(.nocBody.weight(.semibold))
                                .lineLimit(1)
                            Text(playback.currentSong?.artist ?? "")
                                .font(.nocLabel)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            playback.togglePlayPause()
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        Button {
                            playback.next()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

                        if let onQueue {
                            Button {
                                Haptics.tap()
                                onQueue()
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("队列".t)
                        }
                    }
                    .padding(.horizontal, Metrics.m)
                    .padding(.vertical, 9)

                    // 进度条贴底、被 GlassPanel 外层 clipShape 自动裁切，不会溢出圆角。
                    progressBar
                }
            }
        }
        .buttonStyle(.plain)
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
