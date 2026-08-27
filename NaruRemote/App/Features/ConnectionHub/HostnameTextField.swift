import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

/// A text field for machine text: a hostname, a MagicDNS name, an address.
///
/// Spec 039 FR-004. Two things have to be true at once and no `keyboardType`
/// delivers both:
///
/// - The **layout** must carry `.` and `/` on the plane that opens, because a
///   hostname is mostly separators. `.URL` does; `.asciiCapable` does not — it
///   opens a bare alphabet, measured, and turns `studio.tailnet.ts.net` into
///   twelve extra taps switching to the numbers plane and back.
/// - The **language** must be Latin. `keyboardType` does not decide that; the
///   user's last-used input mode does. On a Korean-first phone the URL keyboard
///   is the Korean keyboard with `.com` bolted on.
///
/// So: `.URL` for the layout, and `textInputMode` overridden for the language.
/// That override is the only API iOS offers for "this field cannot accept
/// anything but ASCII, please open somewhere that can produce it", and it needs
/// a `UITextField` to live on.
///
/// The globe key stays. Pinning the *initial* mode is the whole intent; a user
/// who wants another keyboard in this field can still ask for one.
struct HostnameTextField: View {
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String
    /// Mirrors the editor's `@FocusState` so the form can still open with the
    /// cursor here. A `UIViewRepresentable` does not participate in SwiftUI
    /// focus, so the two are bridged explicitly rather than by `.focused()`.
    var isFocused: Bool = false
    /// Called when the field takes focus by tap, so the editor's focus state
    /// follows the user rather than only the other way round.
    var onFocusGained: () -> Void = {}
    /// Called when editing ends, which is what marks the field "visited" and
    /// lets its inline error caption appear.
    var onEditingEnded: () -> Void = {}

    var body: some View {
        #if os(iOS) && canImport(UIKit)
        LatinFirstTextField(
            placeholder: placeholder,
            text: $text,
            accessibilityIdentifier: accessibilityIdentifier,
            isFocused: isFocused,
            onFocusGained: onFocusGained,
            onEditingEnded: onEditingEnded
        )
        #else
        TextField(placeholder, text: $text)
            .autocorrectionDisabled()
            .accessibilityIdentifier(accessibilityIdentifier)
        #endif
    }
}

#if os(iOS) && canImport(UIKit)

private struct LatinFirstTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String
    let isFocused: Bool
    let onFocusGained: () -> Void
    let onEditingEnded: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = LatinFirstUITextField()
        field.placeholder = placeholder
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        // Dynamic Type, which the SwiftUI `TextField` this replaces had for
        // free and a bare `UITextField` does not.
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.accessibilityIdentifier = accessibilityIdentifier
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        // A `Form` row gives the field its width; without this the intrinsic
        // content size fights the row on a narrow phone.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onFocusGained = onFocusGained
        context.coordinator.onEditingEnded = onEditingEnded
        // Only write when the model genuinely diverges: assigning `text` while
        // the user is mid-edit moves the caret to the end.
        if field.text != text {
            field.text = text
        }
        // Focus is driven one way only — into the field. Resigning from here
        // as well would let a stale `isFocused` snatch the keyboard back from
        // whatever the user tapped next.
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocusGained: onFocusGained,
            onEditingEnded: onEditingEnded
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var onFocusGained: () -> Void
        var onEditingEnded: () -> Void

        init(
            text: Binding<String>,
            onFocusGained: @escaping () -> Void,
            onEditingEnded: @escaping () -> Void
        ) {
            self.text = text
            self.onFocusGained = onFocusGained
            self.onEditingEnded = onEditingEnded
        }

        @objc func editingChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            onFocusGained()
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
            onEditingEnded()
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}

/// The one override this whole file exists for.
private final class LatinFirstUITextField: UITextField {
    override var textInputMode: UITextInputMode? {
        Self.latinInputMode ?? super.textInputMode
    }

    /// The first installed keyboard that can produce ASCII letters, preferring
    /// English. Resolved once: `activeInputModes` changes only when the user
    /// edits their keyboard list, which cannot happen while this field is on
    /// screen.
    ///
    /// Nil when the device has no Latin keyboard at all — then `super` decides,
    /// which is the correct answer rather than a broken one: a user with only
    /// a Korean keyboard installed has to use it.
    private static let latinInputMode: UITextInputMode? = {
        let modes = UITextInputMode.activeInputModes
        if let english = modes.first(where: { ($0.primaryLanguage ?? "").hasPrefix("en") }) {
            return english
        }
        return modes.first { mode in
            guard let language = mode.primaryLanguage else { return false }
            return Locale(identifier: language).language.script?.identifier == "Latn"
        }
    }()
}

#endif
