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
        .background(Color(red: 0.84, green: 0.86, blue: 0.88))
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
        Button {
            onTapKey(descriptor.key)
        } label: {
            Text(descriptor.label)
                .font(fontFor(role: descriptor.role))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: descriptor.widthUnits * unitWidth)
        .background(backgroundFor(role: descriptor.role))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
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
            return Color.white
        case .wide, .space:
            return Color(white: 0.92)
        case .toggle, .modifier:
            return Color(white: 0.86)
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
