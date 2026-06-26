import SwiftUI
import StoreKit
import UIKit

/// 设置：服务器、音质、下载、关于。
struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var lm: LanguageManager
    @EnvironmentObject private var playbackSettings: PlaybackSettings
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var cloudSync: CloudSyncStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var serverInfo: [String: String] = [:]
    @State private var editingProfile: ServerProfile?
    @State private var pendingDelete: ServerProfile?
    @State private var paywallFeature: PremiumFeature?
    @State private var selectedIconName: String? = UIApplication.shared.alternateIconName
    @State private var isChangingIcon: Bool = false
    @State private var switchingProfileID: UUID?
    @State private var refreshingQuickConnectID: UUID?

    var body: some View {
        Form {
            currentServerSection
            serversSection
            appIconSection
            themeSection
            languageSection
            qualitySection
            cacheSection
            othersSection
            purchaseSection
            cloudSyncSection
            aboutSection
        }
        .tint(theme.current.accent(in: colorScheme))
        .id("settings-\(theme.currentID)-\(theme.appearance.rawValue)")
        .navigationTitle("设置".t)
        .task { await loadServerInfo() }
        .sheet(item: $editingProfile) { profile in
            ServerEditorView(profile: profile)
                .presentationDetents([.large])
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(feature: feature)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "删除服务器".t,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("删除".t, role: .destructive) {
                if let p = pendingDelete {
                    if session.client?.profile.id == p.id {
                        Task { await signOut() }
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        serverStore.remove(p)
                    }
                }
                pendingDelete = nil
            }
            Button("取消".t, role: .cancel) { pendingDelete = nil }
        } message: {
            if let p = pendingDelete {
                Text("将移除「\(p.name)」与该服务器保存的密码。该操作不可撤销。".t)
            }
        }
    }

    // MARK: 当前会话

    private var currentServerSection: some View {
        Section("当前会话".t) {
            if let active = session.client?.profile {
                infoRow("名称".t, active.name)
                if active.isQuickConnect {
                    infoRow("QuickConnect", active.quickConnectID)
                    quickConnectAddressRow(for: active)
                } else {
                    infoRow("地址".t, active.displayURL)
                }
                infoRow("用户".t, active.username)
                if let v = serverInfo["version_string"] {
                    infoRow("Audio Station", v)
                }
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: { Text("退出登录".t) }
            } else {
                Text("未登录".t).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 服务器列表（收货地址风格）

    private var serversSection: some View {
        Section {
            if serverStore.profiles.isEmpty {
                Text("还没有添加任何服务器。".t)
                    .foregroundStyle(.secondary)
                    .font(.nocCaption)
            } else {
                ForEach(serverStore.profiles) { p in
                    ServerRowItem(
                        profile: p,
                        isDefault: p.id == serverStore.activeProfileID,
                        isCurrentSession: p.id == session.client?.profile.id,
                        isSwitching: p.id == switchingProfileID,
                        onTap: { Task { await switchSession(to: p) } },
                        onEdit: { editingProfile = p }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = p
                        } label: { Label("删除".t, systemImage: "trash") }
                        Button { editingProfile = p } label: { Label("编辑".t, systemImage: "pencil") }
                            .tint(.blue)
                    }
                }
            }
            Button {
                startAddingServer()
            } label: {
                Label("添加服务器".t, systemImage: "plus")
            }
        } header: {
            Text("服务器".t)
        } footer: {
            Text(serverSectionFooter)
        }
    }

    private var themeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("强调色".t)
                    .font(.nocLabel)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(ThemeManager.palettes) { palette in
                            Button {
                                Haptics.tap()
                                theme.currentID = palette.id
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(palette.gradient)
                                        .frame(width: 44, height: 44)
                                    if theme.currentID == palette.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.headline)
                                    }
                                }
                                .overlay(
                                    Circle()
                                        .stroke(theme.currentID == palette.id ? Color.primary.opacity(0.4) : .clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Picker("外观".t, selection: $theme.appearance) {
                    ForEach(AppearancePreference.allCases) { a in
                        Text(a.title.t).tag(a)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("外观".t)
        } footer: {
            Text("强调色与 Light/Dark 偏好；保存到本地。".t)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: $lm.current) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.localizedTitle).tag(lang)
                }
            } label: {
                Label("语言".t, systemImage: "character.bubble")
            }
        } header: {
            Text("语言".t)
        }
    }

    private var appIconSection: some View {
        Section {
            if UIApplication.shared.supportsAlternateIcons {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AppIconChoice.all) { choice in
                            Button {
                                handleAppIconTap(choice)
                            } label: {
                                AppIconChoiceView(
                                    choice: choice,
                                    isSelected: selectedIconName == choice.alternateName,
                                    isLocked: !purchase.canUse(.appIcon) && selectedIconName != choice.alternateName
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isChangingIcon)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("当前设备不支持切换 App 图标".t)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("App 图标".t)
        } footer: {
            Text(purchase.canUse(.appIcon) ? "选择后系统会立即替换主屏幕图标。".t : "免费版暂不支持更换 App 图标。".t)
        }
    }

    private var qualitySection: some View {
        Section {
            Picker("流式音质".t, selection: $playback.quality) {
                ForEach(AudioQuality.allCases) { q in
                    Text(q.titleKey.t).tag(q)
                }
            }
        } header: {
            Text("音质".t)
        } footer: {
            Text("原始音质直接传输源文件（FLAC/WAV 等）。低带宽下选择压缩可降低卡顿概率。".t)
        }
    }

    private var cacheSection: some View {
        Section("下载与缓存".t) {
            if purchase.canUse(.songDownloads) {
                NavigationLink(value: SettingsRoute.downloads) {
                    HStack {
                        Label("已下载歌曲".t, systemImage: "arrow.down.circle")
                        Spacer()
                        Text("管理".t).foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    showPaywall(for: .songDownloads)
                } label: {
                    HStack {
                        Label("已下载歌曲".t, systemImage: "arrow.down.circle")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var othersSection: some View {
        Section {
            if purchase.canUse(.backgroundPlayback) {
                Toggle(isOn: $playbackSettings.backgroundPlaybackEnabled) {
                    Label("后台播放".t, systemImage: "play.circle")
                }
            } else {
                Button {
                    showPaywall(for: .backgroundPlayback)
                } label: {
                    HStack {
                        Label("后台播放".t, systemImage: "play.circle")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            fixedPlaybackFeatureRow("锁屏控制".t, systemImage: "lock.open")
            fixedPlaybackFeatureRow("AirPlay".t, systemImage: "airplayaudio")
        } header: {
            Text("播放".t)
        } footer: {
            Text("锁屏控制与 AirPlay 始终启用，避免系统播放路由与锁屏卡片状态不一致。关闭「后台播放」后，App 进入后台会自动暂停。".t)
        }
    }

    private var purchaseSection: some View {
        Section {
            if purchase.hasFullAccess {
                Label("完整功能已解锁".t, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    showPaywall(for: .allAccess)
                } label: {
                    HStack {
                        Label("解锁完整功能".t, systemImage: "sparkles")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Button {
                Task { await purchase.restorePurchases() }
            } label: {
                Label("已经购买？恢复购买".t, systemImage: "arrow.clockwise.circle")
            }
            Button {
                Task { await purchase.redeemOfferCode() }
            } label: {
                Label("App 兑换".t, systemImage: "giftcard")
            }
            if let message = purchase.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("完整功能".t)
        } footer: {
            Text("订阅与终身版由 App Store 处理；订阅试用需在 App Store Connect 中配置。".t)
        }
    }

    private var cloudSyncSection: some View {
        Section {
            Toggle(isOn: cloudSyncBinding) {
                Label("iCloud 云同步配置".t, systemImage: "icloud")
            }
            if cloudSync.isEnabled {
                Button {
                    cloudSync.pushLocalSnapshotIfNeeded()
                } label: {
                    Label("立即同步配置".t, systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if let message = cloudSync.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("iCloud".t)
        } footer: {
            Text("仅同步服务器地址、用户名和本地歌单；密码仍保存在本机 Keychain。".t)
        }
    }

    private var aboutSection: some View {
        Section("关于".t) {
            infoRow("版本".t, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            Button {
                Haptics.tap()
                requestReview()
            } label: {
                Label("给个好评".t, systemImage: "star.bubble.fill")
            }
            ShareLink(item: shareMessage) {
                Label("分享好友".t, systemImage: "square.and.arrow.up")
            }
            Text("SynoMusic 是一个非官方的 Audio Station 客户端。Synology 商标与 Audio Station 名称归群晖科技所有。".t)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var serverSectionFooter: String {
        if purchase.canUse(.serverProfiles) {
            return "点击行设为默认；下次启动 App 会用默认服务器自动登录。点 ⓘ 编辑配置；左滑删除。".t
        }
        return "免费版最多保存 1 个服务器配置；解锁后可添加多个服务器。".t
    }

    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: { cloudSync.isEnabled },
            set: { enabled in
                if enabled, !purchase.canUse(.iCloudSync) {
                    showPaywall(for: .iCloudSync)
                    return
                }
                cloudSync.setEnabled(enabled)
            }
        )
    }

    private var shareMessage: String {
        "我正在用 SynoMusic 连接自己的 Audio Station 音乐库。".t
    }

    /// 形如 "字段 ······ 值" 的行。
    @ViewBuilder
    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    /// 展示 QuickConnect 设备地址，支持复制和手动刷新。
    private func quickConnectAddressRow(for profile: ServerProfile) -> some View {
        let address = profile.resolvedDisplayURL == "未获取" ? "未获取".t : profile.resolvedDisplayURL
        let isRefreshing = refreshingQuickConnectID == profile.id

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                copyDeviceAddress(address)
            } label: {
                HStack(spacing: 12) {
                    Text("设备地址".t)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Text(address)
                        .font(.nocCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(address == "未获取".t ? Color.secondary.opacity(0.55) : theme.current.accent(in: colorScheme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(address == "未获取".t)

            Button {
                Task { await refreshQuickConnectAddress(for: profile) }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    Text("更新设备地址".t)
                        .font(.nocCaption.weight(.semibold))
                }
                .foregroundStyle(theme.current.accent(in: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(theme.current.accent(in: colorScheme).opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(refreshingQuickConnectID != nil)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    /// 复制设备地址到剪贴板并给出轻量反馈。
    private func copyDeviceAddress(_ address: String) {
        guard !address.isEmpty, address != "未获取".t else { return }
        UIPasteboard.general.string = address
        playback.setStatus("已复制".t)
        Haptics.tap()
    }

    /// 加载当前 Audio Station 服务信息，用于设置页展示会话状态。
    private func loadServerInfo() async {
        guard let api = session.client?.audioStation else { return }
        if let info = try? await api.getInfo() { self.serverInfo = info }
    }

    /// 展示不可关闭的播放能力行，右侧固定为开启状态。
    private func fixedPlaybackFeatureRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("始终开启".t)
                .font(.nocLabel)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// 打开添加服务器编辑器，免费版超过数量限制时改为展示付费墙。
    private func startAddingServer() {
        guard purchase.canUse(.serverProfiles) || serverStore.profiles.count < PurchaseLimits.maxFreeServerProfiles else {
            showPaywall(for: .serverProfiles)
            return
        }
        editingProfile = ServerProfile(host: "", username: "")
    }

    /// 点击图标时先检查购买状态，再执行系统图标切换。
    private func handleAppIconTap(_ choice: AppIconChoice) {
        guard purchase.canUse(.appIcon) || selectedIconName == choice.alternateName else {
            showPaywall(for: .appIcon)
            return
        }
        applyAppIcon(choice)
    }

    /// 统一打开付费墙，减少各入口的状态赋值重复。
    private func showPaywall(for feature: PremiumFeature) {
        Haptics.tap()
        paywallFeature = feature
    }

    /// 调用系统好评弹窗。
    private func requestReview() {
        guard let scene = activeWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
    }

    /// 当前前台窗口场景，用于系统好评弹窗。
    private var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    /// 停止播放并退出当前服务器会话。
    private func signOut() async {
        playback.stop()
        await session.signOut()
    }

    /// 手动刷新 QuickConnect 解析出的真实设备地址，并在当前会话可用时重新连接。
    private func refreshQuickConnectAddress(for profile: ServerProfile) async {
        guard refreshingQuickConnectID == nil else { return }
        refreshingQuickConnectID = profile.id
        defer { refreshingQuickConnectID = nil }
        do {
            let refreshed = try await SynologyLoginHelper.refreshQuickConnectAddress(
                for: profile,
                report: { [weak playback] key in playback?.setStatus(key.t) }
            )
            serverStore.upsert(refreshed)
            if profile.id == session.client?.profile.id,
               let pwd = serverStore.password(for: profile), !pwd.isEmpty {
                let result = try await SynologyLoginHelper.login(profile: refreshed, password: pwd)
                var updated = result.profile
                updated.lastConnectedAt = Date()
                serverStore.upsert(updated)
                serverStore.setActive(updated)
                let oldClient = session.client
                session.sign(in: result.client)
                await oldClient?.logout()
            }
            playback.setStatus("设备地址已更新".t)
            Haptics.success()
        } catch {
            playback.setStatus("更新设备地址失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 切换系统 App 图标，并同步设置页的选中状态。
    private func applyAppIcon(_ choice: AppIconChoice) {
        guard selectedIconName != choice.alternateName else { return }
        Haptics.tap()
        isChangingIcon = true
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            Task { @MainActor in
                isChangingIcon = false
                if let error {
                    playback.setStatus("图标切换失败".t + "：\(error.localizedDescription)")
                    Haptics.warning()
                } else {
                    selectedIconName = choice.alternateName
                    playback.setStatus("图标已切换".t)
                    Haptics.success()
                }
            }
        }
    }

    /// 切换会话到指定档案：设为默认 + 用 Keychain 密码 silent login。
    /// 切换成功后 RootView 的 `.id(client.profile.id)` 会重建 MainShellView，
    /// 各页面的缓存数据（专辑/艺术家/歌曲列表）随之失效并重新加载。
    private func switchSession(to p: ServerProfile) async {
        guard switchingProfileID == nil else { return }
        Haptics.tap()
        serverStore.setActive(p)
        // 已经是当前会话则只更新默认标记
        if p.id == session.client?.profile.id { return }
        guard let pwd = serverStore.password(for: p), !pwd.isEmpty else {
            playback.setStatus("「\(p.name)」" + "未保存密码，请在登录页输入".t)
            navigation.openLogin(for: p)
            return
        }
        switchingProfileID = p.id
        defer { switchingProfileID = nil }
        do {
            let result = try await SynologyLoginHelper.login(
                profile: p,
                password: pwd,
                report: { [weak playback] key in playback?.setStatus(key.t) }
            )
            var updated = result.profile
            updated.lastConnectedAt = Date()
            serverStore.upsert(updated)
            serverStore.setActive(updated)
            let oldClient = session.client
            playback.stop()
            session.sign(in: result.client)
            await oldClient?.logout()
            playback.setStatus("已切换到".t + "「\(p.name)」")
            Haptics.success()
        } catch {
            playback.setStatus("切换失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
        }
    }
}

/// 可切换的 App 图标选项；nil 表示主图标。
private struct AppIconChoice: Identifiable {
    let alternateName: String?
    let assetName: String
    let previewName: String
    let title: String

    var id: String { alternateName ?? "AppIcon" }

    static let all: [AppIconChoice] = [
        AppIconChoice(alternateName: nil, assetName: "AppIcon", previewName: "AppIconPreviewDefault", title: "默认"),
        AppIconChoice(alternateName: "AppIconAlt01", assetName: "AppIconAlt01", previewName: "AppIconPreview01", title: "图标 1"),
        AppIconChoice(alternateName: "AppIconAlt02", assetName: "AppIconAlt02", previewName: "AppIconPreview02", title: "图标 2"),
        AppIconChoice(alternateName: "AppIconAlt03", assetName: "AppIconAlt03", previewName: "AppIconPreview03", title: "图标 3"),
        AppIconChoice(alternateName: "AppIconAlt04", assetName: "AppIconAlt04", previewName: "AppIconPreview04", title: "图标 4"),
        AppIconChoice(alternateName: "AppIconAlt05", assetName: "AppIconAlt05", previewName: "AppIconPreview05", title: "图标 5"),
        AppIconChoice(alternateName: "AppIconAlt06", assetName: "AppIconAlt06", previewName: "AppIconPreview06", title: "图标 6"),
        AppIconChoice(alternateName: "AppIconAlt07", assetName: "AppIconAlt07", previewName: "AppIconPreview07", title: "图标 7"),
        AppIconChoice(alternateName: "AppIconAlt08", assetName: "AppIconAlt08", previewName: "AppIconPreview08", title: "图标 8"),
        AppIconChoice(alternateName: "AppIconAlt09", assetName: "AppIconAlt09", previewName: "AppIconPreview09", title: "图标 9"),
        AppIconChoice(alternateName: "AppIconAlt10", assetName: "AppIconAlt10", previewName: "AppIconPreview10", title: "图标 10")
    ]
}

/// 设置页里的图标选择器单元。
private struct AppIconChoiceView: View {
    let choice: AppIconChoice
    let isSelected: Bool
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            iconPreview
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white, Theme.accent)
                            .offset(x: 5, y: 5)
                    }
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            Text(choice.title.t)
                .font(.nocLabel)
                .foregroundStyle(isSelected ? Theme.accent : .secondary)
        }
        .frame(width: 76)
        .contentShape(Rectangle())
    }

    /// 图标预览；系统 AppIconSet 不作为普通图片暴露，因此使用专门的预览 imageset。
    private var iconPreview: some View {
        Group {
            if let image = UIImage(named: choice.previewName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Theme.accent.opacity(0.95), Color.pink.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

/// 服务器行：仿"收货地址"风格 —— 行 tap = 设默认，✓ 表示默认，ⓘ = 编辑。
private struct ServerRowItem: View {
    let profile: ServerProfile
    let isDefault: Bool
    let isCurrentSession: Bool
    let isSwitching: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            onTap()
        }) {
            HStack(spacing: Metrics.s + 4) {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isDefault ? Theme.accent : Color.secondary.opacity(0.6))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.nocBody.weight(.semibold))
                            .foregroundStyle(.primary)
                        if profile.isQuickConnect {
                            tagPill("QC", color: .blue)
                        }
                        if isCurrentSession {
                            tagPill("已登录".t, color: .green)
                        }
                        if isDefault {
                            tagPill("默认".t, color: Theme.accent)
                        }
                    }
                    Text(serverSubtitle)
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSwitching {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    Button(action: { Haptics.tap(); onEdit() }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("编辑服务器".t)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSwitching)
    }

    /// 备注名为空时回退到主机；保证列表行不出现空白条目。
    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? profile.host : trimmed
    }

    /// 服务器副标题：QC 档案同时展示 ID 与已解析设备地址。
    private var serverSubtitle: String {
        if profile.isQuickConnect {
            let resolved = profile.resolvedDisplayURL == "未获取" ? "未获取".t : profile.resolvedDisplayURL
            return "\(profile.username) @ QC: \(profile.quickConnectID) · \(resolved)"
        }
        return "\(profile.username) @ \(profile.displayURL)"
    }

    private func tagPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 已下载歌曲管理。
struct DownloadsListView: View {
    @EnvironmentObject private var downloads: DownloadManager
    var body: some View {
        Group {
            if downloads.entries.isEmpty {
                EmptyStateView(systemImage: "arrow.down.circle", title: "尚无下载".t, message: "在歌曲长按菜单选择「下载」。".t)
            } else {
                List {
                    Section {
                        HStack {
                            Text("已用空间".t)
                            Spacer()
                            Text(downloads.totalBytes.humanSize)
                                .foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) { downloads.clearAll() } label: {
                            Text("清空全部下载".t)
                        }
                    }
                    Section("歌曲".t) {
                        ForEach(downloads.entries) { e in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(e.title).font(.nocBody)
                                    Spacer()
                                    statusLabel(e.status)
                                }
                                HStack {
                                    Text(e.artist ?? "").font(.nocLabel).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(e.size.humanSize).font(.nocLabel).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { downloads.remove(songID: e.id) } label: { Label("删除".t, systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("下载管理".t)
    }

    /// 下载状态标签，帮助用户区分下载中、失败和已完成。
    @ViewBuilder
    private func statusLabel(_ status: DownloadStatus) -> some View {
        switch status {
        case .completed:
            Text("已下载".t)
                .font(.nocLabel)
                .foregroundStyle(.green)
        case .downloading, .pending:
            Text("下载中".t)
                .font(.nocLabel)
                .foregroundStyle(Theme.accent)
        case .failed:
            Text("下载失败".t)
                .font(.nocLabel)
                .foregroundStyle(.red)
        }
    }
}
