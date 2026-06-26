import WidgetKit
import SwiftUI

/// Widget Extension 入口：承载 Live Activity 和快捷小组件。
@main
struct SynoMusicLiveBundle: WidgetBundle {
    var body: some Widget {
        SynoMusicLiveActivity()
        SynoMusicQuickWidget()
    }
}
