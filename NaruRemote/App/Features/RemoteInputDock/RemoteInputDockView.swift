import SwiftUI
import NaruRemoteCore

public enum RemoteInputDockLayoutStyle: Sendable, Equatable {
    case standard
    case compactAccessory
}

public struct RemoteInputDockView: View {
    @State private var text: String
    /// Tracks whether the compose `TextEditor` has firstResponder.
    /// Forwarded to the parent via `onComposeFocusChange` so future
    /// keyboard-aware surfaces can react to it.  Today no overlay
    /// reads it (the first-run checklist that used to depend on
    /// keyboard focus was removed when onboarding was reduced to a
    /// single empty-state CTA — spec FR-015).  Direct mode renders
    /// its own keyboard, so the focus signal is only meaningful for
    /// the Compose path.
    @FocusState private var composeFieldFocused: Bool

    private let initialText: String
    private let statusText: String
    private let onSend: (String) -> Void
    private let directKeystrokeMode: DirectKeystrokeMode
    private let stickyModifierState: StickyModifierState
    private let layoutStyle: RemoteInputDockLayoutStyle
    /// When `true`, the Compose-mode inline quick-key strip
    /// (Esc / Tab / ⌃C / arrows) is shown.  Gated on an active session
    /// (spec 003 FR-013) — with no live wire there is nothing to send
    /// a control key to, so the strip is hidden rather than dead.
    private let showsComposeQuickKeys: Bool
    private let onToggleDirectMode: () -> Void
    private let onSetDirectKeystrokePage: (KeyboardPage) -> Void
    private let onTapDirectKey: (DirectKey) -> Void
    private let onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void
    private let onComposeQuickKey: (ComposeQuickKey) -> Void
    private let onDismissDirectModeWarning: () -> Void
    private let onComposeFocusChange: (Bool) -> Void

