import Foundation

/// 预览与审核数据：DEBUG 可通过 `-demo` 启动参数启用，审核模式也复用这些假数据。
enum DemoMode {
    /// 是否启用 demo 模式。
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }

    /// 预制服务器档案（仅用于设置页样式预览，不真实连接）。
    static let serverProfiles: [ServerProfile] = [
        ServerProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Demo Server",
            scheme: .http,
            host: "192.168.1.10",
            port: 5000,
            username: "demo"
        ),
        ServerProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Demo NAS",
            scheme: .https,
            host: "office.example.com",
            port: 5001,
            username: "demo"
        )
    ]

    /// 预制专辑。
    static let albums: [Album] = [
        Album(id: "a1", name: "Quiet Architecture", artist: "SynoMusic Studio", displayArtist: "SynoMusic Studio", year: 2026, songCount: 12),
        Album(id: "a2", name: "The Blue Hour", artist: "The Quiet Ensemble", displayArtist: "The Quiet Ensemble", year: 2026, songCount: 13),
        Album(id: "a3", name: "Soft Focus", artist: "North Window", displayArtist: "North Window", year: 2026, songCount: 11),
        Album(id: "a4", name: "After the Rain", artist: "Soft Signals", displayArtist: "Soft Signals", year: 2026, songCount: 17),
        Album(id: "a5", name: "A Place to Stay", artist: "SynoMusic Studio", displayArtist: "SynoMusic Studio", year: 2026, songCount: 10),
        Album(id: "a6", name: "Late Light", artist: "The Quiet Ensemble", displayArtist: "The Quiet Ensemble", year: 2026, songCount: 14),
        Album(id: "a7", name: "Sunday Morning", artist: "North Window", displayArtist: "North Window", year: 2026, songCount: 12),
        Album(id: "a8", name: "Open Water", artist: "Soft Signals", displayArtist: "Soft Signals", year: 2026, songCount: 11),
        Album(id: "a9", name: "Small Hours", artist: "SynoMusic Studio", displayArtist: "SynoMusic Studio", year: 2026, songCount: 12),
        Album(id: "a10", name: "Still Life", artist: "The Quiet Ensemble", displayArtist: "The Quiet Ensemble", year: 2026, songCount: 13),
        Album(id: "a11", name: "Golden Air", artist: "North Window", displayArtist: "North Window", year: 2026, songCount: 10),
        Album(id: "a12", name: "Slow Motion", artist: "Soft Signals", displayArtist: "Soft Signals", year: 2026, songCount: 14)
    ]

    /// 预制艺术家。
    static let artists: [Artist] = [
        Artist(id: "demo-artist-1", name: "SynoMusic Studio", albumCount: 14),
        Artist(id: "demo-artist-2", name: "The Quiet Ensemble", albumCount: 4),
        Artist(id: "demo-artist-3", name: "North Window", albumCount: 3),
        Artist(id: "demo-artist-4", name: "Soft Signals", albumCount: 2),
        Artist(id: "demo-artist-5", name: "SynoMusic Studio", albumCount: 15),
        Artist(id: "demo-artist-6", name: "The Quiet Ensemble", albumCount: 18),
        Artist(id: "demo-artist-7", name: "North Window", albumCount: 9),
        Artist(id: "demo-artist-8", name: "Soft Signals", albumCount: 7)
    ]

    /// 应用原创的演示歌词，只用于示例资料，不依赖在线音乐内容。
    static let lyrics: [LyricLine] = [
        LyricLine(timestamp: 0, text: "A little light across the room"),
        LyricLine(timestamp: 12, text: "A little space to hear the day"),
        LyricLine(timestamp: 24, text: "The quiet follows every note"),
        LyricLine(timestamp: 36, text: "And lets the hurry drift away"),
        LyricLine(timestamp: 48, text: "Your music finds its way back home"),
        LyricLine(timestamp: 60, text: "One moment, one song, your own")
    ]

    /// 预制歌曲（含时长）。
    static let songs: [Song] = [
        Song(id: "s1", title: "First Light", album: "Quiet Architecture", artist: "SynoMusic Studio", albumArtist: "SynoMusic Studio", genre: "Ambient", composer: nil, trackNumber: 1, discNumber: 1, year: 2026, duration: 248, bitrate: 320_000, codec: "flac", filesize: 35_000_000, path: nil, rating: 5),
        Song(id: "s2", title: "Somewhere, Slowly", album: "Quiet Architecture", artist: "SynoMusic Studio", albumArtist: "SynoMusic Studio", genre: "Ambient", composer: nil, trackNumber: 2, discNumber: 1, year: 2026, duration: 267, bitrate: 320_000, codec: "flac", filesize: 50_000_000, path: nil, rating: 5),
        Song(id: "s3", title: "Home Again", album: "Quiet Architecture", artist: "SynoMusic Studio", albumArtist: "SynoMusic Studio", genre: "Ambient", composer: nil, trackNumber: 3, discNumber: 1, year: 2026, duration: 203, bitrate: 320_000, codec: "mp3", filesize: 8_500_000, path: nil, rating: 4),
        Song(id: "s4", title: "Quiet Morning", album: "Quiet Architecture", artist: "SynoMusic Studio", albumArtist: "SynoMusic Studio", genre: "Ambient", composer: nil, trackNumber: 4, discNumber: 1, year: 2026, duration: 287, bitrate: 320_000, codec: "flac", filesize: 60_000_000, path: nil, rating: 5)
    ]
}
