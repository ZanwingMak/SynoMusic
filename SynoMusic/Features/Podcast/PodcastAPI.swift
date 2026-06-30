import Foundation

/// 播客节目，来自 Apple Podcasts 搜索结果或本地订阅。
struct PodcastShow: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let author: String
    let feedURL: URL
    let artworkURL: URL?
    let genre: String?
}

/// 播客单集，来自公开 RSS feed。
struct PodcastEpisode: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let audioURL: URL
    let artworkURL: URL?
    let publishedAt: Date?
    let duration: TimeInterval?

    /// 把播客单集转换为播放器可复用的 Song 快照。
    func asSong(in show: PodcastShow) -> Song {
        Song(
            id: "podcast:\(id)",
            title: title,
            album: show.title,
            artist: show.author,
            albumArtist: nil,
            genre: "播客",
            composer: nil,
            trackNumber: nil,
            discNumber: nil,
            year: publishedAt.map { Calendar.current.component(.year, from: $0) },
            duration: duration ?? 0,
            bitrate: nil,
            codec: audioURL.pathExtension.isEmpty ? nil : audioURL.pathExtension,
            filesize: nil,
            path: audioURL.absoluteString,
            rating: nil
        )
    }
}

/// 播客搜索筛选项，集中传给 Apple Podcasts 搜索和热门榜接口。
struct PodcastSearchOptions: Hashable {
    var countryCode: String
    var languageCode: String?
    var genreID: Int?
}

/// Apple Podcasts 搜索和公开 RSS 解析客户端。
final class PodcastAPI: @unchecked Sendable {
    static let shared = PodcastAPI()

    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// 通过 Apple Podcasts 搜索在线播客资源。
    func search(_ keyword: String, limit: Int = 30, options: PodcastSearchOptions? = nil) async throws -> [PodcastShow] {
        let resolved = options ?? PodcastSearchOptions(countryCode: Locale.current.region?.identifier ?? "US", languageCode: nil, genreID: nil)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        var queryItems = [
            URLQueryItem(name: "term", value: keyword),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: resolved.countryCode)
        ]
        if let languageCode = resolved.languageCode {
            queryItems.append(URLQueryItem(name: "lang", value: languageCode))
        }
        if let genreID = resolved.genreID {
            queryItems.append(URLQueryItem(name: "genreId", value: String(genreID)))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("SynoMusic/1.5.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(ITunesPodcastResponse.self, from: data)
        return response.results.compactMap { $0.show }
    }

    /// 拉取指定国家与分类的 Apple Podcasts 热门榜，并补齐 RSS feed。
    func topPodcasts(limit: Int = 30, options: PodcastSearchOptions) async throws -> [PodcastShow] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        let country = options.countryCode.lowercased()
        if let genreID = options.genreID {
            components.path = "/\(country)/rss/toppodcasts/limit=\(limit)/genre=\(genreID)/json"
        } else {
            components.path = "/\(country)/rss/toppodcasts/limit=\(limit)/json"
        }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("SynoMusic/1.5.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let feed = try decoder.decode(ITunesTopPodcastResponse.self, from: data)
        let ids = feed.feed.entry?.compactMap(\.collectionID) ?? []
        return try await lookupPodcasts(ids: ids, countryCode: options.countryCode)
    }

    /// 读取播客 RSS feed 并解析可播放单集。
    func episodes(for show: PodcastShow) async throws -> [PodcastEpisode] {
        var request = URLRequest(url: show.feedURL)
        request.setValue("SynoMusic/1.5.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let parser = PodcastRSSParser(defaultArtworkURL: show.artworkURL)
        return try parser.parse(data)
    }

    /// 根据 Apple Podcasts collection id 查询完整节目资料。
    private func lookupPodcasts(ids: [String], countryCode: String) async throws -> [PodcastShow] {
        guard !ids.isEmpty else { return [] }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "country", value: countryCode)
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("SynoMusic/1.5.1 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(ITunesPodcastResponse.self, from: data)
        let showsByID = Dictionary(uniqueKeysWithValues: response.results.compactMap { result -> (String, PodcastShow)? in
            guard let show = result.show else { return nil }
            return (String(result.collectionId), show)
        })
        return ids.compactMap { showsByID[$0] }
    }
}

private struct ITunesPodcastResponse: Decodable {
    let results: [ITunesPodcastResult]
}

private struct ITunesPodcastResult: Decodable {
    let collectionId: Int
    let collectionName: String
    let artistName: String?
    let feedUrl: String?
    let artworkUrl100: String?
    let artworkUrl600: String?
    let primaryGenreName: String?

    /// 搜索结果转换为 App 内展示模型，缺少 feed 的结果不可播放。
    var show: PodcastShow? {
        guard let feedUrl, let feedURL = URL(string: feedUrl) else { return nil }
        let artwork = artworkUrl600 ?? artworkUrl100
        return PodcastShow(
            id: feedURL.absoluteString,
            title: collectionName,
            author: artistName ?? "",
            feedURL: feedURL,
            artworkURL: artwork.flatMap(URL.init(string:)),
            genre: primaryGenreName
        )
    }
}

private struct ITunesTopPodcastResponse: Decodable {
    let feed: ITunesTopPodcastFeed
}

private struct ITunesTopPodcastFeed: Decodable {
    let entry: [ITunesTopPodcastEntry]?
}

private struct ITunesTopPodcastEntry: Decodable {
    let id: ITunesTopPodcastID

    /// 热门榜 entry 中的 Apple collection id。
    var collectionID: String? {
        id.attributes.imID
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }
}

private struct ITunesTopPodcastID: Decodable {
    let attributes: ITunesTopPodcastAttributes
}

private struct ITunesTopPodcastAttributes: Decodable {
    let imID: String

    private enum CodingKeys: String, CodingKey {
        case imID = "im:id"
    }
}

private final class PodcastRSSParser: NSObject, XMLParserDelegate {
    private let defaultArtworkURL: URL?
    private var episodes: [PodcastEpisode] = []
    private var currentItem: RSSItem?
    private var currentElement: String = ""
    private var textBuffer: String = ""
    private var channelImageURL: URL?
    private var isInsideItem = false
    private var isInsideImage = false

    init(defaultArtworkURL: URL?) {
        self.defaultArtworkURL = defaultArtworkURL
    }

    /// 解析 RSS XML，返回带音频 enclosure 的单集。
    func parse(_ data: Data) throws -> [PodcastEpisode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return episodes
    }

    /// XMLParser 开始元素回调，用于识别 item、enclosure 和图片。
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        currentElement = name
        textBuffer = ""
        if name == "item" {
            isInsideItem = true
            currentItem = RSSItem()
        } else if name == "image" {
            isInsideImage = true
        } else if isInsideItem, name == "enclosure", let raw = attributeDict["url"], let url = URL(string: raw) {
            currentItem?.audioURL = url
        } else if isInsideItem, name == "image", let raw = attributeDict["href"], let url = URL(string: raw) {
            currentItem?.artworkURL = url
        }
    }

    /// XMLParser 文本回调，累积当前节点文本。
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    /// XMLParser 结束元素回调，把节点文本写入当前 item。
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = normalized(elementName)
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if isInsideItem {
            assignItemValue(value, for: name)
        } else if isInsideImage, name == "url", let url = URL(string: value) {
            channelImageURL = url
        }
        if name == "item" {
            finishItem()
            isInsideItem = false
        } else if name == "image" {
            isInsideImage = false
        }
        textBuffer = ""
    }

