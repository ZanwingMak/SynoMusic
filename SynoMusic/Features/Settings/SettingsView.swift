import SwiftUI
import StoreKit
import UIKit
import UniformTypeIdentifiers
import WidgetKit

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
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.colorScheme) private var colorScheme

    @State private var serverInfo: [String: String] = [:]
    @State private var editingProfile: ServerProfile?
    @State private var pendingDelete: ServerProfile?
    @State private var paywallFeature: PremiumFeature?
    @State private var selectedIconName: String? = UIApplication.shared.alternateIconName
    @State private var isChangingIcon: Bool = false
    @State private var switchingProfileID: UUID?
    @State private var refreshingQuickConnectID: UUID?
    @State private var isSyncingCloud: Bool = false
    @State private var isShowingServerImport = false
    @State private var isShowingServerExport = false
    @State private var serverExportDocument = ServerConfigurationExportDocument()

    /// 当前设置页主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    var body: some View {
        Form {
            currentServerSection
            serversSection
            appIconSection
            themeSection
            languageSection
            qualitySection
            playbackEnhancementSection
            cacheSection
            othersSection
            purchaseSection
            widgetSection
            cloudSyncSection
            aboutSection
        }
        .tint(theme.current.accent(in: colorScheme))
        .reserveMiniPlayer(visible: playback.currentSong != nil)
        .id("settings-\(theme.currentID)-\(theme.appearance.rawValue)")
        .navigationTitle("设置".t)
        .onAppear { handleAddServerRequest() }
        .onChange(of: navigation.addServerRequestID) { _, _ in handleAddServerRequest() }
        .task { await loadServerInfo() }
        .task(id: cloudSync.isEnabled) {
            if cloudSync.isEnabled {
                await cloudSync.refreshCloudAvailability()
            }
        }
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
                    if session.musicClient?.profile.id == p.id {
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
                Text(String(format: "将移除「%@」与该服务器保存的密码。该操作不可撤销。".t, p.name))
            }
        }
        .fileImporter(
            isPresented: $isShowingServerImport,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleServerConfigurationImport(result)
        }
        .fileExporter(
            isPresented: $isShowingServerExport,
            document: serverExportDocument,
            contentType: .json,
            defaultFilename: "SynoMusic-Servers"
        ) { result in
            handleServerConfigurationExportCompletion(result)
        }
    }

    // MARK: 当前会话

    private var currentServerSection: some View {
        Section("当前会话".t) {
            if reviewMode.isEnabled {
                infoRow("名称".t, "测试账号".t)
                infoRow("用户".t, AppReviewMode.reviewUsername)
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: { Text("退出登录".t) }
            } else if let active = session.musicClient?.profile {
                infoRow("音乐源".t, active.providerType.titleKey.t)
                infoRow("名称".t, active.name)
                if active.providerType == .synologyAudioStation, active.isQuickConnect {
                    infoRow("QuickConnect", active.quickConnectID)
                    quickConnectAddressRow(for: active)
                } else {
                    infoRow("地址".t, active.displayURL)
                }
                infoRow("用户".t, active.username)
                if active.providerType == .synologyAudioStation, let v = serverInfo["version_string"] {
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
                        isCurrentSession: p.id == session.musicClient?.profile.id,
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
                            .tint(theme.current.accent(in: colorScheme))
                    }
                }
            }
            Button {
                startAddingServer()
            } label: {
                themedLabel("添加服务器".t, systemImage: "plus")
            }
            serverConfigurationTransferRows
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

    /// 服务器配置导入导出入口；完整功能解锁后可用。
    @ViewBuilder
    private var serverConfigurationTransferRows: some View {
        if purchase.canUse(.serverConfigurationTransfer) {
            Button {
                beginServerConfigurationExport()
            } label: {
                themedLabel("导出服务器配置".t, systemImage: "square.and.arrow.up")
            }
            Button {
                Haptics.tap()
                isShowingServerImport = true
            } label: {
                themedLabel("导入服务器配置".t, systemImage: "square.and.arrow.down")
            }
        } else {
            Button {
                showPaywall(for: .serverConfigurationTransfer)
            } label: {
                HStack {
                    themedLabel("导入/导出服务器配置".t, systemImage: "arrow.up.arrow.down.square")
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: $lm.current) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.localizedTitle).tag(lang)
                }
            } label: {
                themedLabel("语言".t, systemImage: "character.bubble")
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
                                    isLocked: choice.alternateName != nil
                                        && !purchase.canUse(.appIcon)
                                        && selectedIconName != choice.alternateName
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
            Text(purchase.canUse(.appIcon) ? "选择后系统会立即替换主屏幕图标。".t : "默认图标可免费恢复；备用图标需要解锁完整功能。".t)
        }
    }

    private var qualitySection: some View {
        Section {
            Picker(selection: $playback.quality) {
                ForEach(AudioQuality.allCases) { q in
                    Text(q.titleKey.t).tag(q)
                }
            } label: {
                themedLabel("流式音质".t, systemImage: "waveform")
            }
        } header: {
            Text("音质".t)
        } footer: {
            Text("原始音质直接传输源文件（FLAC/WAV 等）。低带宽下选择压缩可降低卡顿概率。".t)
        }
    }

    private var playbackEnhancementSection: some View {
        Section {
            if purchase.canUse(.playbackEnhancements) {
                Picker(selection: $playbackSettings.playerArtworkStyle) {
                    ForEach(PlayerArtworkStyle.allCases) { style in
                        Text(style.titleKey.t).tag(style)
                    }
                } label: {
                    themedLabel("播放器样式".t, systemImage: "rectangle.stack")
                }
                Toggle(isOn: $playbackSettings.crossfadeEnabled) {
                    themedLabel("歌曲淡入淡出".t, systemImage: "waveform")
                }
                if playbackSettings.crossfadeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("淡入淡出时长".t)
                            Spacer()
                            Text(String(format: "%.0f s", playbackSettings.crossfadeDuration))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $playbackSettings.crossfadeDuration, in: 1...8, step: 1)
                    }
                }
                Picker(selection: $playbackSettings.equalizerPreset) {
                    ForEach(EqualizerPreset.allCases) { preset in
                        Text(preset.titleKey.t).tag(preset)
                    }
                } label: {
                    themedLabel("均衡器预设".t, systemImage: "slider.horizontal.3")
                }
            } else {
                Button {
                    showPaywall(for: .playbackEnhancements)
                } label: {
                    HStack {
                        themedLabel("播放增强".t, systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("播放增强".t)
        } footer: {
            Text("黑胶播放器、淡入淡出和均衡器预设属于完整功能。".t)
        }
    }

    @ViewBuilder
    private var cacheSection: some View {
        if shouldShowServerDependentEntries {
            Section("下载与缓存".t) {
                if purchase.canUse(.songDownloads) {
                    NavigationLink(value: SettingsRoute.downloads) {
                        HStack {
                            themedLabel("已下载歌曲".t, systemImage: "arrow.down.circle")
                            Spacer()
                            Text("管理".t).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        showPaywall(for: .songDownloads)
                    } label: {
                        HStack {
                            themedLabel("已下载歌曲".t, systemImage: "arrow.down.circle")
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if purchase.canUse(.localImport) {
                    NavigationLink(value: SettingsRoute.localImports) {
                        localImportRow(isLocked: false)
                    }
                } else {
                    Button {
                        showPaywall(for: .localImport)
                    } label: {
                        localImportRow(isLocked: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 判断是否显示依赖真实服务器会话的下载与导入入口。
    private var shouldShowServerDependentEntries: Bool {
        session.musicClient != nil && !reviewMode.isEnabled
    }

    /// 绘制本地音乐导入入口，锁定时保留设置行样式并改为弹付费墙。
    private func localImportRow(isLocked: Bool) -> some View {
        HStack {
            themedLabel("本地音乐导入".t, systemImage: "square.and.arrow.down")
            Spacer()
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var othersSection: some View {
        Section {
            if purchase.canUse(.backgroundPlayback) {
                Toggle(isOn: $playbackSettings.backgroundPlaybackEnabled) {
                    themedLabel("后台播放".t, systemImage: "play.circle")
                }
            } else {
                Button {
                    showPaywall(for: .backgroundPlayback)
                } label: {
                    HStack {
                        themedLabel("后台播放".t, systemImage: "play.circle")
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
                Button {
                    showPaywall(for: .allAccess)
                } label: {
                    HStack {
                        PremiumAccessBadge(showsText: true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showPaywall(for: .allAccess)
                } label: {
                    HStack {
                        themedLabel("解锁完整功能".t, systemImage: "sparkles")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            Button {
                playback.setStatus("正在恢复购买…".t)
                Task {
                    await purchase.restorePurchases()
                    if let message = purchase.statusMessage {
                        playback.setStatus(message)
                    }
                }
            } label: {
                themedLabel("已经购买？恢复购买".t, systemImage: "arrow.clockwise.circle")
            }
            Button {
                playback.setStatus("正在打开兑换页面…".t)
                Task {
                    await purchase.redeemOfferCode()
                    if let message = purchase.statusMessage {
                        playback.setStatus(message)
                    }
                }
            } label: {
                themedLabel("App 兑换".t, systemImage: "giftcard")
            }
            if let message = purchase.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("完整功能".t)
        } footer: {
            Text("订阅与终身解锁由 App Store 处理；订阅试用需在 App Store Connect 中配置。".t)
        }
    }

    private var widgetSection: some View {
        Section {
            if purchase.canUse(.systemIntegrations) {
                NavigationLink(value: SettingsRoute.widgets) {
                    widgetManagerRow(isLocked: false)
                }
            } else {
                Button {
                    showPaywall(for: .systemIntegrations)
                } label: {
                    widgetManagerRow(isLocked: true)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Siri 与小组件".t)
        } footer: {
            Text("管理桌面小组件入口、快捷指令和深链动作。".t)
        }
    }

    /// 绘制小组件管理入口行；锁定时保持设置列表样式但不触发导航。
    private func widgetManagerRow(isLocked: Bool) -> some View {
        HStack {
            themedLabel("小组件管理".t, systemImage: "rectangle.3.group")
            Spacer()
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var cloudSyncSection: some View {
        Section {
            Toggle(isOn: cloudSyncBinding) {
                themedLabel("iCloud 云同步配置".t, systemImage: "icloud")
            }
            if cloudSync.isEnabled {
                cloudSyncStatusRows
                Toggle(isOn: credentialsSyncBinding) {
                    themedLabel("同步登录凭据".t, systemImage: "key.fill")
                }
                Button {
                    Task { await syncCloudNow() }
                } label: {
                    Label {
                        Text(isSyncingCloud ? "正在同步 iCloud".t : "立即同步配置".t)
                            .foregroundStyle(accentColor)
                    } icon: {
                        if isSyncingCloud {
                            ProgressView()
                                .controlSize(.small)
                                .tint(accentColor)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(accentColor)
                        }
                    }
                }
                .disabled(isSyncingCloud)
            }
            if let message = cloudSync.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("iCloud".t)
        } footer: {
            Text("同步服务器配置、歌单、播放偏好、播客订阅、歌曲资料和历史记录；登录凭据可选择通过 iCloud Keychain 同步。".t)
        }
    }

    /// iCloud 同步状态行：最近同步时间与云端是否已有可同步数据。
    private var cloudSyncStatusRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            syncStatusLine(
                title: "最近同步".t,
                value: cloudSync.lastSyncAt.map(formatSyncDate) ?? "尚未同步".t,
                systemImage: "clock"
            )
            syncStatusLine(
                title: "云端数据".t,
                value: cloudDataStatusText,
                systemImage: cloudSync.hasCloudData ? "checkmark.icloud" : "icloud.slash"
            )
        }
        .padding(.vertical, 4)
    }

    /// 云端数据状态文案。
    private var cloudDataStatusText: String {
        guard cloudSync.hasCloudData else { return "暂无可同步数据".t }
        if let date = cloudSync.cloudDataUpdatedAt {
            return String(format: "可同步，更新于 %@".t, formatSyncDate(date))
        }
        return "有可同步数据".t
    }

    /// 设置页状态行样式。
    private func syncStatusLine(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(accentColor)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// 按用户当前区域格式化同步时间。
    private func formatSyncDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var aboutSection: some View {
        Section("关于".t) {
            HStack {
                themedLabel("版本".t, systemImage: "number.circle")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                requestReview()
            } label: {
                themedLabel("给个好评".t, systemImage: "star.bubble.fill")
            }
            ShareLink(item: shareMessage) {
                themedLabel("分享好友".t, systemImage: "square.and.arrow.up")
            }
            Link(destination: officialWebsiteURL) {
                themedLabel("官网".t, systemImage: "safari")
            }
            Link(destination: feedbackURL) {
                themedLabel("问题反馈".t, systemImage: "exclamationmark.bubble")
            }
            Link(destination: termsURL) {
                themedLabel("服务条款 (EULA)".t, systemImage: "doc.text")
            }
            Link(destination: privacyURL) {
                themedLabel("隐私政策".t, systemImage: "hand.raised")
            }
            Text("SynoMusic 是一个非官方的自托管音乐客户端，支持连接你授权的音乐服务器和本地文件。Synology、Plex、Jellyfin、Emby 等名称归各自所有。".t)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var serverSectionFooter: String {
        if purchase.canUse(.serverProfiles) {
            return "点击行设为默认；下次启动 App 会用默认服务器自动登录。点 ⓘ 编辑配置；左滑删除。导出的配置不包含密码；导入后请重新输入密码或重新授权。".t
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

    private var credentialsSyncBinding: Binding<Bool> {
        Binding(
            get: { cloudSync.credentialsSyncEnabled },
            set: { enabled in
                guard cloudSync.isEnabled else { return }
                cloudSync.setCredentialsSyncEnabled(enabled)
            }
        )
    }

    private var shareMessage: String {
        "我正在用 SynoMusic 连接自己的自托管音乐库。".t
    }

    /// 商业版官网地址。
    private var officialWebsiteURL: URL {
        URL(string: "https://zanwingmak.github.io/SynoMusic-OpenSource/")!
    }

    /// 公开问题反馈地址。
    private var feedbackURL: URL {
        URL(string: "https://github.com/ZanwingMak/SynoMusic-OpenSource/issues")!
    }

    /// 服务条款地址。
    private var termsURL: URL {
        URL(string: "https://zanwingmak.github.io/SynoMusic-OpenSource/terms.html")!
    }

    /// 隐私政策地址。
    private var privacyURL: URL {
        URL(string: "https://zanwingmak.github.io/SynoMusic-OpenSource/privacy.html")!
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
            themedLabel(title, systemImage: systemImage)
            Spacer()
            Text("始终开启".t)
                .font(.nocLabel)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// 构建跟随主题强调色的设置行标签。
    private func themedLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(accentColor)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(accentColor)
        }
    }

    /// 打开添加服务器编辑器，免费版超过数量限制时改为展示付费墙。
    private func startAddingServer() {
        guard purchase.canUse(.serverProfiles) || serverStore.profiles.count < PurchaseLimits.maxFreeServerProfiles else {
            showPaywall(for: .serverProfiles)
            return
        }
        editingProfile = ServerProfile(host: "", username: "")
    }

    /// 响应其它页面发来的添加服务器请求，并立即消费该请求。
    private func handleAddServerRequest() {
        guard navigation.addServerRequestID != nil else { return }
        navigation.consumeAddServerRequest()
        startAddingServer()
    }

    /// 点击图标时允许免费恢复默认图标，备用图标再检查购买状态。
    private func handleAppIconTap(_ choice: AppIconChoice) {
        guard choice.alternateName == nil || purchase.canUse(.appIcon) || selectedIconName == choice.alternateName else {
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

    /// 手动触发 iCloud 同步，并保留短暂 loading 反馈。
    private func syncCloudNow() async {
        guard !isSyncingCloud else { return }
        isSyncingCloud = true
        defer { isSyncingCloud = false }
        await cloudSync.syncNow()
        Haptics.success()
    }

    /// 准备服务器配置导出文件，并打开系统文件保存面板。
    private func beginServerConfigurationExport() {
        guard !serverStore.profiles.isEmpty else {
            playback.setStatus("暂无可导出的服务器配置。".t)
            Haptics.warning()
            return
        }
        do {
            let archive = ServerConfigurationArchive(
                version: 1,
                exportedAt: Date(),
                activeProfileID: serverStore.activeProfileID,
                profiles: serverStore.profiles
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            serverExportDocument = ServerConfigurationExportDocument(data: try encoder.encode(archive))
            Haptics.tap()
            isShowingServerExport = true
        } catch {
            playback.setStatus("服务器配置导出失败".t + "：\(error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 处理系统文件保存面板回调，给用户明确导出结果。
    private func handleServerConfigurationExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            playback.setStatus("服务器配置已导出。".t)
            Haptics.success()
        case .failure(let error):
            playback.setStatus("服务器配置导出失败".t + "：\(error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 处理服务器配置 JSON 导入结果，并合并到当前配置列表。
    private func handleServerConfigurationImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let archive = try decodeServerConfigurationArchive(from: Data(contentsOf: url))
            guard !archive.profiles.isEmpty else {
                playback.setStatus("服务器配置导入失败".t)
                Haptics.warning()
                return
            }
            archive.profiles.forEach { serverStore.upsert($0) }
            if let activeID = archive.activeProfileID,
               let active = archive.profiles.first(where: { $0.id == activeID }) {
                serverStore.setActive(active)
            }
            playback.setStatus(String(format: "已导入 %d 个服务器配置。".t, archive.profiles.count))
            Haptics.success()
        } catch {
            playback.setStatus("服务器配置导入失败".t + "：\(error.localizedDescription)")
            Haptics.warning()
        }
    }

    /// 解码服务器配置归档，兼容新旧日期编码格式。
    private func decodeServerConfigurationArchive(from data: Data) throws -> ServerConfigurationArchive {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let archive = try? isoDecoder.decode(ServerConfigurationArchive.self, from: data) {
            return archive
        }
        return try JSONDecoder().decode(ServerConfigurationArchive.self, from: data)
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
        reviewMode.deactivate()
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
        if p.id == session.musicClient?.profile.id { return }
        guard let pwd = serverStore.password(for: p), !pwd.isEmpty else {
            playback.setStatus("「\(p.name)」" + "未保存密码，请在登录页输入".t)
            navigation.openLogin(for: p)
            return
        }
        switchingProfileID = p.id
        defer { switchingProfileID = nil }
        do {
            let result = try await MusicProviderLoginHelper.login(
                profile: p,
                password: pwd,
                report: { [weak playback] key in playback?.setStatus(key.t) }
            )
            var updated = result.profile
            updated.lastConnectedAt = Date()
            serverStore.upsert(updated)
            serverStore.setActive(updated)
            let oldClient = session.musicClient
            playback.stop()
            session.sign(in: result.musicClient)
            await oldClient?.logout()
            playback.setStatus("已切换到".t + "「\(p.name)」")
            Haptics.success()
        } catch {
            playback.setStatus("切换失败".t + "：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            Haptics.warning()
        }
    }
}

/// 服务器配置导入导出的 JSON 归档；不包含 Keychain 密码。
private struct ServerConfigurationArchive: Codable {
    let version: Int
    let exportedAt: Date
    let activeProfileID: UUID?
    let profiles: [ServerProfile]
}

/// SwiftUI 文件导出用 JSON 文档。
private struct ServerConfigurationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    /// 创建空白或指定内容的导出文档。
    init(data: Data = Data()) {
        self.data = data
    }

    /// 从系统文件读取配置文档内容。
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    /// 将 JSON 数据包装成系统可保存的文件。
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let choice: AppIconChoice
    let isSelected: Bool
    let isLocked: Bool

    /// 当前设置页主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    var body: some View {
        VStack(spacing: 6) {
            iconPreview
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? accentColor : Color.clear, lineWidth: 3)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white, accentColor)
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
                .foregroundStyle(isSelected ? accentColor : .secondary)
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
                    colors: [accentColor.opacity(0.95), Color(hex: theme.current.gradientEnd).opacity(0.8)],
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
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let profile: ServerProfile
    let isDefault: Bool
    let isCurrentSession: Bool
    let isSwitching: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    /// 当前设置页主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    var body: some View {
        Button(action: {
            Haptics.tap()
            onTap()
        }) {
            HStack(spacing: Metrics.s + 4) {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isDefault ? accentColor : Color.secondary.opacity(0.6))

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayName)
                            .font(.nocBody.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        tagRow
                    }
                    Text(serverSubtitle)
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

    /// 服务器状态标签；使用短标签避免长音乐源名称挤压布局。
    private var tagRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                tagItems
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    tagPill(providerBadgeTitle, color: accentColor)
                    if profile.isQuickConnect {
                        tagPill("QC", color: .blue)
                    }
                }
                HStack(spacing: 5) {
                    if isCurrentSession {
                        tagPill("已登录".t, color: .green)
                    }
                    if isDefault {
                        tagPill("默认".t, color: accentColor)
                    }
                }
            }
        }
    }

    /// 根据服务器状态生成标签集合。
    @ViewBuilder
    private var tagItems: some View {
        tagPill(providerBadgeTitle, color: accentColor)
        if profile.isQuickConnect {
            tagPill("QC", color: .blue)
        }
        if isCurrentSession {
            tagPill("已登录".t, color: .green)
        }
        if isDefault {
            tagPill("默认".t, color: accentColor)
        }
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
        if profile.providerType == .smb {
            return profile.musicLibraryName ?? "SMB 文件夹".t
        }
        if profile.providerType == .webDAV, let path = profile.musicLibraryID, !path.isEmpty {
            return "\(profile.username) @ \(profile.displayURL)\(path)"
        }
        return "\(profile.username) @ \(profile.displayURL)"
    }

    /// 服务器音乐源的短显示名。
    private var providerBadgeTitle: String {
        switch profile.providerType {
        case .synologyAudioStation:
            return "Audio Station"
        case .plex:
            return "Plex"
        case .jellyfin:
            return "Jellyfin"
        case .emby:
            return "Emby"
        case .webDAV:
            return "WebDAV"
        case .smb:
            return "SMB"
        }
    }

    /// 绘制单个服务器状态标签。
    private func tagPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// 桌面小组件管理。
struct WidgetManagerView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var reviewMode: AppReviewMode
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    /// 根据会话状态生成小组件展示文案，未登录或审核模式不展示下载卖点。
    private var widgets: [WidgetShowcase] {
        [
            WidgetShowcase(title: "黑胶唱片", subtitle: "在桌面快速进入播放体验", icon: "record.circle", colors: [.black, Color(red: 0.35, green: 0.22, blue: 0.12)]),
            WidgetShowcase(title: "特色功能", subtitle: featureWidgetSubtitle, icon: "sparkles.rectangle.stack", colors: accentPreviewColors),
            WidgetShowcase(title: "最近播放", subtitle: "快速回到上次听到的音乐", icon: "clock.arrow.circlepath", colors: [Color(red: 0.07, green: 0.42, blue: 0.72), Color(red: 0.15, green: 0.68, blue: 0.78)])
        ]
    }

    /// 当前设置页主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    /// 小组件预览里用于主题反馈的渐变色。
    private var accentPreviewColors: [Color] {
        [accentColor, Color(hex: theme.current.gradientEnd)]
    }

    /// 返回特色小组件副标题，避免未登录或审核模式露出下载能力。
    private var featureWidgetSubtitle: String {
        session.musicClient == nil || reviewMode.isEnabled
            ? "智能歌单和小组件管理"
            : "智能歌单、下载和小组件管理"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("iOS 不允许 App 直接替换已添加的小组件；添加后请长按桌面小组件，选择「编辑小组件」切换显示内容。".t)
                        .font(.nocCaption)
                        .foregroundStyle(.secondary)
                    Button {
                        refreshWidgets()
                    } label: {
                        Label("刷新小组件".t, systemImage: "arrow.clockwise")
                            .font(.nocBody.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                ForEach(widgets) { widget in
                    WidgetShowcaseCard(widget: widget)
                }
            }
            .padding(16)
        }
        .navigationTitle("小组件管理".t)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .reserveMiniPlayer(visible: playback.currentSong != nil)
    }

    /// 刷新小组件时间线，并说明切换样式仍需要通过系统编辑入口完成。
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        playback.setStatus("已刷新小组件；如需切换样式，请长按桌面小组件并选择编辑小组件。".t)
        Haptics.success()
    }
}

/// 小组件管理页的一张展示卡。
private struct WidgetShowcaseCard: View {
    let widget: WidgetShowcase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(widget.title.t)
                        .font(.nocSection)
                    Text(widget.subtitle.t)
                        .font(.nocCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("编辑小组件切换".t, systemImage: "hand.tap")
                    .font(.nocLabel.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            WidgetPreview(widget: widget)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 小组件管理页的预览图，模拟桌面小组件排布。
private struct WidgetPreview: View {
    let widget: WidgetShowcase

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemGroupedBackground))
                .overlay(alignment: .trailing) {
                    LazyVGrid(columns: [GridItem(.fixed(52)), GridItem(.fixed(52))], spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 52, height: 52)
                        }
                    }
                    .padding(.trailing, 22)
                }
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: widget.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 154, height: 104)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: widget.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(widget.title.t)
                            .font(.nocBody.weight(.bold))
                            .foregroundStyle(.white)
                        Text("SynoMusic")
                            .font(.nocLabel)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .padding(14)
                }
                .padding(.leading, 22)
        }
        .frame(height: 150)
    }
}

/// 小组件展示数据。
private struct WidgetShowcase: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
}

/// 本地导入音乐管理。
struct LocalImportView: View {
    @EnvironmentObject private var localImports: LocalImportStore
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var remoteURL = ""
    @State private var showFileImporter = false

    /// 当前设置页主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    var body: some View {
        List {
            Section {
                TextField("粘贴音乐链接".t, text: $remoteURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button {
                    Task { await importRemoteURL() }
                } label: {
                    if localImports.isImporting {
                        Label("正在导入".t, systemImage: "hourglass")
                    } else {
                        Label("从链接下载导入".t, systemImage: "link.badge.plus")
                    }
                }
                .disabled(localImports.isImporting || remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    showFileImporter = true
                } label: {
                    Label("从文件导入".t, systemImage: "folder")
                }
                .disabled(localImports.isImporting)
                if let message = localImports.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("导入音乐".t)
            } footer: {
                Text("导入的音乐保存在本机沙盒，可离线播放，不会上传到服务器。".t)
            }

            Section("本地音乐".t) {
                if localImports.tracks.isEmpty {
                    Text("还没有导入音乐。".t)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(localImports.tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            playImportedTrack(at: index)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title)
                                        .foregroundStyle(.primary)
                                    Text(formatDuration(track.duration))
                                        .font(.nocLabel)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(accentColor)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                localImports.delete(track)
                            } label: {
                                Label("删除".t, systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("本地音乐导入".t)
        .reserveMiniPlayer(visible: playback.currentSong != nil)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
    }

    /// 从链接下载并导入音乐。
    private func importRemoteURL() async {
        await localImports.importRemote(from: remoteURL)
        if localImports.statusMessage?.hasPrefix("已导入音乐".t) == true {
            remoteURL = ""
        }
    }

    /// 处理系统文件选择器返回结果。
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await localImports.importFile(from: url) }
        case .failure(let error):
            playback.setStatus("导入失败".t + "：\(error.localizedDescription)")
        }
    }

    /// 播放本地导入音乐，并把全部导入条目作为队列。
    private func playImportedTrack(at index: Int) {
        let songs = localImports.tracks.map(\.song)
        playback.play(queue: songs, startAt: index, honoringShuffle: false, contextTitle: "本地导入".t)
    }

    /// 格式化导入音乐时长。
    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 已下载歌曲管理。
struct DownloadsListView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDownloadingQueue = false
    @State private var queueProgress: (done: Int, total: Int) = (0, 0)

    /// 当前设置页主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    var body: some View {
        Group {
            if downloads.entries.isEmpty {
                VStack(spacing: Metrics.l) {
                    EmptyStateView(systemImage: "arrow.down.circle", title: "尚无下载".t, message: "在歌曲长按菜单选择「下载」。".t)
                    queueDownloadButton
                        .padding(.horizontal, Metrics.l)
                }
            } else {
                List {
                    Section {
                        HStack {
                            Text("已用空间".t)
                            Spacer()
                            Text(downloads.totalBytes.humanSize)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("下载统计".t)
                            Spacer()
                            Text(downloadSummary)
                                .foregroundStyle(.secondary)
                        }
                        Toggle(isOn: $downloads.allowCellularDownload) {
                            Label("允许蜂窝网络下载".t, systemImage: "antenna.radiowaves.left.and.right")
                        }
                        queueDownloadButton
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
        .reserveMiniPlayer(visible: playback.currentSong != nil)
    }

    /// 当前下载统计摘要。
    private var downloadSummary: String {
        let completed = downloads.entries.filter { $0.status == .completed }.count
        let failed = downloads.entries.filter { $0.status == .failed }.count
        return "\(completed) " + "已完成".t + " · \(failed) " + "失败".t
    }

    /// 批量下载当前播放队列的按钮。
    private var queueDownloadButton: some View {
        Button {
            Task { await downloadCurrentQueue() }
        } label: {
            HStack {
                if isDownloadingQueue {
                    ProgressView()
                } else {
                    Image(systemName: "tray.and.arrow.down")
                }
                Text(queueDownloadTitle)
                Spacer()
                if isDownloadingQueue {
                    Text("\(queueProgress.done)/\(queueProgress.total)")
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isDownloadingQueue || playback.queue.isEmpty)
    }

    /// 下载按钮根据状态展示不同标题。
    private var queueDownloadTitle: String {
        if isDownloadingQueue { return "正在下载当前队列".t }
        return playback.queue.isEmpty ? "当前队列为空".t : "下载当前队列".t
    }

    /// 按当前播放队列顺序批量下载歌曲。
    private func downloadCurrentQueue() async {
        guard session.musicClient != nil || session.client != nil else {
            playback.setStatus("请先连接服务器再下载".t)
            return
        }
        let songs = playback.queue.filter { song in
            downloads.status(for: song.id) != .completed
        }
        guard !songs.isEmpty else {
            playback.setStatus("当前队列没有需要下载的歌曲".t)
            return
        }
        isDownloadingQueue = true
        queueProgress = (0, songs.count)
        defer { isDownloadingQueue = false }
        var unsupportedCount = 0
        for song in songs {
            let url: URL?
            do {
                url = try await MusicDownloadResolver.url(
                    for: song,
                    quality: playback.quality,
                    musicClient: session.musicClient,
                    legacyClient: session.client
                )
            } catch {
                playback.setStatus("下载失败".t + "：\(song.title)")
                queueProgress.done += 1
                continue
            }
            guard let url else {
                unsupportedCount += 1
                queueProgress.done += 1
                continue
            }
            let fileExtension = MusicDownloadResolver.fileExtension(for: song, quality: playback.quality, url: url)
            do {
                try await downloads.download(
                    song: song,
                    streamURL: url,
                    fileExtension: fileExtension,
                    allowInvalidCertificate: MusicDownloadResolver.allowsInvalidCertificate(
                        musicClient: session.musicClient,
                        legacyClient: session.client
                    )
                )
            } catch {
                playback.setStatus("下载失败".t + "：\(song.title)")
            }
            queueProgress.done += 1
        }
        playback.setStatus(unsupportedCount == songs.count ? "当前音乐源不支持下载。".t : "队列下载完成".t)
        Haptics.success()
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
                .foregroundStyle(accentColor)
        case .failed:
            Text("下载失败".t)
                .font(.nocLabel)
                .foregroundStyle(.red)
        }
    }
}
