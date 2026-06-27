import SwiftUI

/// 主框架底部 Tab。
enum MainTab: Hashable {
    case library
    case browse
    case search
    case settings
}

/// 设置页可被外部直达的子页面。
enum SettingsRoute: Hashable {
    case downloads
    case login(ServerProfile)
    case widgets
    case localImports
}

/// App 内部导航状态：让全屏播放器等浮层可以请求切换 Tab 或进入设置子页。
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: MainTab
    @Published var browsePath = NavigationPath()
    @Published var settingsPath = NavigationPath()
    @Published var addServerRequestID: UUID?

    /// 按调试启动参数决定初始 Tab，普通启动默认进入资料库。
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-tab=browse") {
            selectedTab = .browse
        } else if args.contains("-tab=search") {
            selectedTab = .search
        } else if args.contains("-tab=settings") {
            selectedTab = .settings
        } else {
            selectedTab = .library
        }
        #else
        selectedTab = .library
        #endif
    }

    /// 切到设置页并打开下载管理。
    func openDownloads() {
        selectedTab = .settings
        settingsPath = NavigationPath()
        settingsPath.append(SettingsRoute.downloads)
    }

    /// 切到设置页并打开小组件管理。
    func openWidgets() {
        selectedTab = .settings
        settingsPath = NavigationPath()
        settingsPath.append(SettingsRoute.widgets)
    }

    /// 切到设置页并打开本地音乐导入。
    func openLocalImports() {
        selectedTab = .settings
        settingsPath = NavigationPath()
        settingsPath.append(SettingsRoute.localImports)
    }

    /// 切到设置页并请求打开添加服务器表单。
    func openAddServer() {
        selectedTab = .settings
        settingsPath = NavigationPath()
        addServerRequestID = UUID()
    }

    /// 消费添加服务器请求，避免设置页重新出现时重复弹出表单。
    func consumeAddServerRequest() {
        addServerRequestID = nil
    }

    /// 切到浏览页并打开智能歌单。
    func openSmartMixes() {
        selectedTab = .browse
        browsePath = NavigationPath()
        browsePath.append(BrowseRoute.smartMixes)
    }

    /// 切到设置页并打开指定服务器的手动登录页。
    func openLogin(for profile: ServerProfile) {
        selectedTab = .settings
        settingsPath.append(SettingsRoute.login(profile))
    }
}
