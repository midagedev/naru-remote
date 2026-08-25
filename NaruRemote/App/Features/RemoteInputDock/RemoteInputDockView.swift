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
    /// Spec 015 v1.1: the compact Compose field is one line tall, full stop.
    /// The founder read the old 88pt box as a multi-line editor eating the
    /// remote screen; long drafts scroll inside this height instead.
    nonisolated static let compactComposeEditorHeight: CGFloat = 40
    nonisolated static let minimumFloatingModeTargetDiameter: CGFloat = 44
    nonisolated static let composeSendFastSnapshotCount = 3
    nonisolated static let composeSendFastDelayNanoseconds: UInt64 = 0
    nonisolated static let composeSendStabilizationSnapshotCount = 30
    nonisolated static let composeSendStabilizationDelayNanoseconds: UInt64 = 16_000_000
    nonisolated static let composeTextPropagationDebounceNanoseconds: UInt64 = 120_000_000
    /// Spec 035 FR-002: bounded focus retry — six attempts, ~50ms apart, so a
    /// mount that lands late still gets a keyboard and one that never lands
    /// stops asking.
    nonisolated static let composeFocusAttemptLimit = 6
    nonisolated static let composeFocusRetryDelayNanoseconds: UInt64 = 50_000_000

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
    /// Fn expansion state of the shared accessory key strip (spec 011).
    @State private var showsAccessoryFnExpansion: Bool = false
    /// Clock-injected hold-repeat machine (spec 012 US2-1). The view
    /// owns the timer; Core never reads the clock.
    @State private var accessoryRepeatCadence = AccessoryKeyRepeatCadence()
    @State private var accessoryRepeatTask: Task<Void, Never>?
    /// Set on touch-down so the Button action (touch-up) does not
    /// emit a second copy of the same press. VoiceOver that never
    /// sets `isPressed` still goes through the action.
    @State private var accessoryRepeatEmittedOnPressDown = false

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
    /// Sends a shared accessory strip key (spec 011 US2). Sticky
    /// modifiers wrap the emission model-side.
    private let onSendAccessoryKey: (AccessoryKey) -> Void
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
    /// Spec 035 FR-003: one word naming a degraded transport, rendered inside
    /// the row instead of a sentence above it. `nil` when the transport is
    /// nominal and there is nothing to disclose.
    private let liveTransportBadgeLabel: String?
    /// Spec 015 FR-006 as narrowed by spec 035 FR-004: only a status the user
    /// must act on earns a row of the compact dock. At standard width both
    /// lines render as before — the height pressure was never there.
    private let liveStatusIsActionable: Bool
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
    /// Is the accessory key panel revealed (spec 015)? Model-owned for the
    /// same reason as `composeExpansionRequested`: the placement swap
    /// recreates this view, and the panel must not collapse under the
    /// user's finger mid-session.
    private let accessoryPanelExpanded: Bool
    private let onSetAccessoryPanelExpanded: (Bool) -> Void

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
        liveTransportBadgeLabel: String? = nil,
        liveStatusIsActionable: Bool = false,
        onToggleDirectMode: @escaping () -> Void = {},
        onSelectMode: @escaping (NaruRemoteAppModel.RemoteInputDockMode) -> Void = { _ in },
        onSetDirectKeystrokePage: @escaping (KeyboardPage) -> Void = { _ in },
        onSetDirectInputSurface: @escaping (DirectKeystrokeInputSurface) -> Void = { _ in },
        onTapDirectKey: @escaping (DirectKey) -> Void = { _ in },
        onSendAccessoryKey: @escaping (AccessoryKey) -> Void = { _ in },
        onHardwareKey: @escaping (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void = { _, _, _ in },
        onMacSessionControl: @escaping (MacSessionControl) -> Void = { _ in },
        onComposeQuickKey: @escaping (ComposeQuickKey) -> Void = { _ in },
        onLiveCommit: @escaping (String, Bool) -> Void = { _, _ in },
        onLiveDeleteBackward: @escaping () -> Void = {},
        onLiveNewline: @escaping () -> Void = {},
        onDismissDirectModeWarning: @escaping () -> Void = {},
        onComposeFocusChange: @escaping (Bool) -> Void = { _ in },
        composeExpansionRequested: Bool = false,
        onRequestComposeExpansion: @escaping (Bool) -> Void = { _ in },
        accessoryPanelExpanded: Bool = false,
        onSetAccessoryPanelExpanded: @escaping (Bool) -> Void = { _ in }
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
        self.liveTransportBadgeLabel = liveTransportBadgeLabel
        self.liveStatusIsActionable = liveStatusIsActionable
        self.onToggleDirectMode = onToggleDirectMode
        self.onSelectMode = onSelectMode
        self.onSetDirectKeystrokePage = onSetDirectKeystrokePage
        self.onSetDirectInputSurface = onSetDirectInputSurface
        self.onTapDirectKey = onTapDirectKey
        self.onSendAccessoryKey = onSendAccessoryKey
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
        self.accessoryPanelExpanded = accessoryPanelExpanded
        self.onSetAccessoryPanelExpanded = onSetAccessoryPanelExpanded
    }

    /// The dock mode derived from the mutually exclusive flags. Type
    /// (type-through) is the session default (spec 011 US1); Compose is
    /// the buffered opt-in.
    private var currentDockMode: NaruRemoteAppModel.RemoteInputDockMode {
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
            onComposeFocusChange(newValue)
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
            stopAccessoryRepeat(clearPressDownToken: true)
        }
        .onChange(of: showsComposeQuickKeys) { _, isLive in
            if !isLive {
                stopAccessoryRepeat(clearPressDownToken: true)
            }
        }
    }

    private var currentWindowWidth: CGFloat? {
        #if os(iOS) && canImport(UIKit)
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

    /// Compact (iPhone) keeps the window width. Regular-width pinned
    /// docks cap at `RemoteInputDockWidthPolicy.regularPinnedContentMaxWidth`
    /// (orca `CONTENT_MAX_WIDTH`). The floating overlay stays
    /// content-sized on regular width.
    private var compactWindowWidth: CGFloat? {
        #if os(iOS) && canImport(UIKit)
        let isCompact = horizontalSizeClass == .compact
        if layoutStyle == .floatingAccessory {
            return RemoteInputDockWidthPolicy.floatingOverlayWidth(
                isCompactSizeClass: isCompact,
                windowWidth: currentWindowWidth
            )
        }
        return RemoteInputDockWidthPolicy.pinnedColumnMaxWidth(
            isCompactSizeClass: isCompact,
            windowWidth: currentWindowWidth
        )
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

                Spacer()

                // Mission control / Mac window controls collapse into a
                // single header menu so they no longer occupy a full row
                // above the editor (frees vertical space for typing).
                if showsMacSessionControls {
                    compactMacControlMenu
                }

                statusBlock
            }

            modePicker

            liveDisclosureBadge
            accessoryKeyStrip
            composeRow
            composeActionRow
            liveStatusLine
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

    /// The keyboard-up compact dock (spec 015): one row. Everything that used
    /// to own a row of its own — modifiers, terminal keys, Fn, remote ⌫/↵, the
    /// Mac window controls — is one tap behind `⋯`, and the status surfaces
    /// only speak when something is degraded or failed.
    ///
    /// Before this, six rows and 368pt (42% of an iPhone 17 Pro) sat between
    /// the keyboard and the remote screen; the gate that holds it down is
    /// `KeyboardUpDockHeightUITests`.
    private var compactAccessoryBody: some View {
        VStack(spacing: 6) {
            // Type mode hosts the strip inside its own row (spec 015 v1.1
            // FR-008): rendering the panel here too would show it twice.
            if !liveTypeThroughActive, showsAccessoryPanel {
                accessoryKeyStrip
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            compactComposeRow
            if let compactStatusText {
                compactStatusLine(compactStatusText)
            }
        }
        // Spec 035 FR-005: 6pt, not 8. Everything between the keyboard and the
        // remote screen is subtracted from what the user came for.
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .remoteChromeSurface()
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NaruColors.hairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var floatingAccessoryBody: some View {
        if showsCompactComposeEditor {
            compactAccessoryBody
        } else {
            floatingControlStrip
        }
    }

    /// The idle live-session floating pill row (spec 011): one tap to
    /// raise the keyboard in Type mode, one tap for the buffered
    /// Compose editor, Mac window controls in a menu. While the pill
    /// row is visible (keyboard down), the hidden hardware-key
    /// responder captures Bluetooth-keyboard presses so a Type-mode
    /// session is typeable without ever opening the software keyboard.
    private var floatingControlStrip: some View {
        HStack(spacing: 6) {
            #if canImport(UIKit)
            DirectKeystrokeResponderView(
                isActive: liveTypeThroughActive,
                onHardwareKey: onHardwareKey
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            #endif

            modeEntryCapsule

            if showsMacSessionControls {
                compactMacControlMenu
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .remoteChromeSurface(Capsule())
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(NaruColors.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
        .padding(.bottom, 8)
    }

    /// One control where there were two (spec 033 FR-002).
    ///
    /// `Type` and `Compose` sat side by side as if they were destinations, but
    /// one of them is always the mode you are already in — so the second pill
    /// was a mode switch wearing a destination's clothes, on the row where an
    /// iPhone can least afford it. The capsule now shows the *current* mode and
    /// carries the switch inside itself: the label opens that mode's dock, the
    /// trailing segment picks the other one.
    ///
    /// The label keeps the mode-specific identifier rather than taking a
    /// generic one, because it genuinely is the Type button while Type is the
    /// mode — which is also what keeps the dock-raising UITests honest.
    private var modeEntryCapsule: some View {
        let mode = currentDockMode
        let isType = mode == .live
        return HStack(spacing: 0) {
            Button {
                onSelectMode(mode)
                onRequestComposeExpansion(true)
            } label: {
                // `square.and.pencil`, not `text.cursor`: the latter renders as
                // a localized letterform ("가|") on Korean devices (spec 016
                // FR-006).
                Label(
                    isType ? "Type" : "Compose",
                    systemImage: isType ? "keyboard" : "square.and.pencil"
                )
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.leading, 15)
                .padding(.trailing, 11)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isType ? "Type" : "Compose")
            .accessibilityIdentifier(
                isType ? "naru.input.type-reveal" : "naru.input.compose-reveal"
            )

            Rectangle()
                .fill(Color.white.opacity(0.32))
                .frame(width: 1, height: 20)
                .accessibilityHidden(true)

            Menu {
                Button {
                    onSelectMode(.live)
                    onRequestComposeExpansion(true)
                } label: {
                    Label("Type", systemImage: "keyboard")
                }
                .accessibilityIdentifier("naru.input.mode-select.type")

                Button {
                    onSelectMode(.compose)
                    onRequestComposeExpansion(true)
                } label: {
                    Label("Compose", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("naru.input.mode-select.compose")
            } label: {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.bold))
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isType ? "Switch to Compose" : "Switch to Type")
            .accessibilityIdentifier("naru.input.mode-switch")
        }
        .foregroundStyle(.white)
        .background(Color.accentColor)
        .clipShape(Capsule())
    }

    /// The single row (spec 015 FR-002): `⋯` · field · mode · Send.
    ///
    /// The disclosure and status lines are siblings rather than row members
    /// because they are sentences, not controls — but they render only when
    /// degraded or failed (FR-006), so the nominal keyboard-up dock is exactly
    /// this row. Trailing controls stay trailing: iOS can drop its AutoFill
    /// affordance over the leading edge above the keyboard, and that overlay
    /// must not cover the mode switch or Send.
    private var compactComposeRow: some View {
        VStack(spacing: 6) {
            liveDisclosureBadge

            if liveTypeThroughActive {
                liveSoftKeyRow
            } else {
                HStack(spacing: 8) {
                    // At regular width the panel never hides, so a toggle for
                    // it would be a button that does nothing (FR-005).
                    if !panelIsPermanent {
                        accessoryPanelToggleButton
                    }

                    if showsCompactComposeEditor {
                        composeTextEditor
                            .frame(height: Self.compactComposeEditorHeight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
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
                    } else {
                        compactComposeRevealButton
                    }

                    compactModeToggleButton
                    compactSendButton
                }
            }

            liveStatusLine
        }
    }

    /// Type mode's whole keyboard-up dock (spec 015 v1.1 FR-008): one row of
    /// soft keys, no text field. The mirror editor still exists — 1×1pt,
    /// invisible — because it is the first responder that keeps the software
    /// keyboard raised and owns the IME commit boundary (marked → committed);
    /// what the founder types leaves through it exactly as before. What shows
    /// is the strip (remote ⌫/↵ leading), a keyboard-dismiss key, and the
    /// mode switch.
    private var liveSoftKeyRow: some View {
        HStack(spacing: 6) {
            composeTextEditor
                .frame(width: 1, height: 1)

            liveTransportBadge

            accessoryKeyStrip

            #if os(iOS) && canImport(UIKit)
            // With the visible field gone, the field's interactive drag was
            // the last way to lower the keyboard — and nothing raised it
            // again (spec 035 FR-001). This key does both.
            keyboardToggleButton
            #endif

            compactModeToggleButton
        }
    }

    #if os(iOS) && canImport(UIKit)
    /// Type mode's keyboard key, both ways (spec 035 FR-001).
    ///
    /// It used to only lower the keyboard. Type mode has no visible field
    /// (spec 015 v1.1 FR-008), and the dock keeps its keyboard-up layout while
    /// the mirror holds a draft — so a focus loss with text in flight (the app
    /// backgrounding, PiP, a system interruption) left a row of soft keys, no
    /// keyboard, and **nothing that raised one**. Compose mode has its reveal
    /// button as the way back; this is Type mode's.
    private var keyboardToggleButton: some View {
        let isRaised = composeFieldFocused
        return Button {
            if isRaised {
                composeCommitController.blur()
            } else {
                // Raising goes through the *same* path the idle capsule takes:
                // request the expanded dock first, then focus. Focusing
                // directly worked and then undid itself — gaining focus flips
                // the shell's placement, which recreates this view (and its
                // `@State` commit controller) out from under the responder that
                // was just installed. Requesting expansion first means the
                // placement is already settled, and the recreated instance
                // takes first responder in its own `onAppear`.
                onRequestComposeExpansion(true)
                requestComposeEditorFocus()
            }
        } label: {
            Image(systemName: isRaised ? "keyboard.chevron.compact.down" : "keyboard")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(NaruColors.surfaceKey)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NaruColors.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRaised ? "Hide keyboard" : "Show keyboard")
        // The dismiss identifier is kept for the raised state so the existing
        // dock-height coverage keeps resolving it; the raise state is its own
        // identifier because a test asserting recovery must not pass by
        // finding the key that hides.
        .accessibilityIdentifier(
            isRaised ? "naru.input.keyboard-dismiss" : "naru.input.keyboard-raise"
        )
    }
    #endif

    /// Persistent one-word disclosure of a degraded Live transport, inside the
    /// row (spec 035 FR-003).
    ///
    /// Spec 009 FR-014 requires that a degraded transport always be disclosed —
    /// the clipboard path overwrites the remote clipboard, the ASCII path cannot
    /// carry Korean. It was disclosed as a full-width two-line caption on its
    /// own row, permanently, for the whole session. Same guarantee, no row.
    @ViewBuilder
    private var liveTransportBadge: some View {
        if let liveTransportBadgeLabel, !liveTransportBadgeLabel.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(liveTransportBadgeLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(NaruColors.warning)
            .padding(.horizontal, 6)
            .frame(height: 36)
            .background(NaruColors.warning.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(liveTransportDisclosureText)
            .accessibilityIdentifier("naru.input.live-transport-badge")
        }
    }

    /// Is the key panel on screen? Compact width hides it until `⋯` (FR-001);
    /// regular width keeps it (FR-005) — the height pressure this spec closes
    /// is an iPhone problem, and an iPad has the room for a permanent strip.
    private var showsAccessoryPanel: Bool {
        panelIsPermanent || accessoryPanelExpanded
    }

    private var panelIsPermanent: Bool {
        #if os(iOS) && canImport(UIKit)
        return horizontalSizeClass == .regular
        #else
        return true
        #endif
    }

    /// `⋯` — the one affordance spec 015 adds. Reveals the accessory key
    /// panel (modifiers, Esc/Tab/⌃C/arrows/Del, Fn, remote ⌫/↵, Mac window
    /// controls) and stays revealed until tapped again.
    private var accessoryPanelToggleButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                onSetAccessoryPanelExpanded(!accessoryPanelExpanded)
            }
        } label: {
            Image(systemName: accessoryPanelExpanded ? "chevron.down" : "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(
                    accessoryPanelExpanded
                        ? Color.accentColor.opacity(0.22)
                        : NaruColors.surfaceKey
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(NaruColors.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Terminal keys")
        .accessibilityValue(accessoryPanelExpanded ? "Shown" : "Hidden")
        .accessibilityIdentifier("naru.input.accessory.panel-toggle")
    }

    /// Icon-only Type⇄Compose switch for the single row (FR-002). Reads as the
    /// mode a tap switches TO, exactly like the labelled one; the row has to
    /// keep a field wide enough to type in, so the title is dropped and the
    /// accessibility label carries it.
    private var compactModeToggleButton: some View {
        let isTypeActive = liveTypeThroughActive
        return Button {
            onSelectMode(isTypeActive ? .compose : .live)
        } label: {
            // `text.cursor` — the labelled toggle's icon — renders as a
            // localized letterform (a Korean 가 with a caret on a Korean
            // device). With no title beside it that reads as a character, not
            // as an action, so the icon-only switch uses the compose glyph.
            Image(systemName: isTypeActive ? "square.and.pencil" : "keyboard")
                .font(.system(size: 16, weight: .semibold))
                // The bordered style adds its own vertical padding, so the
                // label is sized to land the whole control on the row's 40pt
                // — a 40pt label measured 54pt and made the switch, not the
                // field, decide how tall the dock is.
                .frame(width: 32, height: 24)
        }
        .buttonStyle(.bordered)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(height: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isTypeActive ? "Switch to Compose" : "Switch to Type")
        .accessibilityIdentifier("naru.input.mode-toggle")
    }

    /// Icon-only Send for the single row. Same action and identifier as the
    /// standard layout's labelled Send.
    private var compactSendButton: some View {
        Button {
            sendCurrentComposeText()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 24)
        }
        .buttonStyle(.borderedProminent)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(height: 40)
        .disabled(isComposeSendDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Send composed text")
        .accessibilityIdentifier("naru.input.send")
    }

    private var showsCompactComposeEditor: Bool {
        Self.shouldShowCompactComposeEditor(
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
        requestComposeEditorFocus()
    }

    /// Asks for first responder until the editor takes it, or until the
    /// attempts run out (spec 035 FR-002).
    ///
    /// One `Task.yield()` used to be the whole retry policy: if the
    /// `UITextView` was not yet attachable when the request landed, nothing
    /// tried again and nothing reported. The bound matters as much as the
    /// retry — an editor that genuinely cannot take focus must not spin, and
    /// FR-001's keyboard key is what makes that case recoverable by hand.
    private func requestComposeEditorFocus() {
        #if os(iOS) && canImport(UIKit)
        Task { @MainActor in
            for attempt in 0..<Self.composeFocusAttemptLimit {
                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: Self.composeFocusRetryDelayNanoseconds)
                }
                if composeCommitController.focus() {
                    return
                }
            }
        }
        #endif
    }

    nonisolated static func shouldShowCompactComposeEditor(
        isFocused: Bool,
        text: String,
        expansionRequested: Bool
    ) -> Bool {
        let hasDraft = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isFocused || hasDraft || expansionRequested
    }

    private var compactComposeRevealButton: some View {
        Button {
            onRequestComposeExpansion(true)
        } label: {
            Label("Compose", systemImage: "square.and.pencil")
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
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Compose")
        .accessibilityIdentifier("naru.input.compose-reveal")
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(NaruColors.mutedInk)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

            if let helperStatusText = helperStatusText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !helperStatusText.isEmpty {
                Text(helperStatusText)
                    .font(.caption2)
                    .foregroundStyle(NaruColors.mutedInk)
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
            .foregroundStyle(NaruColors.mutedInk)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("naru.input.compact-status")
    }

    /// Segmented picker between the two dock modes (spec 011):
    /// Type (type-through — the default for an active session) and
    /// Compose (buffered local composition). The model is the single
    /// source of truth for mode state; every change dispatches
    /// `onSelectMode`.
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
            Text("Type").tag(NaruRemoteAppModel.RemoteInputDockMode.live)
            Text("Compose").tag(NaruRemoteAppModel.RemoteInputDockMode.compose)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("naru.input.mode-picker")
    }

    /// Persistent Live transport/latency disclosure badge (spec 009 FR-014),
    /// peer to Direct's "IME off" badge. Shown whenever Live is active so the
    /// degraded/observed transport is never misrepresented.
    /// Spec 009 FR-014 must always disclose a *degraded* transport — the
    /// clipboard path overwrites the remote clipboard and settles late, the
    /// ASCII path cannot carry Korean at all. Spec 015 FR-006 stops the
    /// nominal sentence from holding a row of an iPhone screen open while the
    /// user types; at standard width it renders as it always did.
    private var showsLiveDisclosureBadge: Bool {
        // Compact discloses through `liveTransportBadge` (spec 035 FR-003),
        // which costs no row; the full sentence stays at standard width.
        layoutStyle == .standard
    }

    /// Same split for the per-window delivery status (FR-013): everything at
    /// standard width, only what is actionable in the one-row dock.
    private var showsLiveStatusLine: Bool {
        layoutStyle == .standard || liveStatusIsActionable
    }

    @ViewBuilder
    private var liveDisclosureBadge: some View {
        if liveTypeThroughActive, showsLiveDisclosureBadge, !liveTransportDisclosureText.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.caption2)
                Text(liveTransportDisclosureText)
                    .font(.caption2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(NaruColors.mutedInk)
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
        if liveTypeThroughActive, showsLiveStatusLine, let liveStatusText, !liveStatusText.isEmpty {
            Text(liveStatusText)
                .font(.caption2)
                .foregroundStyle(NaruColors.mutedInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("naru.input.live-status")
        }
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
        .accessibilityAddTraits(.isButton)
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
    /// connect. Esc / Tab / arrows / Del are not on this row — they
    /// live on the shared accessory strip (spec 011 US2).
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
                emitComposeQuickKeyAfterFlush(key)
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

    /// Shared accessory key strip (spec 011 US2), modeled on orca
    /// mobile's terminal accessory keys: sticky modifiers + terminal
    /// keys one tap above the editor in BOTH dock modes. The primary
    /// row scrolls horizontally; the Fn toggle stays pinned outside
    /// the scroll.
    private var accessoryKeyStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if liveTypeThroughActive, hostsRowMigratedControls {
                            // Type mode's strip IS its whole dock row (spec
                            // 015 v1.1 FR-008), and the founder named remote
                            // ⌫/↵ as the keys that must work without a
                            // thought — they lead. ⌃C comes third: with Fn,
                            // the dismiss key and the mode switch pinned
                            // after the scroll, an interrupt placed any
                            // later clips at iPhone width (measured), and
                            // spec 012 US2-2 puts it in the no-scroll zone.
                            composeRemoteKeyStripButton(.backspace, label: "⌫")
                            composeRemoteKeyStripButton(.enter, label: "↵")
                            composeControlCStripButton()
                            accessoryKeyButton(.escape)
                            accessoryKeyButton(.tab)
                            accessoryKeyButton(.arrowLeft)
                            accessoryKeyButton(.arrowUp)
                            accessoryKeyButton(.arrowDown)
                            accessoryKeyButton(.arrowRight)
                            accessoryKeyButton(.delete)
                            accessoryModifierKeys
                        } else {
                            // Compose / standard: frequency order for an
                            // AI-CLI session (spec 012 US2-3) — modifiers
                            // then Esc/Tab/⌃C in the no-scroll zone.
                            accessoryModifierKeys
                            accessoryTerminalKeys

                            // Spec 015 FR-003: remote ⌫/↵ lost their own row
                            // and joined the panel. They stay
                            // `ComposeQuickKey` emissions rather than raw
                            // keysyms because in Type mode they must drive
                            // the local mirror in step with the remote (spec
                            // 009 D1) — an `AccessoryKey` backspace would
                            // desync it.
                            if hostsRowMigratedControls {
                                composeRemoteKeyStripButton(.backspace, label: "⌫")
                                composeRemoteKeyStripButton(.enter, label: "↵")
                            }
                        }

                        // Inside the scroll, not pinned beside `Fn`: pinned,
                        // it took ~52pt of the fixed width and pushed keys
                        // out of the no-scroll zone (spec 012 US2-2).
                        if hostsRowMigratedControls, showsMacSessionControls {
                            compactMacControlMenu
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("naru.input.accessory.strip")
                .onDisappear {
                    stopAccessoryRepeat(clearPressDownToken: true)
                }

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        showsAccessoryFnExpansion.toggle()
                    }
                } label: {
                    Text("Fn")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 36)
                        .background(
                            showsAccessoryFnExpansion
                                ? Color.accentColor.opacity(0.22)
                                : NaruColors.surfaceKey
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(NaruColors.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: true)
                .accessibilityLabel("Function keys")
                .accessibilityIdentifier("naru.input.accessory.fn")
            }

            if showsAccessoryFnExpansion {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AccessoryKey.expandedStripKeys, id: \.self) { key in
                            accessoryKeyButton(key)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier("naru.input.accessory.fn-row")
            }
        }
    }

    /// Sticky modifiers, glyph-labelled (spec 012 US2-3): the 36pt keys are
    /// what fit Esc/Tab/⌃C inside an iPhone-width strip.
    private var accessoryModifierKeys: some View {
        ForEach(StickyModifierState.Modifier.stripOrder, id: \.self) { modifier in
            ModifierKeyButton(
                label: modifier.stripLabel,
                modifier: modifier,
                slot: stickyModifierState.slot(for: modifier),
                widthUnits: 1.5,
                unitWidth: 24,
                height: 36
            ) {
                onTapDirectKey(.modifier(modifier))
            }
            .disabled(!showsComposeQuickKeys)
        }
    }

    @ViewBuilder
    private var accessoryTerminalKeys: some View {
        accessoryKeyButton(.escape)
        accessoryKeyButton(.tab)
        composeControlCStripButton()
        accessoryKeyButton(.arrowLeft)
        accessoryKeyButton(.arrowUp)
        accessoryKeyButton(.arrowDown)
        accessoryKeyButton(.arrowRight)
        accessoryKeyButton(.delete)
    }

    /// The compact panel absorbed the rows that used to sit above the editor
    /// (spec 015 FR-003). The standard (regular-width / pre-connect) layout
    /// keeps its own header and action row, so the migrated controls must not
    /// be rendered twice — duplicate accessibility identifiers would also
    /// make every test that resolves them ambiguous.
    private var hostsRowMigratedControls: Bool {
        layoutStyle != .standard
    }

    /// A `ComposeQuickKey` styled as a strip key, for the ⌫/↵ that moved into
    /// the panel. Shares the action *and* the identifier of the standard
    /// layout's action-row buttons, so the emission path and its coverage are
    /// unchanged.
    private func composeRemoteKeyStripButton(
        _ key: ComposeQuickKey,
        label: String
    ) -> some View {
        Button {
            if liveTypeThroughActive, key == .backspace {
                onLiveDeleteBackward()
            } else if liveTypeThroughActive, key == .enter {
                onLiveNewline()
            } else {
                emitComposeQuickKeyAfterFlush(key)
            }
        } label: {
            accessoryKeyChrome(label: label)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!showsComposeQuickKeys)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityIdentifier("naru.input.compose-action.\(key.rawValue)")
    }

    private func accessoryKeyButton(_ key: AccessoryKey) -> some View {
        Group {
            if key.repeatable {
                Button {
                    // Finger hold already emitted on touch-down. Skip
                    // the touch-up action so a tap is not two keys.
                    // VoiceOver that never sets `isPressed` still emits.
                    if accessoryRepeatEmittedOnPressDown {
                        accessoryRepeatEmittedOnPressDown = false
                        return
                    }
                    emitAccessoryKeyAfterFlush(key)
                } label: {
                    accessoryKeyChrome(label: key.label)
                }
                .buttonStyle(
                    AccessoryStripPressButtonStyle { pressed in
                        if pressed {
                            beginAccessoryRepeat(key)
                        } else {
                            stopAccessoryRepeat()
                        }
                    }
                )
            } else {
                Button {
                    emitAccessoryKeyAfterFlush(key)
                } label: {
                    accessoryKeyChrome(label: key.label)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.primary)
        // Strip keys need a live wire; stay visible but inert pre-connect.
        .disabled(!showsComposeQuickKeys)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityIdentifier("naru.input.accessory.\(key.rawValue)")
    }

    /// One-tap ⌃C on the primary row (spec 012 US2-2). Uses the
    /// existing `ComposeQuickKey.controlC` emission — independent of
    /// sticky modifiers, not repeatable.
    private func composeControlCStripButton() -> some View {
        Button {
            emitComposeQuickKeyAfterFlush(.controlC)
        } label: {
            accessoryKeyChrome(label: ComposeQuickKey.controlC.label, minWidth: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!showsComposeQuickKeys)
        .accessibilityLabel(ComposeQuickKey.controlC.accessibilityLabel)
        .accessibilityIdentifier("naru.input.accessory.controlC")
    }

    private func accessoryKeyChrome(label: String, minWidth: CGFloat = 40) -> some View {
        Text(label)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: minWidth, maxWidth: 52, minHeight: 36)
            .background(NaruColors.surfaceKey)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(NaruColors.hairline, lineWidth: 1)
            )
    }

    /// Spec 012 US2-3 view layer: if the Type/Compose editor has
    /// marked text, commit it (so the existing liveCommit / draft
    /// path enqueues first) before the strip/quick-key tap proceeds.
    /// User-initiated — does not fight T015 (model must not overwrite
    /// the field *during* composition).
    private func commitHeldCompositionIfNeeded() {
        #if os(iOS) && canImport(UIKit)
        guard composeCommitController.hasMarkedText else {
            return
        }
        let committed = composeCommitController.commitMarkedTextAndRead(fallback: text)
        if text != committed {
            text = committed
        }
        if liveTypeThroughActive {
            onLiveCommit(committed, false)
        } else {
            flushComposeTextToModelIfNeeded(committed, force: true)
        }
        #endif
    }

    private func emitAccessoryKeyAfterFlush(_ key: AccessoryKey) {
        commitHeldCompositionIfNeeded()
        onSendAccessoryKey(key)
    }

    private func emitComposeQuickKeyAfterFlush(_ key: ComposeQuickKey) {
        commitHeldCompositionIfNeeded()
        onComposeQuickKey(key)
    }

    private func beginAccessoryRepeat(_ key: AccessoryKey) {
        accessoryRepeatTask?.cancel()
        accessoryRepeatTask = nil
        guard showsComposeQuickKeys else {
            return
        }
        accessoryRepeatEmittedOnPressDown = true
        commitHeldCompositionIfNeeded()
        let tick = accessoryRepeatCadence.press(key, at: .now)
        if let emit = tick.emit {
            onSendAccessoryKey(emit)
        }
        if let next = tick.nextTickAt {
            scheduleAccessoryRepeatTick(at: next)
        }
    }

    private func scheduleAccessoryRepeatTick(at deadline: ContinuousClock.Instant) {
        accessoryRepeatTask?.cancel()
        accessoryRepeatTask = Task { @MainActor in
            do {
                try await ContinuousClock().sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            guard showsComposeQuickKeys else {
                stopAccessoryRepeat(clearPressDownToken: true)
                return
            }
            let tick = accessoryRepeatCadence.tick(at: .now)
            if let key = tick.emit {
                onSendAccessoryKey(key)
            }
            if let next = tick.nextTickAt {
                scheduleAccessoryRepeatTick(at: next)
            }
        }
    }

    private func stopAccessoryRepeat(clearPressDownToken: Bool = false) {
        accessoryRepeatCadence.stop()
        accessoryRepeatTask?.cancel()
        accessoryRepeatTask = nil
        if clearPressDownToken {
            accessoryRepeatEmittedOnPressDown = false
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

    func isAttached(to candidate: UITextView) -> Bool {
        textView === candidate
    }

    /// Requests first responder and **reports whether it landed** (spec 035
    /// FR-002). The result used to be discarded, so a request that arrived
    /// before the text view was attachable failed silently — and in Type mode,
    /// where the editor is 1×1 and invisible, a silent failure is a keyboard
    /// that never comes up with nothing on screen to tap.
    @discardableResult
    func focus() -> Bool {
        guard let textView else {
            return false
        }
        if textView.isFirstResponder {
            return true
        }
        return textView.becomeFirstResponder()
    }

    var isFocused: Bool {
        textView?.isFirstResponder ?? false
    }

    /// Type mode's keyboard-dismiss key (spec 015 v1.1): with no visible
    /// field there is no drag surface left to lower the keyboard with.
    func blur() {
        _ = textView?.resignFirstResponder()
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
        // The commit controller is `@State` on `RemoteInputDockView`, so a view
        // recreation hands the coordinator a *new* controller — while UIKit
        // keeps the same `UITextView` and never calls `makeUIView` again. The
        // new controller's weak reference was therefore nil, and every
        // `focus()` against it was a silent no-op: measured as Type mode's
        // keyboard key doing nothing (spec 035 FR-002).
        context.coordinator.attachIfNeeded(textView)
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

        /// Keeps whatever commit controller the current parent carries pointed
        /// at the live text view. Idempotent, so the common case (same
        /// controller, same view) costs one identity comparison.
        func attachIfNeeded(_ textView: UITextView) {
            guard !parent.commitController.isAttached(to: textView) else {
                return
            }
            self.textView = textView
            parent.commitController.attach(textView)
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
#if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_EXPOSE_COMPOSE_LIFECYCLE"],
                  !raw.isEmpty
            else {
                return false
            }
            return raw != "0" && raw.lowercased() != "false"
#else
            false
#endif
        }
    }
}
#endif

/// Tracks `Button` press so repeatable strip keys emit on touch-down
/// (spec 012 US2-1) without inventing new chrome.
private struct AccessoryStripPressButtonStyle: ButtonStyle {
    let onPressedChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressedChange(pressed)
            }
    }
}

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
