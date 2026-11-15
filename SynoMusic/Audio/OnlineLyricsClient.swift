import Foundation

/// 在线歌词客户端：在 Audio Station 没有歌词时，从 LRCLIB 拉取同步或纯文本歌词。
final class OnlineLyricsClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let baseURL = URL(string: "https://lrclib.net/api")!

    /// 创建在线歌词客户端，默认复用系统共享 URLSession。
    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 根据歌曲信息获取歌词；优先精确匹配，失败后用搜索结果兜底。
    func fetch(for song: Song) async throws -> [LyricLine] {
        let query = LyricsQuery(song: song)
        guard query.canSearch else { return [] }
        if let exact = try await requestRecord(path: "get", query: query.exactItems), !exact.isInstrumental {
            return lines(from: exact, duration: song.duration)
        }
        let matches = try await requestSearch(query: query.searchItems)
        guard let best = pickBestMatch(from: matches, query: query), !best.isInstrumental else { return [] }
        return lines(from: best, duration: song.duration)
    }

    /// 请求单条精确歌词记录；404 表示未匹配，不作为错误冒泡。
    private func requestRecord(path: String, query: [URLQueryItem]) async throws -> LyricsRecord? {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.setValue("SynoMusic iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try decoder.decode(LyricsRecord.self, from: data)
    }

    /// 请求搜索歌词记录列表。
    private func requestSearch(query: [URLQueryItem]) async throws -> [LyricsRecord] {
        let url = try makeURL(path: "search", query: query)
        var request = URLRequest(url: url)
        request.setValue("SynoMusic iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        return (try? decoder.decode([LyricsRecord].self, from: data)) ?? []
    }

    /// 构造 LRCLIB API URL。
    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    /// 从候选记录中选最接近当前歌曲的一条。
    private func pickBestMatch(from records: [LyricsRecord], query: LyricsQuery) -> LyricsRecord? {
        records
            .filter { !$0.isInstrumental }
            .max { score($0, query: query) < score($1, query: query) }
    }

    /// 给歌词候选打分，优先歌名/作者完全匹配，其次时长接近。
    private func score(_ record: LyricsRecord, query: LyricsQuery) -> Int {
        var value = 0
        if normalized(record.trackName) == query.normalizedTitle { value += 60 }
        if normalized(record.artistName) == query.normalizedArtist { value += 30 }
        if let duration = query.duration, let recordDuration = record.duration {
            let diff = abs(recordDuration - duration)
            if diff <= 2 { value += 20 }
            else if diff <= 8 { value += 10 }
        }
        return value
    }

    /// 把 LRCLIB 记录转成播放器现有的歌词行模型。
    private func lines(from record: LyricsRecord, duration: TimeInterval) -> [LyricLine] {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            return AudioStationAPI.parseLRC(synced)
        }
        guard let plain = record.plainLyrics, !plain.isEmpty else { return [] }
        let texts = plain
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !texts.isEmpty else { return [] }
        // 纯文本没有可信时间轴，负值明确标记为不可同步、不可点击跳转。
        return texts.map { LyricLine(timestamp: -1, text: $0) }
    }

    /// 用于宽松匹配的归一化字符串。
    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// LRCLIB 查询参数。
private struct LyricsQuery {
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval?

    var canSearch: Bool { !title.isEmpty }
    var normalizedTitle: String { normalize(title) }
    var normalizedArtist: String { normalize(artist) }

    /// 精确查询参数。
    var exactItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration {
            items.append(URLQueryItem(name: "duration", value: String(format: "%.0f", duration)))
        }
        return items
    }

    /// 搜索查询参数。
    var searchItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        if let duration {
            items.append(URLQueryItem(name: "duration", value: String(format: "%.0f", duration)))
        }
        return items
    }

    /// 从歌曲模型生成在线歌词查询。
    init(song: Song) {
        self.title = Self.clean(song.title)
        self.artist = Self.clean(song.artist ?? song.albumArtist ?? "")
        self.album = song.album.map(Self.clean)
        self.duration = song.duration > 0 ? song.duration : nil
    }

    /// 清理标题里常见的版本后缀，提高在线匹配率。
    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s*[\(\[].*?(live|ver\.?|version|remaster|伴奏|inst).*?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 用于宽松匹配的归一化字符串。
    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// LRCLIB 返回的歌词记录。
private struct LyricsRecord: Decodable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?

    var isInstrumental: Bool { instrumental == true }
}
