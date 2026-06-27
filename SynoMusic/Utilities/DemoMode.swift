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
            name: "家里的 DS220+",
            scheme: .http,
            host: "192.168.1.10",
            port: 5000,
            username: "alice"
        ),
        ServerProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "公司 NAS",
            scheme: .https,
            host: "office.example.com",
            port: 5001,
            username: "alice.work"
        )
    ]

    /// 预制专辑。
    static let albums: [Album] = [
        Album(id: "a1", name: "夜航星", artist: "林俊杰", displayArtist: "林俊杰", year: 2023, songCount: 12),
        Album(id: "a2", name: "Currents", artist: "Tame Impala", displayArtist: "Tame Impala", year: 2015, songCount: 13),
        Album(id: "a3", name: "Future Nostalgia", artist: "Dua Lipa", displayArtist: "Dua Lipa", year: 2020, songCount: 11),
        Album(id: "a4", name: "Blonde", artist: "Frank Ocean", displayArtist: "Frank Ocean", year: 2016, songCount: 17),
        Album(id: "a5", name: "范特西", artist: "周杰伦", displayArtist: "周杰伦", year: 2001, songCount: 10),
        Album(id: "a6", name: "Norman Fucking Rockwell!", artist: "Lana Del Rey", displayArtist: "Lana Del Rey", year: 2019, songCount: 14),
        Album(id: "a7", name: "AM", artist: "Arctic Monkeys", displayArtist: "Arctic Monkeys", year: 2013, songCount: 12),
        Album(id: "a8", name: "黄昏与黎明", artist: "陈绮贞", displayArtist: "陈绮贞", year: 2009, songCount: 11),
        Album(id: "a9", name: "Lemonade", artist: "Beyoncé", displayArtist: "Beyoncé", year: 2016, songCount: 12),
        Album(id: "a10", name: "Random Access Memories", artist: "Daft Punk", displayArtist: "Daft Punk", year: 2013, songCount: 13),
        Album(id: "a11", name: "时间的歌", artist: "陈奕迅", displayArtist: "陈奕迅", year: 2014, songCount: 10),
        Album(id: "a12", name: "After Hours", artist: "The Weeknd", displayArtist: "The Weeknd", year: 2020, songCount: 14)
    ]

    /// 预制艺术家。
    static let artists: [Artist] = [
        Artist(id: "林俊杰", name: "林俊杰", albumCount: 14),
        Artist(id: "Tame Impala", name: "Tame Impala", albumCount: 4),
        Artist(id: "Dua Lipa", name: "Dua Lipa", albumCount: 3),
        Artist(id: "Frank Ocean", name: "Frank Ocean", albumCount: 2),
        Artist(id: "周杰伦", name: "周杰伦", albumCount: 15),
        Artist(id: "陈奕迅", name: "陈奕迅", albumCount: 18),
        Artist(id: "Lana Del Rey", name: "Lana Del Rey", albumCount: 9),
        Artist(id: "陈绮贞", name: "陈绮贞", albumCount: 7)
    ]

    /// 预制歌曲（含时长）。
    static let songs: [Song] = [
        Song(id: "s1", title: "夜空中最亮的星", album: "夜航星", artist: "林俊杰", albumArtist: "林俊杰", genre: "流行", composer: nil, trackNumber: 1, discNumber: 1, year: 2023, duration: 248, bitrate: 320_000, codec: "flac", filesize: 35_000_000, path: nil, rating: 5),
        Song(id: "s2", title: "Let It Happen", album: "Currents", artist: "Tame Impala", albumArtist: "Tame Impala", genre: "Psychedelic", composer: nil, trackNumber: 1, discNumber: 1, year: 2015, duration: 467, bitrate: 320_000, codec: "flac", filesize: 50_000_000, path: nil, rating: 5),
        Song(id: "s3", title: "Levitating", album: "Future Nostalgia", artist: "Dua Lipa", albumArtist: "Dua Lipa", genre: "Pop", composer: nil, trackNumber: 5, discNumber: 1, year: 2020, duration: 203, bitrate: 320_000, codec: "mp3", filesize: 8_500_000, path: nil, rating: 4),
        Song(id: "s4", title: "Pyramids", album: "Blonde", artist: "Frank Ocean", albumArtist: "Frank Ocean", genre: "R&B", composer: nil, trackNumber: 9, discNumber: 1, year: 2016, duration: 587, bitrate: 320_000, codec: "flac", filesize: 60_000_000, path: nil, rating: 5)
    ]
}
