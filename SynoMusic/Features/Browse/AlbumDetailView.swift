import SwiftUI
import UIKit

/// 专辑详情：顶部巨幅封面、信息、歌曲列表、播放/随机播放按钮。
struct AlbumDetailView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var reviewMode: AppReviewMode

    let album: Album
    @State private var songs: [Song] = []
    @State private var isLoading: Bool = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.l) {
                header
                actions
                if let err = error {
                    ErrorStateView(title: "加载失败".t, message: err) { Task { await load() } }
                        .frame(height: 200)
                } else if isLoading {
                    LoadingState().frame(height: 200)
                } else {
                    SongListSection(songs: songs) { idx in
                        playback.play(queue: songs, startAt: idx, honoringShuffle: false, contextTitle: album.name)
                    }
                }
            }
            .padding(.horizontal, Metrics.l)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: Metrics.m) {
            CoverArt(
                url: session.client?.audioStation.albumCoverURL(album: album.name, albumArtist: album.artist),
                cornerRadius: Theme.cornerHero,
                fallbackSeed: album.id,
                lookup: CoverLookupQuery(title: album.name, artist: album.artist, album: album.name)
            )
            .frame(width: albumCoverSide, height: albumCoverSide)
            .shadow(color: .black.opacity(0.25), radius: 28, y: 16)
            .padding(.top, Metrics.l)

            VStack(spacing: 4) {
                Text(album.name)
                    .font(.nocTitle)
                    .multilineTextAlignment(.center)
                Text(album.displayArtist)
                    .font(.nocBody)
                    .foregroundStyle(.secondary)
                if let y = album.year, y > 0 {
                    Text(String(y))
                        .font(.nocLabel)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// 根据屏幕高度限制专辑封面边长，避免竖屏封面挤压标题区。
    private var albumCoverSide: CGFloat {
        min(220, UIScreen.main.bounds.height * 0.28)
    }

    private var actions: some View {
        HStack(spacing: Metrics.m) {
            Button {
                playback.isShuffling = false
                playback.play(queue: songs, startAt: 0, honoringShuffle: false, contextTitle: album.name)
            } label: {
                Label("播放".t, systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(songs.isEmpty)

            Button {
                playback.isShuffling = true
                playback.play(queue: songs.shuffled(), startAt: 0, honoringShuffle: false, contextTitle: album.name)
            } label: {
                Label("随机".t, systemImage: "shuffle")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(songs.isEmpty)
        }
    }

    /// 加载专辑歌曲；审核模式按专辑名筛选内置歌曲。
    private func load() async {
        if reviewMode.isEnabled {
            let matched = DemoMode.songs.filter { $0.album == album.name }
            songs = matched.isEmpty ? DemoMode.songs : matched
            return
        }
        guard let api = session.client?.audioStation else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            self.songs = try await api.listSongs(album: album.name, albumArtist: album.artist, sortBy: "track")
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 通用的歌曲列表节，复用于专辑/播放列表详情。
struct SongListSection: View {
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var playlists: PlaylistStore
    let songs: [Song]
    var onTap: (Int) -> Void
    @State private var pickerSong: Song?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                Button {
                    Haptics.tap()
                    onTap(idx)
                } label: {
                    SongRow(song: song, index: idx + 1, isCurrent: playback.currentSong?.id == song.id, isPlaying: playback.isPlaying)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        playback.appendNext(song)
                    } label: { Label("接下来播放".t, systemImage: "text.line.first.and.arrowtriangle.forward") }
                    Button {
                        pickerSong = song
                    } label: { Label("添加到歌单…".t, systemImage: "text.badge.plus") }
                    Button {
                        playlists.toggleFavorite(song)
                        Haptics.tap()
                    } label: {
                        Label(playlists.isFavorite(song) ? "取消喜欢".t : "喜欢".t,
                              systemImage: playlists.isFavorite(song) ? "heart.slash" : "heart")
                    }
                }
                if idx < songs.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .sheet(item: $pickerSong) { song in
            AddToPlaylistSheet(song: song)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct SongRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: Metrics.m) {
            Group {
                if isCurrent {
                    EqualizerIcon(isAnimating: isPlaying)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("\(index)")
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .center)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.nocBody)
                    .foregroundStyle(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                Text(song.artist ?? "")
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(formatDuration(song.duration))
                .font(.nocLabel)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Metrics.s)
        .contentShape(Rectangle())
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 三柱跳动均衡器图标。
struct EqualizerIcon: View {
    var isAnimating: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            Bar(delay: 0.0, animate: isAnimating)
            Bar(delay: 0.15, animate: isAnimating)
            Bar(delay: 0.3, animate: isAnimating)
        }
    }
    private struct Bar: View {
        let delay: Double
        let animate: Bool
        @State private var h: CGFloat = 6
        var body: some View {
            RoundedRectangle(cornerRadius: 1.5)
                .frame(width: 3, height: h)
                .onAppear {
                    guard animate else { h = 4; return }
                    withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(delay)) {
                        h = 18
                    }
                }
                .onChange(of: animate) { _, newValue in
                    if newValue {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever().delay(delay)) { h = 18 }
                    } else {
                        withAnimation { h = 6 }
                    }
                }
        }
    }
}
