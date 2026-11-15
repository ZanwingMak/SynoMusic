import SwiftUI
import UIKit

/// 连接字段显式关闭智能标点，防止系统输入法改写地址、下划线或访问令牌。
struct TVServerField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .asciiCapable
    var secure = false

    /// 使用系统电视文本框保留遥控器焦点、iPhone 键盘和安全密码输入。
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = title
        field.accessibilityLabel = title
        field.textContentType = contentType
        field.keyboardType = keyboard
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .done
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 28)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    /// 不覆盖正在组词的文本；语言切换时同步字段提示。
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        field.placeholder = title
        field.accessibilityLabel = title
        if !field.isFirstResponder && field.markedTextRange == nil && field.text != text { field.text = text }
    }

    /// 文本变化通过绑定交还原生连接表单，不另存凭据。
    func makeCoordinator() -> Coordinator { Coordinator($text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        /// 保留当前绑定，避免表单更新后写入过期状态。
        init(_ text: Binding<String>) { self.text = text }

        /// 接收系统键盘的完整字符串，不修剪或替换口令字符。
        @objc func changed(_ field: UITextField) { text.wrappedValue = field.text ?? "" }

        /// 完成输入后返回服务器表单，遥控器继续选择下一项。
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            changed(textField)
            textField.resignFirstResponder()
            return true
        }
    }
}
