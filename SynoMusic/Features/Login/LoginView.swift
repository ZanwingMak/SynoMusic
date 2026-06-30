import SwiftUI

/// 登录视图：输入密码与可选 OTP，触发认证并切换到主界面。
struct LoginView: View {
    @EnvironmentObject private var serverStore: ServerStore
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let profile: ServerProfile

    @State private var password: String = ""
    @State private var otp: String = ""
    @State private var rememberPassword: Bool = true
    @State private var isLoading: Bool = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.05, blue: 0.16),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Metrics.l) {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(.white)
                            .padding(.top, 40)
                        Text(profile.name)
                            .font(.nocSection)
                            .foregroundStyle(.white)
                        Text(profile.displayURL)
                            .font(.nocLabel)
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    GlassPanel(cornerRadius: Theme.cornerCard) {
                        VStack(spacing: Metrics.m) {
                            FieldRow(title: "用户名".t, value: profile.username, system: "person.fill", trailing: nil)
                            Divider().background(Color.white.opacity(0.08))
                            SecureFieldRow(title: "密码".t, text: $password)
                            Divider().background(Color.white.opacity(0.08))
                            FieldRow(title: "OTP（可选）".t, value: nil, system: "key.fill", trailing: {
                                HStack(spacing: 6) {
                                    TextField("6 位数字".t, text: $otp)
                                        .keyboardType(.numberPad)
                                        .textContentType(.oneTimeCode)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(.white)
                                    if !otp.isEmpty {
                                        Button {
                                            Haptics.tap()
                                            otp = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white.opacity(0.45))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("清除".t)
                                    }
                                }
                                .frame(maxWidth: 128)
                            })
                            Divider().background(Color.white.opacity(0.08))
                            Toggle("记住密码".t, isOn: $rememberPassword)
                                .tint(Theme.accent)
                                .foregroundStyle(.white)
                                .font(.nocBody)
                        }
                        .padding(Metrics.m)
                    }

                    if let error {
                        Text(error)
                            .font(.nocCaption)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Metrics.m)
                            .transition(.opacity)
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text(isLoading ? "正在连接...".t : "连接".t)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(password.isEmpty || isLoading)
                }
                .padding(.horizontal, Metrics.l)
                .padding(.bottom, Metrics.xxl)
            }
        }
        .navigationTitle("登录".t)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { restoreSaved() }
    }

    /// 从 Keychain 恢复当前服务器保存过的密码，减少重复输入。
    private func restoreSaved() {
        if let saved = serverStore.password(for: profile) { password = saved }
    }

    /// 使用当前输入的凭据登录服务器；成功后更新会话并关闭当前登录页。
    private func connect() async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            let result = try await MusicProviderLoginHelper.login(
                profile: profile,
                password: password,
                otp: otp.isEmpty ? nil : otp
            )
            if rememberPassword {
                try? serverStore.savePassword(password, for: result.profile)
            }
            var updated = result.profile
            updated.lastConnectedAt = Date()
            serverStore.upsert(updated)
            serverStore.setActive(updated)
            dismiss()
            session.sign(in: result.musicClient)
            Haptics.success()
        } catch let SynologyError.api(code, _) where code == 403 {
            self.error = "需要双重验证，请输入 OTP。".t
            Haptics.warning()
        } catch let err as SynologyError {
            self.error = err.errorDescription
            Haptics.warning()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: 子组件

private struct FieldRow<Trailing: View>: View {
    let title: String
    let value: String?
    let system: String
    @ViewBuilder var trailing: () -> Trailing
    init(title: String, value: String?, system: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.value = value; self.system = system; self.trailing = trailing
    }
    init(title: String, value: String?, system: String, trailing: Trailing?) where Trailing == EmptyView {
        self.title = title; self.value = value; self.system = system; self.trailing = { EmptyView() }
    }
    var body: some View {
        HStack(spacing: Metrics.m) {
            Image(systemName: system)
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.nocLabel).foregroundStyle(.white.opacity(0.72))
                if let value { Text(value).font(.nocBody).foregroundStyle(.white) }
            }
            Spacer()
            trailing()
        }
    }
}

private struct SecureFieldRow: View {
    let title: String
    @Binding var text: String
    @State private var visible: Bool = false
    var body: some View {
        HStack(spacing: Metrics.m) {
            Image(systemName: "key.fill")
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.nocLabel).foregroundStyle(.white.opacity(0.72))
                Group {
                    if visible {
                        TextField(title, text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(title, text: $text)
                    }
                }
                .font(.nocBody)
                .foregroundStyle(.white)
                .textContentType(.oneTimeCode)
            }
            Spacer()
            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除".t)
            }
            Button { visible.toggle() } label: {
                Image(systemName: visible ? "eye.slash" : "eye")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
