import SwiftUI
import NaruRemoteCore

/// Sticky-modifier button for the shared accessory strip (spec 011 US2).
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
///   double-stroke + filled bottom rule locked)
/// - **foreground** (`.primary` idle/armed, `.white` on the
///   tinted locked fill so the glyph still reads)
/// - **a small status badge** ("•" armed) so the armed state is
///   unambiguous in screenshots and to assistive tech.
///
/// UX punch-list #110: the locked state previously rendered the
/// inline Latin text "LOCK" inside the key, which was small,
/// English-only, and weak for Korean users who toggled Caps Lock
/// by accident.  The visual carriers are now the solid Signal
/// Blue fill plus a thin filled bottom rule under the glyph —
/// no Latin literal.  The accessibility label announces
/// "<modifier> modifier locked" so VoiceOver still reads
/// state changes.
///
/// Accessibility: `accessibilityLabel` announces the modifier
/// kind and the slot state ("Control modifier, armed").  The
/// `accessibilityValue` reflects the slot string so VoiceOver
/// users hear state changes when tapping the same button twice.
struct ModifierKeyButton: View {

    let label: String
    let modifier: DirectKeystrokeModifier
    let slot: StickyModifiers.SlotState
    let widthUnits: CGFloat
    let unitWidth: CGFloat
    /// Explicit render height. The accessory strip proposes 36pt to
    /// match `accessoryKeyButton`; without this, the ZStack fill
    /// consumes the unconstrained ScrollView-row height.
    let height: CGFloat
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

                // Locked state: thin filled bottom rule (3pt under
                // the glyph) reads as a status carrier without
                // resorting to inline Latin text.  Combined with
                // the solid Signal Blue fill above, the lock is
                // visually unambiguous in screenshots.
                if slot == .locked {
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.85))
                            .frame(height: 3)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 4)
                    }
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
        // Pressed tint + haptic on touch-down (founder feedback
        // 2026-07-05) — layered so idle/armed/locked fills stay intact.
        .buttonStyle(DirectModifierKeyButtonStyle())
        .frame(width: widthUnits * unitWidth, height: height)
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
            // The bottom rule overlay carries the locked-state
            // signal; reserve a blank line of identical height so
            // the glyph doesn't jump when the slot transitions.
            Text(" ")
                .font(.system(size: 8))
                .foregroundStyle(Color.clear)
        }
    }

    private var accessibilityLabelText: String {
        // Punch-list #110: previously "<Modifier> modifier, <state>"
        // for all three slots, with the locked state relying on
        // the inline Latin "LOCK" text plus a state-changed
        // announcement.  Keep the existing comma-separated format
        // (existing UITests anchor on it) but pin the locked state
        // copy to "<modifier> modifier, locked" so VoiceOver users
        // hear the slot transition unambiguously.
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

/// Press-feedback style for accessory strip modifier keys (moved
/// from the retired Direct soft keyboard; kept for the shared strip).
struct DirectModifierKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.30 : 0))
            )
            .animation(
                configuration.isPressed ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { NaruHaptics.keyPress() }
            }
    }
}
