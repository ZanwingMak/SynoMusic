import SwiftUI

/// 电视播放页以封面与歌词/队列双栏展示，所有传输动作都可由遥控器聚焦。
struct TVNowPlayingView: View {
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pane = "lyrics"
    @State private var showInfo = false
    @State private var showAdd = false
    @FocusState private var playFocused: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button(action: onClose) { Label("返回".t, systemImage: "chevron.down") }
                Spacer()
                Text("正在播放".t).font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { showInfo = true } label: { Label("歌曲信息".t, systemImage: "info.circle") }
            }
            HStack(spacing: 80) {
                VStack(spacing: 24) {
                    if let song = playback.song {
                        TVArtwork(url: library.client?.songCoverURL(song: song), title: song.album ?? song.title)
                            .frame(width: 390, height: 390).shadow(color: .black.opacity(0.3), radius: 40, y: 20)
                        VStack(spacing: 10) {
                            Text(song.title).font(.system(size: 38, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
                            Text(song.artist ?? "").font(.system(size: 25)).foregroundStyle(.secondary).lineLimit(1)
                            Text(song.album ?? "").font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        ProgressView(value: min(playback.position, max(playback.duration, 1)), total: max(playback.duration, 1)).tint(TVStyle.accent).accessibilityLabel("播放进度".t)
                        HStack {
                            Text(TVSongList.time(playback.position))
                            Spacer()
                            Text(song.id.hasPrefix("radio:") ? "直播".t : TVSongList.time(playback.duration))
                        }.font(.system(size: 19).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 26) {
                        iconButton("backward.fill", label: "上一首", action: playback.previous)
                        Button(action: playback.toggle) {
                            Group { if playback.isBuffering { ProgressView() } else { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") } }.frame(width: 55, height: 55)
                        }.focused($playFocused).accessibilityLabel((playback.isPlaying ? "暂停" : "播放").t)
                        iconButton("forward.fill", label: "下一首") { playback.advance() }
                    }.focusSection()
                    HStack(spacing: 22) {
                        Button { playback.seek(playback.position - 10) } label: { Label("10", systemImage: "gobackward.10") }.disabled(playback.song?.id.hasPrefix("radio:") == true || playback.duration <= 0)
                        Button { playback.seek(playback.position + 10) } label: { Label("10", systemImage: "goforward.10") }.disabled(playback.song?.id.hasPrefix("radio:") == true || playback.duration <= 0)
                    }.focusSection()
                    HStack(spacing: 22) {
                        iconButton("shuffle", label: "随机", selected: playback.shuffle) { playback.shuffle.toggle() }
                        iconButton(playback.repeatMode == .one ? "repeat.1" : "repeat", label: "循环", selected: playback.repeatMode != .off) { playback.repeatMode = playback.repeatMode == .off ? .all : playback.repeatMode == .all ? .one : .off }
                        iconButton(playlists.isFavorite(playback.song?.id ?? "") ? "heart.fill" : "heart", label: "喜欢", selected: playlists.isFavorite(playback.song?.id ?? "")) { if let song = playback.song { playlists.toggleFavorite(song) } }
                    }.focusSection()
                }.frame(width: 620)
                VStack(alignment: .leading, spacing: 28) {
                    Picker("正在播放".t, selection: $pane) {
                        Text("歌词".t).tag("lyrics")
                        Text("队列".t).tag("queue")
                    }.pickerStyle(.segmented)
                    if let error = playback.error {
                        TVEmptyState(title: "无法播放".t, message: error, symbol: "exclamationmark.triangle", retry: { playback.load(at: playback.index) })
                    } else if pane == "lyrics" { TVLyricsView() }
                    else { queue }
                    HStack(spacing: 28) {
                        Button("添加到歌单…".t) { showAdd = true }.disabled(playback.song == nil)
                        Text("\(playback.queue.count) " + "首歌".t).font(.system(size: 20)).foregroundStyle(.secondary)
                    }
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(TVStyle.surface, in: RoundedRectangle(cornerRadius: 30))
            }.frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 64).padding(.vertical, 38)
        .background { LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.14), TVStyle.background], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() }
        .onExitCommand(perform: onClose)
        .onPlayPauseCommand { playback.toggle() }
        .onAppear { playFocused = true }
        .onChange(of: playback.song?.id) { _, id in if id == nil { onClose() } }
        .sheet(isPresented: $showInfo) { if let song = playback.song { TVSongInfoView(song: song).tvControls() } }
        .sheet(isPresented: $showAdd) { if let song = playback.song { TVAddToPlaylistView(song: song).tvControls() } }
    }

    /// 三个一组的传输按钮保证统一焦点范围，开关状态同时由图形和背景表达。
    private func iconButton(_ symbol: String, label: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 42, height: 42).foregroundStyle(selected ? TVStyle.accent : .primary) }
            .accessibilityLabel(label.t).accessibilityValue(selected ? "开启".t : "")
    }

    private var queue: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(playback.queue.enumerated()), id: \.offset) { index, song in
                        Button { playback.load(at: index) } label: {
                            HStack(spacing: 18) {
                                if index == playback.index { Image(systemName: "waveform").foregroundStyle(TVStyle.accent) }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(song.title).font(.system(size: 25, weight: .semibold)).lineLimit(2)
                                    Text(song.artist ?? "").font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.foregroundStyle(.white).padding(8)
                        }.buttonStyle(TVCardStyle()).id(index)
                            .contextMenu { Button("从队列移除".t) { playback.remove(at: index) } }
                    }
                }.padding(8)
            }.scrollClipDisabled()
                .onAppear { proxy.scrollTo(playback.index, anchor: .center) }
        }
    }
}

/// 同步歌词会自动居中；手动浏览后暂停跟随，用户可显式恢复。
private struct TVLyricsView: View {
    @EnvironmentObject private var playback: TVPlayback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var following = true
    var body: some View {
        VStack(spacing: 20) {
            if playback.lyricsLoading { ProgressView("正在查找歌词".t).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if playback.lyrics.isEmpty { TVEmptyState(title: "暂无歌词".t, message: "歌词可用时会显示在这里。".t, symbol: "text.alignleft") }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(playback.lyrics.enumerated()), id: \.offset) { index, line in
                                Button { if line.timestamp >= 0 { playback.seek(line.timestamp) } } label: {
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(.system(size: 30, weight: index == playback.currentLyric ? .bold : .medium))
                                        .foregroundStyle(index == playback.currentLyric ? .white : .white.opacity(0.45))
                                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                }.buttonStyle(TVCardStyle()).id(index)
                            }
                        }.padding(10).padding(.vertical, 40)
                    }.scrollClipDisabled()
                    .onMoveCommand { _ in following = false }
                    .onChange(of: playback.currentLyric) { _, index in
                        guard following, let index else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo(index, anchor: .center) }
                    }
                    .onAppear { if let index = playback.currentLyric { proxy.scrollTo(index, anchor: .center) } }
                }
                Button("跟随歌词".t) { following = true }.disabled(following)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
