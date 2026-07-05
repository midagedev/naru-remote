import SwiftUI
import NaruRemoteCore

#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public enum RemoteInputDockLayoutStyle: Sendable, Equatable {
    case standard
    case compactAccessory
    case floatingAccessory
}

public struct RemoteInputDockView: View {
    nonisolated static let compactComposeIdleMaxHeight: CGFloat = 44
    nonisolated static let compactComposeExpandedMaxHeight: CGFloat = 88
    nonisolated static let composeSendFastSnapshotCount = 3
    nonisolated static let composeSendFastDelayNanoseconds: UInt64 = 0
    nonisolated static let composeSendStabilizationSnapshotCount = 30
    nonisolated static let composeSendStabilizationDelayNanoseconds: UInt64 = 16_000_000
    nonisolated static let composeTextPropagationDebounceNanoseconds: UInt64 = 120_000_000

    #if os(iOS) && canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var text: String
    @State private var lastAppliedInitialText: String
    @State private var lastPropagatedComposeText: String
    @State private var pendingComposeTextPropagation: PendingComposeTextPropagation?
    @State private var composeTextPropagationSequence = 0
    #if os(iOS) && canImport(UIKit)
    @State private var composeCommitController = ComposeTextCommitController()
    @State private var isPreparingComposeSend = false
    @State private var composeSendNeedsMarkedCommitStabilization = false
    #endif
    /// The Compose & Send "crossing" pulse (BRANDING.md §10): a subtle
    /// Signal-Blue packet that rises from the dock when text is sent, while
    /// the status line reports the actual route. `crossingPulse` animates
    /// 0→1; `crossingVisible` fades it in/out; `crossingToken` guards the
    /// auto-hide against a newer pulse.
    @State private var crossingPulse: Double = 0
    @State private var crossingVisible: Bool = false
    @State private var crossingToken: Int = 0
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
    private let helperStatusText: String?
    private let onSend: (String) -> Void
    private let onTextChange: (String) -> Void
    private let onComposeSendPreparation: (ComposeSendPreparationReport) -> Void
    private let directKeystrokeMode: DirectKeystrokeMode
    private let stickyModifierState: StickyModifierState
    private let layoutStyle: RemoteInputDockLayoutStyle
    private let showsCompactStatusText: Bool
    private let showsMacSessionControls: Bool
    /// When `true`, the Compose-mode inline quick-key strip
    /// (Esc / Tab / ⌃C / arrows) is shown.  Gated on an active session
    /// (spec 003 FR-013) — with no live wire there is nothing to send
    /// a control key to, so the strip is hidden rather than dead.
    private let showsComposeQuickKeys: Bool
    private let onToggleDirectMode: () -> Void
    private let onSetDirectKeystrokePage: (KeyboardPage) -> Void
    private let onSetDirectInputSurface: (DirectKeystrokeInputSurface) -> Void
    private let onTapDirectKey: (DirectKey) -> Void
    private let onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void
    private let onMacSessionControl: (MacSessionControl) -> Void
    private let onComposeQuickKey: (ComposeQuickKey) -> Void
    private let onDismissDirectModeWarning: () -> Void
    private let onComposeFocusChange: (Bool) -> Void
    /// Whether Live type-through is the active dock mode (spec 009). Live and
    /// Compose share the editor surface; this flips the editor's commit hook
    /// to type-through dispatch, hides Send, and re-targets ⌫/↵.
    private let liveTypeThroughActive: Bool
    /// Persistent Live transport/latency disclosure (FR-014). Fixed strings.
    private let liveTransportDisclosureText: String
    /// Per-window Live delivery status line (FR-013). Fixed catalog copy.
    private let liveStatusText: String?
    private let onSelectMode: (NaruRemoteAppModel.RemoteInputDockMode) -> Void
    /// Committed-text snapshot hook for Live mode: `(committedText, hasMarkedText)`.
    private let onLiveCommit: (String, Bool) -> Void
    private let onLiveDeleteBackward: () -> Void
    private let onLiveNewline: () -> Void
    /// Hoisted compose-expansion request (compose-reveal fix, 2026-07-05).
    /// Tapping the floating "Compose" reveal flips the dock's *placement*
    /// in the app shell (floating overlay → pinned safe-area inset), which
    /// recreates this view. Local `@State` died with the old instance, so
    /// the editor collapsed before the keyboard ever rose — the request
    /// must live in the shell and arrive back as a prop.
    private let composeExpansionRequested: Bool
    private let onRequestComposeExpansion: (Bool) -> Void

