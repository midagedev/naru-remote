import SwiftUI

/// Small "Direct mode" badge used by the dock header and the session
/// HUD.  Surface for FR-010: while Direct keystroke streaming is
/// active the user must always have a visible cue, both alongside the
/// soft keyboard and on the session HUD when the keyboard is
/// collapsed (or hidden behind a different sheet/tab).
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
/// Visual idiom matches the existing dock — system-tinted small chip
/// with a `keyboard` SF symbol so dark/light both read.  Accent
/// colour (`Color.accentColor`) ties the badge to the same hue as
/// the active sticky-modifier buttons.
///
/// Accessibility: a single combined element announces "Direct
/// keystroke mode active" so VoiceOver doesn't read the icon and
/// label as separate items.
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
                Image(systemName: "keyboard")
                    .font(.system(size: 11, weight: .semibold))
                Text("Direct mode")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.accentColor)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Direct keystroke mode active")
            .accessibilityIdentifier(accessibilityID)
        }
    }
}
