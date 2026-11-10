import CloudKit
import Foundation

/// 原生桥接请求：在同一进程中使用主应用的 iCloud 身份访问私有数据库。
private struct CloudRequest: Codable, Sendable {
    let requestID: String
    let operation: String
    let state: Data?
    let updatedAt: Double?
}

/// 原生桥接结果，仅返回用户自己的资料或可读错误。
private struct CloudReply: Codable, Sendable {
    let requestID: String
    let state: Data?
    let updatedAt: Double?
    let error: String?
}

/// 以 C 回调返回 JSON，并保证返回字符串在回调期间有效。
private func reply(_ value: CloudReply, callback: @escaping @convention(c) (UnsafePointer<CChar>) -> Void) {
    let data = (try? JSONEncoder().encode(value)) ?? Data("{\"error\":\"Unable to encode iCloud response\"}".utf8)
    String(decoding: data, as: UTF8.self).withCString { callback($0) }
}

/// 读取用户私有记录；尚未同步过时返回空值。
private func existing(_ id: CKRecord.ID, database: CKDatabase) async throws -> CKRecord? {
    do { return try await database.record(for: id) }
    catch let error as CKError where error.code == .unknownItem { return nil }
}

/// 提供 Mac 本机资料的可选 iCloud 同步；用户未开启时不连接云端。
@_cdecl("synomusic_cloud_sync")
public func synomusicCloudSync(_ input: UnsafePointer<CChar>, callback: @escaping @convention(c) (UnsafePointer<CChar>) -> Void) {
    guard let request = try? JSONDecoder().decode(CloudRequest.self, from: Data(String(cString: input).utf8)) else {
        reply(CloudReply(requestID: "", state: nil, updatedAt: nil, error: "Invalid iCloud request"), callback: callback)
        return
    }
    Task {
        do {
            let container = CKContainer(identifier: "iCloud.app.synomusic.SynoMusic")
            guard try await container.accountStatus() == .available else {
                reply(CloudReply(requestID: request.requestID, state: nil, updatedAt: nil, error: "Sign in to iCloud in System Settings to sync."), callback: callback)
                return
            }
            let database = container.privateCloudDatabase
            let id = CKRecord.ID(recordName: "synomusic.macDesktop")
            let remote = try await existing(id, database: database)
            let remoteDate = (remote?["updatedAt"] as? Date)?.timeIntervalSince1970 ?? 0
            let localDate = request.updatedAt ?? 0
            if request.operation == "sync", let data = request.state, localDate > remoteDate {
                let record = remote ?? CKRecord(recordType: "SynoMusicSyncDocument", recordID: id)
                record["payload"] = data as NSData
                record["updatedAt"] = Date(timeIntervalSince1970: localDate) as NSDate
                record["schemaVersion"] = 1 as NSNumber
                let saved = try await database.save(record)
                reply(CloudReply(requestID: request.requestID, state: saved["payload"] as? Data, updatedAt: localDate, error: nil), callback: callback)
            } else {
                reply(CloudReply(requestID: request.requestID, state: remote?["payload"] as? Data, updatedAt: remoteDate, error: nil), callback: callback)
            }
        } catch {
            reply(CloudReply(requestID: request.requestID, state: nil, updatedAt: nil, error: error.localizedDescription), callback: callback)
        }
    }
}

/// 仅保留当前进程已开启的目录访问，避免重复增加安全作用域引用计数。
private let fileAccessLock = NSLock()
private var accessibleFolders: [String: URL] = [:]
private let bookmarkDefaultsKey = "synomusic.localFolderBookmarks"

/// 恢复本机安全作用域书签；已失效或被移除的目录等待用户重新选择。
@_cdecl("synomusic_restore_files")
public func restoreMusicFolders() {
    fileAccessLock.lock()
    defer { fileAccessLock.unlock() }
    var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkDefaultsKey) as? [String: Data] ?? [:]
    for (path, data) in bookmarks {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
        if accessibleFolders[url.path] == nil, url.startAccessingSecurityScopedResource() {
            accessibleFolders[url.path] = url
        }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope],
                                                      includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[path] = refreshed
        }
    }
    UserDefaults.standard.set(bookmarks, forKey: bookmarkDefaultsKey)
}

/// 为用户在原生选择器中授权的音乐目录生成本机书签，原始音频保留原位置。
@_cdecl("synomusic_remember_files")
public func rememberMusicFolders(_ input: UnsafePointer<CChar>) -> Int32 {
    guard let paths = try? JSONDecoder().decode([String].self, from: Data(String(cString: input).utf8)) else { return 1 }
    fileAccessLock.lock()
    defer { fileAccessLock.unlock() }
    var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkDefaultsKey) as? [String: Data] ?? [:]
    for path in paths {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                                  includingResourceValuesForKeys: nil, relativeTo: nil) else { return 1 }
        bookmarks[path] = bookmark
        if accessibleFolders[path] == nil, url.startAccessingSecurityScopedResource() {
            accessibleFolders[path] = url
        }
    }
    UserDefaults.standard.set(bookmarks, forKey: bookmarkDefaultsKey)
    return 0
}

/// 通过 Foundation 返回正确的应用支持目录，App Sandbox 下自动定位容器。
@_cdecl("synomusic_support_directory")
public func musicSupportDirectory(callback: @escaping @convention(c) (UnsafePointer<CChar>) -> Void) {
    let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? ""
    path.withCString { callback($0) }
}
