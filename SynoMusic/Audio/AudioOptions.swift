import Foundation

/// 重复模式。
enum RepeatMode: String, CaseIterable, Sendable {
    case off, all, one
}

/// 音质设置。
enum AudioQuality: String, CaseIterable, Identifiable, Sendable {
    case original     // raw 流，不转码
    case high         // 320 kbps mp3
    case standard     // 128 kbps mp3

    var id: String { rawValue }

    /// 用于内置多语言查表的中文标题 key。
    var titleKey: String {
        switch self {
        case .original: return "原始音质"
        case .high: return "高品质 320kbps"
        case .standard: return "标准 128kbps"
        }
    }

    var title: String {
        titleKey
    }

    /// 对应 streamURL 的 format 参数。
    var streamFormat: String {
        switch self {
        case .original: return "raw"
        case .high: return "mp3"
        case .standard: return "mp3"
        }
    }
}
