import SwiftUI
import NaruRemoteCore

public struct RemoteInputDockView: View {
    @State private var text: String
    /// Tracks whether the compose `TextEditor` has firstResponder.
    /// Forwarded to the parent via `onComposeFocusChange` so the
    /// app shell can collapse its OnboardingGuide into a 1-line
    /// summary banner whenever the iOS keyboard is presented —
    /// closes UX punch-list #009.  Direct mode renders its own
    /// keyboard, so the focus signal is only meaningful for the
    /// Compose path.
    @FocusState private var composeFieldFocused: Bool

    private let initialText: String
    private let statusText: String
    private let onSend: (String) -> Void
    private let directKeystrokeMode: DirectKeystrokeMode
    private let stickyModifierState: StickyModifierState
    private let onToggleDirectMode: () -> Void
    private let onSetDirectKeystrokePage: (KeyboardPage) -> Void
    private let onTapDirectKey: (DirectKey) -> Void
    private let onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void
    private let onDismissDirectModeWarning: () -> Void
    private let onComposeFocusChange: (Bool) -> Void

    public init(
        initialText: String,
        statusText: String,
        onSend: @escaping (String) -> Void = { _ in },
        directKeystrokeMode: DirectKeystrokeMode = DirectKeystrokeMode(),
        stickyModifierState: StickyModifierState = StickyModifierState(),
        onToggleDirectMode: @escaping () -> Void = {},
        onSetDirectKeystrokePage: @escaping (KeyboardPage) -> Void = { _ in },
        onTapDirectKey: @escaping (DirectKey) -> Void = { _ in },
        onHardwareKey: @escaping (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void = { _, _, _ in },
        onDismissDirectModeWarning: @escaping () -> Void = {},
        onComposeFocusChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.initialText = initialText
        self._text = State(initialValue: initialText)
        self.statusText = statusText
        self.onSend = onSend
        self.directKeystrokeMode = directKeystrokeMode
        self.stickyModifierState = stickyModifierState
        self.onToggleDirectMode = onToggleDirectMode
        self.onSetDirectKeystrokePage = onSetDirectKeystrokePage
        self.onTapDirectKey = onTapDirectKey
        self.onHardwareKey = onHardwareKey
        self.onDismissDirectModeWarning = onDismissDirectModeWarning
        self.onComposeFocusChange = onComposeFocusChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Remote Input Dock", systemImage: "keyboard")
                    .font(.headline)

                // Dock-side Direct-mode badge.  Sits next to the
                // dock title so the cue is always visible whenever
                // the keyboard is on screen — FR-010 first sentence.
                DirectModeBadge(
                    isVisible: directKeystrokeMode.isActive,
                    accessibilityID: "naru.direct.badge.dock"
                )

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            modePicker

            if directKeystrokeMode.isActive {
                directKeyboard
            } else {
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
        .accessibilityIdentifier("naru.input.dock")
        .onChange(of: initialText) { _, newValue in
            text = newValue
        }
        .onChange(of: composeFieldFocused) { _, newValue in
            // Only meaningful when Compose is the visible mode —
            // Direct mode swaps the editor for the soft keyboard,
            // so its focus signal is irrelevant.  Forward an
            // explicit `false` whenever we're not in Compose so
            // stale focus from a previous mode-switch can't leave
            // the OnboardingGuide collapsed.
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
                .background(Color.white.opacity(0.74))
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
