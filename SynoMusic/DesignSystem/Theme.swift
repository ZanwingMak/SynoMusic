import SwiftUI

/// 主题命名空间：集中维护颜色、圆角、阴影与渐变规范。
/// 强调色从 ThemeManager.shared.current 读取，可由用户在设置里切换。
@MainActor
enum Theme {
    // MARK: Colors

    /// 主强调色：用于按钮高亮、进度条、当前播放指示。
    /// 因为 SwiftUI 视图层级里 Color 是惰性求值，这里返回的是当前帧的快照；
    /// ThemeManager 是 @Published，切换主题时使用 Theme.accent 的视图都会重渲染。
    static var accent: Color {
        ThemeManager.shared.current.accent(in: .dark)
    }

    /// 应用基底背景：在 Light 下接近暖白，Dark 下接近深炭。
    static let background = Color("Brand")

    /// 表层背景：卡片、列表行；半透明叠加在 background 上。
    static var surface: Color {
        Color.primary.opacity(0.04)
    }

    /// 主文本色。
    static let textPrimary: Color = .primary

    /// 次级文本色：副标题、辅助信息。
    static let textSecondary: Color = .secondary

    // MARK: Shapes

    /// 通用卡片圆角。
    static let cornerCard: CGFloat = 18

    /// 大圆角：用于全屏播放器封面与超大卡片。
    static let cornerHero: CGFloat = 28

    /// 胶囊圆角：按钮、芯片、迷你播放器。
    static let cornerPill: CGFloat = 999

    // MARK: Gradients

    /// 主品牌渐变：用于强调按钮和动效背景。
    static var accentGradient: LinearGradient {
        ThemeManager.shared.current.gradient
    }

    /// 全屏播放器背景晕染基色。
    static func ambient(from color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.65), color.opacity(0.15), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// 通用尺寸常量，避免魔法数字。
enum Metrics {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// 迷你播放器高度。
    static let miniPlayerHeight: CGFloat = 64

    /// 迷你播放器相对屏幕底部的原始悬浮距离，用于贴近 TabBar 上方。
    static let miniPlayerBottomOffset: CGFloat = 52

    /// 滚动内容需要为迷你播放器预留的底部空间。
    static let miniPlayerReservedHeight: CGFloat = miniPlayerHeight + miniPlayerBottomOffset + 12

    /// 列表行最小高度（满足 44pt 触控要求）。
    static let listRowMin: CGFloat = 56
}
