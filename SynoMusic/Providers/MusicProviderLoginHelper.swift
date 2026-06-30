import Foundation

/// 统一音乐源登录结果。
struct MusicProviderLoginResult {
    let musicClient: any MusicLibraryClient
    let profile: ServerProfile
}

/// 音乐源登录调度器；根据服务器类型选择对应登录实现。
enum MusicProviderLoginHelper {
    typealias ProgressReporter = @MainActor @Sendable (String) -> Void

    /// 使用指定档案登录音乐源，并返回统一音乐库客户端。
    static func login(
        profile: ServerProfile,
        password: String,
        otp: String? = nil,
        report: ProgressReporter? = nil
    ) async throws -> MusicProviderLoginResult {
        switch profile.providerType {
        case .synologyAudioStation:
            let result = try await SynologyLoginHelper.login(
                profile: profile,
                password: password,
                otp: otp,
                report: report
            )
            return MusicProviderLoginResult(
                musicClient: SynologyMusicLibraryClient(client: result.client),
                profile: result.profile
            )
        case .jellyfin, .emby:
            if let report { await report("正在连接...") }
            let client = MediaBrowserMusicLibraryClient(providerType: profile.providerType, profile: profile)
            try await client.authenticate(password: password)
            return MusicProviderLoginResult(musicClient: client, profile: profile)
        case .plex:
            if let report { await report("正在连接...") }
            let client = PlexMusicLibraryClient(profile: profile)
            try await client.authenticate(token: password)
            return MusicProviderLoginResult(musicClient: client, profile: profile)
        }
    }
}