    public init(
        initialText: String,
        statusText: String,
        onSend: @escaping (String) -> Void = { _ in },
        directKeystrokeMode: DirectKeystrokeMode = DirectKeystrokeMode(),
        stickyModifierState: StickyModifierState = StickyModifierState(),
        layoutStyle: RemoteInputDockLayoutStyle = .standard,
        showsComposeQuickKeys: Bool = false,
        onToggleDirectMode: @escaping () -> Void = {},
        onSetDirectKeystrokePage: @escaping (KeyboardPage) -> Void = { _ in },
        onTapDirectKey: @escaping (DirectKey) -> Void = { _ in },
        onHardwareKey: @escaping (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void = { _, _, _ in },
        onComposeQuickKey: @escaping (ComposeQuickKey) -> Void = { _ in },
        onDismissDirectModeWarning: @escaping () -> Void = {},
        onComposeFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.initialText = initialText
        self._text = State(initialValue: initialText)
        self.statusText = statusText
        self.onSend = onSend
        self.directKeystrokeMode = directKeystrokeMode
        self.stickyModifierState = stickyModifierState
        self.layoutStyle = layoutStyle
        self.showsComposeQuickKeys = showsComposeQuickKeys
        self.onToggleDirectMode = onToggleDirectMode
        self.onSetDirectKeystrokePage = onSetDirectKeystrokePage
        self.onTapDirectKey = onTapDirectKey
        self.onHardwareKey = onHardwareKey
        self.onComposeQuickKey = onComposeQuickKey
        self.onDismissDirectModeWarning = onDismissDirectModeWarning
        self.onComposeFocusChange = onComposeFocusChange
    }

    public var body: some View {
        Group {
            switch layoutStyle {
            case .standard:
                standardBody
            case .compactAccessory:
                compactAccessoryBody
            }
        }
        .accessibilityIdentifier("naru.input.dock")
        .onChange(of: initialText) { _, newValue in
            text = newValue
        }
        .onChange(of: composeFieldFocused) { _, newValue in
            // Only meaningful when Compose is the visible mode —
            // Direct mode swaps the editor for the soft keyboard,
            // so its focus signal is irrelevant.  Forward an
            // explicit `false` whenever we're not in Compose so a
            // stale focus from a previous mode-switch never leaks
            // into a future keyboard-aware overlay.
            onComposeFocusChange(directKeystrokeMode.isActive ? false : newValue)
        }
        .onChange(of: directKeystrokeMode.isActive) { _, isDirect in
            // Switching to Direct mode hides the editor entirely;
            // explicitly clear the focus signal so the app shell
            // can restore the full checklist.
            if isDirect {
                onComposeFocusChange(false)
            }
        }
        // FR-009 — first-entry warning dialog attached at the dock
        // level so the alert chrome sits over the dock and feels
        // anchored to the mode picker the user just tapped.
        .directModeEntryWarning(
            mode: directKeystrokeMode,
            onDismiss: onDismissDirectModeWarning
        )
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    Label("Remote Input Dock", systemImage: "keyboard")
                    Label("Input Dock", systemImage: "keyboard")
                }
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                // Dock-side Direct-mode badge.  Sits next to the
                // dock title so the cue is always visible whenever
                // the keyboard is on screen — FR-010 first sentence.
                DirectModeBadge(
                    isVisible: directKeystrokeMode.isActive,
                    accessibilityID: "naru.direct.badge.dock"
                )

                Spacer()

                if !directKeystrokeMode.isActive {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }

            modePicker

            if directKeystrokeMode.isActive {
                directKeyboard
            } else {
                if showsComposeQuickKeys {
                    composeQuickKeyStrip
                }
                composeRow
            }
        }
        .padding(16)
        .background(NaruColors.dock)
        .overlay(alignment: .top) {
            // UX punch-list #203: the system `Divider()` rendered
            // nearly invisible against the mint-tinted canvas.
            // Use the BRANDING.md Hairline token (1pt) so the dock
            // reads as a separate input surface in both light and
            // dark.
            Rectangle()
                .fill(NaruColors.hairline)
                .frame(height: 1)
        }
    }

    private var compactAccessoryBody: some View {
        VStack(spacing: 8) {
            if directKeystrokeMode.isActive {
                compactDirectHeader
                directKeyboard
            } else {
                compactComposeRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NaruColors.hairline)
                .frame(height: 1)
        }
    }

    private var compactComposeRow: some View {
        HStack(spacing: 10) {
            Button {
                onToggleDirectMode()
            } label: {
                Label("Direct mode", systemImage: "keyboard")
                    .labelStyle(.iconOnly)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .background(NaruColors.surfaceMuted)
            .clipShape(Circle())
            .accessibilityIdentifier("naru.input.direct-toggle")

            TextEditor(text: $text)
                .focused($composeFieldFocused)
                .font(.body)
                .frame(minHeight: 40, maxHeight: 88)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(NaruColors.surfaceEditor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NaruColors.hairline, lineWidth: 1)
                )
                .accessibilityLabel("Remote input text")
                .accessibilityIdentifier("naru.input.editor")

            if showsComposeQuickKeys {
                quickKeyMenu
            }

            Button {
                onSend(text)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.isEmpty)
            .help("Send composed text")
            .accessibilityIdentifier("naru.input.send")
        }
    }

    private var compactDirectHeader: some View {
        HStack(spacing: 8) {
            Button {
                onToggleDirectMode()
            } label: {
                Label("Compose", systemImage: "text.cursor")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("naru.input.compose-toggle")

            Spacer()

            DirectModeBadge(
                isVisible: directKeystrokeMode.isActive,
                accessibilityID: "naru.direct.badge.dock"
            )
        }
    }

    private var quickKeyMenu: some View {
        Menu {
            ForEach(ComposeQuickKey.allCases, id: \.self) { key in
                Button(key.label) {
                    onComposeQuickKey(key)
                }
            }
        } label: {
            Label("Quick keys", systemImage: "command")
                .labelStyle(.iconOnly)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("naru.input.quickkeys.menu")
    }

    /// Segmented picker that switches between Compose and Direct
    /// modes. The binding reads `directKeystrokeMode.isActive` and
    /// every change dispatches `onToggleDirectMode` — the model is
    /// the single source of truth for mode state.
    private var modePicker: some View {
        Picker(
            "Input mode",
            selection: Binding<Bool>(
                get: { directKeystrokeMode.isActive },
                set: { newValue in
                    if newValue != directKeystrokeMode.isActive {
                        onToggleDirectMode()
                    }
                }
            )
        ) {
            Text("Compose").tag(false)
            Text("Direct").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("naru.input.mode-picker")
    }

    /// Inline terminal-control strip shown above the Compose editor
    /// while a session is active (spec 003 US5 / FR-013).  Lets a
    /// multilingual-composing user fire Esc / Tab / ⌃C / arrows once
    /// without switching to Direct mode.  Each button dispatches a
    /// discrete `KeyEvent` through the model's `sendComposeQuickKey`
    /// path; the compose draft is never modified.
    private var composeQuickKeyStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ComposeQuickKey.allCases, id: \.self) { key in
                    Button {
                        onComposeQuickKey(key)
                    } label: {
                        // UX (GRD-parity #5): the tiles read as flat
                        // low-contrast text on the mint dock surface.
                        // Give each a `surfaceKey` fill (one tier above
                        // the dock), a Hairline stroke, and a ≥40pt tap
                        // target so they read as tappable terminal keys.
                        Text(key.label)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 44, minHeight: 40)
                            .padding(.horizontal, 12)
                            .background(NaruColors.surfaceKey)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(NaruColors.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel(key.accessibilityLabel)
                    .accessibilityIdentifier("naru.input.quickkey.\(key.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("naru.input.quickkeys")
    }

    private var composeRow: some View {
        // UX punch-list #204: bumped HStack spacing 12 → 16 and
        // padded the editor's trailing inset so the Send paperplane
        // no longer sits flush against the editor stroke.  Also
        // gives the disabled-state Send button visible breathing
        // room in static screenshots.
        HStack(alignment: .bottom, spacing: 16) {
            TextEditor(text: $text)
                .focused($composeFieldFocused)
                .font(.body)
                .frame(minHeight: 72, maxHeight: 120)
                .scrollContentBackground(.hidden)
                // UX punch-list #302: was `Color.white.opacity(0.74)`
                // which rendered as a stark bright rectangle on the
                // dark canvas.  Adaptive `NaruColors.surfaceEditor`
                // (BRANDING.md §7 `Surface`) reads as paper on light,
                // slate on dark.  Opacity dropped — the system color
                // already has the right contrast at full alpha.
                .background(NaruColors.surfaceEditor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
                .padding(.trailing, 4)
                .accessibilityLabel("Remote input text")
                .accessibilityIdentifier("naru.input.editor")

            Button {
                onSend(text)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.isEmpty)
            .help("Send composed text")
            .accessibilityIdentifier("naru.input.send")
        }
    }

    /// Direct-mode body: hides the Compose TextEditor + Send and
    /// shows the custom soft keyboard.  The
    /// `DirectKeystrokeResponderView` lives in the tree (zero-size)
    /// to keep firstResponder so the iOS system keyboard stays
    /// hidden — FR-001 / R-3.
    @ViewBuilder
    private var directKeyboard: some View {
        VStack(spacing: 8) {
            #if canImport(UIKit)
            DirectKeystrokeResponderView(
                isActive: true,
                onHardwareKey: onHardwareKey
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            #endif

            DirectKeystrokeKeyboardView(
                page: directKeystrokeMode.page,
                stickyModifierState: stickyModifierState,
                onTapKey: onTapDirectKey
            )
        }
    }
}
