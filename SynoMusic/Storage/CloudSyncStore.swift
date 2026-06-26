import Foundation

/// iCloud 配置同步：同步服务器非敏感信息与本地歌单，密码不进入云端。
@MainActor
final class CloudSyncStore: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusMessage: String?

    private weak var serverStore: ServerStore?
    private weak var playlistStore: PlaylistStore?
    private var changeObserver: NSObjectProtocol?

    private let defaults: UserDefaults
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let enabledKey = "syno.icloud.sync.enabled"
    private let snapshotKey = "syno.icloud.config.snapshot"
    private let lastAppliedKey = "syno.icloud.config.lastAppliedAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: enabledKey)
    }

    /// 绑定本地仓库，并开始监听 iCloud 外部变更。
    func configure(serverStore: ServerStore, playlistStore: PlaylistStore) {
        self.serverStore = serverStore
        self.playlistStore = playlistStore
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pullCloudSnapshotIfNewer()
            }
        }
        cloudStore.synchronize()
        if isEnabled {
            mergeCloudSnapshotOnStart()
        }
    }

    /// 开启或关闭 iCloud 配置同步。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)
        defaults.synchronize()
        if enabled {
            mergeCloudSnapshotOnStart()
        } else {
            statusMessage = "iCloud 云同步已关闭".t
        }
    }

    /// 本地配置变化后推送到 iCloud。
    func pushLocalSnapshotIfNeeded() {
        guard isEnabled else { return }
        pushLocalSnapshot()
    }

    /// 清除一次性同步状态提示。
    func clearStatusMessage() {
        statusMessage = nil
    }

    /// 启动或开启同步时，优先应用较新的云端快照；没有云端数据时推送本机快照。
    private func mergeCloudSnapshotOnStart() {
        cloudStore.synchronize()
        if !pullCloudSnapshotIfNewer() {
            pushLocalSnapshot()
        }
    }

    /// 将当前本地配置写入 iCloud KVS。
    private func pushLocalSnapshot() {
        guard let serverStore, let playlistStore else { return }
        let snapshot = CloudConfigSnapshot(
            updatedAt: Date(),
            serverProfiles: serverStore.profiles,
            activeProfileID: serverStore.activeProfileID,
            playlists: playlistStore.playlists
        )
        guard let data = try? JSONEncoder().encode(snapshot) else {
            statusMessage = "iCloud 同步失败：无法编码配置".t
            return
        }
        cloudStore.set(data, forKey: snapshotKey)
        cloudStore.synchronize()
        rememberAppliedDate(snapshot.updatedAt)
        statusMessage = "配置已同步到 iCloud".t
    }

    /// 拉取云端快照；只有云端更新时间较新时才覆盖本地。
    @discardableResult
    private func pullCloudSnapshotIfNewer() -> Bool {
        guard isEnabled,
              let serverStore,
              let playlistStore,
              let data = cloudStore.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(CloudConfigSnapshot.self, from: data) else {
            return false
        }
        guard snapshot.updatedAt > lastAppliedDate else { return false }
        serverStore.replaceProfiles(snapshot.serverProfiles, activeProfileID: snapshot.activeProfileID)
        playlistStore.replacePlaylists(snapshot.playlists)
        rememberAppliedDate(snapshot.updatedAt)
        statusMessage = "已从 iCloud 更新配置".t
        return true
    }

    /// 记录已应用的云端快照时间，避免重复覆盖本地。
    private func rememberAppliedDate(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: lastAppliedKey)
        defaults.synchronize()
    }

    /// 最近一次已应用云端快照的时间。
    private var lastAppliedDate: Date {
        let timestamp = defaults.double(forKey: lastAppliedKey)
        guard timestamp > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: timestamp)
    }
}

/// iCloud 中保存的一次配置快照。
private struct CloudConfigSnapshot: Codable {
    let updatedAt: Date
    let serverProfiles: [ServerProfile]
    let activeProfileID: UUID?
    let playlists: [LocalPlaylist]
}
