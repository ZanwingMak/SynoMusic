import AppIntents
import Foundation

/// 快捷指令和 URL 深链共用的待处理动作。
enum SynoMusicShortcutAction: String {
    case smartMixes
    case downloads

    static let pendingKey = "syno.shortcut.pendingAction"
}

/// 打开智能歌单的 Siri / 快捷指令。
struct OpenSmartMixesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Smart Mixes"
    static let description = IntentDescription("Open SynoMusic smart mixes.")
    static let openAppWhenRun: Bool = true

    /// 记录待处理动作，待 App 激活后由 RootView 读取并导航。
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(SynoMusicShortcutAction.smartMixes.rawValue, forKey: SynoMusicShortcutAction.pendingKey)
        return .result()
    }
}

/// 打开下载管理的 Siri / 快捷指令。
struct OpenDownloadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Downloads"
    static let description = IntentDescription("Open SynoMusic download manager.")
    static let openAppWhenRun: Bool = true

    /// 记录待处理动作，待 App 激活后由 RootView 读取并导航。
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(SynoMusicShortcutAction.downloads.rawValue, forKey: SynoMusicShortcutAction.pendingKey)
        return .result()
    }
}

/// SynoMusic 暴露给系统的快捷指令集合。
struct SynoMusicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSmartMixesIntent(),
            phrases: [
                "Open smart mixes in \(.applicationName)",
                "Play smart mixes in \(.applicationName)"
            ],
            shortTitle: "Smart Mixes",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: OpenDownloadsIntent(),
            phrases: [
                "Open downloads in \(.applicationName)",
                "Show downloads in \(.applicationName)"
            ],
            shortTitle: "Downloads",
            systemImageName: "arrow.down.circle"
        )
    }
}
