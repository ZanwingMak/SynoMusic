import CloudKit
import Foundation

/// iCloud 同步：CloudKit Database 同步资料，KVS 保留为旧版本迁移兜底。
@MainActor
final class CloudSyncStore: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var credentialsSyncEnabled: Bool
    @Published private(set) var statusMessage: String?

    private weak var serverStore: ServerStore?
    private weak var playlistStore: PlaylistStore?
    private weak var themeManager: ThemeManager?
    private weak var playbackSettings: PlaybackSettings?
    private weak var podcastStore: PodcastSubscriptionStore?
    private weak var songUserDataStore: SongUserDataStore?
    private weak var playbackEngine: PlaybackEngine?
    private var changeObserver: NSObjectProtocol?
    private var scheduledPushTask: Task<Void, Never>?

    private let defaults: UserDefaults
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let cloudKit = CloudKitDocumentStore()
    private let enabledKey = "syno.icloud.sync.enabled"
    private let credentialsEnabledKey = "syno.icloud.credentials.sync.enabled"
    private let snapshotKey = "syno.icloud.config.snapshot"
    private let lastAppliedKey = "syno.icloud.config.lastAppliedAt"
    private let cloudDocumentLastAppliedPrefix = "syno.icloud.database.lastApplied."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: enabledKey)
        self.credentialsSyncEnabled = defaults.bool(forKey: credentialsEnabledKey)
    }

    /// 绑定本地仓库，并开始监听 iCloud 外部变更。
    func configure(
        serverStore: ServerStore,
        playlistStore: PlaylistStore,
        themeManager: ThemeManager,
        playbackSettings: PlaybackSettings,
        podcastStore: PodcastSubscriptionStore,
        songUserDataStore: SongUserDataStore,
        playbackEngine: PlaybackEngine
    ) {
        self.serverStore = serverStore
        self.playlistStore = playlistStore
        self.themeManager = themeManager
        self.playbackSettings = playbackSettings
        self.podcastStore = podcastStore
        self.songUserDataStore = songUserDataStore
        self.playbackEngine = playbackEngine
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pullKeyValueSnapshotIfNewer()
            }
        }
        cloudStore.synchronize()
        if isEnabled {
            mergeCloudStateOnStart()
        }
    }

    /// 开启或关闭 iCloud 资料同步。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        defaults.synchronize()
        if enabled {
            mergeCloudStateOnStart()
        } else {
            scheduledPushTask?.cancel()
            if credentialsSyncEnabled {
                setCredentialsSyncEnabled(false)
            }
            statusMessage = "iCloud 云同步已关闭".t
        }
    }

    /// 开启或关闭通过 iCloud Keychain 同步登录凭据。
    func setCredentialsSyncEnabled(_ enabled: Bool) {
        credentialsSyncEnabled = enabled
        defaults.set(enabled, forKey: credentialsEnabledKey)
        defaults.synchronize()
        do {
            let accounts = serverStore?.profiles.map { $0.id.uuidString } ?? []
            try KeychainStore.setCredentialsSyncEnabled(enabled, accounts: accounts)
            statusMessage = enabled ? "登录凭据将通过 iCloud Keychain 同步".t : "登录凭据仅保存在本机".t
            Haptics.success()
        } catch {
            statusMessage = "同步登录凭据失败：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    /// 本地配置变化后推送到 iCloud。
    func pushLocalSnapshotIfNeeded() {
        guard isEnabled else { return }
        pushKeyValueSnapshot()
        scheduleCloudKitPush()
    }

    /// 立即执行一次双向同步：先拉远端，再推本机最新状态。
    func syncNow() async {
        guard isEnabled else { return }
        statusMessage = "正在同步 iCloud".t
        let didPull = await pullCloudKitDocuments()
        pushKeyValueSnapshot()
        await pushCloudKitDocuments()
        statusMessage = didPull ? "已从 iCloud 更新配置".t : "配置已同步到 iCloud".t
    }

    /// 清除一次性同步状态提示。
    func clearStatusMessage() {
        statusMessage = nil
    }

    /// 启动或开启同步时，优先应用 CloudKit；无数据库资料时回退到旧 KVS 快照。
    private func mergeCloudStateOnStart() {
        cloudStore.synchronize()
        Task { [weak self] in
            guard let self else { return }
            let didPullDatabase = await self.pullCloudKitDocuments()
            if !didPullDatabase, !self.pullKeyValueSnapshotIfNewer() {
                self.pushKeyValueSnapshot()
            }
            await self.pushCloudKitDocuments()
        }
    }

    /// 延迟推送 CloudKit，合并短时间内多次设置变化。
    private func scheduleCloudKitPush() {
        scheduledPushTask?.cancel()
        scheduledPushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushCloudKitDocuments()
        }
    }

    /// 将基础配置写入旧版 iCloud KVS，用于旧版本迁移和轻量兜底。
    private func pushKeyValueSnapshot() {
        guard let serverStore, let playlistStore else { return }
        let snapshot = CloudConfigSnapshot(
            updatedAt: Date(),
            serverProfiles: serverStore.profiles,
            activeProfileID: serverStore.activeProfileID,
            playlists: playlistStore.playlists,
            themeID: themeManager?.currentID,
            appearance: themeManager?.appearance.rawValue
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            statusMessage = "iCloud 同步失败：无法编码配置".t
            return
        }
        cloudStore.set(data, forKey: snapshotKey)
        cloudStore.synchronize()
        rememberKeyValueAppliedDate(snapshot.updatedAt)
    }

    /// 拉取旧版 KVS 快照；只有云端更新时间较新时才覆盖本地。
    @discardableResult
    private func pullKeyValueSnapshotIfNewer() -> Bool {
        guard isEnabled,
              let serverStore,
              let playlistStore,
              let data = cloudStore.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(CloudConfigSnapshot.self, from: data) else {
            return false
        }
        guard snapshot.updatedAt > lastKeyValueAppliedDate else { return false }
        serverStore.replaceProfiles(snapshot.serverProfiles, activeProfileID: snapshot.activeProfileID)
        playlistStore.replacePlaylists(snapshot.playlists)
        applyTheme(themeID: snapshot.themeID, appearance: snapshot.appearance)
        rememberKeyValueAppliedDate(snapshot.updatedAt)
        statusMessage = "已从 iCloud 更新配置".t
        return true
    }

    /// 把本机各类资料推送为 CloudKit 私有数据库文档。
    private func pushCloudKitDocuments() async {
        guard isEnabled else { return }
        do {
            let now = Date()
            if let serverStore {
                try await cloudKit.save(
                    ServerProfilesPayload(profiles: serverStore.profiles, activeProfileID: serverStore.activeProfileID),
                    for: .serverProfiles,
                    updatedAt: now
                )
                rememberCloudDocumentAppliedDate(now, for: .serverProfiles)
            }
            if let playlistStore {
                try await cloudKit.save(PlaylistsPayload(playlists: playlistStore.playlists), for: .playlists, updatedAt: now)
                rememberCloudDocumentAppliedDate(now, for: .playlists)
            }
            if let themeManager, let playbackSettings {
                try await cloudKit.save(
                    PreferencesPayload(
                        themeID: themeManager.currentID,
                        appearance: themeManager.appearance.rawValue,
                        playbackSettings: playbackSettings.snapshot()
                    ),
                    for: .preferences,
                    updatedAt: now
                )
                rememberCloudDocumentAppliedDate(now, for: .preferences)
            }
            if let songUserDataStore {
                try await cloudKit.save(SongUserDataPayload(entries: songUserDataStore.entries), for: .songUserData, updatedAt: now)
                rememberCloudDocumentAppliedDate(now, for: .songUserData)
            }
            if let podcastStore {
                try await cloudKit.save(PodcastSubscriptionsPayload(shows: podcastStore.shows), for: .podcastSubscriptions, updatedAt: now)
                rememberCloudDocumentAppliedDate(now, for: .podcastSubscriptions)
            }
            if let playbackEngine {
                try await cloudKit.save(PlaybackHistoryPayload(snapshot: playbackEngine.historySnapshot()), for: .playbackHistory, updatedAt: now)
                rememberCloudDocumentAppliedDate(now, for: .playbackHistory)
            }
            statusMessage = "配置已同步到 iCloud".t
        } catch {
            statusMessage = "iCloud 同步失败：\(error.localizedDescription)"
        }
    }

    /// 从 CloudKit 私有数据库拉取各类资料，并按文档更新时间应用。
    @discardableResult
    private func pullCloudKitDocuments() async -> Bool {
        guard isEnabled else { return false }
        var didApply = false
        do {
            if let envelope: CloudDocumentEnvelope<ServerProfilesPayload> = try await cloudKit.fetch(.serverProfiles),
               shouldApplyCloudDocument(envelope.updatedAt, for: .serverProfiles),
               let serverStore {
                serverStore.replaceProfiles(envelope.payload.profiles, activeProfileID: envelope.payload.activeProfileID)
                rememberCloudDocumentAppliedDate(envelope.updatedAt, for: .serverProfiles)
                didApply = true
            }
            if let envelope: CloudDocumentEnvelope<PlaylistsPayload> = try await cloudKit.fetch(.playlists),
               shouldApplyCloudDocument(envelope.updatedAt, for: .playlists),
               let playlistStore {
                playlistStore.replacePlaylists(envelope.payload.playlists)
                rememberCloudDocumentAppliedDate(envelope.updatedAt, for: .playlists)
                didApply = true
            }
            if let envelope: CloudDocumentEnvelope<PreferencesPayload> = try await cloudKit.fetch(.preferences),
               shouldApplyCloudDocument(envelope.updatedAt, for: .preferences) {
                applyTheme(themeID: envelope.payload.themeID, appearance: envelope.payload.appearance)
                playbackSettings?.applySnapshot(envelope.payload.playbackSettings)
                rememberCloudDocumentAppliedDate(envelope.updatedAt, for: .preferences)
                didApply = true
            }
            if let envelope: CloudDocumentEnvelope<SongUserDataPayload> = try await cloudKit.fetch(.songUserData),
               shouldApplyCloudDocument(envelope.updatedAt, for: .songUserData),
               let songUserDataStore {
                songUserDataStore.replaceEntries(envelope.payload.entries)
                rememberCloudDocumentAppliedDate(envelope.updatedAt, for: .songUserData)
                didApply = true
            }
            if let envelope: CloudDocumentEnvelope<PodcastSubscriptionsPayload> = try await cloudKit.fetch(.podcastSubscriptions),
               shouldApplyCloudDocument(envelope.updatedAt, for: .podcastSubscriptions),
               let podcastStore {
                podcastStore.replaceShows(envelope.payload.shows)
                rememberCloudDocumentAppliedDate(envelope.updatedAt, for: .podcastSubscriptions)
                didApply = true
            }
            if let envelope: CloudDocumentEnvelope<PlaybackHistoryPayload> = try await cloudKit.fetch(.playbackHistory),
               shouldApplyCloudDocument(envelope.updatedAt, for: .playbackHistory),
               let playbackEngine {
                playbackEngine.applyHistorySnapshot(envelope.payload.snapshot)
                rememberCloudDocumentAppliedDate(envelope.updatedAt, for: .playbackHistory)
                didApply = true
            }
        } catch {
            statusMessage = "iCloud 同步失败：\(error.localizedDescription)"
        }
        if didApply {
            statusMessage = "已从 iCloud 更新配置".t
        }
        return didApply
    }

    /// 将云端主题配置应用到本机。
    private func applyTheme(themeID: String?, appearance: String?) {
        guard let themeManager else { return }
        if let themeID,
           ThemeManager.palettes.contains(where: { $0.id == themeID }) {
            themeManager.currentID = themeID
        }
        if let appearance,
           let parsed = AppearancePreference(rawValue: appearance) {
            themeManager.appearance = parsed
        }
    }

    /// 判断 CloudKit 文档是否比本机最近应用版本更新。
    private func shouldApplyCloudDocument(_ date: Date, for document: CloudSyncDocument) -> Bool {
        date > lastCloudDocumentAppliedDate(for: document)
    }

    /// 记录已应用的 KVS 快照时间，避免重复覆盖本地。
    private func rememberKeyValueAppliedDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: lastAppliedKey)
        defaults.synchronize()
    }

    /// 记录已应用的 CloudKit 文档时间。
    private func rememberCloudDocumentAppliedDate(_ date: Date, for document: CloudSyncDocument) {
        defaults.set(date.timeIntervalSince1970, forKey: cloudDocumentAppliedKey(for: document))
        defaults.synchronize()
    }

    /// 读取最近一次应用的 CloudKit 文档时间。
    private func lastCloudDocumentAppliedDate(for document: CloudSyncDocument) -> Date {
        let timestamp = defaults.double(forKey: cloudDocumentAppliedKey(for: document))
        guard timestamp > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// CloudKit 文档应用时间的 UserDefaults key。
    private func cloudDocumentAppliedKey(for document: CloudSyncDocument) -> String {
        "\(cloudDocumentLastAppliedPrefix)\(document.rawValue)"
    }

    /// 最近一次已应用 KVS 快照的时间。
    private var lastKeyValueAppliedDate: Date {
        let timestamp = defaults.double(forKey: lastAppliedKey)
        guard timestamp > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: timestamp)
    }
}

