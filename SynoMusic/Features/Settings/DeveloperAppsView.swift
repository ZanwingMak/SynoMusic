import SwiftUI

/// 用户主动进入的作品推荐页，图标与简介离线可见，不影响音乐播放。
struct DeveloperAppsView: View {
    @EnvironmentObject private var language: LanguageManager
    #if os(tvOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedApp: DeveloperApp?
    #endif

    var body: some View {
        #if os(tvOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack {
                    Text("更多作品".t).font(.title.bold())
                    Spacer()
                    Button("完成".t) { dismiss() }
                }
                Text("同一位开发者，用心做的其他 App。".t).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), spacing: 32)], spacing: 32) {
                    ForEach(DeveloperAppCatalog.availableApps) { app in
                        Button { selectedApp = app } label: { appLabel(app) }
                            .buttonStyle(TVCardStyle())
                    }
                }
            }.padding(64)
        }
        .sheet(item: $selectedApp) { app in
            VStack(spacing: 28) {
                Image(app.icon).resizable().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 22))
                Text(app.name).font(.title.bold())
                Text(app.description(language: language.current.lookupCode)).foregroundStyle(.secondary)
                Button("在 App Store 查看".t) { openURL(app.storeURL) }
                Text("在 Apple TV 的 App Store 搜索".t + "：" + app.name).font(.system(size: 22))
                TVQRCode(text: app.storeURL.absoluteString).frame(width: 200, height: 200)
                Text("用手机扫描二维码打开".t).font(.system(size: 20)).foregroundStyle(.secondary)
                Button("完成".t) { selectedApp = nil }
            }.padding(48).tvControls()
        }
        #else
        List {
            Section {
                ForEach(DeveloperAppCatalog.availableApps) { app in
                    Link(destination: app.storeURL) { appLabel(app) }
                        .accessibilityHint("在 App Store 查看".t)
                }
            } header: {
                Text("同一位开发者，用心做的其他 App。".t).textCase(nil)
            }
        }
        .navigationTitle("更多作品".t)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// 图标、简介与平台各自保留可读空间，辅助字号可自然换行。
    private func appLabel(_ app: DeveloperApp) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(app.icon)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 13)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(app.name).font(.headline).foregroundStyle(.primary)
                Text(app.description(language: language.current.lookupCode))
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(app.platformLabel).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(.vertical, 10).frame(minHeight: 64).contentShape(Rectangle())
    }

    /// 电视端使用更大的真实图标，以便远距离识别。
    private var iconSize: CGFloat {
        #if os(tvOS)
        80
        #else
        56
        #endif
    }
}
