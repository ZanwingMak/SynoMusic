import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// 电视设置提供原生输入、明确的连接状态和服务器选择，不把凭据交给网页。
struct TVSettingsView: View {
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var playback: TVPlayback
    @EnvironmentObject private var servers: ServerStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var language: LanguageManager
    @State private var addServer = false
    @State private var editing: ServerProfile?
    @State private var deleting: ServerProfile?
    @State private var legalLink: TVPublicLink?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                TVHeading(title: "设置".t, subtitle: "SynoMusic for Apple TV")
                Text("服务器".t).font(.title2.bold())
                ForEach(servers.profiles) { profile in
                    Button { Task { await library.connect(profile, password: "", servers: servers, playlists: playlists) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) { Text(profile.name).font(.system(size: 27, weight: .semibold)); Text(profile.displayURL).font(.system(size: 20)).foregroundStyle(.secondary) }
                            Spacer()
                            if library.client?.profile.id == profile.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(TVStyle.accent) }
                        }.padding(12).foregroundStyle(.white)
                    }.buttonStyle(TVCardStyle()).disabled(library.isLoading)
                        .contextMenu { Button("编辑".t) { editing = profile }; Button("移除".t, role: .destructive) { deleting = profile } }
                }
                HStack(spacing: 28) {
                    Button("添加服务器".t) { addServer = true }
                    Button("刷新资料库".t) { Task { await library.refresh() } }.disabled(library.client == nil || library.isLoading)
                    Button("体验演示资料库".t) { library.useDemo(playlists: playlists) }
                }
                if library.isLoading { ProgressView("正在连接...".t) }
                if let error = library.error { Text(error).foregroundStyle(.orange).font(.system(size: 23)) }
                if library.libraries.count > 1, let profile = library.client?.profile {
                    Picker("音乐库".t, selection: Binding(get: { profile.musicLibraryID ?? library.libraries.first?.id ?? "" }, set: { id in
                        var next = profile; next.musicLibraryID = id; next.musicLibraryName = library.libraries.first { $0.id == id }?.name
                        Task { await library.connect(next, password: "", servers: servers, playlists: playlists) }
                    })) { ForEach(library.libraries) { Text($0.name).tag($0.id) } }
                }
                Divider().padding(.vertical, 10)
                Text("播放".t).font(.title2.bold())
                Picker("音质".t, selection: $playback.quality) { ForEach(AudioQuality.allCases) { Text($0.titleKey.t).tag($0) } }
                    .onChange(of: playback.quality) { _, quality in UserDefaults.standard.set(quality.rawValue, forKey: "tv.quality") }
                Text("音质设置对下一首歌曲生效。".t).font(.system(size: 20)).foregroundStyle(.secondary)
                Picker("播放速度".t, selection: Binding(get: { playback.speed }, set: { playback.setSpeed($0) })) { ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { Text("\($0.formatted())×").tag($0) } }
                Picker("睡眠定时".t, selection: Binding(get: { playback.sleepMinutes }, set: { playback.sleep(after: $0) })) { Text("关闭".t).tag(0); ForEach([15, 30, 60, 90], id: \.self) { Text("\($0) " + "分钟".t).tag($0) } }
                Toggle("在线歌词".t, isOn: $playback.onlineLyrics).onChange(of: playback.onlineLyrics) { _, value in UserDefaults.standard.set(value, forKey: "tv.onlineLyrics") }
                Text("缺少歌词时查询 LRCLIB，仅发送歌曲资料，不发送服务器凭据。".t).font(.system(size: 20)).foregroundStyle(.secondary)
                Divider().padding(.vertical, 10)
                Picker("语言".t, selection: $language.current) { ForEach(AppLanguage.allCases) { Text($0.localizedTitle).tag($0) } }
                HStack(spacing: 28) {
                    Button("官网".t) { legalLink = TVPublicLink(title: "官网", address: "https://zanwingmak.github.io/SynoMusic/") }
                    Button("隐私政策".t) { legalLink = TVPublicLink(title: "隐私政策", address: "https://zanwingmak.github.io/SynoMusic/privacy.html") }
                    Button("服务条款".t) { legalLink = TVPublicLink(title: "服务条款", address: "https://zanwingmak.github.io/SynoMusic/terms.html") }
                }
                Text("所有功能免费开放。赞助完全自愿，不解锁额外功能，也不会自动续费。".t).font(.system(size: 22)).foregroundStyle(.secondary)
                Text("SynoMusic · 1.7.0").font(.system(size: 18)).foregroundStyle(.tertiary)
            }.frame(maxWidth: 1400, alignment: .leading).padding(.horizontal, 64).padding(.bottom, 60).frame(maxWidth: .infinity)
        }.scrollClipDisabled()
        .sheet(isPresented: $addServer) { TVServerEditor().tvControls() }
        .sheet(item: $editing) { TVServerEditor(profile: $0).tvControls() }
        .sheet(item: $legalLink) { link in VStack(spacing: 32) { Text(link.title.t).font(.title); TVQRCode(text: link.address).frame(width: 300, height: 300); Text(link.address).font(.system(size: 24)); Text("用手机扫描二维码打开".t).foregroundStyle(.secondary); Button("完成".t) { legalLink = nil } }.padding(60).tvControls() }
        .confirmationDialog("移除服务器".t, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("移除".t, role: .destructive) { if let profile = deleting { if library.client?.profile.id == profile.id { Task { await library.disconnect() } }; servers.remove(profile) }; deleting = nil }
            Button("取消".t, role: .cancel) { deleting = nil }
        }
    }
}