/// CloudKit 私有数据库中的文档类型。
private enum CloudSyncDocument: String, CaseIterable {
    case serverProfiles
    case playlists
    case preferences
    case songUserData
    case podcastSubscriptions
    case playbackHistory

    /// 稳定的 CloudKit record id。
    var recordID: CKRecord.ID {
        CKRecord.ID(recordName: "synomusic.\(rawValue)")
    }
}

/// CloudKit 文档外壳：每类资料独立保存更新时间和 payload。
private struct CloudDocumentEnvelope<Payload: Codable>: Codable {
    let updatedAt: Date
    let payload: Payload
}

/// CloudKit 文档读写器。
@MainActor
private struct CloudKitDocumentStore {
    private let database = CKContainer(identifier: "iCloud.app.synomusic.SynoMusic").privateCloudDatabase
    private let recordType = "SynoMusicSyncDocument"
    private let payloadKey = "payload"
    private let updatedAtKey = "updatedAt"
    private let schemaVersionKey = "schemaVersion"

    /// 保存一类同步文档到 CloudKit 私有数据库。
    func save<Payload: Codable>(_ payload: Payload, for document: CloudSyncDocument, updatedAt: Date) async throws {
        let envelope = CloudDocumentEnvelope(updatedAt: updatedAt, payload: payload)
        let data = try JSONEncoder().encode(envelope)
        let record = try await existingRecord(for: document) ?? CKRecord(recordType: recordType, recordID: document.recordID)
        record[payloadKey] = data as NSData
        record[updatedAtKey] = updatedAt as NSDate
        record[schemaVersionKey] = NSNumber(value: 1)
        _ = try await database.save(record)
    }

