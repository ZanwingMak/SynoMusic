import SwiftUI

/// 播放历史：展示最近播放单曲和被替换的队列快照。
struct PlaybackHistoryView: View {
    @EnvironmentObject private var playback: PlaybackEngine

    var body: some View {
        Group {
            if playback.playedHistory.isEmpty && playback.queueHistory.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "暂无历史记录".t,
                    message: "播放过的歌曲和被替换的队列会显示在这里。".t
                )
            } else {
                List {
                    queueHistorySection
                    playedSongsSection
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("历史记录".t)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("清除".t) {
                    playback.clearPlaybackHistory()
                    Haptics.success()
                }
                .disabled(playback.playedHistory.isEmpty && playback.queueHistory.isEmpty)
            }
        }
    }

    /// 队列快照分区；点击行恢复该队列。
    private var queueHistorySection: some View {
        Section("队列历史".t) {
            if playback.queueHistory.isEmpty {
                Text("暂无队列历史".t)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playback.queueHistory) { snapshot in
                    Button {
                        Haptics.tap()
                        playback.play(queue: snapshot.songs, startAt: startIndex(for: snapshot), honoringShuffle: false, contextTitle: snapshot.title)
                    } label: {
                        QueueHistoryRow(snapshot: snapshot)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            playback.removeQueueHistory(id: snapshot.id)
                        } label: {
                            Label("删除".t, systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    /// 最近播放分区；点击歌曲从历史列表位置开始播放。
    private var playedSongsSection: some View {
        Section("最近播放".t) {
            if playback.playedHistory.isEmpty {
                Text("暂无播放历史".t)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(playback.playedHistory.enumerated()), id: \.element.id) { index, song in
                    SongTrackRow(
                        song: song,
                        index: index + 1,
                        isCurrent: playback.currentSong?.id == song.id,
                        isPlaying: playback.isPlaying
                    ) {
                        playback.play(queue: playback.playedHistory, startAt: index, honoringShuffle: false, contextTitle: "最近播放".t)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            playback.removePlayedHistory(songID: song.id)
                        } label: {
                            Label("删除".t, systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    /// 根据快照中的 currentSongID 找回原队列播放位置。
    private func startIndex(for snapshot: PlaybackQueueSnapshot) -> Int {
        guard let id = snapshot.currentSongID,
              let index = snapshot.songs.firstIndex(where: { $0.id == id }) else {
            return 0
        }
        return index
    }
}

/// 队列历史行：显示标题、歌曲数量和记录时间。
private struct QueueHistoryRow: View {
    let snapshot: PlaybackQueueSnapshot

    var body: some View {
        HStack(spacing: Metrics.m) {
            Image(systemName: "music.note.list")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.title)
                    .font(.nocBody.weight(.semibold))
                    .lineLimit(1)
                Text("\(snapshot.songs.count) " + "首歌".t + " · " + snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
