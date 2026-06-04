import SwiftUI
import NaruRemoteCore

#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum RemoteInputDockLayoutStyle: Sendable, Equatable {
    case standard
    case compactAccessory
}

public struct RemoteInputDockView: View {
    private static let composeSendStabilizationSnapshotCount = 5
    private static let composeSendStabilizationDelayNanoseconds: UInt64 = 8_000_000

    @State private var text: String
    @State private var lastAppliedInitialText: String
    @State private var lastPropagatedComposeText: String
    #if os(iOS) && canImport(UIKit)
    @StateObject private var composeCommitController = ComposeTextCommitController()
    @State private var isPreparingComposeSend = false
    #endif
    /// Tracks whether the compose editor has firstResponder.
    /// Forwarded to the parent via `onComposeFocusChange` so future
    /// keyboard-aware surfaces can react to it.  Today no overlay
    /// reads it (the first-run checklist that used to depend on
    /// keyboard focus was removed when onboarding was reduced to a
    /// single empty-state CTA — spec FR-015).  Direct mode renders
    /// its own keyboard, so the focus signal is only meaningful for
    /// the Compose path.
    @State private var composeFieldFocused: Bool = false

    private let initialText: String
    private let statusText: String
    private let onSend: (String) -> Void
    private let onTextChange: (String) -> Void
    private let directKeystrokeMode: DirectKeystrokeMode
    private let stickyModifierState: StickyModifierState
    private let layoutStyle: RemoteInputDockLayoutStyle
    private let showsCompactStatusText: Bool
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
        onTextChange: @escaping (String) -> Void = { _ in },
        directKeystrokeMode: DirectKeystrokeMode = DirectKeystrokeMode(),
        stickyModifierState: StickyModifierState = StickyModifierState(),
        layoutStyle: RemoteInputDockLayoutStyle = .standard,
        showsCompactStatusText: Bool = false,
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
        self._lastAppliedInitialText = State(initialValue: initialText)
        self._lastPropagatedComposeText = State(initialValue: initialText)
        self.statusText = statusText
        self.onSend = onSend
        self.onTextChange = onTextChange
        self.directKeystrokeMode = directKeystrokeMode
        self.stickyModifierState = stickyModifierState
        self.layoutStyle = layoutStyle
        self.showsCompactStatusText = showsCompactStatusText
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
            guard shouldApplyExternalComposeText(newValue) else {
                return
            }
            lastAppliedInitialText = newValue
            guard text != newValue else {
                return
            }
            lastPropagatedComposeText = newValue
            text = newValue
        }
        .onChange(of: text) { _, newValue in
            propagateComposeTextToModelIfNeeded(newValue)
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
                composeFieldFocused = false
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
                if Self.shouldShowCompactStatusText(
                    hasStatus: showsCompactStatusText,
                    statusText: statusText
                ) {
                    compactStatusLine
                }
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

            composeTextEditor
                .frame(minHeight: 40, maxHeight: 88)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(NaruColors.surfaceEditor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NaruColors.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .simultaneousGesture(TapGesture().onEnded {
                    focusComposeEditor()
                })
                .composeEditorShellAccessibility()

            if showsComposeQuickKeys {
                quickKeyMenu
            }

            Button {
                sendCurrentComposeText()
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isComposeSendDisabled)
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

    private var compactStatusLine: some View {
        Text(statusText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("naru.input.compact-status")
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
            composeTextEditor
                .frame(minHeight: 72, maxHeight: 120)
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
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .simultaneousGesture(TapGesture().onEnded {
                    focusComposeEditor()
                })
                .composeEditorShellAccessibility()

            Button {
                sendCurrentComposeText()
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isComposeSendDisabled)
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

    private func updateComposeFocus(_ focused: Bool) {
        composeFieldFocused = focused
    }

    private var isComposeSendDisabled: Bool {
        #if os(iOS) && canImport(UIKit)
        isPreparingComposeSend || composeCommitController.readCurrentText(fallback: text).isEmpty
        #else
        text.isEmpty
        #endif
    }

    private var composeTextEditor: some View {
        #if os(iOS) && canImport(UIKit)
        ComposeTextEditingView(
            text: $text,
            onFocusChange: updateComposeFocus(_:),
            onCommittedTextChange: handleCommittedComposeText(_:),
            commitController: composeCommitController
        )
        #else
        ComposeTextEditingView(
            text: $text,
            onFocusChange: updateComposeFocus(_:)
        )
        #endif
    }

    private func handleCommittedComposeText(_ committedText: String) {
        guard !directKeystrokeMode.isActive else {
            return
        }
        if text != committedText {
            text = committedText
        }
        propagateComposeTextToModelIfNeeded(committedText)
    }

    private func focusComposeEditor() {
        #if os(iOS) && canImport(UIKit)
        composeCommitController.focus()
        #endif
    }

    private func sendCurrentComposeText() {
        #if os(iOS) && canImport(UIKit)
        guard !isPreparingComposeSend else { return }
        isPreparingComposeSend = true
        let immediateText = composeCommitController.commitMarkedTextAndRead(fallback: text)
        if immediateText != text {
            text = immediateText
        }
        propagateComposeTextToModelIfNeeded(immediateText)
        Task { @MainActor in
            let finalText = await composeCommitController.readStabilizedCurrentText(
                fallback: immediateText,
                snapshotCount: Self.composeSendStabilizationSnapshotCount,
                snapshotDelayNanoseconds: Self.composeSendStabilizationDelayNanoseconds
            )
            if finalText != text {
                text = finalText
            }
            propagateComposeTextToModelIfNeeded(finalText)
            isPreparingComposeSend = false
            guard !finalText.isEmpty else { return }
            onSend(finalText)
        }
        #else
        onSend(text)
        #endif
    }

    private func shouldApplyExternalComposeText(_ newValue: String) -> Bool {
        #if os(iOS) && canImport(UIKit)
        let hasMarkedText = composeCommitController.hasMarkedText
        #else
        let hasMarkedText = false
        #endif

        return Self.shouldApplyExternalComposeText(
            newValue: newValue,
            lastAppliedInitialText: lastAppliedInitialText,
            currentText: text,
            isDirectModeActive: directKeystrokeMode.isActive,
            isComposeFieldFocused: composeFieldFocused,
            hasMarkedText: hasMarkedText
        )
    }

    private func shouldPropagateLocalComposeTextToModel() -> Bool {
        #if os(iOS) && canImport(UIKit)
        let hasMarkedText = composeCommitController.hasMarkedText
        #else
        let hasMarkedText = false
        #endif

        return Self.shouldPropagateLocalComposeTextToModel(
            isDirectModeActive: directKeystrokeMode.isActive,
            hasMarkedText: hasMarkedText
        )
    }

    private func shouldPropagateLocalComposeTextToModel(_ newValue: String) -> Bool {
        #if os(iOS) && canImport(UIKit)
        let hasMarkedText = composeCommitController.hasMarkedText
        #else
        let hasMarkedText = false
        #endif

        return Self.shouldPropagateLocalComposeTextToModel(
            newValue: newValue,
            lastPropagatedText: lastPropagatedComposeText,
            isDirectModeActive: directKeystrokeMode.isActive,
            hasMarkedText: hasMarkedText
        )
    }

    private func propagateComposeTextToModelIfNeeded(_ newValue: String) {
        guard shouldPropagateLocalComposeTextToModel(newValue) else {
            return
        }
        lastPropagatedComposeText = newValue
        onTextChange(newValue)
    }

    nonisolated static func shouldPropagateLocalComposeTextToModel(
        isDirectModeActive: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        !isDirectModeActive && !hasMarkedText
    }

    nonisolated static func shouldPropagateLocalComposeTextToModel(
        newValue: String,
        lastPropagatedText: String,
        isDirectModeActive: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        shouldPropagateLocalComposeTextToModel(
            isDirectModeActive: isDirectModeActive,
            hasMarkedText: hasMarkedText
        ) && newValue != lastPropagatedText
    }

    nonisolated static func didCommitMarkedComposeText(
        previouslyHadMarkedText: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        previouslyHadMarkedText && !hasMarkedText
    }

    nonisolated static func shouldDeferUIKitComposeBindingWrite(
        hasMarkedText: Bool,
        isFirstResponder: Bool,
        proposedText: String,
        lastAppliedBindingText: String,
        currentUIKitText: String
    ) -> Bool {
        if hasMarkedText {
            return true
        }

        return isFirstResponder
            && proposedText == lastAppliedBindingText
            && currentUIKitText != proposedText
    }

    nonisolated static func shouldApplyExternalComposeText(
        newValue: String,
        lastAppliedInitialText: String,
        currentText: String,
        isDirectModeActive: Bool,
        isComposeFieldFocused: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        guard newValue != lastAppliedInitialText || newValue != currentText else {
            return true
        }

        if isDirectModeActive {
            return true
        }

        if hasMarkedText {
            return false
        }

        if newValue.isEmpty {
            return true
        }

        return !isComposeFieldFocused || currentText.isEmpty
    }

    nonisolated static func resolvedCommittedComposeText(
        committedText: String?,
        markedTextBeforeCommit: String?,
        currentTextBeforeCommit: String
    ) -> String {
        if let committedText {
            if !committedText.isEmpty,
               currentTextBeforeCommit.hasPrefix(committedText),
               currentTextBeforeCommit.count > committedText.count {
                return currentTextBeforeCommit
            }
            if let markedTextBeforeCommit,
               !markedTextBeforeCommit.isEmpty,
               !committedText.contains(markedTextBeforeCommit),
               currentTextBeforeCommit.contains(markedTextBeforeCommit) {
                return currentTextBeforeCommit
            }
            if !committedText.isEmpty {
                return committedText
            }
            if let markedTextBeforeCommit, !markedTextBeforeCommit.isEmpty {
                return markedTextBeforeCommit
            }
            return ""
        }

        if let markedTextBeforeCommit, !markedTextBeforeCommit.isEmpty {
            return markedTextBeforeCommit
        }

        return currentTextBeforeCommit
    }

    nonisolated static func resolvedStabilizedComposeText(
        immediateText: String,
        stabilizedText: String
    ) -> String {
        if stabilizedText.isEmpty {
            return immediateText
        }
        if immediateText.isEmpty {
            return stabilizedText
        }
        if immediateText.hasPrefix(stabilizedText),
           immediateText.count > stabilizedText.count {
            return immediateText
        }
        return stabilizedText
    }

    nonisolated static func resolvedStabilizedComposeText(
        immediateText: String,
        stabilizedSnapshots: [String]
    ) -> String {
        stabilizedSnapshots.reduce(immediateText) { resolved, snapshot in
            resolvedStabilizedComposeText(
                immediateText: resolved,
                stabilizedText: snapshot
            )
        }
    }

    nonisolated static func shouldShowCompactStatusText(
        hasStatus: Bool,
        statusText: String
    ) -> Bool {
        let trimmed = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasStatus && !trimmed.isEmpty
    }

    nonisolated static func resolvedCurrentComposeText(
        viewText: String?,
        markedText: String?,
        controllerText: String,
        fallback: String
    ) -> String {
        if let markedText, !markedText.isEmpty {
            if let viewText, !viewText.isEmpty {
                if viewText.contains(markedText) {
                    return viewText
                }
                if !controllerText.isEmpty,
                   controllerText.contains(markedText),
                   controllerText.count > viewText.count {
                    return controllerText
                }
                if !fallback.isEmpty,
                   !fallback.contains(markedText),
                   viewText.hasPrefix(fallback) || fallback.hasPrefix(viewText) {
                    return fallback + markedText
                }
                return viewText
            }

            if !controllerText.isEmpty {
                return controllerText
            }
            if !fallback.isEmpty, !fallback.contains(markedText) {
                return fallback + markedText
            }
            return markedText
        }

        if let viewText, !viewText.isEmpty {
            return viewText
        }

        if !controllerText.isEmpty {
            return controllerText
        }

        return fallback
    }
}

private struct ComposeTextEditingView: View {
    @Binding var text: String
    let onFocusChange: (Bool) -> Void
    #if os(iOS) && canImport(UIKit)
    let onCommittedTextChange: (String) -> Void
    let commitController: ComposeTextCommitController
    #endif

    var body: some View {
        #if os(iOS) && canImport(UIKit)
        MultilingualComposeTextView(
            text: $text,
            onFocusChange: onFocusChange,
            onCommittedTextChange: onCommittedTextChange,
            commitController: commitController
        )
        #else
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
        #endif
    }
}

#if os(iOS) && canImport(UIKit)
@MainActor
final class ComposeTextCommitController: ObservableObject {
    private weak var textView: UITextView?
    @Published private(set) var currentText: String = ""

    func attach(_ textView: UITextView) {
        self.textView = textView
        currentText = textView.text ?? ""
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    func updateCurrentText(from textView: UITextView) {
        currentText = textView.text ?? ""
    }

    var hasMarkedText: Bool {
        textView?.markedTextRange != nil
    }

    func readCurrentText(fallback: String) -> String {
        guard let textView else {
            return currentText.isEmpty ? fallback : currentText
        }
        return RemoteInputDockView.resolvedCurrentComposeText(
            viewText: textView.text,
            markedText: markedText(in: textView),
            controllerText: currentText,
            fallback: fallback
        )
    }

    @MainActor
    func readStabilizedCurrentText(
        fallback: String,
        snapshotCount: Int = 3,
        snapshotDelayNanoseconds: UInt64 = 0
    ) async -> String {
        var resolved = fallback
        for _ in 0..<max(1, snapshotCount) {
            if snapshotDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: snapshotDelayNanoseconds)
            } else {
                await Task.yield()
            }
            let next = readCurrentText(fallback: resolved)
            resolved = RemoteInputDockView.resolvedStabilizedComposeText(
                immediateText: resolved,
                stabilizedSnapshots: [next]
            )
        }
        return resolved
    }

    func commitMarkedTextAndRead(fallback: String) -> String {
        guard let textView else {
            return currentText.isEmpty ? fallback : currentText
        }
        let markedTextBeforeCommit = markedText(in: textView)
        let currentTextBeforeCommit = RemoteInputDockView.resolvedCurrentComposeText(
            viewText: textView.text,
            markedText: markedTextBeforeCommit,
            controllerText: currentText,
            fallback: fallback
        )
        if markedTextBeforeCommit != nil {
            textView.unmarkText()
        }
        textView.layoutIfNeeded()
        let committedText = RemoteInputDockView.resolvedCommittedComposeText(
            committedText: textView.text,
            markedTextBeforeCommit: markedTextBeforeCommit,
            currentTextBeforeCommit: currentTextBeforeCommit
        )
        currentText = committedText
        return committedText
    }

    private func markedText(in textView: UITextView) -> String? {
        textView.markedTextRange.flatMap { range in
            textView.text(in: range)
        }
    }
}

private struct MultilingualComposeTextView: UIViewRepresentable {
    @Binding var text: String
    let onFocusChange: (Bool) -> Void
    let onCommittedTextChange: (String) -> Void
    let commitController: ComposeTextCommitController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = "Remote input text"
        textView.accessibilityIdentifier = "naru.input.editor"
        textView.isAccessibilityElement = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.accessibilityLabel = "Remote input text"
        textView.accessibilityIdentifier = "naru.input.editor"
        textView.isAccessibilityElement = true

        // Do not overwrite UIKit's in-flight marked text. Korean/CJK
        // composition keeps intermediate state inside UITextView; setting
        // `text` during that window can collapse or reorder the candidate.
        if context.coordinator.shouldDeferBindingWrite(
            proposedText: text,
            textView: textView
        ) {
            context.coordinator.parent.commitController.updateCurrentText(from: textView)
            return
        }

        if textView.text != text {
            textView.text = text
            context.coordinator.parent.commitController.updateCurrentText(from: textView)
        }
        context.coordinator.markBindingTextApplied(text)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MultilingualComposeTextView
        private weak var textView: UITextView?
        private var previouslyHadMarkedText = false
        private var lastCommittedTextNotification: String?
        private var lastAppliedBindingText = ""

        init(parent: MultilingualComposeTextView) {
            self.parent = parent
        }

        func attach(_ textView: UITextView) {
            self.textView = textView
            parent.commitController.attach(textView)
            previouslyHadMarkedText = textView.markedTextRange != nil
            lastCommittedTextNotification = textView.text ?? ""
            lastAppliedBindingText = parent.text
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.commitController.updateCurrentText(from: textView)
            let resolvedText = parent.commitController.readCurrentText(fallback: parent.text)
            if textView.markedTextRange == nil, parent.text != resolvedText {
                parent.text = resolvedText
            }
            notifyIfMarkedTextCommitted(textView, resolvedText: resolvedText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.commitController.updateCurrentText(from: textView)
            let resolvedText = parent.commitController.readCurrentText(fallback: parent.text)
            if RemoteInputDockView.didCommitMarkedComposeText(
                previouslyHadMarkedText: previouslyHadMarkedText,
                hasMarkedText: textView.markedTextRange != nil
            ), parent.text != resolvedText {
                parent.text = resolvedText
            }
            notifyIfMarkedTextCommitted(textView, resolvedText: resolvedText)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        func shouldDeferBindingWrite(
            proposedText: String,
            textView: UITextView
        ) -> Bool {
            RemoteInputDockView.shouldDeferUIKitComposeBindingWrite(
                hasMarkedText: textView.markedTextRange != nil,
                isFirstResponder: textView.isFirstResponder,
                proposedText: proposedText,
                lastAppliedBindingText: lastAppliedBindingText,
                currentUIKitText: textView.text ?? ""
            )
        }

        func markBindingTextApplied(_ text: String) {
            lastAppliedBindingText = text
        }

        private func notifyIfMarkedTextCommitted(
            _ textView: UITextView,
            resolvedText: String
        ) {
            let hasMarkedText = textView.markedTextRange != nil
            defer { previouslyHadMarkedText = hasMarkedText }

            guard RemoteInputDockView.didCommitMarkedComposeText(
                previouslyHadMarkedText: previouslyHadMarkedText,
                hasMarkedText: hasMarkedText
            ) else {
                return
            }
            guard lastCommittedTextNotification != resolvedText else {
                return
            }
            lastCommittedTextNotification = resolvedText
            parent.onCommittedTextChange(resolvedText)
        }
    }
}
#endif

private extension View {
    @ViewBuilder
    func composeEditorShellAccessibility() -> some View {
        #if os(iOS) && canImport(UIKit)
        self
        #else
        self
            .accessibilityLabel("Remote input text")
            .accessibilityIdentifier("naru.input.editor")
        #endif
    }
}
