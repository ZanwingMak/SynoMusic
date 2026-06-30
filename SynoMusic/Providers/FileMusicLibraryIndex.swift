import Foundation

/// 文件型音乐源扫描后的轻量条目，供 WebDAV / SMB 复用。
struct FileMusicTrack: Hashable, Sendable {
    let remoteID: String
    let title: String
    let album: String?
    let artist: String?
    let duration: TimeInterval
    let codec: String?
    let filesize: Int64?
    let path: String
    let modifiedAt: Date?
}

/// 文件型音乐源的通用索引工具，负责统一 ID、排序和聚合。
enum FileMusicLibraryIndex {
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "alac", "flac", "wav", "aiff", "aif",
        "ogg", "opus", "wma", "dsf", "dff"
    ]

    /// 判断 URL 是否为 SynoMusic 支持的音频文件。
    static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// 把文件条目映射为播放器使用的 Song 模型。
    static func song(from track: FileMusicTrack, providerType: MusicProviderType, profile: ServerProfile) -> Song {
        Song(
            id: globalID(track.remoteID, providerType: providerType, profile: profile),
            title: track.title,
            album: track.album,
            artist: track.artist,
            albumArtist: track.artist,
            genre: nil,
            composer: nil,
            trackNumber: nil,
            discNumber: nil,
            year: nil,
            duration: track.duration,
            bitrate: nil,
            codec: track.codec,
            filesize: track.filesize,
            path: track.path,
            rating: nil
        )
    }

    /// 从文件条目聚合专辑列表。
    static func albums(from tracks: [FileMusicTrack], providerType: MusicProviderType, profile: ServerProfile) -> [Album] {
        let grouped = Dictionary(grouping: tracks) { track in
            "\(track.album ?? "未知专辑")|\(track.artist ?? "未知艺术家")"
        }
        return grouped.map { key, values in
            let first = values.first
            let name = first?.album ?? "未知专辑"
            let artist = first?.artist ?? "未知艺术家"
            return Album(
                id: globalID("album:\(key)", providerType: providerType, profile: profile),
                name: name,
                artist: artist,
                displayArtist: artist,
                year: nil,
                songCount: values.count
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 从文件条目聚合艺人列表。
    static func artists(from tracks: [FileMusicTrack], providerType: MusicProviderType, profile: ServerProfile) -> [Artist] {
        let grouped = Dictionary(grouping: tracks) { $0.artist ?? "未知艺术家" }
        return grouped.map { name, values in
            let albumCount = Set(values.map { $0.album ?? "未知专辑" }).count
            return Artist(
                id: globalID("artist:\(name)", providerType: providerType, profile: profile),
                name: name,
                albumCount: albumCount
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 对歌曲列表执行本地排序和分页。
    static func sortedSongs(
        from tracks: [FileMusicTrack],
        providerType: MusicProviderType,
        profile: ServerProfile,
        sortBy: String,
        sortDirection: String
    ) -> [Song] {
        let descending = sortDirection.uppercased() == "DESC"
        let sorted: [FileMusicTrack]
        switch sortBy {
        case "recently_added":
            sorted = tracks.sorted {
                let lhs = $0.modifiedAt ?? .distantPast
                let rhs = $1.modifiedAt ?? .distantPast
                return descending ? lhs > rhs : lhs < rhs
            }
        case "random":
            sorted = tracks.shuffled()
        default:
            sorted = tracks.sorted {
                let result = $0.title.localizedCaseInsensitiveCompare($1.title)
                return descending ? result == .orderedDescending : result == .orderedAscending
            }
        }
        return sorted.map { song(from: $0, providerType: providerType, profile: profile) }
    }

    /// 对任意集合做安全分页，避免 offset 越界。
    static func page<T>(_ values: [T], limit: Int, offset: Int) -> [T] {
        guard offset < values.count else { return [] }
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return [] }
        let end = min(values.count, offset + safeLimit)
        return Array(values[offset..<end])
    }

    /// 生成跨服务器稳定 ID。
    static func globalID(_ remoteID: String, providerType: MusicProviderType, profile: ServerProfile) -> String {
        "\(providerType.rawValue):\(profile.id.uuidString):\(remoteID)"
    }

    /// 从通用 ID 还原文件型音乐源的远端 ID。
    static func remoteID(from id: String, providerType: MusicProviderType, profile: ServerProfile) -> String {
        let prefix = "\(providerType.rawValue):\(profile.id.uuidString):"
        guard id.hasPrefix(prefix) else { return id }
        return String(id.dropFirst(prefix.count))
    }

    /// 根据文件名和目录层级生成基础音乐信息。
    static func metadata(from url: URL, relativeTo rootURL: URL) -> (title: String, album: String?, artist: String?) {
        let title = cleanName(url.deletingPathExtension().lastPathComponent, unknown: "未知歌曲")
        let rootComponents = rootURL.standardized.pathComponents
        let components = url.standardized.deletingLastPathComponent().pathComponents
        let relative = Array(components.dropFirst(min(rootComponents.count, components.count)))
        let album = relative.last.map { cleanName($0, unknown: "未知专辑") }
        let artist = relative.dropLast().last.map { cleanName($0, unknown: "未知艺术家") }
        return (title, album, artist)
    }

    /// 清理路径中的百分号编码和空白文本。
    static func cleanName(_ raw: String, unknown: String) -> String {
        let decoded = raw.removingPercentEncoding ?? raw
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknown : trimmed
    }
}
