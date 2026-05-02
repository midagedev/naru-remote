import SwiftUI
import NaruRemoteCore

public struct RemoteInputDockView: View {
    @State private var text: String

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
        onDismissDirectModeWarning: @escaping () -> Void = {}
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
            Divider()
        }
        .accessibilityIdentifier("naru.input.dock")
        .onChange(of: initialText) { _, newValue in
            text = newValue
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
        HStack(alignment: .bottom, spacing: 12) {
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 72, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.74))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
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
