import NaruRemoteCore
import SwiftUI
#if os(iOS) && canImport(UIKit)
import UIKit
#endif

public struct NaruRemoteAppShell: View {
    #if os(iOS) && canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @StateObject private var model: NaruRemoteAppModel
    @State private var showsProfileEditor = false
    /// Screenshot/UI-test pin only. Which primary surface is on is *derived*
    /// from session facts by `RemoteControlSurfacePolicy` — see
    /// `showsRemoteControlSurface`. Nothing flips a route on tap any more:
    /// doing that, and then correcting it once the session caught up, is what
    /// produced a visible third screen twice (the failure overlay in spec 013,
    /// then the pre-first-frame connecting state).
    private let pinsRemoteControlSurfaceForTesting: Bool
    @State private var pendingPublicConnection: ConnectionProfile?
    @State private var showsDiagnosticDetail = false
    /// While the PiP region picker is up, the input dock steps aside — its
    /// floating capsule sat over the picker's confirm buttons in the first
    /// capture of it (spec 034 FR-005).
    @State private var isChoosingPiPRegion = false
    @State private var showsGridDiagnosticDetail = false
    /// When non-nil, an "Edit Profile" sheet is presented for this
    /// profile.  Using `Identifiable` here means SwiftUI will tear
    /// down and re-create the editor's state on each invocation, so
    /// pre-filled fields always reflect the latest stored values.
    @State private var editingProfile: EditingProfile?
    /// A profile-store delete can fail while leaving the sidebar row intact.
    /// Keep only the typed, fixed-catalog failure plus the profile id needed
    /// for an explicit retry; no raw persistence error crosses into the UI.
    @State private var pendingProfileDeletionRetry: ProfileDeletionRetryState?
    @State private var profileDeletionInFlightID: ConnectionProfile.ID?
    /// Mirrors the compose `TextEditor` focus state inside
    /// `RemoteInputDockView`.  Reserved for future keyboard-aware
    /// surfaces; today no overlay reads it (the first-run checklist
    /// that used to depend on it was removed when onboarding was
    /// reduced to a single empty-state CTA — spec FR-015).
    @State private var composeFieldFocused = false
    /// Hoisted compose-expansion request (compose-reveal fix, 2026-07-05).
    /// Granting the request flips the dock between the floating overlay
    /// and the pinned safe-area inset, which recreates the dock view —
    /// so the request must outlive any single dock instance. See
    /// `RemoteInputDockView.composeExpansionRequested`.
    @State private var composeExpansionRequested = false
    /// Session id whose full-screen live layout has already been entered.
    /// If the first frame arrives during a UIKit IME transaction, defer the
    /// parent layout swap until focus leaves so the UITextView is not torn
    /// down under the keyboard.
    @State private var liveSessionLayoutSessionID: RemoteSession.ID?
    /// Build version label used in the diagnostic share-text header.
    /// The iOS app entry passes
    /// `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`;
    /// previews / tests pass `nil` and the formatter renders "n/a".
    private let buildVersion: String?

    public init(
        snapshot: NaruRemoteAppSnapshot,
        buildVersion: String? = nil,
        startsOnSelectedProfileDetail: Bool = false
    ) {
        self._model = StateObject(wrappedValue: NaruRemoteAppModel(snapshot: snapshot))
        self.pinsRemoteControlSurfaceForTesting = startsOnSelectedProfileDetail
        self.buildVersion = buildVersion
    }

    public init(
        model: NaruRemoteAppModel,
        buildVersion: String? = nil,
        startsOnSelectedProfileDetail: Bool = false
    ) {
        self._model = StateObject(wrappedValue: model)
        self.pinsRemoteControlSurfaceForTesting = startsOnSelectedProfileDetail
        self.buildVersion = buildVersion
    }

    /// Which primary surface is on, derived — never assigned.
    /// `RemoteControlSurfacePolicy` owns the rule; this only supplies the
    /// facts and the screenshot pins.
    private var showsRemoteControlSurface: Bool {
        let snapshot = model.snapshot
        return RemoteControlSurfacePolicy.showsRemoteControl(
            sessionState: snapshot.session?.state,
            hasFramebuffer: snapshot.latestFramebuffer != nil,
            isPinnedForTesting: pinsRemoteControlSurfaceForTesting,
            retainsEndedSessionForTesting: Self.forcesInputDockForTesting
        )
    }