/// 外部链接只展示公开页面地址，二维码中不包含 NAS 账号、口令或会话。
private struct TVPublicLink: Identifiable { let title: String; let address: String; var id: String { address } }

/// 原生 Core Image 生成清晰二维码，电视端不依赖浏览器或第三方图片服务。
struct TVQRCode: View {
    let text: String
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().interpolation(.none).scaledToFit() } else { Image(systemName: "qrcode") } }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(text.utf8)
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// 六种音乐源共用手机已有的登录实现；可用 iPhone 系统键盘辅助输入。
struct TVServerEditor: View {
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var servers: ServerStore
    @EnvironmentObject private var playlists: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    var profile: ServerProfile?
    @State private var provider = MusicProviderType.synologyAudioStation
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var otp = ""
    @State private var quickConnect = ""
    @State private var libraryID = ""
    @State private var trustCertificate = false
    @State private var error: String?
    @State private var showPlex = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TVHeading(title: (profile == nil ? "添加服务器" : "编辑服务器").t)
                Picker("协议".t, selection: $provider) { ForEach(MusicProviderType.allCases) { Text($0 == .synologyAudioStation ? "Synology" : $0.titleKey).tag($0) } }
                if provider == .plex { Button("登录 Plex".t) { showPlex = true } }
                TextField("名称".t, text: $name)
                TVServerField(title: "服务器地址".t, text: $address, contentType: .URL).frame(height: 72)
                TVServerField(title: "账号".t, text: $username, contentType: .username).frame(height: 72)
                TVServerField(title: "密码 / 访问令牌".t, text: $password, contentType: .password, secure: true).frame(height: 72)
                if provider == .synologyAudioStation {
                    TVServerField(title: "二步验证码（OTP）".t, text: $otp, contentType: .oneTimeCode, keyboard: .numberPad).frame(height: 72)
                    TVServerField(title: "QuickConnect ID", text: $quickConnect).frame(height: 72)
                }
                TVServerField(title: "音乐库 ID / 共享路径（可选）".t, text: $libraryID).frame(height: 72)
                Toggle("信任自签名证书".t, isOn: $trustCertificate)
                if library.isLoading { ProgressView("正在连接...".t) }
                if let message = error ?? library.error { Text(message).font(.system(size: 23)).foregroundStyle(.orange) }
                HStack(spacing: 28) {
                    Button("连接".t) { Task { await connect() } }.disabled(library.isLoading || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quickConnect.isEmpty)
                    Button("取消".t) { dismiss() }.disabled(library.isLoading)
                }
            }.frame(maxWidth: 1150, alignment: .leading).padding(70).frame(maxWidth: .infinity)
        }
        .onAppear {
            guard let profile else { return }
            provider = profile.providerType; name = profile.name; address = "\(profile.scheme.rawValue)://\(profile.host):\(profile.port)"; username = profile.username; quickConnect = profile.quickConnectID; libraryID = profile.musicLibraryID ?? ""; trustCertificate = profile.ignoreInvalidCertificate
        }
        .sheet(isPresented: $showPlex) { TVPlexLinkView().tvControls() }
    }

    /// 校验地址并构造配置，密码只交给原生登录和 Keychain。
    private func connect() async {
        error = nil
        let raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw.contains("://") ? raw : "https://" + raw
        let components = URLComponents(string: value)
        let usesQC = provider == .synologyAudioStation && !quickConnect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard usesQC || components?.host?.isEmpty == false else { error = "请输入有效的服务器地址。".t; return }
        let scheme = components?.scheme == "http" ? ServerProfile.Scheme.http : .https
        let port = components?.port ?? (provider == .smb ? 445 : scheme == .https ? 443 : 80)
        let path = libraryID.isEmpty && (provider == .webDAV || provider == .smb) ? components?.path : libraryID
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = usesQC ? quickConnect : components?.host ?? ""
        let next = ServerProfile(id: profile?.id ?? UUID(), providerType: provider, name: displayName.isEmpty ? host : displayName, scheme: usesQC ? .https : scheme, host: host, port: usesQC ? 5001 : port, username: username, ignoreInvalidCertificate: trustCertificate, isQuickConnect: usesQC, quickConnectID: quickConnect, musicLibraryID: path?.isEmpty == false ? path : nil)
        await library.connect(next, password: password, otp: otp, servers: servers, playlists: playlists)
        if library.client?.profile.id == next.id && library.error == nil { dismiss() }
    }
}

