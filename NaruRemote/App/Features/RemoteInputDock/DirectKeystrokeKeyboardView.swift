import SwiftUI
import NaruRemoteCore

/// SwiftUI rendering of the Direct-mode soft keyboard.  Bottom-docked
/// in `RemoteInputDockView` whenever `mode.isActive == true`.  Page
/// (QWERTY vs special-keys) follows `mode.page` — the renderer never
/// mutates state directly; every tap dispatches through the
/// `onTapKey` closure so the model owns emission.
///
/// FR-002: tapping the page-toggle key swaps pages without emitting
/// any KeyEvent over the wire.
///
/// Phase 4: the four modifier slots on the special-keys page render
/// as `ModifierKeyButton` instead of plain key buttons so the
/// idle / armed / locked sticky-modifier states are visually
/// distinct (FR-005).  The renderer reads slot state from
/// `stickyModifierState` (or, in previews, the default `.init()`).
struct DirectKeystrokeKeyboardView: View {

    let page: KeyboardPage
    let stickyModifierState: StickyModifierState
    let onTapKey: (DirectKey) -> Void

    /// Transient highlight that flashes the Clear-modifiers button
    /// for ~200 ms after the user taps it (FR-013 visual feedback).
    /// Kept local to the view because the model-level state machine
    /// doesn't carry a "just-pressed" hint, and the flash is purely
    /// presentational.
    @State private var clearFlashing: Bool = false