    /// True once the session is streaming (or in bounded auto-reconnect) or
    /// any frame has arrived. Remote control is always full-height; this flag
    /// only selects live input-accessory behavior and test/performance chrome.
    /// Pure local layout decision — constitution §I (no new RFB message).
    private var isLiveSession: Bool {
        let snapshot = model.snapshot
        if snapshot.latestFramebuffer != nil {
            return true
        }
        guard let state = snapshot.session?.state else {
            return false
        }
        switch state {
        case .active, .reconnecting:
            return true
        default:
            return false
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

    private var compactWindowWidth: CGFloat? {
        #if os(iOS) && canImport(UIKit)
        guard horizontalSizeClass == .compact else {
            return nil
        }
        return currentWindowWidth
        #else
        return nil
        #endif
    }

    /// Pinned dock column (spec 012 US3-1). Regular width caps at
    /// orca `CONTENT_MAX_WIDTH` (720) and centers; compact is unchanged.
    private var pinnedDockColumnMaxWidth: CGFloat? {
        #if os(iOS) && canImport(UIKit)
        RemoteInputDockWidthPolicy.pinnedColumnMaxWidth(
            isCompactSizeClass: horizontalSizeClass == .compact,
            windowWidth: currentWindowWidth
        )
        #else
        return nil
        #endif
    }

    /// The session viewport with all model wiring.  Extracted so the
    /// call site is not duplicated across the hero and scrollable layout
    /// branches; Operation always requests the immersive full-height form.
    @ViewBuilder
    private func sessionViewport(fillsAvailableHeight: Bool) -> some View {
        let snapshot = model.snapshot
        let showsInlineHealth = Self.showsInlineHealthAccessory(
            sessionState: snapshot.session?.state,
            prefersCollapsedPresentation: sessionHealthState.prefersCollapsedPresentation
        )
        return SessionViewportFrameBridge(
            model: model,
            snapshot: snapshot,
            frameStore: model.frameStore,
            trackpadCursorStore: model.trackpadCursorStore,
            fillsAvailableHeight: fillsAvailableHeight,
            onReturnToConnections: returnToConnections,
            onOpenDiagnostics: { showsDiagnosticDetail = true },
            isChoosingPiPRegion: $isChoosingPiPRegion,
            healthAccessory: showsInlineHealth
                ? AnyView(sessionHealthAffordance(presentation: .collapsed))
                : nil
        )
    }

    /// The render-ready health summary — typed session state, coarse quality,
    /// and fixed-catalog rows only. Both placements read the same value, so
    /// they cannot disagree about whether the session is healthy.
    private var sessionHealthState: SessionDiagnosticCornerState {
        SessionDiagnosticCornerState(
            session: model.snapshot.session,
            connectionQuality: model.connectionQuality,
            rows: model.snapshot.diagnosticRows
        )
    }

    private func sessionHealthAffordance(
        presentation: SessionDiagnosticCornerView.Presentation
    ) -> some View {
        SessionDiagnosticCornerView(
            state: sessionHealthState,
            presentation: presentation,
            isDetailPresented: $showsDiagnosticDetail,
            shareTextProvider: { [buildVersion] in
                model.makeDiagnosticExport()
                    .renderSharePayload(buildVersion: buildVersion)
            }
        )
    }

    @ViewBuilder
    private func remoteInputDockHost(state: RemoteInputDockRenderState) -> some View {
        RemoteInputDockEquatableHost(
            state: state,
            onSend: { model.sendComposedTextUsingPreferredDelivery($0, submittingWithReturn: true) },
            onTextChange: { model.updateComposeDraftText($0) },
            onComposeSendPreparation: { model.recordComposeSendPreparation($0) },
            onToggleDirectMode: { model.toggleDirectKeystrokeMode() },
            onSelectMode: { model.setRemoteInputDockMode($0) },
            onSetDirectInputSurface: { model.setDirectKeystrokeInputSurface($0) },
            onTapDirectKey: { key in Task { await model.tapDirectKey(key) } },
            onSendAccessoryKey: { key in Task { await model.sendAccessoryKey(key) } },
            onHardwareKey: { keysym, modifiers, isDown in
                Task {
                    await model.handleHardwareKey(
                        keysym: keysym,
                        modifiers: modifiers,
                        isDown: isDown
                    )
                }
            },
            onMacSessionControl: { control in
                Task { await model.sendMacSessionControl(control) }
            },
            onComposeQuickKey: { key in Task { await model.sendComposeQuickKey(key) } },
            onLiveCommit: { committedText, hasMarkedText in
                model.liveCommit(committedText: committedText, hasMarkedText: hasMarkedText)
            },
            onLiveDeleteBackward: { model.liveDeleteBackward() },
            onLiveNewline: { model.liveNewline() },
            onDismissDirectModeWarning: { model.dismissDirectModeEntryWarning() },
            onComposeFocusChange: { focused in
                let focusedSessionID = model.snapshot.session?.id
                if focused,
                   isLiveSession,
                   let focusedSessionID {
                    liveSessionLayoutSessionID = focusedSessionID
                }
                composeFieldFocused = focused
                if !focused,
                   isLiveSession,
                   let focusedSessionID {
                    liveSessionLayoutSessionID = focusedSessionID
                }
                model.setComposeInputEditingActive(focused)
            },
            onRequestComposeExpansion: { requested in
                composeExpansionRequested = requested
            },
            onSetAccessoryPanelExpanded: { expanded in
                model.setRemoteInputAccessoryPanelExpanded(expanded)
            }
        )
        .equatable()
    }

    private func performProfileDeletion(id: ConnectionProfile.ID) {
        guard profileDeletionInFlightID == nil else { return }
        pendingProfileDeletionRetry = nil
        profileDeletionInFlightID = id
        Task { @MainActor in
            let result = await model.deleteProfile(id: id)
            guard profileDeletionInFlightID == id else { return }
            profileDeletionInFlightID = nil
            pendingProfileDeletionRetry = Self.profileDeletionRetryState(
                profileID: id,
                result: result
            )
        }
    }

    private func openConnection(id: ConnectionProfile.ID) {
        guard let profile = model.snapshot.profiles.first(where: { $0.id == id }) else {
            return
        }

        // The card stays tappable while its connect runs (spec 013 US-4), so
        // an impatient second tap must not tear down the attempt in flight and
        // start over. Cancel is the control for changing your mind.
        if let card = model.snapshot.connectionGridCards.first(where: { $0.id == id }),
           card.connecting != nil {
            return
        }

        if Self.requiresPublicConnectionConfirmation(hostKind: profile.hostKind) {
            pendingPublicConnection = profile
            return
        }

        beginConnection(to: profile.id)
    }

    private func beginConnection(to profileID: ConnectionProfile.ID) {
        // Connecting stays on the host list (spec 013 US-4): the tapped card
        // reports progress and offers cancel, and remote control opens when
        // the first frame arrives. So this starts the work and routes nothing.
        composeFieldFocused = false
        composeExpansionRequested = false
        Task { await model.connectProfile(id: profileID) }
    }

    /// Cancels an in-flight connect from the card that started it.
    private func cancelConnection() {
        model.disconnect()
        composeFieldFocused = false
        composeExpansionRequested = false
    }

    private func editProfile(id: ConnectionProfile.ID) {
        guard let profile = model.snapshot.profiles.first(where: { $0.id == id }) else {
            return
        }
        editingProfile = EditingProfile(
            profile: profile,
            hasExistingCredential: profile.credentialRef != nil
        )
    }

    private func returnToConnections() {
        // Ending the session *is* the navigation: the surface is derived, so
        // there is no route to unset. `disconnect()` invalidates any late
        // callback before the grid becomes visible again.
        model.disconnect()
        clearRemoteControlSurfaceState()
    }

    /// Local view state that only makes sense while remote control is on.
    private func clearRemoteControlSurfaceState() {
        composeFieldFocused = false
        composeExpansionRequested = false
        liveSessionLayoutSessionID = nil
        showsDiagnosticDetail = false
    }

    private func openDiagnostics(for profileID: ConnectionProfile.ID) {
        let snapshot = model.snapshot
        let hasRowsForProfile = snapshot.diagnosticRun?.profileID == profileID
            && !snapshot.diagnosticRows.isEmpty
        // Existing results win: re-selecting a profile resets the run, so
        // running checks unconditionally would throw away the rows the user
        // asked to see. Only a profile with no results of its own needs a
        // fresh run, and `runConnectionChecks()` works on the *selected*
        // profile, so that card has to become the selection first.
        if !hasRowsForProfile {
            if snapshot.selectedProfile?.id != profileID {
                model.selectProfile(id: profileID)
            }
            model.runConnectionChecks()
        }
        showsGridDiagnosticDetail = true
    }

    nonisolated static func requiresPublicConnectionConfirmation(
        hostKind: ConnectionProfile.HostKind
    ) -> Bool {
        hostKind == .advancedManualPublicEndpoint
    }

    /// The Remote Input Dock is a *session* surface, not a fixed part of
    /// the pre-connect detail screen.  Per `PRODUCT_SPEC.md` the local
    /// compose path is about "원격 세션이 열렸을 때 로컬 입력 경로가
    /// 준비됐는지" — so before a connection exists there is nothing to
    /// send to, and the dock would only bury the Connect button and the
    /// diagnostics list.
    ///
    /// Since spec 013 US-4 the connecting cases here are effectively
    /// unreachable in the product: connecting keeps the user on the host list,
    /// so the dock cannot mount before there is a session to send to. They
    /// remain because the screenshot pins do mount this surface without a live
    /// session, and those captures need the dock.
    static func showsInputDock(for snapshot: NaruRemoteAppSnapshot) -> Bool {
        if sessionWarrantsInputDock(snapshot.session?.state) {
            return true
        }
        return forcesInputDockForTesting
    }

    nonisolated static func sessionWarrantsInputDock(_ state: RemoteSessionState?) -> Bool {
        guard let state else {
            return false
        }
        switch state {
        case .failed, .closed:
            return false
        case .connecting, .authenticating, .active, .degraded, .reconnecting:
            return true
        }
    }

    /// Same live-or-connecting cases as the input dock. Failed and closed
    /// no longer occur on this surface after automatic return.
    nonisolated static func showsDiagnosticCapsule(sessionState: RemoteSessionState?) -> Bool {
        sessionWarrantsInputDock(sessionState)
    }

    /// Does the health affordance render as a **standalone** chip over the
    /// remote screen? (spec 033 FR-004.)
    ///
    /// Only when it has something to say. A healthy session's affordance moves
    /// into the session control bar instead, so a good connection costs an icon
    /// rather than a permanent 248-point capsule. A warning cannot live only in
    /// the bar, because the bar auto-hides after 2.4 s — so exactly one of the
    /// two placements is used at a time, and this decides which.
    nonisolated static func showsStandaloneHealthChip(
        sessionState: RemoteSessionState?,
        prefersCollapsedPresentation: Bool
    ) -> Bool {
        showsDiagnosticCapsule(sessionState: sessionState) && !prefersCollapsedPresentation
    }

    /// The complement: the affordance rides inside the control bar.
    nonisolated static func showsInlineHealthAccessory(
        sessionState: RemoteSessionState?,
        prefersCollapsedPresentation: Bool
    ) -> Bool {
        showsDiagnosticCapsule(sessionState: sessionState) && prefersCollapsedPresentation
    }

    nonisolated static func shouldShowConnectionGrid(
        isEmptyHome: Bool,
        showsRemoteControlSurface: Bool
    ) -> Bool {
        !isEmptyHome && !showsRemoteControlSurface
    }

    struct ProfileDeletionRetryState: Identifiable, Equatable, Sendable {
        let profileID: ConnectionProfile.ID
        let failure: ProfilePersistenceFailure

        var id: ConnectionProfile.ID { profileID }
        var message: String { failure.safeMessage }
    }

    nonisolated static func profileDeletionRetryState(
        profileID: ConnectionProfile.ID,
        result: ProfilePersistenceResult
    ) -> ProfileDeletionRetryState? {
        guard let failure = result.failure else {
            return nil
        }
        return ProfileDeletionRetryState(
            profileID: profileID,
            failure: failure
        )
    }

    /// Focused input-dock UI tests drive the dock without a live RFB
    /// socket (they start on a selected profile and toggle Compose /
    /// Direct).  They opt in via `NARU_TEST_START_PROFILE_DETAIL`
    /// (already set by the Direct-keystroke / compose suites) or the
    /// dedicated `NARU_TEST_FORCE_INPUT_DOCK` flag used by the
    /// grid-entry screenshot helpers.  Inert in production.
    private static var forcesInputDockForTesting: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["NARU_TEST_FORCE_INPUT_DOCK"] == "1" {
            return true
        }
        guard let raw = environment["NARU_TEST_START_PROFILE_DETAIL"], !raw.isEmpty else {
            return false
        }
        return raw != "0" && raw.lowercased() != "false"
#else
        false
#endif
    }

    @ViewBuilder
    private func sessionDetailSurface(
        snapshot: NaruRemoteAppSnapshot,
        isEmptyHome: Bool,
        showsConnectionGrid: Bool,
        usesLiveSessionLayout: Bool
    ) -> some View {
        // Connections and Operation are the only primary surfaces. Operation
        // is full-height from the first connecting state; diagnostics use a
        // corner capsule/sheet instead of a third, stacked detail layout.
        ZStack {
            Group {
                if isEmptyHome {
                    EmptyHomeView(onAddProfile: { showsProfileEditor = true })
                } else if showsConnectionGrid {
                    ConnectionGridView(
                        cards: snapshot.connectionGridCards,
                        onSelect: openConnection,
                        onAddProfile: { showsProfileEditor = true },
                        onDiagnostics: openDiagnostics,
                        onEdit: editProfile,
                        onDelete: performProfileDeletion,
                        onCancelConnection: cancelConnection
                    )
                    .navigationBarBackButtonHidden(true)
                } else {
                    sessionViewport(fillsAvailableHeight: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .naruLiveSessionChromeHidden()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Only a warning stands alone over the remote screen (spec 033
            // FR-004); a healthy session's affordance is inside the control
            // bar, which `healthAccessory` supplies to the viewport.
            if !isEmptyHome && !showsConnectionGrid
                && Self.showsStandaloneHealthChip(
                    sessionState: snapshot.session?.state,
                    prefersCollapsedPresentation: sessionHealthState.prefersCollapsedPresentation
                ) {
                sessionHealthAffordance(presentation: .labelled)
                    // The immersive action bar occupies the first row; a
                    // warning sits just beneath it rather than under it.
                    .padding(.top, 66)
                    .padding(.trailing, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if !isEmptyHome && !showsConnectionGrid && Self.showsInputDock(for: snapshot),
               !isChoosingPiPRegion {
                let accessoryChrome = RemoteInputAccessoryChromeState(
                    snapshot: snapshot,
                    incomingClipboardReview: model.pendingIncomingClipboard,
                    isLiveSession: usesLiveSessionLayout,
                    isComposeFieldFocused: composeFieldFocused
                )
                let dockState = RemoteInputDockRenderState(
                    snapshot: snapshot,
                    isLiveSession: usesLiveSessionLayout,
                    isComposeFieldFocused: composeFieldFocused,
                    isComposeExpansionRequested: composeExpansionRequested
                )

                if accessoryChrome.usesFloatingOverlay(for: dockState) {
                    remoteInputDockHost(state: dockState)
                        .frame(width: compactWindowWidth, alignment: .center)
                        .padding(.horizontal, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Spec FR-015: empty home -> no Compose/Direct preview,
            // no clipboard banner. The dock has nothing to send
            // to until a profile exists, and surfacing it before
            // the user has added a computer is exactly the
            // pre-announcement of capabilities the empty-home CTA
            // is meant to remove.
            if !isEmptyHome && !showsConnectionGrid && Self.showsInputDock(for: snapshot),
               !isChoosingPiPRegion {
                let accessoryChrome = RemoteInputAccessoryChromeState(
                    snapshot: snapshot,
                    incomingClipboardReview: model.pendingIncomingClipboard,
                    isLiveSession: usesLiveSessionLayout,
                    isComposeFieldFocused: composeFieldFocused
                )
                let dockState = RemoteInputDockRenderState(
                    snapshot: snapshot,
                    isLiveSession: usesLiveSessionLayout,
                    isComposeFieldFocused: composeFieldFocused,
                    isComposeExpansionRequested: composeExpansionRequested
                )

                if !accessoryChrome.usesFloatingOverlay(for: dockState) {
                    VStack(spacing: 0) {
                        IncomingClipboardBanner(
                            review: accessoryChrome.incomingClipboardReview,
                            onAccept: { model.acceptIncomingClipboard() },
                            onDismiss: { model.dismissIncomingClipboard() }
                        )

                        // Spec 015 FR-006: the status line rides *above* the
                        // dock as an overlay instead of as a stack row. Two
                        // reasons, both measured: as a row it cost 25pt of an
                        // iPhone screen whenever the field was focused, and
                        // adding/removing that row mid-typing changed the
                        // VStack's children — which is what previously
                        // collapsed the keyboard safe-area layout under UIKit
                        // IME and forced a permanent "Ready to compose
                        // locally" placeholder to hold the slot open.
                        remoteInputDockHost(state: dockState)
                            .overlay(alignment: .top) {
                                if let statusLine = accessoryChrome.statusLine {
                                    RemoteInputDockStatusLine(text: statusLine.text)
                                        .alignmentGuide(.top) { $0[.bottom] }
                                        // It is a sentence, not a control: as a
                                        // row it could not steal taps, and as an
                                        // overlay over the remote screen it must
                                        // not start.
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .frame(maxWidth: pinnedDockColumnMaxWidth, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        // UX punch-list #107: the HUD badge collided with the dock
        // badge whenever the soft keyboard was up. Direct mode and
        // Compose editing still keep the dock pinned through the
        // bottom inset, while idle live sessions use the floating
        // accessory strip below.
        .background(NaruColors.canvas)
        .overlay(alignment: .topLeading) {
#if DEBUG
            ZStack(alignment: .topLeading) {
                if ProcessInfo.processInfo.environment["NARU_TEST_EXPOSE_COMPOSE_LIFECYCLE"] == "1",
                   snapshot.session?.hasReceivedFrame == true {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("First frame received")
                        .accessibilityIdentifier("naru.test.session.firstFrameReceived")
                        .allowsHitTesting(false)
                }

                if ProcessInfo.processInfo.environment["NARU_TEST_EXPOSE_DIAGNOSTIC_EXPORT_RELAY"] == "1",
                   let payload = model.diagnosticExportRelayForTesting {
                    Text("Diagnostic export captured")
                        .font(.caption2)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0.01)
                        .accessibilityIdentifier("naru.test.diagnosticExportRelay")
                        .accessibilityLabel("Diagnostic export captured")
                        .accessibilityValue(payload)
                    .allowsHitTesting(false)
                }
            }
#else
            EmptyView()
#endif
        }
    }

    public var body: some View {
        let snapshot = model.snapshot
        // First-launch surface (spec FR-015): zero saved profiles
        // → render exactly one primary "add a computer" CTA and
        // hide the session viewport / diagnostic chrome.  No
        // capability checklist, no feature preview.  Visibility is
        // derived purely from `profiles.isEmpty` — no persisted
        // dismissal flag.
        let isEmptyHome = snapshot.profiles.isEmpty
        let currentSessionID = snapshot.session?.id
        let usesLiveSessionLayout = isLiveSession
            && (!composeFieldFocused || liveSessionLayoutSessionID == currentSessionID)
        let showsRemoteControl = showsRemoteControlSurface
        let showsConnectionGrid = Self.shouldShowConnectionGrid(
            isEmptyHome: isEmptyHome,
            showsRemoteControlSurface: showsRemoteControl
        )

        Group {
            if isEmptyHome {
                // First launch (zero profiles): present the single-CTA
                // home as the full-screen root rather than the detail
                // pane of a NavigationSplitView.  In compact width the
                // split view injected a stray "back" chevron that led to
                // an equally-empty sidebar — a confusing double empty
                // state on the very first screen.  Promoting the empty
                // home to root removes that chevron and the dead-end
                // back navigation (spec FR-015 is still satisfied: one
                // title, one primary action, nothing else).
                EmptyHomeView(onAddProfile: { showsProfileEditor = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NaruColors.canvas)
            } else {
                sessionDetailSurface(
                    snapshot: snapshot,
                    isEmptyHome: isEmptyHome,
                    showsConnectionGrid: showsConnectionGrid,
                    usesLiveSessionLayout: usesLiveSessionLayout
                )
            }
        }
        .overlay(alignment: .topLeading) {
            if isLiveSession, SessionPerformanceHUDGate.isEnabled {
                SessionPerformanceHUDView(model: model)
                    .padding(.top, 8)
                    .padding(.leading, 8)
                    .allowsHitTesting(true)
            }
        }
        .onChange(of: currentSessionID) { _, newSessionID in
            if liveSessionLayoutSessionID != newSessionID {
                liveSessionLayoutSessionID = nil
            }
            composeExpansionRequested = false
        }
        .onChange(of: isLiveSession) { _, isLive in
            if !isLive {
                liveSessionLayoutSessionID = nil
            } else if !composeFieldFocused, let currentSessionID {
                liveSessionLayoutSessionID = currentSessionID
            }
        }
        .onChange(of: showsRemoteControl) { _, isShowing in
            // Leaving remote control (session ended, dropped, or cancelled)
            // must not strand compose focus or a pinned live layout.
            if !isShowing {
                clearRemoteControlSurfaceState()
            }
        }
        .sheet(isPresented: $showsGridDiagnosticDetail) {
            // Hosted in its own observing view: a run started by
            // `openDiagnostics` fills in after presentation, and a value
            // captured at presentation time would freeze the sheet on
            // "No diagnostics yet".
            GridDiagnosticSheetHost(
                model: model,
                buildVersion: buildVersion
            )
            .diagnosticsSheetPresentation()
        }
        .sheet(isPresented: $showsProfileEditor) {
            ProfileEditorView(
                onTest: { host, port, password in
                    await model.runProfileEditorReachabilityTest(
                        host: host,
                        port: port,
                        password: password
                    )
                },
                onSave: { profile, credentials in
                    Task {
                        await model.addProfile(
                            profile,
                            password: credentials.vncPassword,
                            helperPairingSecret: credentials.helperPairingSecret,
                            helperVideoPairingSecret: credentials.helperVideoPairingSecret
                        )
                    }
                }
            )
        }
        .sheet(item: $editingProfile) { editing in
            ProfileEditorView(
                editing: editing.profile,
                hasExistingCredential: editing.hasExistingCredential,
                onTest: { host, port, password in
                    await model.runProfileEditorReachabilityTest(
                        host: host,
                        port: port,
                        password: password
                    )
                },
                // Helper-handshake test needs a persisted profile (spec 010
                // FR-013); the add sheet keeps host reachability only until
                // the profile is saved.
                onTestHelper: {
                    await model.testHelperTextBridge(for: editing.profile.id).availability
                },
                onSave: { profile, credentials in
                    Task {
                        await model.editProfile(
                            profile,
                            password: credentials.vncPassword,
                            helperPairingSecret: credentials.helperPairingSecret,
                            helperVideoPairingSecret: credentials.helperVideoPairingSecret
                        )
                    }
                }
            )
        }
        .confirmationDialog(
            "Connect to a public address?",
            isPresented: Binding(
                get: { pendingPublicConnection != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingPublicConnection = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingPublicConnection
        ) { profile in
            Button("Connect to Public Address") {
                pendingPublicConnection = nil
                beginConnection(to: profile.id)
            }
            .accessibilityIdentifier("naru.connection.public.confirm")

            Button("Cancel", role: .cancel) {
                pendingPublicConnection = nil
            }
            .accessibilityIdentifier("naru.connection.public.cancel")
        } message: { _ in
            Text("Public VNC endpoints bypass Naru’s private-network safety assumptions. Continue only if you trust and secure this server.")
        }
        .alert(
            "Profile wasn’t deleted",
            isPresented: Binding(
                get: { pendingProfileDeletionRetry != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingProfileDeletionRetry = nil
                    }
                }
            ),
            presenting: pendingProfileDeletionRetry
        ) { retryState in
            Button("Retry Delete", role: .destructive) {
                performProfileDeletion(id: retryState.profileID)
            }
            .accessibilityIdentifier("naru.profile.delete.retry")

            Button("Cancel", role: .cancel) {
                pendingProfileDeletionRetry = nil
            }
            .accessibilityIdentifier("naru.profile.delete.failure.cancel")
        } message: { retryState in
            Text(retryState.message)
                .accessibilityIdentifier("naru.profile.delete.failure.message")
        }
        .task {
            await model.loadStoredProfiles()
            await model.loadStoredSettings()
        }
    }

}

/// Diagnostics sheet opened from a host card (spec 013 US2-1). Observes the
/// model so rows appear as `runConnectionChecks()` progresses.
private struct GridDiagnosticSheetHost: View {
    @ObservedObject var model: NaruRemoteAppModel
    let buildVersion: String?

    var body: some View {
        SessionDiagnosticDetailSheet(
            rows: rows,
            shareTextProvider: { [buildVersion] in
                model.makeDiagnosticExport()
                    .renderSharePayload(buildVersion: buildVersion)
            }
        )
    }

    /// The capsule sheet renders `snapshot.diagnosticRows` directly; this
    /// one does the same. `openDiagnostics` is what guarantees the run
    /// belongs to the tapped host — re-filtering here only produced an
    /// empty sheet whenever the two disagreed for a moment.
    private var rows: [DiagnosticSummaryRow] {
        model.snapshot.diagnosticRows
    }
}

struct RemoteInputAccessoryChromeState: Equatable, Sendable {
    var incomingClipboardReview: IncomingClipboardReview?
    var statusLine: RemoteInputDockStatusLineState?

    init(
        snapshot: NaruRemoteAppSnapshot,
        incomingClipboardReview: IncomingClipboardReview?,
        isLiveSession: Bool,
        isComposeFieldFocused: Bool
    ) {
        self.incomingClipboardReview = isComposeFieldFocused ? nil : incomingClipboardReview
        self.statusLine = RemoteInputDockStatusLineState(
            snapshot: snapshot,
            isLiveSession: isLiveSession,
            isComposeFieldFocused: isComposeFieldFocused
        )
    }

    func usesFloatingOverlay(for dockState: RemoteInputDockRenderState) -> Bool {
        dockState.layoutStyle == .floatingAccessory
            && incomingClipboardReview == nil
            && statusLine == nil
    }
}

struct RemoteInputDockRenderState: Equatable, Sendable {
    var initialText: String
    var statusText: String
    var helperStatusText: String?
    var directKeystrokeMode: DirectKeystrokeMode
    var liveTypeThroughMode: LiveTypeThroughMode
    var liveTransportDisclosureText: String
    var liveStatusText: String?
    /// Is the locked delivery tier one that loses something (clipboard
    /// overwrite / ASCII-only)? Spec 009 FR-014 must always show those;
    /// spec 015 FR-006 lets the compact dock stay quiet otherwise.
    var liveTransportIsDegraded: Bool
    /// Is the per-window status one the user can act on or be misled by
    /// (failed, unconfirmed, ASCII last resort, window start)?
    var liveStatusIsActionable: Bool
    var stickyModifierState: StickyModifierState
    var layoutStyle: RemoteInputDockLayoutStyle
    var showsCompactStatusText: Bool
    var showsMacSessionControls: Bool
    var showsComposeQuickKeys: Bool
    var isComposeFieldFocused: Bool
    /// Hoisted compose-expansion request (compose-reveal fix, 2026-07-05):
    /// once the user taps the floating "Compose" reveal, the dock leaves
    /// the floating placement immediately — BEFORE the keyboard rises —
    /// so the pinned instance owns the editor and first responder.
    var isComposeExpansionRequested: Bool
    /// Spec 015 FR-004: model-owned so a placement swap cannot collapse the
    /// panel, and part of `==` so toggling it actually repaints the equatable
    /// dock host.
    var isAccessoryPanelExpanded: Bool

    init(
        snapshot: NaruRemoteAppSnapshot,
        isLiveSession: Bool,
        isComposeFieldFocused: Bool = false,
        isComposeExpansionRequested: Bool = false
    ) {
        self.directKeystrokeMode = snapshot.directKeystrokeMode
        self.liveTypeThroughMode = snapshot.liveTypeThroughMode
        // In Live mode the editor renders the model's authoritative line mirror
        // so a sealed/committed line can be cleared by the model (spec 009).
        self.initialText = snapshot.liveTypeThroughMode.isActive
            ? snapshot.liveFieldText
            : (snapshot.composeDraft?.text ?? "")
        self.liveTransportDisclosureText = snapshot.liveTransportDisclosureText
        self.liveStatusText = snapshot.liveStatusText
        // Spec 015 FR-006 applies to the *compact* dock, where a sentence
        // costs a row of an iPhone screen. Spec 009 FR-013/FR-014 are
        // unchanged at standard width, which is where they were affordable all
        // along; these two flags are what lets the compact dock keep only the
        // lines a user can act on or be misled by.
        self.liveTransportIsDegraded = snapshot.liveDegradedTransportDisclosureText != nil
        self.liveStatusIsActionable = snapshot.liveActionableStatusText != nil
        self.statusText = isLiveSession ? "" : snapshot.inputStatusText
        self.helperStatusText = isLiveSession ? nil : snapshot.inputHelperStatusText
        self.stickyModifierState = snapshot.stickyModifierState
        self.layoutStyle = Self.resolvedLayoutStyle(
            snapshot: snapshot,
            isLiveSession: isLiveSession,
            isComposeFieldFocused: isComposeFieldFocused,
            isComposeExpansionRequested: isComposeExpansionRequested
        )
        self.showsCompactStatusText = isLiveSession ? false : snapshot.latestInjectionAttempt != nil
        self.showsMacSessionControls = snapshot.session?.state == .active
        self.showsComposeQuickKeys = snapshot.session?.state == .active
        self.isComposeFieldFocused = isComposeFieldFocused
        self.isComposeExpansionRequested = isComposeExpansionRequested
        self.isAccessoryPanelExpanded = snapshot.isRemoteInputAccessoryPanelExpanded
    }

    nonisolated static func resolvedLayoutStyle(
        snapshot: NaruRemoteAppSnapshot,
        isLiveSession: Bool,
        isComposeFieldFocused: Bool,
        isComposeExpansionRequested: Bool = false
    ) -> RemoteInputDockLayoutStyle {
        guard isLiveSession else {
            return .standard
        }
        return shouldUseFloatingLiveAccessory(
            snapshot: snapshot,
            isComposeFieldFocused: isComposeFieldFocused,
            isComposeExpansionRequested: isComposeExpansionRequested
        ) ? .floatingAccessory : .compactAccessory
    }

    nonisolated static func shouldUseFloatingLiveAccessory(
        snapshot: NaruRemoteAppSnapshot,
        isComposeFieldFocused: Bool,
        isComposeExpansionRequested: Bool = false
    ) -> Bool {
        guard !isComposeFieldFocused,
              !isComposeExpansionRequested,
              snapshot.latestInjectionAttempt == nil
        else {
            return false
        }

        let draftText = snapshot.composeDraft?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard draftText.isEmpty else {
            return false
        }

        let helperStatusText = snapshot.inputHelperStatusText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return helperStatusText?.isEmpty ?? true
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.directKeystrokeMode == rhs.directKeystrokeMode,
              lhs.liveTypeThroughMode == rhs.liveTypeThroughMode,
              lhs.isComposeFieldFocused == rhs.isComposeFieldFocused,
              lhs.isComposeExpansionRequested == rhs.isComposeExpansionRequested,
              // Ahead of the focus freeze below: revealing the key panel is a
              // deliberate user action and must repaint even while the compose
              // field holds UIKit focus.
              lhs.isAccessoryPanelExpanded == rhs.isAccessoryPanelExpanded
        else {
            return false
        }

        // The compose focus-freeze keeps the UITextView bridge stable while
        // UIKit owns IME focus. Live type-through is excluded: its transport
        // disclosure, per-window status, and model-driven line clears must
        // repaint even while the field is focused (spec 009 FR-013/FR-014).
        let freezeModelMirroredComposeFields = lhs.isComposeFieldFocused
            && rhs.isComposeFieldFocused
            && !lhs.liveTypeThroughMode.isActive
            && !rhs.liveTypeThroughMode.isActive
        if freezeModelMirroredComposeFields {
            return true
        }

        guard lhs.stickyModifierState == rhs.stickyModifierState,
              lhs.layoutStyle == rhs.layoutStyle,
              lhs.showsMacSessionControls == rhs.showsMacSessionControls,
              lhs.showsComposeQuickKeys == rhs.showsComposeQuickKeys
        else {
            return false
        }

        return lhs.initialText == rhs.initialText
            && lhs.statusText == rhs.statusText
            && lhs.helperStatusText == rhs.helperStatusText
            && lhs.liveTransportDisclosureText == rhs.liveTransportDisclosureText
            && lhs.liveStatusText == rhs.liveStatusText
            && lhs.showsCompactStatusText == rhs.showsCompactStatusText
    }
}

/// The live session's single status line, rendered above the dock and outside
/// the equatable input host (a focused Compose field is a UIKit-owned
/// transaction; status churn must not repaint the `UITextView` bridge).
///
/// Spec 015 FR-006/FR-007: this line costs a row, so it earns one only when it
/// carries something the user can act on or be misled by. A nominal send is
/// signalled by the crossing pulse overlay, which has no height — it is not
/// worth 25pt of an iPhone's screen to say "Ready to compose locally" or
/// "Sent" to someone watching the remote screen react.
struct RemoteInputDockStatusLineState: Equatable, Sendable {
    var text: String

    init?(
        snapshot: NaruRemoteAppSnapshot,
        isLiveSession: Bool,
        isComposeFieldFocused: Bool
    ) {
        guard isLiveSession else {
            return nil
        }

        // A delivery that failed or could not be confirmed keeps the user's
        // text locally and must say so (FR-013 honesty); a delivery that
        // landed says nothing.
        if let attempt = snapshot.latestInjectionAttempt, attempt.status != .sent {
            let statusText = snapshot.inputStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !statusText.isEmpty {
                self.text = statusText
                return
            }
        }

        let helperStatusText = snapshot.inputHelperStatusText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let helperStatusText, !helperStatusText.isEmpty else {
            return nil
        }
        self.text = helperStatusText
    }
}

private struct RemoteInputDockStatusLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(NaruColors.mutedInk)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .remoteChromeSurface()
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NaruColors.hairline)
                    .frame(height: 1)
            }
            .accessibilityIdentifier("naru.input.focused-status")
    }
}

private struct RemoteInputDockEquatableHost: View, Equatable {
    var state: RemoteInputDockRenderState
    var onSend: (String) -> Void
    var onTextChange: (String) -> Void
    var onComposeSendPreparation: (ComposeSendPreparationReport) -> Void
    var onToggleDirectMode: () -> Void
    var onSelectMode: (NaruRemoteAppModel.RemoteInputDockMode) -> Void
    var onSetDirectInputSurface: (DirectKeystrokeInputSurface) -> Void
    var onTapDirectKey: (DirectKey) -> Void
    var onSendAccessoryKey: (AccessoryKey) -> Void
    var onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void
    var onMacSessionControl: (MacSessionControl) -> Void
    var onComposeQuickKey: (ComposeQuickKey) -> Void
    var onLiveCommit: (String, Bool) -> Void
    var onLiveDeleteBackward: () -> Void
    var onLiveNewline: () -> Void
    var onDismissDirectModeWarning: () -> Void
    var onComposeFocusChange: (Bool) -> Void
    var onRequestComposeExpansion: (Bool) -> Void
    var onSetAccessoryPanelExpanded: (Bool) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state
    }

    var body: some View {
        RemoteInputDockView(
            initialText: state.initialText,
            statusText: state.statusText,
            helperStatusText: state.helperStatusText,
            onSend: onSend,
            onTextChange: onTextChange,
            onComposeSendPreparation: onComposeSendPreparation,
            directKeystrokeMode: state.directKeystrokeMode,
            stickyModifierState: state.stickyModifierState,
            layoutStyle: state.layoutStyle,
            showsCompactStatusText: state.showsCompactStatusText,
            showsMacSessionControls: state.showsMacSessionControls,
            showsComposeQuickKeys: state.showsComposeQuickKeys,
            liveTypeThroughActive: state.liveTypeThroughMode.isActive,
            liveTransportDisclosureText: state.liveTransportDisclosureText,
            liveStatusText: state.liveStatusText,
            liveTransportIsDegraded: state.liveTransportIsDegraded,
            liveStatusIsActionable: state.liveStatusIsActionable,
            onToggleDirectMode: onToggleDirectMode,
            onSelectMode: onSelectMode,
            onSetDirectInputSurface: onSetDirectInputSurface,
            onTapDirectKey: onTapDirectKey,
            onSendAccessoryKey: onSendAccessoryKey,
            onHardwareKey: onHardwareKey,
            onMacSessionControl: onMacSessionControl,
            onComposeQuickKey: onComposeQuickKey,
            onLiveCommit: onLiveCommit,
            onLiveDeleteBackward: onLiveDeleteBackward,
            onLiveNewline: onLiveNewline,
            onDismissDirectModeWarning: onDismissDirectModeWarning,
            onComposeFocusChange: onComposeFocusChange,
            composeExpansionRequested: state.isComposeExpansionRequested,
            onRequestComposeExpansion: onRequestComposeExpansion,
            accessoryPanelExpanded: state.isAccessoryPanelExpanded,
            onSetAccessoryPanelExpanded: onSetAccessoryPanelExpanded
        )
    }
}

private struct SessionViewportFrameBridge: View {
    let model: NaruRemoteAppModel
    let snapshot: NaruRemoteAppSnapshot
    @ObservedObject var frameStore: SessionFrameStore
    @ObservedObject var trackpadCursorStore: TrackpadCursorStore
    let fillsAvailableHeight: Bool
    let onReturnToConnections: () -> Void
    let onOpenDiagnostics: () -> Void
    let isChoosingPiPRegion: Binding<Bool>
    /// Supplied by the shell rather than built here: the diagnostic rows and
    /// the share payload belong to the shell, and this bridge exists to watch
    /// frames (spec 033 FR-003).
    let healthAccessory: AnyView?

    var body: some View {
        let frameState = frameStore.state
        SessionViewportView(
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            session: snapshot.session,
            framebuffer: frameState.framebuffer,
            inputCoordinateSpace: snapshot.inputCoordinateSpace,
            frameStore: frameStore,
            frameDirtyRectangles: frameState.dirtyRectangles,
            frameChangedPixelCount: frameState.changedPixelCount,
            serverCursor: frameState.serverCursor,
            isPiPWatchAvailable: model.canStartPiPWatch,
            pipWatchStatusText: model.pipWatchStatusText,
            isPiPWatching: snapshot.pipWatchSession?.state == .watching,
            usesHelperVideoPrimaryPreview: snapshot.visualTransportMode == .helperVideo,
            pointerControlMode: model.pointerControlMode,
            trackpadCursor: trackpadCursorStore.cursor,
            pipLayerHost: model.pipLayerHost,
            helperVideoLayerHost: model.helperVideoLayerHost,
            onRunChecks: snapshot.selectedProfile == nil ? nil : { model.runConnectionChecks() },
            onConnect: snapshot.selectedProfile == nil ? nil : { Task { await model.connectSelectedProfile() } },
            onDisconnect: snapshot.selectedProfile == nil ? nil : onReturnToConnections,
            onReturnToConnections: onReturnToConnections,
            onStartPiPWatch: model.canStartPiPWatch ? { model.startPiPWatch() } : nil,
            onStopPiPWatch: { model.stopPiPWatch() },
            pipFramingMode: model.effectivePiPFramingMode,
            pipChosenRegion: model.pipChosenRegion,
            onSelectPiPFramingMode: { model.setPiPFramingMode($0) },
            onChoosePiPRegion: { region in
                model.setPiPChosenRegion(region)
                model.setPiPFramingMode(.chosenRegion)
            },
            isChoosingPiPRegion: isChoosingPiPRegion,
            onOpenDiagnostics: onOpenDiagnostics,
            healthAccessory: healthAccessory,
            onFramebufferTap: { point, size in
                model.sendTapAt(viewPoint: point, viewSize: size)
            },
            onFramebufferRightClick: { point, size in
                model.sendRightClickAt(viewPoint: point, viewSize: size)
            },
            onFramebufferScroll: { point, size, delta in
                model.sendScrollAt(
                    viewPoint: point,
                    viewSize: size,
                    deltaX: delta.width,
                    deltaY: delta.height
                )
            },
            onFramebufferPointerDown: { point, size in
                Task { await model.sendPointerDownAt(viewPoint: point, viewSize: size) }
            },
            onFramebufferPointerMove: { point, size in
                Task { await model.sendPointerMoveTo(viewPoint: point, viewSize: size) }
            },
            onFramebufferPointerUp: { point, size in
                Task { await model.sendPointerUpAt(viewPoint: point, viewSize: size) }
            },
            onTrackpadGesture: { gesture, transform, cursor in
                model.handleTrackpadGesture(gesture, transform: transform, cursor: cursor)
            },
            onViewportTransformChange: { transform in
                model.updateViewportTransform(transform)
            },
            onViewportSizeChange: { size in
                model.updateViewportSize(size)
            },
            onViewportDisplayPixelScaleChange: { scale in
                model.updateViewportDisplayPixelScale(scale)
            },
            onViewportInteractionChange: { isActive, frameStrategy in
                model.setViewportInteractionActive(isActive, frameStrategy: frameStrategy)
            },
            onViewportRedrawDiagnostics: { diagnostics in
                model.recordViewportRedrawDiagnostics(diagnostics)
            },
            onFramePresentationLedger: { ledger in
                model.recordFramePresentationLedger(ledger)
            },
            onRendererUploadTiming: { milliseconds in
                model.recordRendererUploadTiming(milliseconds: milliseconds)
            },
            onTogglePointerMode: {
                model.togglePointerControlMode()
            },
            streamPowerMode: model.appSettings.streamPowerMode,
            onToggleStreamPowerMode: {
                model.toggleStreamPowerMode()
            },
            composeDelivery: model.appSettings.composeDelivery,
            onToggleComposeDeliveryMode: {
                model.toggleComposeDeliveryMode()
            },
            streamEncodingMode: model.appSettings.streamEncodingMode,
            onToggleStreamEncodingMode: {
                model.toggleStreamEncodingMode()
            },
            startupPreflightMode: model.appSettings.startupPreflightMode,
            onToggleStartupPreflightMode: {
                model.toggleStartupPreflightMode()
            },
            startupGlanceScaleMode: model.appSettings.startupGlanceScaleMode,
            onToggleStartupGlanceScaleMode: {
                model.toggleStartupGlanceScaleMode()
            },
            canUseStartupGlanceScaleMode: model.canUseStartupGlanceScaleMode,
            connectionQuality: model.connectionQuality,
            fillsAvailableHeight: fillsAvailableHeight
        )
    }
}

/// Sheet-item payload that carries both the profile being edited
/// and the UI-only "is there a saved password?" hint.  The hint is
/// derived from `credentialRef` — the actual stored password is
/// never read for display (constitution §IV).
private struct EditingProfile: Identifiable {
    let profile: ConnectionProfile
    let hasExistingCredential: Bool

    var id: ConnectionProfile.ID { profile.id }
}

private extension View {
    @ViewBuilder
    func naruLiveSessionChromeHidden() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