    /// 把 XML 元素名标准化，兼容 itunes:duration 这类命名空间前缀。
    private func normalized(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    /// 按 RSS 节点名给当前单集赋值。
    private func assignItemValue(_ value: String, for name: String) {
        guard !value.isEmpty else { return }
        switch name {
        case "title":
            currentItem?.title = value
        case "description", "summary":
            if currentItem?.summary.isEmpty != false {
                currentItem?.summary = value.strippingHTMLTags()
            }
        case "guid":
            currentItem?.guid = value
        case "pubDate":
            currentItem?.publishedAt = Self.date(from: value)
        case "duration":
            currentItem?.duration = Self.duration(from: value)
        default:
            break
        }
    }

    /// 当前 item 结束时生成可播放单集。
    private func finishItem() {
        guard let item = currentItem,
              let audioURL = item.audioURL,
              !item.title.isEmpty else {
            currentItem = nil
            return
        }
        let id = item.guid.isEmpty ? audioURL.absoluteString : item.guid
        episodes.append(PodcastEpisode(
            id: id,
            title: item.title,
            summary: item.summary,
            audioURL: audioURL,
            artworkURL: item.artworkURL ?? channelImageURL ?? defaultArtworkURL,
            publishedAt: item.publishedAt,
            duration: item.duration
        ))
        currentItem = nil
    }

    /// 解析 RSS 日期，兼容常见英文 feed 日期格式。
    private static func date(from raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    /// 解析 itunes:duration，支持 HH:mm:ss、mm:ss 和秒数。
    private static func duration(from raw: String) -> TimeInterval? {
        if let seconds = TimeInterval(raw) { return seconds }
        let parts = raw.split(separator: ":").compactMap { TimeInterval($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}

private struct RSSItem {
    var title = ""
    var summary = ""
    var guid = ""
    var audioURL: URL?
    var artworkURL: URL?
    var publishedAt: Date?
    var duration: TimeInterval?
}

private extension String {
    /// 去掉简单 HTML 标签，保留 RSS 描述里的可读文本。
    func strippingHTMLTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
