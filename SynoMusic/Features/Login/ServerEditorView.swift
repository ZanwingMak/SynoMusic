import SwiftUI

/// 服务器档案编辑：新增或编辑 NAS 连接信息；同时承担"测试并登录"功能。
struct ServerEditorView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var playback: PlaybackEngine
    @EnvironmentObject private var purchase: PurchaseStore
    @Environment(\.dismiss) private var dismiss

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
                modeSection
                if mode == .quickConnect { quickConnectSection } else { directSection }
                accountSection
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
            .onAppear { setupOnAppear() }
        }
    }

    // MARK: 章节

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
                let defaultsToFollow: Set<Int> = [5000, 5001]
                if defaultsToFollow.contains(profile.port) {
                    profile.port = (newValue == .https) ? 5001 : 5000
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

    private var accountSection: some View {
        Section {
            ClearableTextField(title: "用户名".t, text: $profile.username)
            ClearableSecureField(title: "密码".t, text: $password)
        } header: {
            Text("账号".t)
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
                ClearableTextField(title: "二步验证码（OTP）".t, text: $otp, keyboard: .numberPad)
                Toggle("记住密码".t, isOn: $rememberPassword)
                if profile.scheme == .https {
                    Toggle("信任自签名证书".t, isOn: $profile.ignoreInvalidCertificate)
                }
                if isEditingExisting {
                    Button("仅保存配置，不立即登录".t) { saveOnly() }
                }
            } label: {
                Label("高级".t, systemImage: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("启用了二步验证的账号需在「高级」填入 OTP。密码加密保存于 Keychain。".t)
        }
    }

    // MARK: 行为

    private var canSubmit: Bool {
        guard !profile.username.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else { return false }
        switch mode {
        case .quickConnect:
            return !profile.quickConnectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .direct:
            return !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && profile.port > 0 && profile.port <= 65535
        }
    }

    private var progressButtonTitle: String {
        if loadingShown {
            return progressMessage ?? "正在连接...".t
        }
        return "连接并保存".t
    }

    private func setupOnAppear() {
        portText = String(profile.port)
        // 编辑现有档案：用 isQuickConnect 字段决定初始模式
        if isEditingExisting {
            mode = profile.isQuickConnect ? .quickConnect : .direct
            password = serverStore.password(for: profile) ?? ""
        } else {
            // 添加新档案：强制清空密码，避免 SwiftUI 复用 / 系统自动填残留
            password = ""
            mode = .direct
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
        guard canSaveProfileUnderLimit() else { return }
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
            let result = try await SynologyLoginHelper.login(
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
            session.sign(in: result.client)
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
}
