import SwiftUI
import NaruRemoteCore

/// Modifier key button for the Direct-mode special-keys page.
///
/// Renders the three-state sticky-modifier UX (idle / armed /
/// locked) using system-color tokens so dark and light modes both
/// read correctly.  Per the constitution feedback note —
/// `feedback_phase9_keyboard_is_ship_blocker` — visible color
/// difference is the indicator, not just text.  Each state is
/// distinct in:
///
/// - **fill colour** (`Color(.systemGray5)` idle, `accentColor`
///   tinted armed, solid `accentColor` locked)
/// - **stroke** (no stroke idle, accent-coloured stroke armed,
///   double-stroke + filled badge locked)
/// - **foreground** (`.primary` idle/armed, `.white` on the
///   tinted locked fill so the glyph still reads)
/// - **a small status badge** ("•" armed, "⏼" locked) so the
///   state is unambiguous in screenshots and to assistive tech.
///
/// Accessibility: `accessibilityLabel` announces the modifier
/// kind and the slot state ("Control modifier, armed").  The
/// `accessibilityValue` reflects the slot string so VoiceOver
/// users hear state changes when tapping the same button twice.
struct ModifierKeyButton: View {

    let label: String
    let modifier: StickyModifierState.Modifier
    let slot: StickyModifierState.SlotState
    let widthUnits: CGFloat
    let unitWidth: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Body fill
                RoundedRectangle(cornerRadius: 6)
                    .fill(fillColor)

                // Border / stroke distinguishes armed from idle
                // even when the user is in light mode where the
                // accent tint is subtle.
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)

                // Inner double-line on locked, for unambiguous
                // visual difference vs armed at a glance.
                if slot == .locked {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                        .padding(2)
                }

                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(foregroundStyle)
                    statusBadge
                }
                .padding(.vertical, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: widthUnits * unitWidth)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(slot.rawValue)
        .accessibilityIdentifier("naru.direct.modifier.\(modifier.rawValue).\(slot.rawValue)")
    }

    // MARK: - Visual tokens (system-coloured for dark+light)

    private var fillColor: Color {
        switch slot {
        case .idle:
            #if canImport(UIKit)
            return Color(.systemGray5)
            #else
            return Color.gray.opacity(0.18)
            #endif
        case .armed:
            return Color.accentColor.opacity(0.32)
        case .locked:
            return Color.accentColor
        }
    }

    private var strokeColor: Color {
        switch slot {
        case .idle:
            #if canImport(UIKit)
            return Color(.separator)
            #else
            return Color.gray.opacity(0.30)
            #endif
        case .armed:
            return Color.accentColor
        case .locked:
            return Color.accentColor
        }
    }

    private var strokeWidth: CGFloat {
        switch slot {
        case .idle:   return 0.5
        case .armed:  return 2.0
        case .locked: return 2.0
        }
    }

    private var foregroundStyle: Color {
        switch slot {
        case .idle, .armed:
            return Color.primary
        case .locked:
            return Color.white
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch slot {
        case .idle:
            // Reserve same vertical space so the label doesn't
            // jump when armed/locked appears.
            Text(" ")
                .font(.system(size: 8))
                .foregroundStyle(Color.clear)
        case .armed:
            Text("•")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentColor)
        case .locked:
            Text("LOCK")
                .font(.system(size: 7, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Color.white)
        }
    }

    private var accessibilityLabelText: String {
        let stateText: String
        switch slot {
        case .idle:   stateText = "idle"
        case .armed:  stateText = "armed"
        case .locked: stateText = "locked"
        }
        return "\(modifierName) modifier, \(stateText)"
    }

    private var modifierName: String {
        switch modifier {
        case .control: return "Control"
        case .shift:   return "Shift"
        case .alt:     return "Alt"
        case .meta:    return "Command"
        }
    }
}
