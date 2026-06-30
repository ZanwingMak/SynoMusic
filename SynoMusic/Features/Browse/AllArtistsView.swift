import SwiftUI

/// 全部艺术家：圆形头像网格。
struct AllArtistsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var artists: [Artist] = []
    @State private var isLoading = false
    @State private var error: String?
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: Metrics.m)]

    var body: some View {
        Group {
            if isLoading && artists.isEmpty {
                LoadingState()
            } else if let err = error {
                ErrorStateView(title: "加载失败".t, message: err) { Task { await load() } }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Metrics.l) {
                        ForEach(artists) { artist in
                            NavigationLink(value: BrowseRoute.artist(artist)) {
                                ArtistTile(artist: artist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Metrics.l)
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationTitle("艺术家".t)
        .task { await load() }
    }

    /// 加载艺术家列表。
    private func load() async {
        guard let musicClient = session.musicClient else { return }
        isLoading = true; defer { isLoading = false }
        do { self.artists = try await musicClient.listArtists(limit: 1000, offset: 0) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct ArtistTile: View {
    let artist: Artist
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(gradient)
                .overlay(
                    Text(String(artist.name.prefix(1)).uppercased())
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            Text(artist.name)
                .font(.nocBody.weight(.medium))
                .lineLimit(1)
            if let count = artist.albumCount, count > 0 {
                Text("\(count) " + "张专辑".t)
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
            }
        }
    }
    private var gradient: LinearGradient {
        let hue = abs(Double(artist.name.hashValue % 1000)) / 1000.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.85),
                Color(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.5)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
