import SwiftUI

/// Small "Direct — IME off" badge used by the dock header.  Surface
/// for FR-010: while Direct keystroke streaming is active the user
/// must always have a visible cue.  Per UX punch-list #008 the badge
/// also has to *educate* — a returning user who turned Direct on
/// yesterday won't see the first-entry warning dialog again, so the
/// persistent badge has to call out that IME is disabled on its own.
///
/// The badge takes a Bool and renders nothing when it is false — that
/// keeps consumer call-sites tidy:
///
/// ```swift
/// DirectModeBadge(isVisible: snapshot.directKeystrokeMode.isActive)
/// ```
///
/// rather than wrapping every call in `if`.  Consumers may still
/// guard externally if they need to insert spacing only when the
/// badge is present.
///
/// Visual idiom: warning-tinted small chip with an
/// `exclamationmark.triangle.fill` SF symbol and the copy
/// "Direct — IME off".  Coral fill (`NaruColors.coral`) reads as a
/// state-warning rather than a neutral mode indicator.
///
/// Accessibility: a single combined element announces "Direct
/// keystroke mode active, IME disabled" so VoiceOver doesn't read
/// the icon and label as separate items.
struct DirectModeBadge: View {

    let isVisible: Bool
    /// Accessibility identifier passed by the caller so multiple
    /// instances (dock vs HUD) can be addressed independently from
    /// XCUITests.  Defaults to the dock identifier.
    let accessibilityID: String

    init(isVisible: Bool, accessibilityID: String = "naru.direct.badge.dock") {
        self.isVisible = isVisible
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Direct — IME off")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(NaruColors.coral)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Direct keystroke mode active, IME disabled")
            .accessibilityIdentifier(accessibilityID)
        }
    }
}
