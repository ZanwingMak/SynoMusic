import Foundation

/// 下载条目状态。
enum DownloadStatus: String, Codable { case pending, downloading, completed, failed }

/// 已下载/正在下载的歌曲条目。
struct DownloadedSong: Identifiable, Codable, Hashable {
    let id: String           // = Song.id
    var title: String
    var artist: String?
    var album: String?
    var fileURLPath: String  // 沙盒相对路径
    var size: Int64
    var status: DownloadStatus
    var addedAt: Date
}

/// 离线下载管理器：把流 URL 下载到沙盒 Documents/Downloads/{songID}.{ext}。
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var entries: [DownloadedSong] = []
    @Published var allowCellularDownload: Bool {
        didSet {
            UserDefaults.standard.set(allowCellularDownload, forKey: cellularKey)
            UserDefaults.standard.synchronize()
        }
    }

    private let fileManager = FileManager.default
    private let indexKey = "noc.downloads.index"
    private let cellularKey = "noc.downloads.allowCellular"

    init() {
        self.allowCellularDownload = UserDefaults.standard.bool(forKey: cellularKey)
        load()
    }

    /// 下载目录的绝对 URL。
    var downloadsDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 返回歌曲当前下载状态；没有记录时返回 nil。
    func status(for songID: String) -> DownloadStatus? {
        entries.first(where: { $0.id == songID })?.status
    }

    /// 已下载歌曲对应的本地文件 URL；若没下完返回 nil。
    func localURL(for songID: String) -> URL? {
        guard let entry = entries.first(where: { $0.id == songID && $0.status == .completed }) else { return nil }
        let url = downloadsDir.appendingPathComponent(entry.fileURLPath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// 下载一首歌；网络 URL 抓取字节，本地 file URL 直接复制到下载目录。
    func download(song: Song, streamURL: URL, fileExtension: String, allowInvalidCertificate: Bool = false) async throws {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "mp3"
            : fileExtension.lowercased()
        let filename = "\(song.id).\(ext)"
        let dest = downloadsDir.appendingPathComponent(filename)

        var entry = DownloadedSong(
            id: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album,
            fileURLPath: filename,
            size: 0,
            status: .downloading,
            addedAt: Date()
        )
        upsert(entry)

        do {
            if streamURL.isFileURL {
                entry.size = try copyLocalFile(from: streamURL, to: dest)
            } else {
                let session = makeSession(allowInvalidCertificate: allowInvalidCertificate)
                let (data, _) = try await session.data(from: streamURL)
                try data.write(to: dest, options: .atomic)
                entry.size = Int64(data.count)
            }
            entry.status = .completed
            upsert(entry)
        } catch {
            entry.status = .failed
            upsert(entry)
            throw error
        }
    }

    /// 删除一项。
    func remove(songID: String) {
        if let entry = entries.first(where: { $0.id == songID }) {
            let url = downloadsDir.appendingPathComponent(entry.fileURLPath)
            try? fileManager.removeItem(at: url)
        }
        entries.removeAll { $0.id == songID }
        save()
    }

    /// 清空所有下载。
    func clearAll() {
        for e in entries {
            try? fileManager.removeItem(at: downloadsDir.appendingPathComponent(e.fileURLPath))
        }
        entries = []
        save()
    }

    /// 已用空间（字节）。
    var totalBytes: Int64 {
        entries.filter { $0.status == .completed }.reduce(0) { $0 + $1.size }
    }

    /// 已完成下载的歌曲快照，用于智能歌单离线播放。
    var completedSongSnapshots: [Song] {
        entries
            .filter { $0.status == .completed }
            .sorted { $0.addedAt > $1.addedAt }
            .map { $0.songSnapshot }
    }

    // MARK: 持久化

    /// 插入或替换下载索引中的条目。
    private func upsert(_ entry: DownloadedSong) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        save()
    }

    /// 从 UserDefaults 读取下载索引。
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: indexKey) else { return }
        if let list = try? JSONDecoder().decode([DownloadedSong].self, from: data) {
            self.entries = list
        }
    }

    /// 将下载索引保存到 UserDefaults。
    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }

    /// 创建下载用 URLSession；必要时允许用户已信任的自签名证书。
    private func makeSession(allowInvalidCertificate: Bool) -> URLSession {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = allowCellularDownload
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        guard allowInvalidCertificate else {
            return URLSession(configuration: config)
        }
        return URLSession(configuration: config, delegate: DownloadCertDelegate(), delegateQueue: nil)
    }

    /// 把本地文件复制到下载目录，并返回复制后的文件大小。
    private func copyLocalFile(from source: URL, to destination: URL) throws -> Int64 {
        let isSameFile = source.standardizedFileURL == destination.standardizedFileURL
        if !isSameFile && fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if !isSameFile {
            try fileManager.copyItem(at: source, to: destination)
        }
        let attrs = try fileManager.attributesOfItem(atPath: destination.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// 下载请求专用的证书代理；仅在用户配置允许自签名证书时使用。
private final class DownloadCertDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    /// 对下载请求的 session 级证书挑战进行处理。
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        complete(challenge, completionHandler: completionHandler)
    }

    /// 对下载请求的 task 级证书挑战进行处理。
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        complete(challenge, completionHandler: completionHandler)
    }

    /// 根据认证类型决定是否信任当前服务器证书。
    private func complete(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension DownloadedSong {
    /// 将下载索引中的轻量信息还原成可播放队列使用的歌曲快照。
    var songSnapshot: Song {
        Song(
            id: id,
            title: title,
            album: album,
            artist: artist,
            albumArtist: artist,
            genre: nil,
            composer: nil,
            trackNumber: nil,
            discNumber: nil,
            year: nil,
            duration: 0,
            bitrate: nil,
            codec: URL(fileURLWithPath: fileURLPath).pathExtension,
            filesize: size,
            path: nil,
            rating: nil
        )
    }
}

/// 字节数 → 可读字符串。
extension Int64 {
    var humanSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
