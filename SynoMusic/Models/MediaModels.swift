import Foundation

// MARK: - 核心媒体模型

/// 一首歌曲（已解析为 UI 友好的形式）。
struct Song: Identifiable, Hashable, Codable {
    let id: String           // 群晖 Song.id（如 music_xxxxxxxx）
    let title: String
    let album: String?
    let artist: String?
    let albumArtist: String?
    let genre: String?
    let composer: String?
    let trackNumber: Int?
    let discNumber: Int?
    let year: Int?
    let duration: TimeInterval // 秒
    let bitrate: Int?         // bps
    let codec: String?        // 'flac' / 'mp3' / ...
    let filesize: Int64?      // 字节
    let path: String?         // 服务器侧文件路径
    let rating: Int?          // 0-5
}

extension Song {
    /// 标记电台和播客这类直接使用远程 URL 播放的媒体。
    var isDirectRemoteStream: Bool {
        id.hasPrefix("radio:") || id.hasPrefix("podcast:")
    }

    /// 返回只更新评分的新歌曲快照，用于接口成功后刷新本地队列状态。
    func withRating(_ newRating: Int?) -> Song {
        Song(
            id: id,
            title: title,
            album: album,
            artist: artist,
            albumArtist: albumArtist,
            genre: genre,
            composer: composer,
            trackNumber: trackNumber,
            discNumber: discNumber,
            year: year,
            duration: duration,
            bitrate: bitrate,
            codec: codec,
            filesize: filesize,
            path: path,
            rating: newRating
        )
    }
}

/// 专辑。
struct Album: Identifiable, Hashable, Codable {
    /// 拼接 ID（"album_name|artist"），群晖 Album 没有原生 id。
    let id: String
    let name: String
    let artist: String        // album_artist
    let displayArtist: String // 用于展示，可能是 various
    let year: Int?
    let songCount: Int?
}

/// 艺术家。
struct Artist: Identifiable, Hashable, Codable {
    let id: String            // 名称即 ID
    let name: String
    let albumCount: Int?
}

/// 流派。
struct Genre: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

/// 播放列表（含智能列表）。
struct Playlist: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let library: String       // 'shared' / 'personal'
    let songCount: Int?
    let isSmart: Bool
    let owner: String?
}

/// 文件夹节点（用于按文件路径浏览）。
struct FolderNode: Identifiable, Hashable, Codable {
    let id: String            // 服务器侧 ID
    let title: String
    let path: String
    let type: String          // 'folder' / 'file'
    let songID: String?       // 当 type == 'file' 时携带
}

/// 一行歌词。
struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String
}
