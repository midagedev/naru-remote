#if canImport(UIKit)
import SwiftUI
import UIKit

/// Invisible first-responder bridge for the Direct-mode iOS keyboard
/// surface. Unlike `DirectKeystrokeResponderView`, this view conforms
/// to `UIKeyInput`, so UIKit presents the system keyboard and reports
/// committed ASCII text through `insertText(_:)`.
struct DirectKeystrokeSystemKeyboardView: UIViewRepresentable {
    let isActive: Bool
    let onTextInput: (String) -> Void
    let onBackspace: () -> Void

    func makeUIView(context: Context) -> TextInputView {
        let view = TextInputView()
        view.onTextInput = onTextInput
        view.onBackspace = onBackspace
        return view
    }

    func updateUIView(_ view: TextInputView, context: Context) {
        view.onTextInput = onTextInput
        view.onBackspace = onBackspace

        if isActive {
            if !view.isFirstResponder {
                _ = view.becomeFirstResponder()
            }
        } else if view.isFirstResponder {
            _ = view.resignFirstResponder()
        }
    }

    final class TextInputView: UIView, UIKeyInput {
        var onTextInput: (String) -> Void = { _ in }
        var onBackspace: () -> Void = {}

        override var canBecomeFirstResponder: Bool { true }

        var hasText: Bool { true }
        var keyboardType: UIKeyboardType = .asciiCapable
        var returnKeyType: UIReturnKeyType = .default
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var autocorrectionType: UITextAutocorrectionType = .no
        var spellCheckingType: UITextSpellCheckingType = .no
        var smartQuotesType: UITextSmartQuotesType = .no
        var smartDashesType: UITextSmartDashesType = .no
        var smartInsertDeleteType: UITextSmartInsertDeleteType = .no

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = true
            isHidden = false
            isOpaque = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func insertText(_ text: String) {
            onTextInput(text)
        }

        func deleteBackward() {
            onBackspace()
        }
    }
}
#endif
