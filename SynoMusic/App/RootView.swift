import SwiftUI

/// 根视图：直接显示主框架；若有默认服务器和密码则后台静默登录。
/// 启动时若有默认服务器档案且 Keychain 中存了密码，则后台静默登录。
struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFullPlayer: Bool = false
    @State private var isAutoLogging: Bool = false

    /// 仅 DEBUG：`-demo` 启动参数直接进入主框架，便于演示。
    private var isDemo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            MainShellView(showFullPlayer: $showFullPlayer)
                // 关键：用当前会话的 profile.id 当 stable identity。
                // 切换不同账号时整个子树会重建，所有 @State / @StateObject 的
                // 缓存（专辑/艺术家/歌曲列表）随之失效，下一次出现立即重新加载。
                .id(shellIdentity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            // 顶部 Toast：播放/连接状态消息
            if let message = playback.statusMessage {
                StatusToast(message: message) { playback.dismissStatus() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: session.isLoggedIn)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playback.statusMessage)
        .animation(.easeInOut(duration: 0.18), value: theme.currentID)
        .tint(theme.current.accent(in: colorScheme))
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showFullPlayer) {
            FullPlayerView(isPresented: $showFullPlayer)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: playback.currentSong?.id) { oldID, newID in
            if newID == nil {
                showFullPlayer = false
                return
            }
            guard oldID == nil, newID != nil else { return }
            showFullPlayer = true
        }
        .onChange(of: shellIdentity) { oldIdentity, newIdentity in
            handleSessionIdentityChange(from: oldIdentity, to: newIdentity)
        }
        .task { await attemptAutoLogin() }
        .onAppear { handlePendingShortcutAction() }
        .onOpenURL { handleDeepLink($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                handlePendingShortcutAction()
            }
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-fullplayer") {
                playback.play(queue: DemoMode.songs, startAt: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    playback.pause()
                    showFullPlayer = true
                }
            } else if args.contains("-miniplayer") {
                playback.play(queue: DemoMode.songs, startAt: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    playback.pause()
                }
            }
        }
        #endif
    }

    /// 主框架身份：真实会话按服务器区分，审核/Demo 使用稳定值避免反复重建。
    private var shellIdentity: String {
        if let profile = session.musicClient?.profile {
            return [
                profile.providerType.rawValue,
                profile.id.uuidString,
                profile.musicLibraryID ?? ""
            ].joined(separator: ":")
        }
        if reviewMode.isEnabled { return AppReviewMode.shellIdentity }
        if !serverStore.profiles.isEmpty { return "no-active-session-with-profiles" }
        return "demo-mode"
    }

    /// 会话身份变化时停止旧服务器的播放，并同步收起播放器界面。
    private func handleSessionIdentityChange(from oldIdentity: String, to newIdentity: String) {
        guard oldIdentity != newIdentity else { return }
        showFullPlayer = false
        guard isRealSessionIdentity(oldIdentity) || isRealSessionIdentity(newIdentity) else { return }
        guard playback.currentSong != nil else { return }
        playback.stop()
    }

    /// 判断身份字符串是否来自真实服务器会话，而非 Demo / 未登录占位。
    private func isRealSessionIdentity(_ identity: String) -> Bool {
        identity.contains(":")
    }

    /// 启动时尝试用默认档案 + Keychain 密码静默登录。
    private func attemptAutoLogin() async {
        guard !session.isLoggedIn, !isDemo, !reviewMode.isEnabled else {
            session.setRestoringStartupSession(false)
            return
        }
        guard let p = serverStore.defaultProfile,
              let pwd = serverStore.password(for: p), !pwd.isEmpty else {
            session.setRestoringStartupSession(false)
            return
        }
        isAutoLogging = true
        session.setRestoringStartupSession(true)
        // 暴露给 LoginFlowView：让用户在多档案列表里看到「正在自动登录…」高亮哪一行
        session.autoLoginProfileID = p.id
        defer {
            isAutoLogging = false
            session.setRestoringStartupSession(false)
            if session.musicClient == nil { session.autoLoginProfileID = nil }
        }
        do {
            let result = try await MusicProviderLoginHelper.login(
                profile: p,
                password: pwd,
                report: { [weak playback] key in playback?.setStatus(key.t) }
            )
            var updated = result.profile
            updated.lastConnectedAt = Date()
            serverStore.upsert(updated)
            session.sign(in: result.musicClient)
            Haptics.success()
        } catch {
            // 静默失败：用户进入 LoginFlowView 手动处理
            playback.setStatus("自动登录失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    /// 处理 Siri / 快捷指令留下的待导航动作。
    private func handlePendingShortcutAction() {
        guard let raw = UserDefaults.standard.string(forKey: SynoMusicShortcutAction.pendingKey),
              let action = SynoMusicShortcutAction(rawValue: raw) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: SynoMusicShortcutAction.pendingKey)
        openShortcutAction(action)
    }

    /// 处理小组件和外部 URL 的深链。
    private func handleDeepLink(_ url: URL) {
        let target = url.host ?? url.pathComponents.dropFirst().first
        switch target {
        case "smart-mixes":
            openShortcutAction(.smartMixes)
        case "downloads":
            openShortcutAction(.downloads)
        case "widgets":
            navigation.openWidgets()
        case "plex-auth":
            navigation.selectedTab = .settings
            NotificationCenter.default.post(name: .plexAuthReturned, object: nil)
        default:
            break
        }
    }

    /// 根据动作切换到对应页面。
    private func openShortcutAction(_ action: SynoMusicShortcutAction) {
        switch action {
        case .smartMixes:
            navigation.openSmartMixes()
        case .downloads:
            navigation.openDownloads()
        }
    }
}

/// App 内部通知名集合。
extension Notification.Name {
    static let plexAuthReturned = Notification.Name("synomusic.plexAuthReturned")
}

/// 顶部状态条：从顶部滑入，可点关闭。
private struct StatusToast: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: Metrics.s) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.white)
                Text(message)
                    .font(.nocCaption)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.m)
            .padding(.vertical, Metrics.s + 2)
            .background(Color.black.opacity(0.78), in: Capsule())
            .padding(.horizontal, Metrics.m)
            .padding(.top, Metrics.s)
            Spacer()
        }
    }
}