    public init(
        initialText: String,
        statusText: String,
        helperStatusText: String? = nil,
        onSend: @escaping (String) -> Void = { _ in },
        onTextChange: @escaping (String) -> Void = { _ in },
        onComposeSendPreparation: @escaping (ComposeSendPreparationReport) -> Void = { _ in },
        directKeystrokeMode: DirectKeystrokeMode = DirectKeystrokeMode(),
        stickyModifierState: StickyModifierState = StickyModifierState(),
        layoutStyle: RemoteInputDockLayoutStyle = .standard,
        showsCompactStatusText: Bool = false,
        showsMacSessionControls: Bool = false,
        showsComposeQuickKeys: Bool = false,
        liveTypeThroughActive: Bool = false,
        liveTransportDisclosureText: String = "",
        liveStatusText: String? = nil,
        onToggleDirectMode: @escaping () -> Void = {},
        onSelectMode: @escaping (NaruRemoteAppModel.RemoteInputDockMode) -> Void = { _ in },
        onSetDirectKeystrokePage: @escaping (KeyboardPage) -> Void = { _ in },
        onSetDirectInputSurface: @escaping (DirectKeystrokeInputSurface) -> Void = { _ in },
        onTapDirectKey: @escaping (DirectKey) -> Void = { _ in },
        onHardwareKey: @escaping (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void = { _, _, _ in },
        onMacSessionControl: @escaping (MacSessionControl) -> Void = { _ in },
        onComposeQuickKey: @escaping (ComposeQuickKey) -> Void = { _ in },
        onLiveCommit: @escaping (String, Bool) -> Void = { _, _ in },
        onLiveDeleteBackward: @escaping () -> Void = {},
        onLiveNewline: @escaping () -> Void = {},
        onDismissDirectModeWarning: @escaping () -> Void = {},
        onComposeFocusChange: @escaping (Bool) -> Void = { _ in },
        composeExpansionRequested: Bool = false,
        onRequestComposeExpansion: @escaping (Bool) -> Void = { _ in }
    ) {
        self.initialText = initialText
        self._text = State(initialValue: initialText)
        self._lastAppliedInitialText = State(initialValue: initialText)
        self._lastPropagatedComposeText = State(initialValue: initialText)
        self.statusText = statusText
        self.helperStatusText = helperStatusText
        self.onSend = onSend
        self.onTextChange = onTextChange
        self.onComposeSendPreparation = onComposeSendPreparation
        self.directKeystrokeMode = directKeystrokeMode
        self.stickyModifierState = stickyModifierState
        self.layoutStyle = layoutStyle
        self.showsCompactStatusText = showsCompactStatusText
        self.showsMacSessionControls = showsMacSessionControls
        self.showsComposeQuickKeys = showsComposeQuickKeys
        self.liveTypeThroughActive = liveTypeThroughActive
        self.liveTransportDisclosureText = liveTransportDisclosureText
        self.liveStatusText = liveStatusText
        self.onToggleDirectMode = onToggleDirectMode
        self.onSelectMode = onSelectMode
        self.onSetDirectKeystrokePage = onSetDirectKeystrokePage
        self.onSetDirectInputSurface = onSetDirectInputSurface
        self.onTapDirectKey = onTapDirectKey
        self.onHardwareKey = onHardwareKey
        self.onMacSessionControl = onMacSessionControl
        self.onComposeQuickKey = onComposeQuickKey
        self.onLiveCommit = onLiveCommit
        self.onLiveDeleteBackward = onLiveDeleteBackward
        self.onLiveNewline = onLiveNewline
        self.onDismissDirectModeWarning = onDismissDirectModeWarning
        self.onComposeFocusChange = onComposeFocusChange
        self.composeExpansionRequested = composeExpansionRequested
        self.onRequestComposeExpansion = onRequestComposeExpansion
    }

    /// The dock mode derived from the two mutually exclusive flags. Compose is
    /// the default; Live and Direct are opt-ins (FR-001/FR-016).
    private var currentDockMode: NaruRemoteAppModel.RemoteInputDockMode {
        if directKeystrokeMode.isActive { return .direct }
        if liveTypeThroughActive { return .live }
        return .compose
    }

    public var body: some View {
        Group {
            switch layoutStyle {
            case .standard:
                standardBody
            case .compactAccessory:
                compactAccessoryBody
            case .floatingAccessory:
                floatingAccessoryBody
            }
        }
        .frame(maxWidth: compactWindowWidth, alignment: .center)
        .overlay(alignment: .top) {
            crossingPulseOverlay
        }
        .onChange(of: initialText) { _, newValue in
            if liveTypeThroughActive {
                applyLiveExternalText(newValue)
                return
            }
            guard shouldApplyExternalComposeText(newValue) else {
                return
            }
            cancelPendingComposeTextPropagation()
            lastAppliedInitialText = newValue
            guard text != newValue else {
                return
            }
            lastPropagatedComposeText = newValue
            text = newValue
        }
        .onChange(of: text) { _, newValue in
            if liveTypeThroughActive {
                handleLiveTextChange(newValue)
            } else {
                scheduleComposeTextPropagationIfNeeded(newValue)
            }
        }
        .task(id: pendingComposeTextPropagation) {
            await runPendingComposeTextPropagation()
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
                flushComposeTextToModelIfNeeded(currentComposeTextSnapshot(), force: true)
                composeFieldFocused = false
                onRequestComposeExpansion(false)
                onComposeFocusChange(false)
            }
        }
        // Compose-reveal fix (2026-07-05): the expansion request is
        // hoisted to the shell, and granting it can swap the dock's
        // placement (floating overlay → pinned inset), recreating this
        // view. The recreated instance owns the editor, so it — not the
        // tapped instance — takes first responder.
        .onAppear {
            focusComposeEditorForGrantedExpansionIfNeeded()
        }
        .onChange(of: composeExpansionRequested) { _, requested in
            if requested {
                focusComposeEditorForGrantedExpansionIfNeeded()
            }
        }
        .onDisappear {
            cancelPendingComposeTextPropagation()
        }
        // FR-009 — first-entry warning dialog attached at the dock
        // level so the alert chrome sits over the dock and feels
        // anchored to the mode picker the user just tapped.
        .directModeEntryWarning(
            mode: directKeystrokeMode,
            onDismiss: onDismissDirectModeWarning
        )
    }

