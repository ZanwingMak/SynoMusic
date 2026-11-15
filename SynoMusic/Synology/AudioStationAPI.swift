import Foundation

/// Audio Station REST 接口封装。
/// 所有方法返回上层 UI 友好的模型；DTO 仅用于解码。
final class AudioStationAPI: @unchecked Sendable {
    unowned let client: SynologyClient

    init(client: SynologyClient) {
        self.client = client
    }

    // MARK: 信息

    /// 拉取 Audio Station 元信息（版本、是否启用 dsd 转码等）。
    func getInfo() async throws -> [String: String] {
        struct InfoData: Decodable {
            let version: String?
            let version_string: String?
            let is_manager: Bool?
        }
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Info"),
            .init(name: "version", value: "4"),
            .init(name: "method", value: "getinfo")
        ]
        let payload: InfoData = try await client.request(path: "AudioStation/info.cgi", query: items, as: InfoData.self)
        var dict: [String: String] = [:]
        if let v = payload.version { dict["version"] = v }
        if let s = payload.version_string { dict["version_string"] = s }
        return dict
    }

    // MARK: 专辑

    /// 列出专辑。
    /// - parameter limit: 每页数量
    /// - parameter offset: 偏移
    /// - parameter artist: 限定艺术家
    /// - parameter genre: 限定流派
    /// - parameter sortBy: name | artist | year | random | recently_added
    func listAlbums(
        limit: Int = 200,
        offset: Int = 0,
        artist: String? = nil,
        genre: String? = nil,
        sortBy: String = "name",
        sortDirection: String = "ASC"
    ) async throws -> [Album] {
        var items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Album"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "list"),
            .init(name: "library", value: "shared"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "sort_by", value: sortBy),
            .init(name: "sort_direction", value: sortDirection),
            .init(name: "additional", value: "song_tag")
        ]
        if let artist { items.append(.init(name: "artist", value: artist)) }
        if let genre { items.append(.init(name: "genre", value: genre)) }
        let list: ASListResult<ASAlbum> = try await client.request(
            path: "AudioStation/album.cgi",
            query: items,
            as: ASListResult<ASAlbum>.self
        )
        return list.items.map { dto in
            let displayArtist = dto.display_artist ?? dto.album_artist ?? dto.artist ?? "未知艺术家"
            let canonicalArtist = dto.album_artist ?? dto.artist ?? "Various Artists"
            return Album(
                id: "\(dto.name)|\(canonicalArtist)",
                name: dto.name,
                artist: canonicalArtist,
                displayArtist: displayArtist,
                year: dto.year,
                songCount: dto.song_count
            )
        }
    }

    // MARK: 艺术家

    func listArtists(limit: Int = 500, offset: Int = 0) async throws -> [Artist] {
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Artist"),
            .init(name: "version", value: "4"),
            .init(name: "method", value: "list"),
            .init(name: "library", value: "shared"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "additional", value: "avg_rating")
        ]
        let list: ASListResult<ASArtist> = try await client.request(
            path: "AudioStation/artist.cgi",
            query: items,
            as: ASListResult<ASArtist>.self
        )
        return list.items.map { Artist(id: $0.name, name: $0.name, albumCount: $0.album_count) }
    }

    // MARK: 流派

    func listGenres(limit: Int = 200, offset: Int = 0) async throws -> [Genre] {
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Genre"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "list"),
            .init(name: "library", value: "shared"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset))
        ]
        let list: ASListResult<ASGenre> = try await client.request(
            path: "AudioStation/genre.cgi",
            query: items,
            as: ASListResult<ASGenre>.self
        )
        return list.items.map { Genre(id: $0.name, name: $0.name) }
    }

    // MARK: 歌曲

    /// 从全库随机抓 `count` 首歌；用于随机歌单。
    /// 注意：Audio Station 的 sort_by=random 在不同 DSM 版本支持度不同，做兜底——
    /// 先 random 取，失败回退到拉取较大 limit 然后客户端打乱。
    func randomSongs(count: Int = 100) async throws -> [Song] {
        do {
            return try await listSongs(limit: count, sortBy: "random")
        } catch {
            let pool = try await listSongs(limit: max(count * 4, 400))
            return Array(pool.shuffled().prefix(count))
        }
    }

    /// 列出歌曲，可按专辑/艺术家/流派限定。
    func listSongs(
        limit: Int = 500,
        offset: Int = 0,
        album: String? = nil,
        albumArtist: String? = nil,
        artist: String? = nil,
        genre: String? = nil,
        composer: String? = nil,
        sortBy: String = "track",
        sortDirection: String = "ASC"
    ) async throws -> [Song] {
        var items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Song"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "list"),
            .init(name: "library", value: "shared"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "sort_by", value: sortBy),
            .init(name: "sort_direction", value: sortDirection),
            .init(name: "additional", value: "song_tag,song_audio,song_rating")
        ]
        if let album { items.append(.init(name: "album", value: album)) }
        if let albumArtist { items.append(.init(name: "album_artist", value: albumArtist)) }
        if let artist { items.append(.init(name: "artist", value: artist)) }
        if let genre { items.append(.init(name: "genre", value: genre)) }
        if let composer { items.append(.init(name: "composer", value: composer)) }
        let list: ASListResult<ASSong> = try await client.request(
            path: "AudioStation/song.cgi",
            query: items,
            as: ASListResult<ASSong>.self
        )
        return list.items.map(Self.mapSong)
    }

    /// 给歌曲打分（0..5）。AudioStation 没有 ID3 tag 编辑 API，唯一可写的元数据就是评分。
    func setRating(songID: String, rating: Int) async throws {
        let r = max(0, min(rating, 5))
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Song"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "setrating"),
            .init(name: "id", value: songID),
            .init(name: "rating", value: String(r))
        ]
        _ = try await client.request(
            path: "AudioStation/song.cgi",
            query: items,
            as: EmptyPayload.self
        )
    }

    /// 通过 File Station 删除一首歌曲文件。Audio Station 没有删除接口，必须走 File Station。
    /// `paths` 是文件在 NAS 上的绝对路径，多个用逗号分隔。
    /// 返回 taskid，调用方可在 UI 上提示"已下发删除任务"。
    @discardableResult
    func deleteFiles(paths: [String]) async throws -> String? {
        struct DeleteResult: Decodable { let taskid: String? }
        // 用 JSON 数组拼装路径字段（File Station 的约定）
        let joined = "[\"" + paths.map { $0.replacingOccurrences(of: "\"", with: "\\\"") }.joined(separator: "\",\"") + "\"]"
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.FileStation.Delete"),
            .init(name: "version", value: "2"),
            .init(name: "method", value: "start"),
            .init(name: "path", value: joined),
            .init(name: "recursive", value: "true")
        ]
        let result: DeleteResult = try await client.request(
            path: "entry.cgi",
            query: items,
            as: DeleteResult.self
        )
        return result.taskid
    }

    /// 搜索歌曲（按标题）。
    func searchSongs(keyword: String, limit: Int = 100, offset: Int = 0) async throws -> [Song] {
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Song"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "search"),
            .init(name: "library", value: "shared"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "title", value: keyword),
            .init(name: "additional", value: "song_tag,song_audio")
        ]
        let list: ASListResult<ASSong> = try await client.request(
            path: "AudioStation/song.cgi",
            query: items,
            as: ASListResult<ASSong>.self
        )
        return list.items.map(Self.mapSong)
    }

    // MARK: 播放列表

    func listPlaylists(limit: Int = 200, offset: Int = 0) async throws -> [Playlist] {
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Playlist"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "list"),
            .init(name: "library", value: "all"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "additional", value: "songs_total")
        ]
        let list: ASListResult<ASPlaylist> = try await client.request(
            path: "AudioStation/playlist.cgi",
            query: items,
            as: ASListResult<ASPlaylist>.self
        )
        return list.items.map { dto in
            Playlist(
                id: dto.id,
                name: dto.name,
                library: dto.library ?? "shared",
                songCount: dto.additional?.songs_total,
                isSmart: (dto.type ?? "").contains("smart"),
                owner: dto.owner
            )
        }
    }

    /// 获取一个播放列表内的歌曲。
    func playlistSongs(id: String, limit: Int = 1000, offset: Int = 0) async throws -> [Song] {
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Playlist"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "getinfo"),
            .init(name: "id", value: id),
            .init(name: "library", value: "all"),
            .init(name: "songs_offset", value: String(offset)),
            .init(name: "songs_limit", value: String(limit)),
            .init(name: "additional", value: "songs,songs_song_tag,songs_song_audio")
        ]
        struct PlaylistInfoResp: Decodable {
            struct Container: Decodable { let additional: PlaylistInfoAdditional? }
            struct PlaylistInfoAdditional: Decodable { let songs: [ASSong]? }
            let playlists: [Container]
        }
        let payload: PlaylistInfoResp = try await client.request(
            path: "AudioStation/playlist.cgi",
            query: items,
            as: PlaylistInfoResp.self
        )
        let songs = payload.playlists.first?.additional?.songs ?? []
        return songs.map(Self.mapSong)
    }

    // MARK: 文件夹

    func listFolders(parentID: String? = nil, limit: Int = 500, offset: Int = 0) async throws -> [FolderNode] {
        var items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Folder"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "list"),
            .init(name: "library", value: "shared"),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "additional", value: "song_tag,song_audio")
        ]
        if let parentID {
            items.append(.init(name: "id", value: parentID))
        }
        let list: ASListResult<ASFolder> = try await client.request(
            path: "AudioStation/folder.cgi",
            query: items,
            as: ASListResult<ASFolder>.self
        )
        return list.items.map { dto in
            FolderNode(id: dto.id, title: dto.title, path: dto.path, type: dto.type, songID: dto.additional?.song_id)
        }
    }

    // MARK: 歌词

    func getLyrics(songID: String) async throws -> [LyricLine] {
        let items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Lyrics"),
            .init(name: "version", value: "2"),
            .init(name: "method", value: "getlyrics"),
            .init(name: "id", value: songID)
        ]
        let payload: ASLyricsPayload = try await client.request(
            path: "AudioStation/lyrics.cgi",
            query: items,
            as: ASLyricsPayload.self
        )
        return Self.parseLRC(payload.lyrics ?? "")
    }

    // MARK: URL 构造（封面与流）

    /// 封面图 URL：返回直接给 AsyncImage 即可。
    func songCoverURL(songID: String) -> URL? {
        var items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Cover"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "getsongcover"),
            .init(name: "view", value: "default"),
            .init(name: "id", value: songID)
        ]
        if let sid = client.sessionID {
            items.append(.init(name: "_sid", value: sid))
        }
        return try? client.makeURL(path: "AudioStation/cover.cgi", query: items)
    }

    /// 封面 URL（按 album+artist 取）。
    func albumCoverURL(album: String, albumArtist: String) -> URL? {
        var items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Cover"),
            .init(name: "version", value: "3"),
            .init(name: "method", value: "getcover"),
            .init(name: "view", value: "default"),
            .init(name: "album_name", value: album),
            .init(name: "album_artist_name", value: albumArtist)
        ]
        if let sid = client.sessionID {
            items.append(.init(name: "_sid", value: sid))
        }
        return try? client.makeURL(path: "AudioStation/cover.cgi", query: items)
    }

    /// 音频流 URL（原码流）。
    /// - parameter format: 'raw' 不转码；其他值如 'mp3' 触发 transcode。
    func streamURL(songID: String, format: String = "raw") -> URL? {
        let method = (format == "raw") ? "stream" : "transcode"
        var items: [URLQueryItem] = [
            .init(name: "api", value: "SYNO.AudioStation.Stream"),
            .init(name: "version", value: "2"),
            .init(name: "method", value: method),
            .init(name: "id", value: songID)
        ]
        if format != "raw" {
            items.append(.init(name: "format", value: format))
        }
        if let sid = client.sessionID {
            items.append(.init(name: "_sid", value: sid))
        }
        return try? client.makeURL(path: "AudioStation/stream.cgi", query: items)
    }

    // MARK: 内部映射

    private static func mapSong(_ dto: ASSong) -> Song {
        let tag = dto.additional?.song_tag
        let audio = dto.additional?.song_audio
        let rating = dto.additional?.song_rating
        return Song(
            id: dto.id,
            title: dto.title,
            album: tag?.album,
            artist: tag?.artist,
            albumArtist: tag?.album_artist,
            genre: tag?.genre,
            composer: tag?.composer,
            trackNumber: tag?.track,
            discNumber: tag?.disc,
            year: tag?.year,
            duration: TimeInterval(audio?.duration ?? 0),
            bitrate: audio?.bitrate,
            codec: audio?.codec,
            filesize: audio?.filesize,
            path: dto.path,
            rating: rating?.rating
        )
    }

    /// 解析 LRC 文本为时间轴歌词。
    /// 支持 `[mm:ss.xx]` 与 `[mm:ss]` 两种时间戳。
    static func parseLRC(_ text: String) -> [LyricLine] {
        guard !text.isEmpty else { return [] }
        var lines: [LyricLine] = []
        let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#)
        text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).forEach { rawLine in
            let raw = String(rawLine)
            guard let regex else { return }
            let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            let matches = regex.matches(in: raw, range: nsRange)
            guard !matches.isEmpty else { return }
            let lastMatch = matches.last!
            guard let timestampRange = Range(lastMatch.range, in: raw) else { return }
            let lyric = String(raw[timestampRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: raw),
                      let secRange = Range(match.range(at: 2), in: raw) else { continue }
                let minutes = Int(raw[minRange]) ?? 0
                let seconds = Int(raw[secRange]) ?? 0
                var millis = 0
                if let msRange = Range(match.range(at: 3), in: raw) {
                    let msStr = String(raw[msRange])
                    millis = Int(msStr) ?? 0
                    if msStr.count == 1 { millis *= 100 }
                    if msStr.count == 2 { millis *= 10 }
                }
                let ts = Double(minutes * 60 + seconds) + Double(millis) / 1000.0
                lines.append(LyricLine(timestamp: ts, text: lyric))
            }
        }
        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