/// Plex 通过官方 PIN 在手机上授权，电视只接收官方返回的服务器列表。
private struct TVPlexLinkView: View {
    @EnvironmentObject private var library: TVLibraryStore
    @EnvironmentObject private var servers: ServerStore
    @EnvironmentObject private var playlists: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    @State private var pin: PlexAuthPin?
    @State private var account: PlexAccountInfo?
    @State private var foundServers: [PlexDiscoveredServer] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                TVHeading(title: "登录 Plex".t)
                if let message = error ?? library.error { Text(message).foregroundStyle(.orange) }
                else if let account {
                    Text("发现服务器".t).font(.title2)
                    serverChoices(account: account)
                    if foundServers.isEmpty { Text("没有发现可用的音乐服务器。".t) }
                } else if let pin {
                    HStack(spacing: 60) {
                        TVQRCode(text: pin.authURL.absoluteString).frame(width: 280, height: 280)
                        VStack(alignment: .leading, spacing: 24) { Text(pin.code).font(.system(size: 70, weight: .bold, design: .monospaced)); Text("用手机扫描二维码完成 Plex 授权。".t).font(.title3); Text("plex.tv/link").foregroundStyle(.secondary) }
                    }
                    ProgressView("等待授权…".t)
                } else { ProgressView() }
                Button("返回".t) { dismiss() }
            }.padding(70)
        }.task { await authorize() }
    }

    /// 将连接选择拆分为小视图，保持原生焦点按钮并减少视图类型推断复杂度。
    private func serverChoices(account: PlexAccountInfo) -> some View {
        ForEach(foundServers) { server in
            ForEach(server.connections) { connection in
                Button("\(server.name) · \(connection.labelKey.t)") {
                    Task { await connect(account: account, server: server, connection: connection) }
                }.disabled(library.isLoading)
            }
        }
    }

    /// 只连接用户明确选择的官方发现地址，并复用已有安全凭据保存流程。
    private func connect(account: PlexAccountInfo, server: PlexDiscoveredServer, connection: PlexServerConnection) async {
        let base = ServerProfile(providerType: .plex, name: server.name, host: connection.host, port: connection.port, username: account.username)
        let profile = PlexAccountService.makeProfile(from: base, account: account, server: server, connection: connection)
        let credential = PlexAccountService.makeCredential(accountToken: account.authToken, serverToken: server.token)
        await library.connect(profile, password: credential, servers: servers, playlists: playlists)
        if library.error == nil { dismiss() }
    }

    /// PIN 轮询随页面销毁取消，并尊重官方返回的过期时间。
    private func authorize() async {
        do {
            let pin = try await PlexAccountService.createPin(); self.pin = pin
            for _ in 0..<150 {
                try Task.checkCancellation()
                if let expires = pin.expiresAt, expires < Date() { throw URLError(.timedOut) }
                if let account = try await PlexAccountService.checkPin(pin) { self.account = account; foundServers = try await PlexAccountService.fetchServers(account: account); return }
                try await Task.sleep(for: .seconds(2))
            }
            error = "授权已过期，请返回后重试。".t
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
