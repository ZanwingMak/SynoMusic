import SwiftUI
import UniformTypeIdentifiers

/// 服务器档案编辑：新增或编辑 NAS 连接信息；同时承担"测试并登录"功能。
struct ServerEditorView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var purchase: PurchaseStore
    @EnvironmentObject private var reviewMode: AppReviewMode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State var profile: ServerProfile
    @State private var password: String = ""
    @State private var otp: String = ""
    @State private var portText: String = ""
    @State private var passwordVisible: Bool = false
    @State private var rememberPassword: Bool = true
    @State private var advancedExpanded: Bool = false

    @State private var isConnecting: Bool = false
    @State private var error: String?
    @State private var progressMessage: String?
    @State private var plexLoginMode: PlexLoginMode = .account
    @State private var plexConnectionOptions: [PlexConnectionOption] = []
    @State private var plexPendingAccount: PlexAccountInfo?
    @State private var plexPendingOption: PlexConnectionOption?
    @State private var plexPin: PlexAuthPin?
    @State private var plexAuthPollTask: Task<Void, Never>?
    @State private var isCheckingPlexPin: Bool = false
    @State private var showPlexServerPicker: Bool = false
    @State private var showPlexLibraryPicker: Bool = false
    @State private var showPlexPinSheet: Bool = false
    @State private var showSMBFolderImporter: Bool = false

    /// 编辑模式（QC / 直连）。
    enum Mode: String, CaseIterable, Identifiable {
        case direct, quickConnect
        var id: String { rawValue }
        /// 返回中文 key；调用处使用 `.t` 翻译。
        var titleKey: String {
            switch self {
            case .direct: return "直接连接"
            case .quickConnect: return "QuickConnect"
            }
        }
    }
    @State private var mode: Mode = .direct

    /// Plex 登录模式：账号发现服务器，或手动 Token 直连。
    enum PlexLoginMode: String, CaseIterable, Identifiable {
        case account, token

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .account: return "Plex 账号"
            case .token: return "Token"
            }
        }
    }

    private var loadingShown: Bool {
        #if DEBUG
        return isConnecting || ProcessInfo.processInfo.arguments.contains("-fakeloading")
        #else
        return isConnecting
        #endif
    }

    private var isEditingExisting: Bool {
        serverStore.profiles.contains(where: { $0.id == profile.id })
    }

    private var isLockedQuickConnect: Bool {
        isEditingExisting && profile.isQuickConnect
    }

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                if profile.providerType == .synologyAudioStation {
                    modeSection
                    if mode == .quickConnect { quickConnectSection } else { directSection }
                } else if profile.providerType == .plex {
                    plexLoginModeSection
                    if plexLoginMode == .token {
                        directSection
                    }
                } else if profile.providerType == .webDAV {
                    directSection
                    webDAVPathSection
                } else if profile.providerType == .smb {
                    smbFolderSection
                } else {
                    directSection
                }
                if profile.providerType != .smb {
                    accountSection
                }
                actionSection
                advancedSection
            }
            .navigationTitle((isEditingExisting ? "编辑服务器" : "添加服务器").t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { dismiss() }
                }
            }
            .alert(
                "连接失败".t,
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("我知道了".t, role: .cancel) { error = nil }
                if (error ?? "").contains("Audio Station") {
                    Button("复制 DSM 路径".t) {
                        UIPasteboard.general.string = "控制面板 → 用户与群组 → 编辑用户 → 应用程序 → Audio Station → 允许".t
                    }
                }
            } message: {
                Text(error ?? "")
            }
            .sheet(isPresented: $showPlexServerPicker) {
                PlexServerPickerSheet(
                    options: plexConnectionOptions,
                    onCancel: { showPlexServerPicker = false },
                    onSelect: { option in
                        Task { await finishPlexConnectionSelection(option) }
                    }
                )
            }
            .sheet(isPresented: $showPlexLibraryPicker) {
                if let option = plexPendingOption {
                    PlexLibraryPickerSheet(
                        option: option,
                        onCancel: { showPlexLibraryPicker = false },
                        onSelect: { library in
                            Task { await finishPlexLibrarySelection(library) }
                        }
                    )
                }
            }
            .sheet(isPresented: $showPlexPinSheet, onDismiss: {
                cancelPlexAuthPolling()
            }) {
                if let plexPin {
                    PlexPinAuthSheet(
                        pin: plexPin,
                        onOpen: { openURL(plexPin.authURL) },
                        onCancel: {
                            cancelPlexAuthPolling()
                            showPlexPinSheet = false
                        },
                        onContinue: { Task { await continuePlexPinAuthorization() } }
                    )
                }
            }
            .onAppear { setupOnAppear() }
            .onReceive(NotificationCenter.default.publisher(for: .plexAuthReturned)) { _ in
                guard showPlexPinSheet, plexPin != nil else { return }
                Task { await continuePlexPinAuthorization(showPendingError: false) }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, showPlexPinSheet, plexPin != nil else { return }
                Task { await pollPlexPinAuthorizationOnce() }
            }
            .fileImporter(isPresented: $showSMBFolderImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                handleSMBFolderImport(result)
            }
        }
    }

    // MARK: 章节

    private var providerSection: some View {
        Section {
            Picker("音乐源".t, selection: $profile.providerType) {
                ForEach(MusicProviderType.allCases) { type in
                    Text(type.titleKey.t).tag(type)
                }
            }
            .onChange(of: profile.providerType) { _, newValue in
                applyProviderDefaults(newValue)
            }
            if !isProviderConnectable {
                Label("该音乐源正在接入中，当前版本暂不可连接。".t, systemImage: "hammer")
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("音乐源".t)
        } footer: {
            Text("Jellyfin、Emby、Plex、WebDAV 和 SMB 仅接入音乐库，不会加入视频、电视或照片功能。".t)
        }
    }

    private var modeSection: some View {
        Section {
            if isLockedQuickConnect {
                Label("QuickConnect", systemImage: "bolt.horizontal.circle.fill")
                    .foregroundStyle(Theme.accent)
            } else {
                Picker("模式".t, selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.titleKey.t).tag(m) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newValue in
                    if newValue == .quickConnect {
                        enterQuickConnectMode()
                    }
                }
            }
        } footer: {
            Text(mode == .quickConnect
                ? "QuickConnect ID 由群晖服务解析为真实地址，无需自己填 IP 与端口。".t
                : "直连 IP / DDNS 域名，自行指定协议和端口。".t)
        }
    }

    /// Plex 登录模式选择：账号模式会自动发现服务器，Token 模式保留直连入口。
    private var plexLoginModeSection: some View {
        Section {
            Picker("模式".t, selection: $plexLoginMode) {
                ForEach(PlexLoginMode.allCases) { mode in
                    Text(mode.titleKey.t).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(plexLoginMode == .account
                ? "Plex 授权会自动发现可访问服务器；如需手动填写地址和 Token，请切换到 Token 模式。".t
                : "已有 X-Plex-Token 时，可以手动填写服务器地址直连。".t)
        }
    }

    /// QuickConnect 模式：只需 ID + 通道（HTTP/HTTPS）。
    private var quickConnectSection: some View {
        Section {
            ClearableTextField(title: "QuickConnect ID", text: $profile.quickConnectID, keyboard: .URL)
            if profile.isQuickConnect, profile.host != profile.quickConnectID, !profile.host.isEmpty {
                HStack {
                    Text("设备地址".t)
                    Spacer()
                    Text(profile.resolvedDisplayURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text("QuickConnect")
        } footer: {
            Text("在 DSM 控制面板 → QuickConnect 中查到的 ID（不包含 quickconnect.to 域名）。App 会自动使用 HTTPS QuickConnect 通道。".t)
        }
    }

    /// 直连模式：协议 / 主机 / 端口。
    private var directSection: some View {
        Section {
            Picker("协议".t, selection: $profile.scheme) {
                ForEach(ServerProfile.Scheme.allCases) { s in
                    Text(s.rawValue.uppercased()).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: profile.scheme) { _, newValue in
                let defaultsToFollow: Set<Int> = profile.providerType == .webDAV ? [5005, 5006] : [5000, 5001]
                if defaultsToFollow.contains(profile.port) {
                    if profile.providerType == .webDAV {
                        profile.port = (newValue == .https) ? 5006 : 5005
                    } else {
                        profile.port = (newValue == .https) ? 5001 : 5000
                    }
                    portText = String(profile.port)
                }
            }
            ClearableTextField(title: "主机或 DDNS".t, text: $profile.host, keyboard: .URL)
            HStack {
                Text("端口".t)
                Spacer()
                ClearableTextField(title: "5000", text: $portText, keyboard: .numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .onChange(of: portText) { _, new in
                        let digits = new.filter(\.isNumber)
                        if digits != new { portText = digits }
                        if let v = Int(digits), v > 0, v <= 65535 { profile.port = v }
                    }
            }
        } header: {
            Text("连接".t)
        }
    }

    /// WebDAV 根目录设置；留空时扫描服务器根目录。
    private var webDAVPathSection: some View {
        Section {
            ClearableTextField(title: "目录路径（例如 /music）".t, text: optionalText(\.musicLibraryID), keyboard: .URL)
        } header: {
            Text("WebDAV 目录".t)
        } footer: {
            Text("Synology WebDAV 常用 HTTPS 端口是 5006；目录路径应填写音乐所在目录，例如 /music。".t)
        }
    }

    /// SMB 文件夹选择；通过系统文件 App 授权共享目录。
    private var smbFolderSection: some View {
        Section {
            Button {
                showSMBFolderImporter = true
            } label: {
                Label(smbFolderButtonTitle, systemImage: "folder.badge.plus")
            }
            if let name = profile.musicLibraryName, !name.isEmpty {
                HStack {
                    Text("已选择".t)
                    Spacer()
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("SMB 文件夹".t)
        } footer: {
            Text("请先在系统「文件」App 中连接 SMB 共享，然后在这里选择音乐文件夹。SynoMusic 会保存文件夹授权，不保存 SMB 账号密码。".t)
        }
    }

    private var accountSection: some View {
        Section {
            if profile.providerType == .plex {
                if plexLoginMode == .account {
                    Label("通过 Plex 官方网页授权，无需在 App 输入账号密码。".t, systemImage: "checkmark.shield")
                        .font(.nocBody)
                        .foregroundStyle(.secondary)
                } else {
                    ClearableSecureField(title: "X-Plex-Token".t, text: $password)
                }
            } else {
                ClearableTextField(title: "用户名".t, text: $profile.username)
                ClearableSecureField(title: "密码".t, text: $password)
            }
        } header: {
            if profile.providerType == .plex {
                Text(plexLoginMode == .token ? "访问令牌".t : "Plex 授权".t)
            } else {
                Text("账号".t)
            }
        } footer: {
            if profile.providerType == .plex, plexLoginMode == .account {
                Text("授权成功后，App 只保存所选服务器的访问令牌；账号密码不会保存在本机。".t)
            } else if profile.providerType == .plex {
                Text("Plex 需要填入 X-Plex-Token；可在 Plex Web 中查看服务器请求或账号设置获取。".t)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await connectAndSave() }
            } label: {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if loadingShown {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text(progressButtonTitle)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .disabled(!canSubmit || isConnecting)
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $advancedExpanded) {
                ClearableTextField(title: "备注名（家里的 DS220+）".t, text: $profile.name, autocapitalization: .sentences)
                if profile.providerType == .synologyAudioStation {
                    ClearableTextField(title: "二步验证码（OTP）".t, text: $otp, keyboard: .numberPad)
                }
                if shouldShowCredentialOptions {
                    Toggle("记住密码".t, isOn: $rememberPassword)
                }
                if shouldShowCredentialOptions, profile.scheme == .https {
                    Toggle("信任自签名证书".t, isOn: $profile.ignoreInvalidCertificate)
                }
                if isEditingExisting, shouldShowCredentialOptions {
                    Button("仅保存配置，不立即登录".t) { saveOnly() }
                }
            } label: {
                Label("高级".t, systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(advancedFooterText)
        }
    }

    // MARK: 行为

    private var canSubmit: Bool {
        if isReviewCredential {
            return true
        }
        guard isProviderConnectable else { return false }
        if profile.providerType == .smb {
            return !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if profile.providerType == .plex, plexLoginMode == .account {
            return true
        }
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if profile.providerType != .plex,
           profile.username.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        switch mode {
        case .quickConnect:
            return !profile.quickConnectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .direct:
            return !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && profile.port > 0 && profile.port <= 65535
        }
    }

    private var progressButtonTitle: String {
        if !isProviderConnectable {
            return "即将支持".t
        }
        if loadingShown {
            return progressMessage ?? "正在连接...".t
        }
        if profile.providerType == .plex, plexLoginMode == .account {
            return "授权并发现服务器".t
        }
        if profile.providerType == .smb {
            return "连接文件夹".t
        }
        return "连接并保存".t
    }

    /// Plex 账号授权模式不展示可编辑凭据选项，避免用户误改造成连接失败。
    private var shouldShowCredentialOptions: Bool {
        !(profile.providerType == .plex && plexLoginMode == .account) && profile.providerType != .smb
    }

    /// SMB 文件夹按钮标题。
    private var smbFolderButtonTitle: String {
        if profile.musicLibraryName?.isEmpty == false {
            return "重新选择 SMB 文件夹".t
        }
        return "选择 SMB 文件夹".t
    }

    /// 高级区说明文案。
    private var advancedFooterText: String {
        if profile.providerType == .synologyAudioStation {
            return "启用了二步验证的账号需在「高级」填入 OTP。密码加密保存于 Keychain。".t
        }
        if profile.providerType == .smb {
            return "SMB 文件夹授权会加密保存于 Keychain。".t
        }
        return "密码或访问令牌会加密保存于 Keychain。".t
    }

    /// 当前音乐源是否已有可用登录实现。
    private var isProviderConnectable: Bool {
        true
    }

    /// 当前输入是否命中 App Store 审核账号。
    private var isReviewCredential: Bool {
        AppReviewMode.matches(username: profile.username, password: password)
    }

    private func setupOnAppear() {
        portText = String(profile.port)
        // 编辑现有档案：用 isQuickConnect 字段决定初始模式
        if isEditingExisting {
            mode = profile.isQuickConnect ? .quickConnect : .direct
            plexLoginMode = .account
            password = serverStore.password(for: profile) ?? ""
        } else {
            // 添加新档案：强制清空密码，避免 SwiftUI 复用 / 系统自动填残留
            password = ""
            mode = .direct
            plexLoginMode = .account
        }
        if mode == .quickConnect {
            enterQuickConnectMode()
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-password"), i + 1 < args.count { password = args[i + 1] }
        if args.contains("-autoconnect"), !Self.autoconnectFired {
            Self.autoconnectFired = true
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await connectAndSave()
            }
        }
        #endif
    }

    #if DEBUG
    private static var autoconnectFired: Bool = false
    #endif

    private func saveOnly() {
        guard canSaveProfileUnderLimit() else { return }
        var p = applyMode(to: profile)
        if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = displayName(of: p) }
        serverStore.upsert(p)
        if rememberPassword, !password.isEmpty {
            try? serverStore.savePassword(password, for: p)
        }
        Haptics.success()
        dismiss()
    }

    /// 把当前编辑器 mode 反映到 profile 上（QC 模式下补 isQuickConnect / quickConnectID）。
    private func applyMode(to p: ServerProfile) -> ServerProfile {
        var copy = p
        guard copy.providerType == .synologyAudioStation else {
            copy.isQuickConnect = false
            copy.quickConnectID = ""
            return copy
        }
        copy.isQuickConnect = (mode == .quickConnect)
        if mode == .quickConnect {
            let id = QuickConnectResolver.strip(copy.quickConnectID)
            copy.quickConnectID = id
            copy.host = id
            copy.scheme = .https
            copy.port = 5001
            copy.ignoreInvalidCertificate = true
        } else {
            copy.quickConnectID = ""
        }
        return copy
    }

    /// 根据所选音乐源应用常见默认端口，并避免非 Synology 源保留 QuickConnect 状态。
    private func applyProviderDefaults(_ providerType: MusicProviderType) {
        switch providerType {
        case .synologyAudioStation:
            mode = .direct
            if profile.port == 8096 || profile.port == 32400 || profile.port == 5006 || profile.port == 445 {
                profile.port = profile.scheme == .https ? 5001 : 5000
                portText = String(profile.port)
            }
        case .jellyfin, .emby:
            mode = .direct
            profile.isQuickConnect = false
            profile.quickConnectID = ""
            if profile.port == 5000 || profile.port == 5001 || profile.port == 32400 || profile.port == 5006 || profile.port == 445 {
                profile.port = 8096
                portText = "8096"
            }
        case .plex:
            mode = .direct
            plexLoginMode = .account
            profile.isQuickConnect = false
            profile.quickConnectID = ""
            if profile.port == 5000 || profile.port == 5001 || profile.port == 8096 || profile.port == 5006 || profile.port == 445 {
                profile.port = 32400
                portText = "32400"
            }
        case .webDAV:
            mode = .direct
            profile.isQuickConnect = false
            profile.quickConnectID = ""
            profile.scheme = .https
            if profile.port == 5000 || profile.port == 5001 || profile.port == 8096 || profile.port == 32400 || profile.port == 445 {
                profile.port = 5006
                portText = "5006"
            }
        case .smb:
            mode = .direct
            profile.isQuickConnect = false
            profile.quickConnectID = ""
            profile.username = ""
            if profile.port == 5000 || profile.port == 5001 || profile.port == 8096 || profile.port == 32400 || profile.port == 5006 {
                profile.port = 445
                portText = "445"
            }
        }
    }

    /// 同步 QuickConnect 表单的派生字段，避免出现 HTTPS 仍保存 5000 端口的中间状态。
    private func syncQuickConnectDefaults(for scheme: ServerProfile.Scheme) {
        profile.port = scheme == .https ? 5001 : 5000
        portText = String(profile.port)
        if scheme == .https {
            profile.ignoreInvalidCertificate = true
        }
    }

    /// 进入 QuickConnect 模式时优先使用 HTTPS，与群晖实际返回的中继通道保持一致。
    private func enterQuickConnectMode() {
        profile.scheme = .https
        syncQuickConnectDefaults(for: .https)
        if !profile.isQuickConnect {
            profile.host = ""
        }
    }

    /// 列表显示名：QC 模式优先用 ID。
    private func displayName(of p: ServerProfile) -> String {
        if p.isQuickConnect, !p.quickConnectID.isEmpty { return p.quickConnectID }
        return p.host
    }

    private func connectAndSave() async {
        guard canSubmit else { return }
        if isReviewCredential {
            enterReviewMode()
            return
        }
        guard isProviderConnectable else {
            error = "该音乐源正在接入中，当前版本暂不可连接。".t
            return
        }
        guard canSaveProfileUnderLimit() else { return }
        if profile.providerType == .plex, plexLoginMode == .account {
            await beginPlexPinAuthorization()
            return
        }
        isConnecting = true
        progressMessage = "正在连接...".t
        defer {
            isConnecting = false
            progressMessage = nil
        }
        error = nil

        var p = applyMode(to: profile)
        if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = displayName(of: p) }

        // 立即 upsert 一份基础配置，登录成败都留得下
        serverStore.upsert(p)

        do {
            let result = try await MusicProviderLoginHelper.login(
                profile: p,
                password: password,
                otp: otp.isEmpty ? nil : otp,
                report: { key in progressMessage = key.t }
            )
            var updated = result.profile
            updated.lastConnectedAt = Date()
            serverStore.upsert(updated)
            serverStore.setActive(updated)
            if rememberPassword {
                try? serverStore.savePassword(password, for: updated)
            }
            session.sign(in: result.musicClient)
            Haptics.success()
            dismiss()
        } catch let SynologyError.api(code, _) where code == 403 {
            self.error = "账号启用了两步验证。请展开「高级」填入 6 位 OTP 代码后再试。配置已保存到「服务器」列表，可稍后重试。".t
            advancedExpanded = true
            Haptics.warning()
        } catch let err as SynologyError {
            self.error = (err.errorDescription ?? "连接失败".t) + "\n\n" + "配置已保存到「服务器」列表，可在列表中点 ⓘ 修改后重试。".t
            Haptics.warning()
        } catch {
            self.error = error.localizedDescription + "\n\n" + "配置已保存到「服务器」列表。".t
            Haptics.warning()
        }
    }

    /// 创建 Plex 浏览器授权 PIN，并打开授权说明页。
    private func beginPlexPinAuthorization() async {
        isConnecting = true
        progressMessage = "正在创建 Plex 授权码...".t
        error = nil
        defer {
            isConnecting = false
            progressMessage = nil
        }

        do {
            plexPin = try await PlexAccountService.createPin()
            showPlexPinSheet = true
            startPlexAuthPolling()
        } catch {
            self.error = error.localizedDescription.t
            Haptics.warning()
        }
    }

    /// 在用户完成浏览器授权后继续 Plex 服务器发现。
    private func continuePlexPinAuthorization(showPendingError: Bool = true) async {
        guard let plexPin else { return }
        guard !isCheckingPlexPin else { return }
        isCheckingPlexPin = true
        isConnecting = true
        progressMessage = "正在确认 Plex 授权...".t
        defer {
            isConnecting = false
            progressMessage = nil
            isCheckingPlexPin = false
        }

        do {
            guard let account = try await PlexAccountService.checkPin(plexPin) else {
                throw PlexAccountError.authorizationPending
            }
            cancelPlexAuthPolling()
            showPlexPinSheet = false
            try await continuePlexServerDiscovery(account: account)
        } catch PlexAccountError.authorizationPending where !showPendingError {
            return
        } catch {
            self.error = error.localizedDescription.t
            Haptics.warning()
        }
    }

    /// 启动 Plex PIN 授权状态轮询，避免依赖 Plex 网页是否成功回调自定义 URL scheme。
    private func startPlexAuthPolling() {
        cancelPlexAuthPolling()
        guard let pin = plexPin else { return }
        plexAuthPollTask = Task { @MainActor in
            while !Task.isCancelled {
                if let expiresAt = pin.expiresAt, Date() > expiresAt {
                    break
                }
                guard showPlexPinSheet, plexPin?.id == pin.id else {
                    break
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await pollPlexPinAuthorizationOnce()
            }
        }
    }

    /// 取消 Plex PIN 授权状态轮询。
    private func cancelPlexAuthPolling() {
        plexAuthPollTask?.cancel()
        plexAuthPollTask = nil
    }

    /// 静默检查一次 Plex PIN 状态，授权完成时自动进入服务器发现。
    private func pollPlexPinAuthorizationOnce() async {
        guard let plexPin, !isCheckingPlexPin else { return }
        isCheckingPlexPin = true
        defer { isCheckingPlexPin = false }
        do {
            guard let account = try await PlexAccountService.checkPin(plexPin) else { return }
            cancelPlexAuthPolling()
            showPlexPinSheet = false
            isConnecting = true
            defer {
                isConnecting = false
                progressMessage = nil
            }
            try await continuePlexServerDiscovery(account: account)
        } catch PlexAccountError.authorizationPending {
            return
        } catch {
            self.error = error.localizedDescription.t
            Haptics.warning()
        }
    }

    /// 拉取 Plex 服务器并验证所有可用连接。
    private func continuePlexServerDiscovery(account: PlexAccountInfo) async throws {
        progressMessage = "正在发现 Plex 服务器...".t
        let servers = try await PlexAccountService.fetchServers(account: account)
        progressMessage = "正在测试 Plex 连接...".t
        let options = await validatePlexConnections(account: account, servers: servers)
        guard !options.isEmpty else { throw PlexAccountError.noConnection }

        plexPendingAccount = account
        plexConnectionOptions = options
        if options.count == 1, let first = options.first {
            try await preparePlexLibrarySelection(first)
        } else {
            showPlexServerPicker = true
        }
    }

    /// 并发测试 Plex 连接地址，并只保留可访问音乐库的候选。
    private func validatePlexConnections(
        account: PlexAccountInfo,
        servers: [PlexDiscoveredServer]
    ) async -> [PlexConnectionOption] {
        let baseProfile = profile
        return await withTaskGroup(of: PlexConnectionOption?.self) { group in
            for server in servers {
                for connection in server.connections {
                    group.addTask {
                        let start = Date()
                        let candidateProfile = PlexAccountService.makeProfile(
                            from: baseProfile,
                            account: account,
                            server: server,
                            connection: connection
                        )
                        let client = PlexMusicLibraryClient(profile: candidateProfile)
                        do {
                            try await client.authenticate(token: server.token)
                            let libraries = try await client.loadLibraries()
                            return PlexConnectionOption(
                                id: "\(server.id)-\(connection.id)",
                                server: server,
                                connection: connection,
                                libraries: libraries,
                                responseTime: Date().timeIntervalSince(start)
                            )
                        } catch {
                            return nil
                        }
                    }
                }
            }

            var options: [PlexConnectionOption] = []
            for await option in group {
                if let option { options.append(option) }
            }
            return options.sorted(by: PlexAccountService.sortOptions)
        }
    }

    /// 完成用户在 Plex 服务器选择页中的连接选择。
    private func finishPlexConnectionSelection(_ option: PlexConnectionOption) async {
        showPlexServerPicker = false
        isConnecting = true
        progressMessage = "正在连接...".t
        defer {
            isConnecting = false
            progressMessage = nil
        }

        do {
            try await preparePlexLibrarySelection(option)
        } catch {
            self.error = error.localizedDescription.t
            Haptics.warning()
        }
    }

    /// 根据连接候选决定是否需要让用户选择具体音乐库。
    private func preparePlexLibrarySelection(_ option: PlexConnectionOption) async throws {
        guard !option.libraries.isEmpty else { throw PlexMusicError.noMusicLibrary }
        plexPendingOption = option
        if option.libraries.count == 1, let library = option.libraries.first {
            try await savePlexAccountSelection(option: option, library: library)
        } else {
            showPlexLibraryPicker = true
        }
    }

    /// 完成用户在 Plex 音乐库选择页中的选择。
    private func finishPlexLibrarySelection(_ library: MusicLibrary) async {
        guard let option = plexPendingOption else {
            error = "Plex 登录状态已失效，请重新登录。".t
            return
        }
        showPlexLibraryPicker = false
        isConnecting = true
        progressMessage = "正在连接...".t
        defer {
            isConnecting = false
            progressMessage = nil
        }

        do {
            try await savePlexAccountSelection(option: option, library: library)
        } catch {
            self.error = error.localizedDescription.t
            Haptics.warning()
        }
    }

    /// 保存 Plex 服务器与音乐库选择，写入 Keychain token，并切换当前音乐会话。
    private func savePlexAccountSelection(option: PlexConnectionOption, library: MusicLibrary) async throws {
        guard let account = plexPendingAccount else {
            throw PlexAccountError.invalidResponse
        }
        var selectedProfile = PlexAccountService.makeProfile(
            from: profile,
            account: account,
            server: option.server,
            connection: option.connection,
            library: library
        )
        serverStore.upsert(selectedProfile)

        let client = PlexMusicLibraryClient(profile: selectedProfile)
        try await client.authenticate(token: option.server.token)
        selectedProfile.lastConnectedAt = Date()
        serverStore.upsert(selectedProfile)
        serverStore.setActive(selectedProfile)
        if rememberPassword {
            try? serverStore.savePassword(option.server.token, for: selectedProfile)
        }
        session.sign(in: client)
        Haptics.success()
        dismiss()
    }

    /// 进入审核模式，不保存真实服务器配置，也不发起网络登录。
    private func enterReviewMode() {
        reviewMode.activate()
        playback.stop()
        Haptics.success()
        dismiss()
    }

    /// 校验免费版服务器数量限制，避免新增入口以外的路径写入超量配置。
    private func canSaveProfileUnderLimit() -> Bool {
        guard !isEditingExisting,
              !purchase.canUse(.serverProfiles),
              serverStore.profiles.count >= PurchaseLimits.maxFreeServerProfiles else {
            return true
        }
        error = PremiumFeature.serverProfiles.lockedMessage.t
        Haptics.warning()
        return false
    }

    /// 处理用户从系统文件 App 选择的 SMB 文件夹授权。
    private func handleSMBFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                password = try FolderMusicLibraryClient.makeBookmark(for: url)
                profile.host = url.lastPathComponent
                profile.musicLibraryID = url.absoluteString
                profile.musicLibraryName = url.lastPathComponent
                if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.name = url.lastPathComponent
                }
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
                Haptics.warning()
            }
        case .failure(let error):
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }

    /// 为可选字符串字段创建非可选 Binding，便于表单编辑。
    private func optionalText(_ keyPath: WritableKeyPath<ServerProfile, String?>) -> Binding<String> {
        Binding(
            get: { profile[keyPath: keyPath] ?? "" },
            set: { profile[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }
}

/// Plex 服务器与远程访问地址选择页。
private struct PlexServerPickerSheet: View {
    let options: [PlexConnectionOption]
    let onCancel: () -> Void
    let onSelect: (PlexConnectionOption) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(options) { option in
                    optionRow(option)
                }
                Section {
                    Text("请选择要连接的 Plex 服务器或远程访问地址。".t)
                        .font(.nocCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("选择 Plex 服务器".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { onCancel() }
                }
            }
        }
    }

    /// 生成单个可用 Plex 连接候选行。
    private func optionRow(_ option: PlexConnectionOption) -> some View {
        Button {
            onSelect(option)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: iconName(for: option.connection))
                        .foregroundStyle(Theme.accent)
                    Text(option.server.name)
                        .font(.nocBody.weight(.semibold))
                    if option.server.hasPlexPass {
                        Text("Plex Pass".t)
                            .font(.nocCaption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }
                }
                Text(option.connection.labelKey.t + " · " + option.connection.displayURL)
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(String(format: "已发现 %d 个音乐库".t, option.libraries.count))
                    .font(.nocCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    /// 根据连接类型返回 SF Symbols 图标。
    private func iconName(for connection: PlexServerConnection) -> String {
        if connection.isRelay { return "point.3.connected.trianglepath.dotted" }
        return connection.isLocal ? "house.and.flag" : "network"
    }
}

/// Plex 音乐库选择页。
private struct PlexLibraryPickerSheet: View {
    let option: PlexConnectionOption
    let onCancel: () -> Void
    let onSelect: (MusicLibrary) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(option.libraries) { library in
                        Button {
                            onSelect(library)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: library.isDefault ? "music.note.house.fill" : "music.note.list")
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name)
                                        .font(.nocBody.weight(.semibold))
                                    Text(option.connection.displayURL)
                                        .font(.nocCaption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } footer: {
                    Text("请选择要在 SynoMusic 中使用的 Plex 音乐库。".t)
                }
            }
            .navigationTitle("选择音乐库".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { onCancel() }
                }
            }
        }
    }
}

/// Plex 浏览器授权页。
private struct PlexPinAuthSheet: View {
    let pin: PlexAuthPin
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "safari")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("使用浏览器完成 Plex 授权".t)
                    .font(.nocTitle)
                Text("授权完成后回到 SynoMusic，会自动继续。".t)
                    .font(.nocBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pin.code)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                Button {
                    onOpen()
                } label: {
                    Label("打开 Plex 授权页".t, systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    onContinue()
                } label: {
                    Label("我已完成授权".t, systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Plex 授权".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