    init(
        page: KeyboardPage,
        stickyModifierState: StickyModifierState = StickyModifierState(),
        onTapKey: @escaping (DirectKey) -> Void
    ) {
        self.page = page
        self.stickyModifierState = stickyModifierState
        self.onTapKey = onTapKey
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(layout.rows.enumerated()), id: \.offset) { index, row in
                rowView(row)
                    .accessibilityIdentifier("naru.direct.keyboard.row.\(index)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        // UX punch-list #205: the keyboard surface used a
        // hard-coded mid-grey that made the keyboard read as a
        // generic iOS-style surface.  Reuse the existing
        // `naru.surface.dock` token so the keyboard reads as
        // part of Naru, and adapts in dark mode.
        .background(NaruColors.dock)
        .accessibilityIdentifier("naru.direct.keyboard.\(page.rawValue)")
    }

    private var layout: DirectKeystrokeKeyboardLayouts.PageLayout {
        DirectKeystrokeKeyboardLayouts.layout(for: page)
    }

    @ViewBuilder
    private func rowView(_ row: DirectKeystrokeKeyboardLayouts.Row) -> some View {
        GeometryReader { proxy in
            let totalUnits = row.keys.reduce(0.0) { $0 + $1.widthUnits }
            let spacing: CGFloat = 4
            let totalSpacing = spacing * CGFloat(max(0, row.keys.count - 1))
            let unitWidth = max(0, (proxy.size.width - totalSpacing) / max(0.001, totalUnits))
            HStack(spacing: spacing) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, descriptor in
                    keyView(descriptor: descriptor, unitWidth: unitWidth)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 42)
    }

    @ViewBuilder
    private func keyView(
        descriptor: DirectKeystrokeKeyboardLayouts.KeyDescriptor,
        unitWidth: CGFloat
    ) -> some View {
        // Branch: sticky-modifier slots render as ModifierKeyButton
        // (three visual states); everything else stays a plain
        // keyButton.  We branch on the `.modifier(_)` payload of
        // the DirectKey rather than `descriptor.role` because the
        // role is layout-only — the truth of "is this a sticky
        // modifier" is the key payload itself.
        if case .modifier(let modifier) = descriptor.key {
            ModifierKeyButton(
                label: descriptor.label,
                modifier: modifier,
                slot: stickyModifierState.slot(for: modifier),
                widthUnits: descriptor.widthUnits,
                unitWidth: unitWidth,
                onTap: { onTapKey(descriptor.key) }
            )
        } else {
            keyButton(descriptor: descriptor, unitWidth: unitWidth)
        }
    }

    @ViewBuilder
    private func keyButton(
        descriptor: DirectKeystrokeKeyboardLayouts.KeyDescriptor,
        unitWidth: CGFloat
    ) -> some View {
        let isClear = descriptor.key == .clearModifiers
        Button {
            onTapKey(descriptor.key)
            if isClear {
                // Brief flash so the user gets visual confirmation
                // that the panic clear actually fired (FR-013).
                clearFlashing = true
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await MainActor.run { clearFlashing = false }
                }
            }
        } label: {
            Text(descriptor.label)
                .font(fontFor(role: descriptor.role))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .foregroundStyle(isClear && clearFlashing ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(DirectKeyButtonStyle(
            fill: (isClear && clearFlashing) ? Color.accentColor : backgroundFor(role: descriptor.role),
            popLabel: descriptor.role == .standard ? descriptor.label : nil
        ))
        .frame(width: descriptor.widthUnits * unitWidth)
        .accessibilityLabel(accessibilityLabel(for: descriptor))
        .accessibilityIdentifier("naru.direct.key.\(accessibilityIdentifier(for: descriptor))")
    }

    private func fontFor(role: DirectKeystrokeKeyboardLayouts.KeyDescriptor.Role) -> Font {
        switch role {
        case .standard, .modifier, .wide, .toggle:
            return .system(size: 16, weight: .medium)
        case .space:
            return .system(size: 12, weight: .regular)
        }
    }

    private func backgroundFor(role: DirectKeystrokeKeyboardLayouts.KeyDescriptor.Role) -> Color {
        switch role {
        case .standard:
            // UX punch-list #301: was hardcoded `Color.white` so dark
            // mode rendered key tiles as white-on-white (`Color.primary`
            // resolves to white in dark).  Adaptive `NaruColors.surfaceKey`
            // token follows BRANDING.md §7 `Surface` so the tile reads
            // as paper in light, slate in dark.
            return NaruColors.surfaceKey
        case .wide:
            // UX punch-list #301: same root cause as `.standard`.
            // Wide keys (Tab/Esc/return/backspace) use a slightly
            // darker tier so the alpha row vs. system-key row reads
            // as two visual tiers.  Adaptive in dark mode.
            return NaruColors.surfaceKeyAlt
        case .space:
            // UX punch-list #205: the spacebar previously used the
            // same neutral grey as wide keys, leaving the QWERTY
            // page indistinguishable from the iOS system keyboard
            // at a glance.  A faint accent stripe says "this is
            // Naru's keyboard" without overpowering the row.
            return Color.accentColor.opacity(0.15)
        case .toggle, .modifier:
            // UX punch-list #301: same root cause.  Toggle / modifier
            // tiles share the same darker tier as `.wide` so the
            // keyboard reads as two tiers (alphas vs. system keys).
            return NaruColors.surfaceKeyAlt
        }
    }

    private func accessibilityLabel(
        for descriptor: DirectKeystrokeKeyboardLayouts.KeyDescriptor
    ) -> String {
        switch descriptor.key {
        case .character(let c):     return "Key \(c)"
        case .named(let named):     return "Key \(named.rawValue)"
        case .pageToggle:           return "Switch keyboard page"
        case .modifier(let m):      return "\(m.rawValue) modifier"
        case .clearModifiers:       return "Clear modifiers"
        }
    }

    private func accessibilityIdentifier(
        for descriptor: DirectKeystrokeKeyboardLayouts.KeyDescriptor
    ) -> String {
        switch descriptor.key {
        case .character(let c):     return "char.\(c.asciiValue.map { String($0) } ?? String(c))"
        case .named(let named):     return "named.\(named.rawValue)"
        case .pageToggle:           return "pageToggle"
        case .modifier(let m):      return "modifier.\(m.rawValue)"
        case .clearModifiers:       return "clearModifiers"
        }
    }
}

/// Pressed-state feedback for Direct-mode keys (founder feedback
/// 2026-07-05): the remote screen echo can lag behind the wire, so the
/// key itself must acknowledge the press *instantly* — an accent tint on
/// touch-down (no animation in, quick fade out on release), a light
/// haptic, and an iOS-keyboard-style magnified pop bubble on character
/// keys so the eye catches which key registered without looking away
/// from the remote screen.
struct DirectKeyButtonStyle: ButtonStyle {
    let fill: Color
    var popLabel: String?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.32 : 0))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
            )
            // The pop is applied AFTER `clipShape` so it can escape the
            // key bounds. Rows are laid out top-to-bottom, so a lower
            // row's pop paints over the row above it.
            .overlay(alignment: .top) {
                if configuration.isPressed, let popLabel {
                    DirectKeyPopBubble(label: popLabel)
                        .offset(y: -52)
                }
            }
            .animation(
                configuration.isPressed ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { NaruHaptics.keyPress() }
            }
    }
}

/// Sticky-modifier variant: `ModifierKeyButton` draws its own fill /
/// stroke state machine, so this style only layers the pressed tint and
/// haptic on top without disturbing the idle / armed / locked visuals.
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

/// Magnified key-echo bubble shown above a pressed character key —
/// the same local-confirmation idiom as the iOS system keyboard.
struct DirectKeyPopBubble: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(minWidth: 44)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(NaruColors.surfaceKey)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