    private var compactWindowWidth: CGFloat? {
        #if os(iOS) && canImport(UIKit)
        guard horizontalSizeClass == .compact else {
            return nil
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else {
                continue
            }
            if let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first {
                return max(1, window.bounds.width)
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                // Mission control / Mac window controls collapse into a
                // single header menu so they no longer occupy a full row
                // above the editor (frees vertical space for typing).
                if showsMacSessionControls, !directKeystrokeMode.isActive {
                    compactMacControlMenu
                }

                if !directKeystrokeMode.isActive {
                    statusBlock
                }
            }

            modePicker

            if directKeystrokeMode.isActive {
                directKeyboard
            } else {
                liveDisclosureBadge
                composeRow
                composeActionRow
                liveStatusLine
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                if let compactStatusText {
                    compactStatusLine(compactStatusText)
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

    @ViewBuilder
    private var floatingAccessoryBody: some View {
        if showsCompactComposeEditor || directKeystrokeMode.isActive {
            compactAccessoryBody
        } else {
            floatingControlStrip
        }
    }

    private var floatingControlStrip: some View {
        HStack(spacing: 6) {
            Button {
                onToggleDirectMode()
            } label: {
                Label("Direct mode", systemImage: "keyboard")
                    .labelStyle(.iconOnly)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .background(NaruColors.surfaceMuted)
            .clipShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Direct mode")
            .accessibilityIdentifier("naru.input.direct-toggle")

            liveModeToggleButton(diameter: 38)

            Button {
                onRequestComposeExpansion(true)
            } label: {
                // Primary action of the idle live HUD: tap to type.
                // Labelled (not icon-only) so the floating pill reads
                // as "Compose" instead of a guessable glyph — the
                // Direct toggle + menus stay compact icons beside it.
                Label("Compose", systemImage: "text.cursor")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Compose")
            .accessibilityIdentifier("naru.input.compose-reveal")

            if showsMacSessionControls {
                compactMacControlMenu
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(NaruColors.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
        .padding(.bottom, 8)
    }

    /// Compact/floating Live-mode toggle (spec 009 FR-001), sitting beside the
    /// Direct toggle so Live is one tap away on the phone-first live-session
    /// accessory where the segmented mode picker does not render.
    private func liveModeToggleButton(diameter: CGFloat) -> some View {
        Button {
            onSelectMode(liveTypeThroughActive ? .compose : .live)
        } label: {
            Label("Live type-through", systemImage: "dot.radiowaves.left.and.right")
                .labelStyle(.iconOnly)
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .background(NaruColors.surfaceMuted)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(liveTypeThroughActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(liveTypeThroughActive ? "Exit Live type-through" : "Live type-through")
        .accessibilityIdentifier("naru.input.live-toggle")
    }

    private var compactComposeRow: some View {
        VStack(spacing: 8) {
            // Mission control row on top — Direct + Live toggles + Mac window
            // controls — so the editor + action row below own the space.
            HStack(spacing: 10) {
                Button {
                    onToggleDirectMode()
                } label: {
                    Label("Direct mode", systemImage: "keyboard")
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(NaruColors.surfaceMuted)
                .clipShape(Circle())
                .accessibilityIdentifier("naru.input.direct-toggle")

                liveModeToggleButton(diameter: 36)

                if showsMacSessionControls {
                    compactMacControlMenu
                }

                Spacer(minLength: 0)
            }

            liveDisclosureBadge

            if showsCompactComposeEditor {
                composeTextEditor
                    .frame(minHeight: 40, maxHeight: compactComposeEditorMaxHeight)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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

                composeActionRow
                liveStatusLine
            } else {
                compactComposeRevealButton
            }
        }
    }

    private var showsCompactComposeEditor: Bool {
        Self.shouldShowCompactComposeEditor(
            isFocused: composeFieldFocused,
            text: text,
            expansionRequested: composeExpansionRequested
        )
    }

    private var compactComposeEditorMaxHeight: CGFloat {
        Self.compactComposeEditorMaxHeight(
            isFocused: composeFieldFocused,
            text: text,
            expansionRequested: composeExpansionRequested
        )
    }

    /// Focus the compose editor after the shell granted an expansion
    /// request (see `composeExpansionRequested`). Called from both
    /// `onAppear` (placement swap recreated the dock) and the request's
    /// `onChange` (same instance kept). The yield lets the editor mount
    /// before first responder is requested.
    private func focusComposeEditorForGrantedExpansionIfNeeded() {
        guard composeExpansionRequested,
              !directKeystrokeMode.isActive,
              !composeFieldFocused
        else { return }
        Task { @MainActor in
            await Task.yield()
            focusComposeEditor()
        }
    }

    nonisolated static func shouldShowCompactComposeEditor(
        isFocused: Bool,
        text: String,
        expansionRequested: Bool
    ) -> Bool {
        let hasDraft = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isFocused || hasDraft || expansionRequested
    }

    nonisolated static func compactComposeEditorMaxHeight(
        isFocused: Bool,
        text: String,
        expansionRequested: Bool = false
    ) -> CGFloat {
        Self.shouldShowCompactComposeEditor(
            isFocused: isFocused,
            text: text,
            expansionRequested: expansionRequested
        )
            ? compactComposeExpandedMaxHeight
            : compactComposeIdleMaxHeight
    }

    private var compactComposeRevealButton: some View {
        Button {
            onRequestComposeExpansion(true)
        } label: {
            Label("Compose", systemImage: "text.cursor")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .background(NaruColors.surfaceEditor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(NaruColors.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compose")
        .accessibilityIdentifier("naru.input.compose-reveal")
    }

    private var compactDirectHeader: some View {
        ViewThatFits(in: .horizontal) {
            compactDirectHeaderRow(showsComposeTitle: true, usesShortSurfaceLabel: false)
            compactDirectHeaderRow(showsComposeTitle: false, usesShortSurfaceLabel: false)
            compactDirectHeaderRow(showsComposeTitle: false, usesShortSurfaceLabel: true)
        }
    }

    private func compactDirectHeaderRow(
        showsComposeTitle: Bool,
        usesShortSurfaceLabel: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                onToggleDirectMode()
            } label: {
                if showsComposeTitle {
                    Label("Compose", systemImage: "text.cursor")
                } else {
                    Label("Compose", systemImage: "text.cursor")
                        .labelStyle(.iconOnly)
                        .frame(width: 38, height: 32)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Compose")
            .accessibilityIdentifier("naru.input.compose-toggle")

            if showsMacSessionControls {
                compactMacControlMenu
            }

            directInputSurfaceControl(usesShortLabel: usesShortSurfaceLabel)

            Spacer(minLength: 0)

            DirectModeBadge(
                isVisible: directKeystrokeMode.isActive,
                accessibilityID: "naru.direct.badge.dock"
            )
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

            if let helperStatusText = helperStatusText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !helperStatusText.isEmpty {
                Text(helperStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("naru.input.helper-status")
            }
        }
    }

    private var compactStatusText: String? {
        Self.resolvedCompactStatusText(
            hasStatus: showsCompactStatusText,
            statusText: statusText,
            helperStatusText: helperStatusText
        )
    }

    private func compactStatusLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("naru.input.compact-status")
    }

    /// Segmented picker that switches among the three coexisting dock modes
    /// (spec 009 FR-001): Compose & Send (default), Live type-through, and
    /// Direct Keystroke. The model is the single source of truth for mode
    /// state; every change dispatches `onSelectMode`.
    private var modePicker: some View {
        Picker(
            "Input mode",
            selection: Binding<NaruRemoteAppModel.RemoteInputDockMode>(
                get: { currentDockMode },
                set: { newValue in
                    if newValue != currentDockMode {
                        onSelectMode(newValue)
                    }
                }
            )
        ) {
            Text("Compose").tag(NaruRemoteAppModel.RemoteInputDockMode.compose)
            Text("Live").tag(NaruRemoteAppModel.RemoteInputDockMode.live)
            Text("Direct").tag(NaruRemoteAppModel.RemoteInputDockMode.direct)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("naru.input.mode-picker")
    }

    /// Persistent Live transport/latency disclosure badge (spec 009 FR-014),
    /// peer to Direct's "IME off" badge. Shown whenever Live is active so the
    /// degraded/observed transport is never misrepresented.
    @ViewBuilder
    private var liveDisclosureBadge: some View {
        if liveTypeThroughActive, !liveTransportDisclosureText.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                Text(liveTransportDisclosureText)
                    .font(.caption2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NaruColors.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("naru.input.live-disclosure")
        }
    }

    @ViewBuilder
    private var liveStatusLine: some View {
        if liveTypeThroughActive, let liveStatusText, !liveStatusText.isEmpty {
            Text(liveStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("naru.input.live-status")
        }
    }

    /// Mac-aware session controls similar to the buttons users
    /// expect in Apple-oriented remote desktop clients. They emit
    /// documented macOS keyboard shortcuts over the existing VNC
    /// `KeyEvent` path; no Compose text is changed.
    private var macSessionControlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MacSessionControl.allCases, id: \.self) { control in
                    Button {
                        onMacSessionControl(control)
                    } label: {
                        Label(control.label, systemImage: control.systemImageName)
                            .font(.system(size: 13, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .frame(minHeight: 38)
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
                    .accessibilityLabel(control.accessibilityLabel)
                    .accessibilityIdentifier("naru.input.mac-control.\(control.rawValue)")
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("naru.input.mac-controls")
    }

    /// Compact live sessions keep the remote screen dominant: Mac window
    /// controls remain one tap away, but collapse from a permanent strip into
    /// a menu inside the accessory row.
    private var compactMacControlMenu: some View {
        Menu {
            ForEach(MacSessionControl.allCases, id: \.self) { control in
                Button {
                    onMacSessionControl(control)
                } label: {
                    Label(control.label, systemImage: control.systemImageName)
                }
                .accessibilityLabel(control.accessibilityLabel)
                .accessibilityIdentifier("naru.input.mac-control.\(control.rawValue)")
            }
        } label: {
            Image(systemName: "rectangle.3.group")
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
        }
        .buttonStyle(.bordered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mac controls")
        .accessibilityIdentifier("naru.input.mac-controls.menu")
    }

    /// Standard-layout compose editor height: slim when there is
    /// nothing to compose yet (disconnected / idle), full multi-line
    /// height once focused or holding a draft.
    private var standardComposeEditorMinHeight: CGFloat {
        isStandardComposeEditorExpanded ? 72 : 48
    }

    private var standardComposeEditorMaxHeight: CGFloat {
        isStandardComposeEditorExpanded ? 120 : 48
    }

    private var isStandardComposeEditorExpanded: Bool {
        composeFieldFocused
            || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The always-visible Compose action row: remote ⌫ / ↵ on the left
    /// and the prominent Send on the right. Backspace/Enter dispatch
    /// discrete remote `KeyEvent`s (compose a command → Send types it →
    /// Enter runs it); they need a live session, so they disable pre-
    /// connect. Per product direction the terminal shortcut strip
    /// (Esc/Tab/⌃C/arrows) is NOT here — those live on the Direct
    /// (virtual keyboard) special page.
    private var composeActionRow: some View {
        HStack(spacing: 10) {
            composeRemoteKeyButton(.backspace, systemImage: "delete.left")
            composeRemoteKeyButton(.enter, systemImage: "return")

            Spacer(minLength: 8)

            // Live type-through has no Send — commit is the trigger (FR-002).
            if !liveTypeThroughActive {
                Button {
                    sendCurrentComposeText()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 40)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isComposeSendDisabled)
                .help("Send composed text")
                .accessibilityIdentifier("naru.input.send")
            }
        }
    }

    private func composeRemoteKeyButton(
        _ key: ComposeQuickKey,
        systemImage: String
    ) -> some View {
        Button {
            // In Live mode ⌫/↵ drive the editing window so the local mirror
            // and the remote stay in step (D1); in Compose they emit a
            // discrete remote KeyEvent.
            if liveTypeThroughActive, key == .backspace {
                onLiveDeleteBackward()
            } else if liveTypeThroughActive, key == .enter {
                onLiveNewline()
            } else {
                onComposeQuickKey(key)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 50, height: 40)
                .background(NaruColors.surfaceKey)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NaruColors.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        // Remote keys need a live session; stay visible but inert pre-connect.
        .disabled(!showsComposeQuickKeys)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityIdentifier("naru.input.compose-action.\(key.rawValue)")
    }

    private var composeRow: some View {
        // UX punch-list #204: bumped HStack spacing 12 → 16 and
        // padded the editor's trailing inset so the Send paperplane
        // no longer sits flush against the editor stroke.  Also
        // gives the disabled-state Send button visible breathing
        // room in static screenshots.
        composeTextEditor
            // The editor now owns the dock's vertical space: the Send /
            // backspace / enter actions sit in `composeActionRow` below,
            // and the terminal strip + Mac controls no longer stack above
            // it, so the field can breathe without the dock growing tall.
            .frame(
                minHeight: standardComposeEditorMinHeight,
                maxHeight: standardComposeEditorMaxHeight
            )
            .frame(maxWidth: .infinity)
            // UX punch-list #302: adaptive `NaruColors.surfaceEditor`
            // (BRANDING.md §7 `Surface`) reads as paper on light, slate
            // on dark.
            .background(NaruColors.surfaceEditor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .simultaneousGesture(TapGesture().onEnded {
                focusComposeEditor()
            })
            .composeEditorShellAccessibility()
    }

    /// Direct-mode body: hides the Compose TextEditor + Send and
    /// switches among the available Direct input surfaces. The
    /// default `.customKeyboard` surface preserves FR-001; the
    /// `.systemKeyboard` and `.hardwareKeyboard` surfaces are
    /// explicit opt-ins for native iOS typing and screen-space
    /// recovery with Bluetooth keyboards.
    @ViewBuilder
    private var directKeyboard: some View {
        VStack(spacing: 8) {
            if Self.shouldShowPersistentDirectInputSurfacePicker(layoutStyle: layoutStyle) {
                HStack(spacing: 10) {
                    Text("Keyboard")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    directInputSurfaceControl()
                    Spacer(minLength: 0)
                }
            }
            if Self.shouldShowPersistentMacControlStrip(
                showsMacSessionControls: showsMacSessionControls,
                layoutStyle: layoutStyle
            ) {
                macSessionControlStrip
            }

            switch directKeystrokeMode.inputSurface {
            case .customKeyboard:
                customDirectKeyboard
            case .systemKeyboard:
                systemDirectKeyboard
            case .hardwareKeyboard:
                hardwareDirectKeyboard
            }
        }
    }

    /// Single, self-explanatory keyboard-source control used in both
    /// the standard dock and the compact live header.  Replaces the
    /// old cryptic three-segment "Naru | iOS | HW" picker that stacked
    /// a second segmented control under Compose|Direct: a user now
    /// reads "Naru keyboard ▾" and the menu spells out each option in
    /// full, instead of guessing what three abbreviations mean.
    private func directInputSurfaceControl(usesShortLabel: Bool = false) -> some View {
        Menu {
            ForEach(DirectKeystrokeInputSurface.allCases, id: \.self) { surface in
                Button {
                    onSetDirectInputSurface(surface)
                } label: {
                    Label(
                        Self.directInputSurfaceLabel(for: surface),
                        systemImage: Self.directInputSurfaceSystemImageName(for: surface)
                    )
                }
                .accessibilityIdentifier("naru.direct.input-surface-menu.\(surface.rawValue)")
            }
        } label: {
            let surfaceLabel = usesShortLabel
                ? Self.directInputSurfaceShortLabel(for: directKeystrokeMode.inputSurface)
                : Self.directInputSurfaceLabel(for: directKeystrokeMode.inputSurface)
            HStack(spacing: 6) {
                Image(systemName: Self.directInputSurfaceSystemImageName(for: directKeystrokeMode.inputSurface))
                Text(surfaceLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 38)
            .padding(.horizontal, 12)
            .fixedSize(horizontal: true, vertical: false)
            // Decorative icon + chevron must not surface as separate
            // "chevron.down" / glyph buttons in the accessibility tree —
            // the menu carries its own combined label below.
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(
            "Keyboard, \(Self.directInputSurfaceLabel(for: directKeystrokeMode.inputSurface))"
        )
        .accessibilityIdentifier("naru.direct.input-surface-menu")
    }

    @ViewBuilder
    private var customDirectKeyboard: some View {
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

    @ViewBuilder
    private var systemDirectKeyboard: some View {
        #if canImport(UIKit)
        DirectKeystrokeSystemKeyboardView(
            isActive: true,
            onTextInput: { insertedText in
                for key in Self.directKeys(fromSystemKeyboardText: insertedText) {
                    onTapDirectKey(key)
                }
            },
            onBackspace: {
                onTapDirectKey(.named(.backspace))
            }
        )
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
        #else
        customDirectKeyboard
        #endif
    }

    @ViewBuilder
    private var hardwareDirectKeyboard: some View {
        #if canImport(UIKit)
        DirectKeystrokeResponderView(
            isActive: true,
            onHardwareKey: onHardwareKey
        )
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        #endif
    }

    nonisolated static func directKeys(fromSystemKeyboardText text: String) -> [DirectKey] {
        text.compactMap { character in
            switch character {
            case "\n", "\r":
                return .named(.return)
            case "\t":
                return .named(.tab)
            default:
                guard KeysymMapping.keysym(for: character) != nil else {
                    return nil
                }
                return .character(character)
            }
        }
    }

    private func updateComposeFocus(_ focused: Bool) {
        composeFieldFocused = focused
        if !focused {
            let currentText = currentComposeTextSnapshot()
            flushComposeTextToModelIfNeeded(currentText, force: true)
            if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onRequestComposeExpansion(false)
            }
        }
    }

    private var isComposeSendDisabled: Bool {
        #if os(iOS) && canImport(UIKit)
        Self.composeSendDisabled(
            isPreparingComposeSend: isPreparingComposeSend,
            isComposeFieldFocused: composeFieldFocused,
            currentText: composeCommitController.readCurrentText(fallback: text)
        )
        #else
        text.isEmpty
        #endif
    }

    private var composeTextEditor: some View {
        #if os(iOS) && canImport(UIKit)
        ComposeTextEditingView(
            text: $text,
            onFocusChange: updateComposeFocus(_:),
            onMarkedTextCommit: handleMarkedComposeTextCommit(_:),
            commitController: composeCommitController,
            liveModeActive: liveTypeThroughActive
        )
        #else
        ComposeTextEditingView(
            text: $text,
            onFocusChange: updateComposeFocus(_:)
        )
        #endif
    }

    private func handleMarkedComposeTextCommit(_ committedText: String) {
        guard !directKeystrokeMode.isActive else {
            return
        }
        // Live mode delivers each committed unit as it commits (FR-002/FR-003):
        // the marked→committed boundary is exactly the trigger.
        if liveTypeThroughActive {
            onLiveCommit(committedText, false)
            return
        }
        #if os(iOS) && canImport(UIKit)
        composeSendNeedsMarkedCommitStabilization = true
        #endif
        guard !composeFieldFocused else {
            return
        }
        if text != committedText {
            text = committedText
        }
        scheduleComposeTextPropagationIfNeeded(committedText)
    }

    /// Live-mode editor change: feed the committed-text snapshot (marked range
    /// excluded) to the model on each non-composing change. Marked/composing
    /// text is never dispatched (FR-002) — it delivers at the commit boundary
    /// via `handleMarkedComposeTextCommit`.
    private func handleLiveTextChange(_ newValue: String) {
        #if os(iOS) && canImport(UIKit)
        guard !composeCommitController.hasMarkedText else {
            return
        }
        #endif
        onLiveCommit(newValue, false)
    }

    /// Live-mode external text application: the model owns the authoritative
    /// line mirror (`liveFieldText`) and drives clears on Return/seal. Apply
    /// the model's value even while focused, but never during IME composition
    /// so the candidate window is not disrupted (T015 protection).
    private func applyLiveExternalText(_ newValue: String) {
        #if os(iOS) && canImport(UIKit)
        guard !composeCommitController.hasMarkedText else {
            return
        }
        #endif
        lastAppliedInitialText = newValue
        if text != newValue {
            text = newValue
        }
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
        let hadMarkedTextBeforeSend = composeCommitController.hasMarkedText
        let needsMarkedCommitStabilization = composeSendNeedsMarkedCommitStabilization
        let immediateText = composeCommitController.commitMarkedTextAndRead(fallback: text)
        if immediateText != text {
            text = immediateText
        }
        flushComposeTextToModelIfNeeded(immediateText, force: true)
        Task { @MainActor in
            let plan = Self.composeSendPreparationPlan(
                hadMarkedTextBeforeSend: hadMarkedTextBeforeSend,
                needsMarkedCommitStabilization: needsMarkedCommitStabilization
            )
            let preparationStartedAt = Date()
            let finalText = await composeCommitController.readStabilizedCurrentText(
                fallback: immediateText,
                snapshotCount: plan.snapshotCount,
                snapshotDelayNanoseconds: plan.snapshotDelayNanoseconds
            )
            let preparationMilliseconds = Int(
                (Date().timeIntervalSince(preparationStartedAt) * 1_000).rounded()
            )
            let preparationReport = ComposeSendPreparationReport(
                mode: plan.mode,
                snapshotCount: plan.snapshotCount,
                durationBucket: DiagnosticTimingBucket.bucket(milliseconds: preparationMilliseconds)
            )
            if finalText != text {
                text = finalText
            }
            flushComposeTextToModelIfNeeded(finalText, force: true)
            onComposeSendPreparation(preparationReport)
            composeSendNeedsMarkedCommitStabilization = false
            isPreparingComposeSend = false
            guard !finalText.isEmpty else { return }
            triggerCrossingPulse()
            onSend(finalText)
        }
        #else
        onSend(text)
        #endif
    }

    /// Fires the Compose & Send "crossing" pulse (BRANDING.md §10 step 2:
    /// "press Send → a subtle pulse appears"). It marks the act of sending;
    /// the status line reports whether the text actually landed, so this is
    /// honest for any dispatch, not a success claim.
    private func triggerCrossingPulse() {
        crossingToken += 1
        let token = crossingToken
        crossingPulse = 0
        crossingVisible = true
        withAnimation(.easeOut(duration: 0.45)) {
            crossingPulse = 1
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 480_000_000)
            guard token == crossingToken else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                crossingVisible = false
            }
        }
    }

    /// The pulse itself — a Signal-Blue packet rising along a short faint
    /// lane above the dock (the §6.2 "pulse" primitive). Always present in
    /// the tree; invisible until a send fires.
    private var crossingPulseOverlay: some View {
        ZStack(alignment: .bottom) {
            Capsule()
                .fill(Color(NaruColors.signalBlue).opacity(0.16))
                .frame(width: 4, height: 38)
            Circle()
                .fill(Color(NaruColors.signalBlue))
                .frame(width: 11, height: 11)
                .shadow(color: Color(NaruColors.signalBlue).opacity(0.55), radius: 5)
                .offset(y: -CGFloat(crossingPulse) * 28)
        }
        .frame(width: 11, height: 38)
        .opacity(crossingVisible ? 1 : 0)
        .offset(y: -26)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    nonisolated static func composeSendPreparationPlan(
        hadMarkedTextBeforeSend: Bool,
        needsMarkedCommitStabilization: Bool = false
    ) -> (
        mode: ComposeSendPreparationMode,
        snapshotCount: Int,
        snapshotDelayNanoseconds: UInt64
    ) {
        if hadMarkedTextBeforeSend || needsMarkedCommitStabilization {
            return (
                .markedTextStabilization,
                composeSendStabilizationSnapshotCount,
                composeSendStabilizationDelayNanoseconds
            )
        }
        return (
            .fastSnapshot,
            composeSendFastSnapshotCount,
            composeSendFastDelayNanoseconds
        )
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
            hasMarkedText: hasMarkedText,
            isComposeFieldFocused: composeFieldFocused
        )
    }

    private func shouldPropagateLocalComposeTextToModel(
        _ newValue: String,
        force: Bool = false
    ) -> Bool {
        #if os(iOS) && canImport(UIKit)
        let hasMarkedText = composeCommitController.hasMarkedText
        #else
        let hasMarkedText = false
        #endif

        return Self.shouldPropagateLocalComposeTextToModel(
            newValue: newValue,
            lastPropagatedText: lastPropagatedComposeText,
            isDirectModeActive: directKeystrokeMode.isActive,
            hasMarkedText: hasMarkedText,
            isComposeFieldFocused: composeFieldFocused,
            force: force
        )
    }

    private func currentComposeTextSnapshot() -> String {
        #if os(iOS) && canImport(UIKit)
        composeCommitController.readCurrentText(fallback: text)
        #else
        text
        #endif
    }

    private func scheduleComposeTextPropagationIfNeeded(_ newValue: String) {
        guard shouldPropagateLocalComposeTextToModel(newValue) else {
            return
        }
        // Keep UIKit's IME loop local; AppModel only sees the latest idle snapshot.
        composeTextPropagationSequence &+= 1
        pendingComposeTextPropagation = PendingComposeTextPropagation(
            sequence: composeTextPropagationSequence,
            text: newValue
        )
    }

    private func runPendingComposeTextPropagation() async {
        guard let pendingComposeTextPropagation else {
            return
        }
        do {
            try await Task.sleep(nanoseconds: Self.composeTextPropagationDebounceNanoseconds)
        } catch {
            return
        }
        guard !Task.isCancelled else {
            return
        }
        flushComposeTextToModelIfNeeded(pendingComposeTextPropagation.text)
    }

    private func flushComposeTextToModelIfNeeded(_ newValue: String, force: Bool = false) {
        cancelPendingComposeTextPropagation()
        guard shouldPropagateLocalComposeTextToModel(newValue, force: force) else {
            return
        }
        lastPropagatedComposeText = newValue
        onTextChange(newValue)
    }

    private func cancelPendingComposeTextPropagation() {
        pendingComposeTextPropagation = nil
    }

    private struct PendingComposeTextPropagation: Equatable {
        let sequence: Int
        let text: String
    }

    nonisolated static func shouldPropagateLocalComposeTextToModel(
        isDirectModeActive: Bool,
        hasMarkedText: Bool,
        isComposeFieldFocused: Bool = false,
        force: Bool = false
    ) -> Bool {
        if force {
            return true
        }
        return !isDirectModeActive && !hasMarkedText && !isComposeFieldFocused
    }

    nonisolated static func shouldPropagateLocalComposeTextToModel(
        newValue: String,
        lastPropagatedText: String,
        isDirectModeActive: Bool,
        hasMarkedText: Bool,
        isComposeFieldFocused: Bool = false,
        force: Bool = false
    ) -> Bool {
        shouldPropagateLocalComposeTextToModel(
            isDirectModeActive: isDirectModeActive,
            hasMarkedText: hasMarkedText,
            isComposeFieldFocused: isComposeFieldFocused,
            force: force
        ) && newValue != lastPropagatedText
    }

    nonisolated static func didCommitMarkedComposeText(
        previouslyHadMarkedText: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        previouslyHadMarkedText && !hasMarkedText
    }

    nonisolated static func shouldAdoptUIKitComposeTextChange(
        resolvedText: String,
        currentBindingText: String,
        hasMarkedText: Bool = false,
        isFirstResponder: Bool = false,
        liveModeActive: Bool = false
    ) -> Bool {
        // Compose keeps the model out of the IME loop by only adopting UIKit
        // text when unfocused. Live type-through must see every committed
        // change (including ASCII while focused) so it can dispatch as-you-type,
        // so it adopts while focused too — but never during composition.
        (liveModeActive || !isFirstResponder)
            && !hasMarkedText
            && resolvedText != currentBindingText
    }

    nonisolated static func composeSendDisabled(
        isPreparingComposeSend: Bool,
        isComposeFieldFocused: Bool,
        currentText: String
    ) -> Bool {
        if isPreparingComposeSend {
            return true
        }
        if isComposeFieldFocused {
            return false
        }
        return currentText.isEmpty
    }

    nonisolated static func shouldDeferUIKitComposeBindingWrite(
        hasMarkedText: Bool,
        isFirstResponder: Bool,
        proposedText: String,
        lastAppliedBindingText: String,
        currentUIKitText: String,
        liveModeActive: Bool = false
    ) -> Bool {
        if hasMarkedText {
            return true
        }

        // Live type-through: the model owns the authoritative line mirror and
        // must be able to clear it on Return/seal even while the field is
        // focused. Only in-composition writes are deferred (handled above).
        if liveModeActive {
            return false
        }

        if isFirstResponder,
           !currentUIKitText.isEmpty,
           proposedText.isEmpty {
            return true
        }

        if isFirstResponder,
           !proposedText.isEmpty,
           proposedText.count < currentUIKitText.count,
           currentUIKitText.hasPrefix(proposedText) {
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

        if newValue == currentText {
            return true
        }

        if newValue.isEmpty {
            if isComposeFieldFocused,
               !currentText.isEmpty,
               currentText != lastAppliedInitialText {
                return false
            }
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
                if currentTextBeforeCommit.contains(markedTextBeforeCommit) {
                    return currentTextBeforeCommit
                }
                return markedTextBeforeCommit
            }
            return ""
        }

        if let markedTextBeforeCommit, !markedTextBeforeCommit.isEmpty {
            if currentTextBeforeCommit.contains(markedTextBeforeCommit) {
                return currentTextBeforeCommit
            }
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
        if immediateText.contains(stabilizedText),
           immediateText.count > stabilizedText.count {
            return immediateText
        }
        if stabilizedText.hasPrefix(immediateText),
           stabilizedText.count > immediateText.count {
            return stabilizedText
        }
        if stabilizedText.contains(immediateText),
           stabilizedText.count > immediateText.count {
            return stabilizedText
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

    /// Event-driven exit test for the Compose Send stabilization loop
    /// (QW1). The fixed 30×16ms poll was pure latency for the common case
    /// (already-committed text). We stop early once the IME has released
    /// its marked range *and* two consecutive raw snapshots agree — at that
    /// point further polling cannot change the resolved text. While marked
    /// text is still in flight we never exit, which preserves the
    /// delayed-Korean-commit guarantee; the caller's snapshot count remains
    /// the upper bound safety net.
    nonisolated static func composeStabilizationShouldExitEarly(
        hasMarkedText: Bool,
        previousSnapshot: String?,
        currentSnapshot: String
    ) -> Bool {
        guard !hasMarkedText else { return false }
        guard let previousSnapshot else { return false }
        return previousSnapshot == currentSnapshot
    }

    struct ComposeStabilizationOutcome: Equatable {
        var text: String
        var snapshotsTaken: Int
    }

    /// Pure driver mirroring `ComposeTextCommitController.readStabilizedCurrentText`
    /// over a pre-recorded snapshot sequence, so the early-exit policy is
    /// testable without a live `UITextView`. `snapshots` are the
    /// `(text, hasMarkedText)` reads in the order the loop would observe
    /// them; `snapshotCount` is the upper bound.
    nonisolated static func simulateComposeStabilization(
        fallback: String,
        snapshotCount: Int,
        snapshots: [(text: String, hasMarkedText: Bool)]
    ) -> ComposeStabilizationOutcome {
        var resolved = fallback
        var previousSnapshot: String?
        var taken = 0
        let upperBound = max(1, snapshotCount)
        for index in 0..<upperBound {
            // If the recording runs short, keep reading the last observed
            // value — the live loop would re-read the same steady text.
            let snapshot = index < snapshots.count
                ? snapshots[index]
                : (snapshots.last ?? (text: resolved, hasMarkedText: false))
            taken += 1
            resolved = resolvedStabilizedComposeText(
                immediateText: resolved,
                stabilizedSnapshots: [snapshot.text]
            )
            if composeStabilizationShouldExitEarly(
                hasMarkedText: snapshot.hasMarkedText,
                previousSnapshot: previousSnapshot,
                currentSnapshot: snapshot.text
            ) {
                break
            }
            previousSnapshot = snapshot.text
        }
        return ComposeStabilizationOutcome(text: resolved, snapshotsTaken: taken)
    }

    nonisolated static func shouldShowCompactStatusText(
        hasStatus: Bool,
        statusText: String
    ) -> Bool {
        let trimmed = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        return hasStatus && !trimmed.isEmpty
    }

    nonisolated static func shouldShowPersistentMacControlStrip(
        showsMacSessionControls: Bool,
        layoutStyle: RemoteInputDockLayoutStyle
    ) -> Bool {
        showsMacSessionControls && layoutStyle == .standard
    }

    nonisolated static func shouldInlineDirectInputSurfacePicker(
        layoutStyle: RemoteInputDockLayoutStyle,
        availableWidth: CGFloat? = nil,
        showsMacSessionControls: Bool = false
    ) -> Bool {
        guard layoutStyle == .compactAccessory else {
            return false
        }
        guard let availableWidth else {
            return true
        }
        let minimumWidth: CGFloat = showsMacSessionControls ? 430 : 360
        return availableWidth >= minimumWidth
    }

    nonisolated static func shouldShowCompactDirectInputSurfaceMenu(
        layoutStyle: RemoteInputDockLayoutStyle,
        availableWidth: CGFloat?,
        showsMacSessionControls: Bool
    ) -> Bool {
        layoutStyle == .compactAccessory && !shouldInlineDirectInputSurfacePicker(
            layoutStyle: layoutStyle,
            availableWidth: availableWidth,
            showsMacSessionControls: showsMacSessionControls
        )
    }

    nonisolated static func shouldShowPersistentDirectInputSurfacePicker(
        layoutStyle: RemoteInputDockLayoutStyle
    ) -> Bool {
        layoutStyle == .standard
    }

    nonisolated static func directInputSurfaceLabel(
        for surface: DirectKeystrokeInputSurface
    ) -> String {
        switch surface {
        case .customKeyboard:
            return "Naru keyboard"
        case .systemKeyboard:
            return "iOS keyboard"
        case .hardwareKeyboard:
            return "Hardware keyboard"
        }
    }

    nonisolated static func directInputSurfaceShortLabel(
        for surface: DirectKeystrokeInputSurface
    ) -> String {
        switch surface {
        case .customKeyboard:
            return "Naru"
        case .systemKeyboard:
            return "iOS"
        case .hardwareKeyboard:
            return "HW"
        }
    }

    nonisolated static func directInputSurfaceSystemImageName(
        for surface: DirectKeystrokeInputSurface
    ) -> String {
        switch surface {
        case .customKeyboard:
            return "keyboard"
        case .systemKeyboard:
            return "text.cursor"
        case .hardwareKeyboard:
            return "command"
        }
    }

    nonisolated static func resolvedCompactStatusText(
        hasStatus: Bool,
        statusText: String,
        helperStatusText: String?
    ) -> String? {
        if shouldShowCompactStatusText(hasStatus: hasStatus, statusText: statusText) {
            return statusText
        }

        let helperStatusText = helperStatusText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let helperStatusText, !helperStatusText.isEmpty else {
            return nil
        }
        return helperStatusText
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
    let onMarkedTextCommit: (String) -> Void
    let commitController: ComposeTextCommitController
    var liveModeActive: Bool = false
    #endif

    var body: some View {
        #if os(iOS) && canImport(UIKit)
        MultilingualComposeTextView(
            text: $text,
            onFocusChange: onFocusChange,
            onMarkedTextCommit: onMarkedTextCommit,
            commitController: commitController,
            liveModeActive: liveModeActive
        )
        #else
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
        #endif
    }
}

#if os(iOS) && canImport(UIKit)
private struct ComposeEditorLifecycleProbe: Equatable, Sendable {
    var instanceToken: String
    var makeCount: Int
    var updateCount: Int
    var textChangeCount: Int
    var focusEventCount: Int
    var isFirstResponder: Bool

    var accessibilityValue: String {
        [
            "token=\(instanceToken)",
            "make=\(makeCount)",
            "update=\(updateCount)",
            "change=\(textChangeCount)",
            "focus=\(focusEventCount)",
            "firstResponder=\(isFirstResponder ? "true" : "false")"
        ].joined(separator: ";")
    }
}

@MainActor
final class ComposeTextCommitController {
    private weak var textView: UITextView?
    private(set) var currentText: String = ""

    func attach(_ textView: UITextView) {
        self.textView = textView
        updateCurrentTextSnapshot(textView.text ?? "")
    }

    func focus() {
        textView?.becomeFirstResponder()
    }

    func updateCurrentText(from textView: UITextView) {
        updateCurrentTextSnapshot(textView.text ?? "")
    }

    internal func updateCurrentTextSnapshot(_ text: String) {
        currentText = text
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
        var previousSnapshot: String?
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
            if RemoteInputDockView.composeStabilizationShouldExitEarly(
                hasMarkedText: hasMarkedText,
                previousSnapshot: previousSnapshot,
                currentSnapshot: next
            ) {
                break
            }
            previousSnapshot = next
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
        updateCurrentText(from: textView)
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
    let onMarkedTextCommit: (String) -> Void
    let commitController: ComposeTextCommitController
    var liveModeActive: Bool = false

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
        textView.isAccessibilityElement = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.attach(textView)
        context.coordinator.reportLifecycle(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.recordUpdate()
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.accessibilityLabel = "Remote input text"
        textView.isAccessibilityElement = true
        context.coordinator.applyAccessibilityIdentifier(to: textView)

        // Do not overwrite UIKit's in-flight marked text. Korean/CJK
        // composition keeps intermediate state inside UITextView; setting
        // `text` during that window can collapse or reorder the candidate.
        if context.coordinator.shouldDeferBindingWrite(
            proposedText: text,
            textView: textView
        ) {
            context.coordinator.parent.commitController.updateCurrentText(from: textView)
            context.coordinator.reportLifecycle(textView)
            return
        }

        if textView.text != text {
            textView.text = text
            context.coordinator.parent.commitController.updateCurrentText(from: textView)
        }
        context.coordinator.markBindingTextApplied(text)
        context.coordinator.reportLifecycle(textView)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MultilingualComposeTextView
        private weak var textView: UITextView?
        private let instanceToken = UUID().uuidString
        private var makeCount = 0
        private var updateCount = 0
        private var textChangeCount = 0
        private var focusEventCount = 0
        private var previouslyHadMarkedText = false
        private var lastCommittedTextNotification: String?
        private var lastAppliedBindingText = ""
        private var lastReportedFocus = false

        init(parent: MultilingualComposeTextView) {
            self.parent = parent
        }

        func attach(_ textView: UITextView) {
            self.textView = textView
            parent.commitController.attach(textView)
            makeCount += 1
            previouslyHadMarkedText = textView.markedTextRange != nil
            lastCommittedTextNotification = textView.text ?? ""
            lastAppliedBindingText = parent.text
        }

        func recordUpdate() {
            updateCount += 1
        }

        func applyAccessibilityIdentifier(to textView: UITextView) {
            textView.accessibilityIdentifier = accessibilityIdentifier
        }

        func textViewDidChange(_ textView: UITextView) {
            textChangeCount += 1
            reportFocus(textView.isFirstResponder)
            parent.commitController.updateCurrentText(from: textView)
            let resolvedText = parent.commitController.readCurrentText(fallback: parent.text)
            if RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: resolvedText,
                currentBindingText: parent.text,
                hasMarkedText: textView.markedTextRange != nil,
                isFirstResponder: textView.isFirstResponder,
                liveModeActive: parent.liveModeActive
            ) {
                parent.text = resolvedText
            }
            notifyIfMarkedTextCommitted(textView, resolvedText: resolvedText)
            reportLifecycle(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            reportFocus(textView.isFirstResponder)
            parent.commitController.updateCurrentText(from: textView)
            let resolvedText = parent.commitController.readCurrentText(fallback: parent.text)
            if RemoteInputDockView.didCommitMarkedComposeText(
                previouslyHadMarkedText: previouslyHadMarkedText,
                hasMarkedText: textView.markedTextRange != nil
            ), RemoteInputDockView.shouldAdoptUIKitComposeTextChange(
                resolvedText: resolvedText,
                currentBindingText: parent.text,
                hasMarkedText: textView.markedTextRange != nil,
                isFirstResponder: textView.isFirstResponder,
                liveModeActive: parent.liveModeActive
            ) {
                parent.text = resolvedText
            }
            notifyIfMarkedTextCommitted(textView, resolvedText: resolvedText)
            reportLifecycle(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            reportFocus(true)
            reportLifecycle(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            reportFocus(false)
            reportLifecycle(textView)
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
                currentUIKitText: textView.text ?? "",
                liveModeActive: parent.liveModeActive
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
            parent.onMarkedTextCommit(resolvedText)
        }

        private func reportFocus(_ focused: Bool) {
            guard lastReportedFocus != focused else {
                return
            }
            lastReportedFocus = focused
            focusEventCount += 1
            parent.onFocusChange(focused)
        }

        fileprivate func reportLifecycle(_ textView: UITextView) {
            applyAccessibilityIdentifier(to: textView)
        }

        private var accessibilityIdentifier: String {
            guard Self.exposesLifecycleIdentifier else {
                return "naru.input.editor"
            }
            let probe = ComposeEditorLifecycleProbe(
                instanceToken: instanceToken,
                makeCount: makeCount,
                updateCount: updateCount,
                textChangeCount: textChangeCount,
                focusEventCount: focusEventCount,
                isFirstResponder: textView?.isFirstResponder ?? false
            )
            return "naru.input.editor;\(probe.accessibilityValue)"
        }

        private static var exposesLifecycleIdentifier: Bool {
            guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_EXPOSE_COMPOSE_LIFECYCLE"],
                  !raw.isEmpty
            else {
                return false
            }
            return raw != "0" && raw.lowercased() != "false"
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
