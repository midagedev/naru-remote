#if canImport(UIKit)
import SwiftUI
import UIKit

/// Invisible UIKit view that becomes first responder while Direct
/// mode is active.  Because it does NOT conform to `UITextInput`,
/// iOS does not present its system keyboard — which is exactly the
/// behavior we want when the custom soft keyboard is on screen
/// (FR-001 / `research.md` R-3).
///
/// Phase 5 will extend this same view (or a sibling) to capture
/// hardware keyboard `UIPress` events; Phase 3 only needs the
/// firstResponder side-effect.
struct DirectKeystrokeResponderView: UIViewRepresentable {
    let isActive: Bool

    func makeUIView(context: Context) -> ResponderView {
        ResponderView()
    }

    func updateUIView(_ view: ResponderView, context: Context) {
        if isActive {
            if !view.isFirstResponder {
                _ = view.becomeFirstResponder()
            }
        } else if view.isFirstResponder {
            _ = view.resignFirstResponder()
        }
    }

    final class ResponderView: UIView {
        override var canBecomeFirstResponder: Bool { true }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
#endif
