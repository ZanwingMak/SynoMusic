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