    /// 从 CloudKit 私有数据库读取指定同步文档。
    func fetch<Payload: Codable>(_ document: CloudSyncDocument) async throws -> CloudDocumentEnvelope<Payload>? {
        guard let record = try await existingRecord(for: document),
              let raw = record[payloadKey] else {
            return nil
        }
        let data: Data
        if let value = raw as? Data {
            data = value
        } else if let value = raw as? NSData {
            data = value as Data
        } else {
            return nil
        }
        return try JSONDecoder().decode(CloudDocumentEnvelope<Payload>.self, from: data)
    }

    /// 读取已存在的 CloudKit 记录；不存在时返回 nil。
    private func existingRecord(for document: CloudSyncDocument) async throws -> CKRecord? {
        do {
            return try await database.record(for: document.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
}

/// iCloud KVS 中保存的一次旧版配置快照。
private struct CloudConfigSnapshot: Codable {
    let updatedAt: Date
    let serverProfiles: [ServerProfile]
    let activeProfileID: UUID?
    let playlists: [LocalPlaylist]
    let themeID: String?
    let appearance: String?
}

/// 服务器配置同步 payload。
private struct ServerProfilesPayload: Codable {
    let profiles: [ServerProfile]
    let activeProfileID: UUID?
}

/// 本地歌单同步 payload。
private struct PlaylistsPayload: Codable {
    let playlists: [LocalPlaylist]
}

/// 偏好设置同步 payload。
private struct PreferencesPayload: Codable {
    let themeID: String
    let appearance: String
    let playbackSettings: PlaybackSettingsSnapshot
}

/// 歌曲自定义资料同步 payload。
private struct SongUserDataPayload: Codable {
    let entries: [String: SongUserData]
}

/// 播客订阅同步 payload。
private struct PodcastSubscriptionsPayload: Codable {
    let shows: [PodcastShow]
}

/// 播放历史同步 payload。
private struct PlaybackHistoryPayload: Codable {
    let snapshot: PlaybackHistorySnapshot
}
