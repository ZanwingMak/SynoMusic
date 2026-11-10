import AppKit
import CoreText
import Foundation

/// 供宣传图脚本调用的原生文字排版参数。
private struct TextRequest: Decodable {
    let text: String
    let size: Double
    let width: Int
    let color: String
    let lineSpacing: Double
    let rightToLeft: Bool
}

/// 使用 CoreText 正确处理阿拉伯连写、双向文字和字体回退。
@main
private struct MarketingTextRenderer {
    /// 从标准输入读取文字任务，将透明 PNG 写入标准输出。
    static func main() throws {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let request = try JSONDecoder().decode(TextRequest.self, from: input)
        let font = NSFont(name: "GeezaPro-Bold", size: request.size)
            ?? NSFont.systemFont(ofSize: request.size, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = request.rightToLeft ? .right : .left
        paragraph.baseWritingDirection = request.rightToLeft ? .rightToLeft : .leftToRight
        paragraph.lineSpacing = request.lineSpacing
        let string = NSAttributedString(string: request.text, attributes: [
            .font: font,
            .foregroundColor: color(request.color),
            .paragraphStyle: paragraph
        ])
        let padding = max(8, Int(ceil(request.size * 0.12)))
        let textWidth = max(1, request.width - padding * 2)
        let measured = string.boundingRect(
            with: NSSize(width: textWidth, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = max(1, Int(ceil(measured.height)) + padding * 2)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: request.width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "SynoMusicMarketing", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create text bitmap"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        string.draw(
            with: NSRect(x: padding, y: padding, width: textWidth, height: height - padding * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SynoMusicMarketing", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot encode text bitmap"])
        }
        FileHandle.standardOutput.write(png)
    }

    /// 将六位十六进制颜色转换为 AppKit 颜色。
    private static func color(_ value: String) -> NSColor {
        let rgb = UInt32(value.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return NSColor(
            red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255,
            alpha: 1
        )
    }
}
