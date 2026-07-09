import Foundation
import AVFoundation
import UIKit

/// 播放器封面展示样式。
enum PlayerArtworkStyle: String, CaseIterable, Identifiable {
    case cover
    case vinyl

    var id: String { rawValue }

    /// 设置页展示标题。
    var titleKey: String {
        switch self {
        case .cover: return "方形封面"
        case .vinyl: return "黑胶唱片"
        }
    }
}

/// 均衡器预设；当前用于保存用户偏好，后续可接入更完整的音频引擎。
enum EqualizerPreset: String, CaseIterable, Identifiable {
    case flat
    case bass
    case vocal
    case bright
    case night

    var id: String { rawValue }

    /// 设置页展示标题。
    var titleKey: String {
        switch self {
        case .flat: return "均衡器：关闭"
        case .bass: return "低音增强"
        case .vocal: return "人声突出"
        case .bright: return "清亮高频"
        case .night: return "夜间柔和"
        }
    }
}

/// 可同步的播放偏好快照；只保存用户偏好，不保存实时播放状态。
struct PlaybackSettingsSnapshot: Codable, Hashable {
    var backgroundPlaybackEnabled: Bool
    var playerArtworkStyle: String
    var crossfadeEnabled: Bool
    var crossfadeDuration: Double
    var equalizerPreset: String
}

/// 播放相关偏好开关：后台播放 / 锁屏控制 / AirPlay。
/// 全部持久化到 UserDefaults，并对 AVAudioSession 实时生效。
@MainActor
final class PlaybackSettings: ObservableObject {
    @Published var backgroundPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundPlaybackEnabled, forKey: bgKey)
            UserDefaults.standard.synchronize()
            applyAudioSession()
        }
    }
    @Published private(set) var lockScreenControlsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(lockScreenControlsEnabled, forKey: lockKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published private(set) var airPlayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(airPlayEnabled, forKey: airKey)
            UserDefaults.standard.synchronize()
            applyAudioSession()
        }
    }
    @Published var playerArtworkStyle: PlayerArtworkStyle {
        didSet {
            UserDefaults.standard.set(playerArtworkStyle.rawValue, forKey: artworkStyleKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var crossfadeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(crossfadeEnabled, forKey: crossfadeEnabledKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var crossfadeDuration: Double {
        didSet {
            crossfadeDuration = crossfadeDuration.clamped(to: 1...8, defaultValue: 3)
            UserDefaults.standard.set(crossfadeDuration, forKey: crossfadeDurationKey)
            UserDefaults.standard.synchronize()
        }
    }
    @Published var equalizerPreset: EqualizerPreset {
        didSet {
            UserDefaults.standard.set(equalizerPreset.rawValue, forKey: equalizerPresetKey)
            UserDefaults.standard.synchronize()
        }
    }

    private let bgKey = "syno.playback.background"
    private let lockKey = "syno.playback.lockscreen"
    private let airKey = "syno.playback.airplay"
    private let artworkStyleKey = "syno.playback.artworkStyle"
    private let crossfadeEnabledKey = "syno.playback.crossfade.enabled"
    private let crossfadeDurationKey = "syno.playback.crossfade.duration"
    private let equalizerPresetKey = "syno.playback.equalizer.preset"

    init() {
        let defaults = UserDefaults.standard
        self.backgroundPlaybackEnabled = defaults.object(forKey: bgKey) as? Bool ?? true
        self.lockScreenControlsEnabled = true
        self.airPlayEnabled = true
        self.playerArtworkStyle = PlayerArtworkStyle(rawValue: defaults.string(forKey: artworkStyleKey) ?? "") ?? .cover
        self.crossfadeEnabled = defaults.object(forKey: crossfadeEnabledKey) as? Bool ?? false
        self.crossfadeDuration = defaults.double(forKey: crossfadeDurationKey).clamped(to: 1...8, defaultValue: 3)
        self.equalizerPreset = EqualizerPreset(rawValue: defaults.string(forKey: equalizerPresetKey) ?? "") ?? .flat
        defaults.set(true, forKey: lockKey)
        defaults.set(true, forKey: airKey)
    }

    /// 导出可同步的播放偏好。
    func snapshot() -> PlaybackSettingsSnapshot {
        PlaybackSettingsSnapshot(
            backgroundPlaybackEnabled: backgroundPlaybackEnabled,
            playerArtworkStyle: playerArtworkStyle.rawValue,
            crossfadeEnabled: crossfadeEnabled,
            crossfadeDuration: crossfadeDuration,
            equalizerPreset: equalizerPreset.rawValue
        )
    }

    /// 应用云端播放偏好，并通过既有 didSet 逻辑落盘。
    func applySnapshot(_ snapshot: PlaybackSettingsSnapshot) {
        backgroundPlaybackEnabled = snapshot.backgroundPlaybackEnabled
        playerArtworkStyle = PlayerArtworkStyle(rawValue: snapshot.playerArtworkStyle) ?? .cover
        crossfadeEnabled = snapshot.crossfadeEnabled
        crossfadeDuration = snapshot.crossfadeDuration
        equalizerPreset = EqualizerPreset(rawValue: snapshot.equalizerPreset) ?? .flat
    }

    /// 根据当前开关重新配置 AVAudioSession。
    func applyAudioSession() {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        options.insert(.allowAirPlay)
        options.insert(.allowBluetoothA2DP)
        do {
            try session.setCategory(
                backgroundPlaybackEnabled ? .playback : .ambient,
                mode: .default,
                options: options
            )
            try session.setActive(true, options: [])
        } catch {
            // 静默：失败时仍能前台播放
        }
    }
}

private extension Double {
    /// 将数值限制在闭区间内，首次读取 0 时使用业务默认值。
    func clamped(to range: ClosedRange<Double>, defaultValue: Double) -> Double {
        let value = self == 0 ? defaultValue : self
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
