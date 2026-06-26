import SwiftUI

// MARK: - 玻璃面板

/// 半透明毛玻璃容器：用于卡片、迷你播放器、底部条。
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = Theme.cornerCard
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - 主要按钮样式

/// 主要按钮：渐变胶囊 + 按压回弹。
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nocBody.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.accentGradient, in: Capsule(style: .continuous))
            .shadow(color: Theme.accent.opacity(0.25), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 次级按钮：描边胶囊。
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.nocBody.weight(.medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 圆形图标按钮

/// 圆形图标按钮：用于播放控制条。
struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 44
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.soft()
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(prominent ? .white : Color.primary)
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(Theme.accentGradient)
                    } else {
                        Circle().fill(Color.primary.opacity(0.08))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 完整功能徽章

/// 已购买用户的完整功能金色徽章。
struct PremiumAccessBadge: View {
    var showsText: Bool = false

    var body: some View {
        HStack(spacing: showsText ? 10 : 0) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.82, blue: 0.32),
                                Color(red: 0.96, green: 0.56, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    }
                    .shadow(color: Color.orange.opacity(0.28), radius: 8, y: 4)
                Image(systemName: "crown.fill")
                    .font(.system(size: showsText ? 16 : 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: showsText ? 34 : 30, height: showsText ? 34 : 30)

            if showsText {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完整功能已解锁".t)
                        .font(.nocBody.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("完整功能".t)
                        .font(.nocLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("完整功能已解锁".t)
    }
}

/// 顶部工具栏里的完整功能图标，使用系统符号避免 toolbar 生成方形底色。
struct PremiumToolbarIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.35),
                            Color(red: 0.98, green: 0.55, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.orange.opacity(0.28), radius: 8, y: 4)
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
            .accessibilityLabel("完整功能已解锁".t)
    }
}

// MARK: - 加载/空态/错误状态

/// 通用加载占位。
struct LoadingState: View {
    var body: some View {
        VStack(spacing: Metrics.m) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.accent)
            Text("正在加载".t)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("正在加载".t)
    }
}

/// 通用空态。
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.nocSection)
            Text(message)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metrics.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 通用错误态。
struct ErrorStateView: View {
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(title)
                .font(.nocSection)
            Text(message)
                .font(.nocCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Metrics.xl)
            if let retry {
                RetryButton(action: retry)
                    .frame(maxWidth: 200)
                    .padding(.top, Metrics.s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 带旋转 + 缩放动效的"重试"按钮。
private struct RetryButton: View {
    let action: () -> Void
    @State private var rotation: Double = 0
    @State private var pressed: Bool = false

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                rotation += 360
                pressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                pressed = false
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(rotation))
                Text("重试".t)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .scaleEffect(pressed ? 0.9 : 1)
    }
}

// MARK: - 网络封面

/// 远程加载的封面图：失败/未加载时显示渐变占位。
struct CoverArt: View {
    let url: URL?
    var cornerRadius: CGFloat = 10
    var fallbackSeed: String = ""

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.35))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                placeholderGradient
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 用种子生成稳定渐变，避免占位看起来千篇一律。
    private var placeholderGradient: some View {
        let hue = abs(Double(fallbackSeed.hashValue % 1000)) / 1000.0
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.45, brightness: 0.85),
                Color(hue: (hue + 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
