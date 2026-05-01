#if canImport(UIKit)
import SwiftUI
import UIKit
import NaruRemoteCore

/// Invisible UIKit view that becomes first responder while Direct
/// mode is active and serves two purposes:
///
/// 1. **iOS-keyboard suppression** — because this view does NOT
///    conform to `UITextInput`, iOS does not present its system
///    keyboard while it is first responder.  This is the FR-001 /
///    R-3 mechanism that hides the iOS keyboard when the custom
///    soft keyboard is on screen.
/// 2. **Hardware-keyboard capture** — overrides
///    `pressesBegan(_:with:)` and `pressesEnded(_:with:)` to receive
///    raw `UIPress` events from a Bluetooth / Magic Keyboard.  Each
///    press's `keyCode` (`UIKeyboardHIDUsage`) is mapped through
///    `KeysymMapping+UIKit` and routed to the `onHardwareKey`
///    closure.
///
/// One composite view handles both jobs so the firstResponder chain
/// is unambiguous — there is exactly one responder for the input
/// dock, not two competing ones (`research.md` R-3 + R-2).
///
/// Phase 5 / US-3 / T032.  `onHardwareKey` is closure-injected
/// (mirroring the on-screen `onTapKey` pattern) so this view does
/// not hold a strong reference to `NaruRemoteAppModel`.
struct DirectKeystrokeResponderView: UIViewRepresentable {
    let isActive: Bool
    /// Called for every hardware-keyboard press / release while
    /// `isActive == true` and the press maps to an X11 keysym
    /// (unmapped keys — Globe, Dictation — are dropped silently per
    /// FR-015).  `isDown == true` for `pressesBegan`, `false` for
    /// `pressesEnded`.
    let onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void

    init(
        isActive: Bool,
        onHardwareKey: @escaping (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void = { _, _, _ in }
    ) {
        self.isActive = isActive
        self.onHardwareKey = onHardwareKey
    }

    func makeUIView(context: Context) -> ResponderView {
        let view = ResponderView()
        view.onHardwareKey = onHardwareKey
        return view
    }

    func updateUIView(_ view: ResponderView, context: Context) {
        // Keep the closure pointer fresh — SwiftUI re-creates the
        // representable on every state change, so a stale closure
        // captured at `makeUIView` time would otherwise hold a
        // stale model snapshot.
        view.onHardwareKey = onHardwareKey

        if isActive {
            if !view.isFirstResponder {
                _ = view.becomeFirstResponder()
            }
        } else if view.isFirstResponder {
            _ = view.resignFirstResponder()
        }
    }

    final class ResponderView: UIView {
        var onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void = { _, _, _ in }

        override var canBecomeFirstResponder: Bool { true }

        override init(frame: CGRect) {
            super.init(frame: frame)
            // The view itself is never tappable (the SwiftUI
            // representable parents it at `frame: 0×0`); leaving
            // `isUserInteractionEnabled = true` is required for
            // `pressesBegan` / `pressesEnded` to fire — UIKit drops
            // press events on views with interaction disabled.
            isUserInteractionEnabled = true
            isHidden = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: - Hardware keyboard capture (`research.md` R-2)

        override func pressesBegan(
            _ presses: Set<UIPress>,
            with event: UIPressesEvent?
        ) {
            for press in presses {
                guard let key = press.key else {
                    super.pressesBegan(presses, with: event)
                    continue
                }
                guard let keysym = KeysymMapping.keysym(forUIKeyCode: key.keyCode) else {
                    // FR-015 — drop silently; let the OS handle
                    // the press (Globe, Dictation, etc.) by
                    // forwarding to super.
                    super.pressesBegan([press], with: event)
                    continue
                }
                let modifiers = KeysymMapping.modifiers(fromUIKeyModifierFlags: key.modifierFlags)
                onHardwareKey(keysym, modifiers, true)
            }
        }

        override func pressesEnded(
            _ presses: Set<UIPress>,
            with event: UIPressesEvent?
        ) {
            for press in presses {
                guard let key = press.key else {
                    super.pressesEnded(presses, with: event)
                    continue
                }
                guard let keysym = KeysymMapping.keysym(forUIKeyCode: key.keyCode) else {
                    super.pressesEnded([press], with: event)
                    continue
                }
                let modifiers = KeysymMapping.modifiers(fromUIKeyModifierFlags: key.modifierFlags)
                onHardwareKey(keysym, modifiers, false)
            }
        }
    }
}
#endif
