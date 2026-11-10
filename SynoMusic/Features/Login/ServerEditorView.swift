import SwiftUI
import UniformTypeIdentifiers

/// 服务器档案编辑：新增或编辑 NAS 连接信息；同时承担"测试并登录"功能。
struct ServerEditorView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var reviewMode: AppReviewMode
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var isCheckingPlexPin: Bool = false
    @State private var showPlexServerPicker: Bool = false
    @State private var showPlexLibraryPicker: Bool = false
    @State private var showPlexPinSheet: Bool = false
    @State private var showSMBFolderImporter: Bool = false
    @State private var showWebDAVDirectoryPicker: Bool = false

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

    /// SMB 连接模式：手动 SMB2 连接，或沿用系统文件 App 授权文件夹。
    enum SMBConnectionMode: String, CaseIterable, Identifiable {
        case manual, fileProvider

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .manual: return "手动连接"
            case .fileProvider: return "文件 App"
            }
        }
    }
    @State private var smbConnectionMode: SMBConnectionMode = .manual

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

    /// 当前添加服务器页使用的主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
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
                    smbConnectionModeSection
                    if smbConnectionMode == .manual {
                        smbManualConnectionSection
                        smbManualPathSection
                    } else {
                        smbFolderSection
                    }
                } else {
                    directSection
                }
                if shouldShowAccountSection {
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
            .sheet(isPresented: $showPlexPinSheet) {
                if let plexPin {
                    PlexPinAuthSheet(
                        pin: plexPin,
                        onOpen: { openURL(plexPin.authURL) },
                        onCancel: {
                            showPlexPinSheet = false
                        },
                        onContinue: { Task { await continuePlexPinAuthorization() } }
                    )
                }
            }
            .sheet(isPresented: $showWebDAVDirectoryPicker) {
                WebDAVDirectoryPickerSheet(
                    profile: profile,
                    password: password,
                    onCancel: { showWebDAVDirectoryPicker = false },
                    onSelect: { item in
                        profile.musicLibraryID = item.path
                        profile.musicLibraryName = item.name
                        showWebDAVDirectoryPicker = false
                    }
                )
            }
            .onAppear { setupOnAppear() }
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
                    .foregroundStyle(accentColor)
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

    /// SMB 连接模式选择：优先使用手动 SMB2 连接，系统文件 App 作为兼容备用。
    private var smbConnectionModeSection: some View {
        Section {
            Picker("模式".t, selection: $smbConnectionMode) {
                ForEach(SMBConnectionMode.allCases) { mode in
                    Text(mode.titleKey.t).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(smbConnectionMode == .manual
                ? "手动连接会使用 SMB2 读取音乐文件；路径可留空，也可填写 /共享名/子目录。".t
                : "文件 App 模式适合已在系统文件 App 中连接过的 SMB 共享。".t)
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
                applySchemeDefaults(newValue)
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

    /// SMB 手动连接只需要主机和端口，不展示 HTTP/HTTPS 协议。
    private var smbManualConnectionSection: some View {
        Section {
            ClearableTextField(title: "SMB 地址".t, text: $profile.host, keyboard: .URL)
            HStack {
                Text("端口".t)
                Spacer()
                ClearableTextField(title: "445", text: $portText, keyboard: .numberPad)
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
            Button {
                showWebDAVDirectoryPicker = true
            } label: {
                Label("浏览目录".t, systemImage: "folder")
            }
            .disabled(!canBrowseWebDAV)
        } header: {
            Text("WebDAV 目录".t)
        } footer: {
            Text(canBrowseWebDAV
                ? "可以先连接 WebDAV 根目录，再从目录列表中选择音乐所在文件夹。".t
                : "请先填写 WebDAV 地址、账号和密码，再浏览目录。".t)
        }
    }

    /// SMB 手动连接的共享路径设置。
    private var smbManualPathSection: some View {
        Section {
            ClearableTextField(title: "共享路径（选填，如 /music）".t, text: optionalText(\.musicLibraryID), keyboard: .URL)
        } header: {
            Text("SMB 路径".t)
        } footer: {
            Text("路径留空会扫描可访问的磁盘共享；建议填写 /共享名/音乐目录 以减少扫描时间。".t)
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
            if smbConnectionMode == .fileProvider {
                return !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && profile.port > 0 && profile.port <= 65535
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
            return smbConnectionMode == .manual ? "连接并保存".t : "连接文件夹".t
        }
        return "连接并保存".t
    }

    /// 是否展示账号密码区域。
    private var shouldShowAccountSection: Bool {
        profile.providerType != .smb || smbConnectionMode == .manual
    }

    /// Plex 账号授权模式不展示可编辑凭据选项，避免用户误改造成连接失败。
    private var shouldShowCredentialOptions: Bool {
        !(profile.providerType == .plex && plexLoginMode == .account)
            && !(profile.providerType == .smb && smbConnectionMode == .fileProvider)
    }

    /// WebDAV 目录浏览前需要具备的连接信息。
    private var canBrowseWebDAV: Bool {
        profile.providerType == .webDAV
            && !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && profile.port > 0
            && !profile.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            return smbConnectionMode == .manual
                ? "SMB 密码会加密保存于 Keychain。".t
                : "SMB 文件夹授权会加密保存于 Keychain。".t
        }
        if [.jellyfin, .emby].contains(profile.providerType) {
            return "Jellyfin/Emby 的默认端口：HTTP 8096，HTTPS 8920。HTTPS 会默认信任自签名证书；如使用有效证书，可关闭此开关。".t
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
            smbConnectionMode = profile.providerType == .smb && profile.musicLibraryID?.hasPrefix("file:") == true ? .fileProvider : .manual
            password = serverStore.password(for: profile) ?? ""
        } else {
            // 添加新档案：强制清空密码，避免 SwiftUI 复用 / 系统自动填残留
            password = ""
            mode = .direct
            plexLoginMode = .account
            smbConnectionMode = .manual
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
        case .jellyfin, .emby:
            mode = .direct
            profile.isQuickConnect = false
            profile.quickConnectID = ""
        case .plex:
            mode = .direct
            plexLoginMode = .account
            profile.isQuickConnect = false
            profile.quickConnectID = ""
        case .webDAV:
            mode = .direct
            profile.isQuickConnect = false
            profile.quickConnectID = ""
            profile.scheme = .https
        case .smb:
            mode = .direct
            smbConnectionMode = .manual
            profile.isQuickConnect = false
            profile.quickConnectID = ""
        }
        applyCurrentProviderPortDefault()
        applyCertificateDefaultIfNeeded()
    }

    /// 根据当前音乐源和协议同步常见默认端口，只覆盖仍停留在已知默认端口的值。
    private func applyCurrentProviderPortDefault() {
        guard isKnownDefaultPort(profile.port) else { return }
        profile.port = defaultPort(for: profile.providerType, scheme: profile.scheme)
        portText = String(profile.port)
    }

    /// 协议切换时同步默认端口，并在 Jellyfin/Emby HTTPS 下默认允许自签名证书。
    private func applySchemeDefaults(_ scheme: ServerProfile.Scheme) {
        if isKnownDefaultPort(profile.port) {
            profile.port = defaultPort(for: profile.providerType, scheme: scheme)
            portText = String(profile.port)
        }
        if [.jellyfin, .emby].contains(profile.providerType) {
            profile.ignoreInvalidCertificate = (scheme == .https)
        }
    }

    /// HTTPS 切换或音乐源切换后，按 Jellyfin/Emby 的常见自签名场景设置证书默认值。
    private func applyCertificateDefaultIfNeeded() {
        if [.jellyfin, .emby].contains(profile.providerType), profile.scheme == .https {
            profile.ignoreInvalidCertificate = true
        }
    }

    /// 返回音乐源在对应协议下的默认端口。
    private func defaultPort(for providerType: MusicProviderType, scheme: ServerProfile.Scheme) -> Int {
        switch providerType {
        case .synologyAudioStation:
            return scheme == .https ? 5001 : 5000
        case .jellyfin, .emby:
            return scheme == .https ? 8920 : 8096
        case .plex:
            return 32400
        case .webDAV:
            return scheme == .https ? 5006 : 5005
        case .smb:
            return 445
        }
    }

    /// 判断当前端口是否仍是 App 维护的默认端口，避免覆盖用户手动填写的自定义端口。
    private func isKnownDefaultPort(_ port: Int) -> Bool {
        [5000, 5001, 5005, 5006, 8096, 8920, 32400, 445].contains(port)
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
        } catch {
            self.error = error.localizedDescription.t
            Haptics.warning()
        }
    }

    /// 在用户完成浏览器授权后继续 Plex 服务器发现。
    private func continuePlexPinAuthorization() async {
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
            showPlexPinSheet = false
            try await continuePlexServerDiscovery(account: account)
        } catch is CancellationError {
            playback.setStatus("Plex 授权检查被系统中断，请再点一次「我已完成授权」。".t)
            Haptics.warning()
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

        let credential = PlexAccountService.makeCredential(
            accountToken: account.authToken,
            serverToken: option.server.token
        )
        let client = PlexMusicLibraryClient(profile: selectedProfile)
        try await client.authenticate(token: credential)
        selectedProfile = client.profile
        selectedProfile.lastConnectedAt = Date()
        serverStore.upsert(selectedProfile)
        serverStore.setActive(selectedProfile)
        if rememberPassword {
            try? serverStore.savePassword(credential, for: selectedProfile)
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

/// WebDAV 目录选择页；登录后用 PROPFIND 浏览目录，让用户选择音乐根目录。
private struct WebDAVDirectoryPickerSheet: View {
    let profile: ServerProfile
    let password: String
    let onCancel: () -> Void
    let onSelect: (WebDAVDirectoryItem) -> Void

    @State private var currentPath: String
    @State private var items: [WebDAVDirectoryItem] = []
    @State private var isLoading = false
    @State private var error: String?

    init(
        profile: ServerProfile,
        password: String,
        onCancel: @escaping () -> Void,
        onSelect: @escaping (WebDAVDirectoryItem) -> Void
    ) {
        self.profile = profile
        self.password = password
        self.onCancel = onCancel
        self.onSelect = onSelect
        _currentPath = State(initialValue: profile.musicLibraryID?.isEmpty == false ? profile.musicLibraryID! : "/")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(currentPath)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            onSelect(WebDAVDirectoryItem(path: currentPath, name: selectedName, isDirectory: true))
                        } label: {
                            Label("选择当前目录".t, systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let error {
                        Text(error)
                            .foregroundStyle(.secondary)
                    } else if items.isEmpty {
                        EmptyStateView(systemImage: "folder", title: "空目录".t, message: "这里还没有音频文件。".t)
                    } else {
                        ForEach(items) { item in
                            if item.isDirectory {
                                Button {
                                    currentPath = item.path
                                } label: {
                                    Label(item.name, systemImage: "folder.fill")
                                }
                            } else {
                                Label(item.name, systemImage: "music.note")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("浏览目录".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消".t) { onCancel() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("根目录".t) { currentPath = "/" }
                    Button("上级".t) { currentPath = parentPath }
                        .disabled(currentPath == "/")
                }
            }
            .task(id: currentPath) {
                await load()
            }
        }
    }

    /// 当前目录展示名。
    private var selectedName: String {
        let name = currentPath.split(separator: "/").last.map(String.init) ?? "WebDAV"
        return name.isEmpty ? "WebDAV" : name
    }

    /// 当前目录的上级路径。
    private var parentPath: String {
        var parts = currentPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return "/" }
        parts.removeLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }

    /// 读取当前目录内容。
    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = WebDAVMusicLibraryClient(profile: profile, password: password)
            items = try await client.browseDirectory(path: currentPath)
        } catch {
            items = []
            self.error = error.localizedDescription
        }
    }
}

/// Plex 服务器与远程访问地址选择页。
private struct PlexServerPickerSheet: View {
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let options: [PlexConnectionOption]
    let onCancel: () -> Void
    let onSelect: (PlexConnectionOption) -> Void

    /// 当前 Plex 服务器选择页使用的主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

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
                        .foregroundStyle(accentColor)
                    Text(option.server.name)
                        .font(.nocBody.weight(.semibold))
                    if option.server.hasPlexPass {
                        Text("Plex Pass".t)
                            .font(.nocCaption.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.14), in: Capsule())
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
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let option: PlexConnectionOption
    let onCancel: () -> Void
    let onSelect: (MusicLibrary) -> Void

    /// 当前 Plex 音乐库选择页使用的主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

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
                                    .foregroundStyle(accentColor)
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
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let pin: PlexAuthPin
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onContinue: () -> Void

    /// 当前 Plex 授权页使用的主题强调色。
    private var accentColor: Color {
        theme.current.accent(in: colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "safari")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text("使用浏览器完成 Plex 授权".t)
                    .font(.nocTitle)
                Text("授权完成后回到 SynoMusic，点击「我已完成授权」。".t)
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
                        .font(.nocBody.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PrimaryButtonStyle())
                .controlSize(.large)
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
