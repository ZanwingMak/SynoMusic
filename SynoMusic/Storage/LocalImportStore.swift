import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// 本地导入的音乐条目，文件存放在 App 沙盒 Documents/ImportedMusic。
struct LocalImportedTrack: Identifiable, Hashable, Codable {
    let id: UUID
    let title: String
    let artist: String?
    let filename: String
    let duration: TimeInterval
    let importedAt: Date

    /// 转成播放器可直接使用的 Song 快照。
    var song: Song {
        Song(
            id: "local:\(id.uuidString)",
            title: title,
            album: "本地导入",
            artist: artist,
            albumArtist: artist,
            genre: nil,
            composer: nil,
            trackNumber: nil,
            discNumber: nil,
            year: nil,
            duration: duration,
            bitrate: nil,
            codec: URL(fileURLWithPath: filename).pathExtension,
            filesize: nil,
            path: fileURL.path,
            rating: nil
        )
    }

    /// 沙盒内音频文件 URL。
    var fileURL: URL {
        LocalImportStore.importDirectory.appendingPathComponent(filename)
    }
}

/// 管理本地导入音乐：支持文件导入、链接下载导入、删除和持久化。
@MainActor
final class LocalImportStore: ObservableObject {
    @Published private(set) var tracks: [LocalImportedTrack] = []
    @Published private(set) var isImporting = false
    @Published private(set) var statusMessage: String?

    nonisolated static let importDirectory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ImportedMusic", isDirectory: true)
    }()

    private let indexKey = "syno.local.imports"

    init() {
        ensureImportDirectory()
        loadIndex()
    }

    /// 从文件选择器导入一个音频文件。
    func importFile(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let track = try await copyIntoLibrary(sourceURL: url, preferredName: url.lastPathComponent)
            tracks.insert(track, at: 0)
            persistIndex()
            statusMessage = "已导入音乐".t + "：\(track.title)"
        } catch {
            statusMessage = "导入失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 从网络链接下载音频并导入沙盒。
    func importRemote(from text: String) async {
        guard !isImporting else { return }
        guard let url = normalizedURL(from: text) else {
            statusMessage = "请输入有效的音乐链接".t
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            let name = response.suggestedFilename ?? url.lastPathComponent
            let track = try await copyIntoLibrary(sourceURL: tempURL, preferredName: name.isEmpty ? "ImportedMusic.mp3" : name)
            tracks.insert(track, at: 0)
            persistIndex()
            statusMessage = "已导入音乐".t + "：\(track.title)"
        } catch {
            statusMessage = "导入失败".t + "：\(error.localizedDescription)"
        }
    }

    /// 删除本地导入音乐及其沙盒文件。
    func delete(_ track: LocalImportedTrack) {
        try? FileManager.default.removeItem(at: track.fileURL)
        tracks.removeAll { $0.id == track.id }
        persistIndex()
        statusMessage = "已删除".t
    }

    /// 清除一次性状态提示。
    func clearStatusMessage() {
        statusMessage = nil
    }

    /// 确保导入目录存在。
    private func ensureImportDirectory() {
        try? FileManager.default.createDirectory(at: Self.importDirectory, withIntermediateDirectories: true)
    }

    /// 从 UserDefaults 恢复导入索引，同时过滤已不存在的文件。
    private func loadIndex() {
        guard let data = UserDefaults.standard.data(forKey: indexKey),
              let decoded = try? JSONDecoder().decode([LocalImportedTrack].self, from: data) else {
            return
        }
        tracks = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    /// 持久化导入索引。
    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        UserDefaults.standard.set(data, forKey: indexKey)
    }

    /// 把来源文件复制到 App 沙盒，并生成可播放条目。
    private func copyIntoLibrary(sourceURL: URL, preferredName: String) async throws -> LocalImportedTrack {
        ensureImportDirectory()
        let filename = uniqueFilename(for: preferredName)
        let destination = Self.importDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return await buildTrack(for: destination, filename: filename)
    }

    /// 基于文件名和音频时长生成导入条目。
    private func buildTrack(for fileURL: URL, filename: String) async -> LocalImportedTrack {
        let asset = AVURLAsset(url: fileURL)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let title = fileURL.deletingPathExtension().lastPathComponent
        return LocalImportedTrack(
            id: UUID(),
            title: title,
            artist: nil,
            filename: filename,
            duration: duration.isFinite ? duration : 0,
            importedAt: Date()
        )
    }

    /// 生成不会覆盖已有文件的文件名。
    private func uniqueFilename(for originalName: String) -> String {
        let sanitized = originalName.replacingOccurrences(of: "/", with: "-")
        let baseURL = URL(fileURLWithPath: sanitized.isEmpty ? "ImportedMusic.mp3" : sanitized)
        let ext = baseURL.pathExtension.isEmpty ? "mp3" : baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        var candidate = "\(stem).\(ext)"
        var index = 1
        while FileManager.default.fileExists(atPath: Self.importDirectory.appendingPathComponent(candidate).path) {
            candidate = "\(stem)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }

    /// 把用户输入的链接规范化为 URL。
    private func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://" + trimmed)
    }
}
