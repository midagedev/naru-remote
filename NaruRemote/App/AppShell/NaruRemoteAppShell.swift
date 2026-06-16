import NaruRemoteCore
import SwiftUI

public struct NaruRemoteAppShell: View {
    @StateObject private var model: NaruRemoteAppModel
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    @State private var showsProfileEditor = false
    @State private var showsSelectedProfileDetail = false
    /// When non-nil, an "Edit Profile" sheet is presented for this
    /// profile.  Using `Identifiable` here means SwiftUI will tear
    /// down and re-create the editor's state on each invocation, so
    /// pre-filled fields always reflect the latest stored values.
    @State private var editingProfile: EditingProfile?
    /// Mirrors the compose `TextEditor` focus state inside
    /// `RemoteInputDockView`.  Reserved for future keyboard-aware
    /// surfaces; today no overlay reads it (the first-run checklist
    /// that used to depend on it was removed when onboarding was
    /// reduced to a single empty-state CTA — spec FR-015).
    @State private var composeFieldFocused = false
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
        self._showsSelectedProfileDetail = State(initialValue: startsOnSelectedProfileDetail)
        self.buildVersion = buildVersion
    }

    public init(
        model: NaruRemoteAppModel,
        buildVersion: String? = nil,
        startsOnSelectedProfileDetail: Bool = false
    ) {
        self._model = StateObject(wrappedValue: model)
        self._showsSelectedProfileDetail = State(initialValue: startsOnSelectedProfileDetail)
        self.buildVersion = buildVersion
    }

    /// True once the session is streaming (or in the bounded
    /// auto-reconnect window) or any frame has arrived — the cue that the
    /// remote screen should become the dominant full-bleed hero (spec 003
    /// FR-001) instead of a small aspect-fit box stacked above
    /// diagnostics.  Pure local layout decision — constitution §I (no new
    /// RFB message).
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

    /// The session viewport with all model wiring.  Extracted so the
    /// call site is not duplicated across the hero and scrollable layout
    /// branches; `fillsAvailableHeight` switches the dark container
    /// between the immersive full-height hero and the historical
    /// width-driven aspect-fit box.
    @ViewBuilder
    private func sessionViewport(fillsAvailableHeight: Bool) -> some View {
        let snapshot = model.snapshot
        SessionViewportFrameBridge(
            model: model,
            snapshot: snapshot,
            frameStore: model.frameStore,
            trackpadCursorStore: model.trackpadCursorStore,
            fillsAvailableHeight: fillsAvailableHeight
        )
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
        let showsConnectionGrid = !isEmptyHome
            && !isLiveSession
            && !showsSelectedProfileDetail
            && snapshot.session == nil
            && snapshot.diagnosticRun == nil

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            ProfileListView(
                profiles: snapshot.profiles,
                selectedProfileID: snapshot.selectedProfile?.id,
                verdicts: snapshot.lastDiagnosticVerdict,
                onSelect: { id in
                    model.selectProfile(id: id)
                    showsSelectedProfileDetail = true
                    preferredCompactColumn = .detail
                },
                onEdit: { profile in
                    editingProfile = EditingProfile(
                        profile: profile,
                        hasExistingCredential: profile.credentialRef != nil
                    )
                },
                onDelete: { id in
                    Task { await model.deleteProfile(id: id) }
                }
            )
            .navigationTitle("Naru Remote")
            .toolbar {
                Button {
                    showsProfileEditor = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
                .accessibilityIdentifier("naru.profile.add")
            }
        } detail: {
            // GRD-parity hero (spec 003 FR-001): during a live session the
            // remote screen is the dominant full-bleed surface — no
            // ScrollView wrapper, no diagnostics stacked beneath, so when
            // the soft keyboard rises the bottom dock rises with it and the
            // filling viewport merely shrinks instead of being crushed to a
            // sliver.  Pre-connect / disconnected keeps the historical
            // scrollable stack so the diagnostics summary stays reachable.
            ZStack {
                Group {
                    if isEmptyHome {
                        EmptyHomeView(onAddProfile: { showsProfileEditor = true })
                    } else if showsConnectionGrid {
                        ConnectionGridView(
                            cards: snapshot.connectionGridCards,
                            onSelect: { id in
                                model.selectProfile(id: id)
                                showsSelectedProfileDetail = true
                                preferredCompactColumn = .detail
                            },
                            onAddProfile: { showsProfileEditor = true }
                        )
                        .navigationBarBackButtonHidden(true)
                    } else if usesLiveSessionLayout {
                        sessionViewport(fillsAvailableHeight: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .naruLiveSessionChromeHidden()
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                sessionViewport(fillsAvailableHeight: false)

                                DiagnosticSummaryView(
                                    rows: snapshot.diagnosticRows,
                                    shareTextProvider: { [buildVersion] in
                                        model.makeDiagnosticExport()
                                            .renderSharePayload(buildVersion: buildVersion)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Spec FR-015: empty home → no Compose/Direct preview,
                // no clipboard banner.  The dock has nothing to send
                // to until a profile exists, and surfacing it before
                // the user has added a computer is exactly the
                // pre-announcement of capabilities the empty-home CTA
                // is meant to remove.
                if !isEmptyHome && !showsConnectionGrid {
                    let accessoryChrome = RemoteInputAccessoryChromeState(
                        snapshot: snapshot,
                        incomingClipboardReview: model.pendingIncomingClipboard,
                        isLiveSession: usesLiveSessionLayout,
                        isComposeFieldFocused: composeFieldFocused
                    )

                    VStack(spacing: 0) {
                        IncomingClipboardBanner(
                            review: accessoryChrome.incomingClipboardReview,
                            onAccept: { model.acceptIncomingClipboard() },
                            onDismiss: { model.dismissIncomingClipboard() }
                        )

                        if let statusLine = accessoryChrome.statusLine {
                            RemoteInputDockStatusLine(text: statusLine.text)
                        }

                        RemoteInputDockEquatableHost(
                            state: RemoteInputDockRenderState(
                                snapshot: snapshot,
                                isLiveSession: usesLiveSessionLayout,
                                isComposeFieldFocused: composeFieldFocused
                            ),
                            onSend: { model.sendComposedText($0) },
                            onTextChange: { model.updateComposeDraftText($0) },
                            onComposeSendPreparation: { model.recordComposeSendPreparation($0) },
                            onToggleDirectMode: { model.toggleDirectKeystrokeMode() },
                            onTapDirectKey: { key in Task { await model.tapDirectKey(key) } },
                            onHardwareKey: { keysym, modifiers, isDown in
                                Task {
                                    await model.handleHardwareKey(
                                        keysym: keysym,
                                        modifiers: modifiers,
                                        isDown: isDown
                                    )
                                }
                            },
                            onComposeQuickKey: { key in Task { await model.sendComposeQuickKey(key) } },
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
                            }
                        )
                        .equatable()
                    }
                }
            }
            .onChange(of: currentSessionID) { _, newSessionID in
                if liveSessionLayoutSessionID != newSessionID {
                    liveSessionLayoutSessionID = nil
                }
            }
            .onChange(of: isLiveSession) { _, isLive in
                if !isLive {
                    liveSessionLayoutSessionID = nil
                } else if !composeFieldFocused, let currentSessionID {
                    liveSessionLayoutSessionID = currentSessionID
                }
            }
            // UX punch-list #107: the HUD badge collided with the
            // dock badge whenever the soft keyboard was up — they
            // sat ~10pt apart vertically and read as duplicate cues.
            // The dock is always pinned via `.safeAreaInset(edge:
            // .bottom)` so the dock badge is always on screen while
            // Direct mode is active; the HUD instance is redundant.
            // Removing the HUD instance is the chosen fix; if a
            // future revision lets the dock collapse, re-add an HUD
            // fallback gated on `dockBadgeIsVisible == false`.
            .background(NaruColors.canvas)
            .overlay(alignment: .topLeading) {
                if ProcessInfo.processInfo.environment["NARU_TEST_EXPOSE_COMPOSE_LIFECYCLE"] == "1",
                   snapshot.session?.hasReceivedFrame == true {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("First frame received")
                        .accessibilityIdentifier("naru.test.session.firstFrameReceived")
                        .allowsHitTesting(false)
                }
            }
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
        .task {
            await model.loadStoredProfiles()
            await model.loadStoredSettings()
        }
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
}

struct RemoteInputDockRenderState: Equatable, Sendable {
    var initialText: String
    var statusText: String
    var helperStatusText: String?
    var directKeystrokeMode: DirectKeystrokeMode
    var stickyModifierState: StickyModifierState
    var layoutStyle: RemoteInputDockLayoutStyle
    var showsCompactStatusText: Bool
    var showsComposeQuickKeys: Bool
    var isComposeFieldFocused: Bool

    init(
        snapshot: NaruRemoteAppSnapshot,
        isLiveSession: Bool,
        isComposeFieldFocused: Bool = false
    ) {
        self.directKeystrokeMode = snapshot.directKeystrokeMode
        self.initialText = snapshot.composeDraft?.text ?? ""
        self.statusText = isLiveSession ? "" : snapshot.inputStatusText
        self.helperStatusText = isLiveSession ? nil : snapshot.inputHelperStatusText
        self.stickyModifierState = snapshot.stickyModifierState
        self.layoutStyle = isLiveSession ? .compactAccessory : .standard
        self.showsCompactStatusText = isLiveSession ? false : snapshot.latestInjectionAttempt != nil
        self.showsComposeQuickKeys = snapshot.session?.state == .active
        self.isComposeFieldFocused = isComposeFieldFocused
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.directKeystrokeMode == rhs.directKeystrokeMode,
              lhs.isComposeFieldFocused == rhs.isComposeFieldFocused
        else {
            return false
        }

        let freezeModelMirroredComposeFields = lhs.isComposeFieldFocused
            && rhs.isComposeFieldFocused
            && !lhs.directKeystrokeMode.isActive
            && !rhs.directKeystrokeMode.isActive
        if freezeModelMirroredComposeFields {
            // While UIKit owns IME focus, model-mirrored compose text is
            // advisory. Status/helper chrome is now rendered by a sibling
            // line, so the input host can keep the UITextView bridge stable
            // even when previous send state, helper state, or frame liveness
            // changes under the active keyboard.
            return true
        }

        guard lhs.stickyModifierState == rhs.stickyModifierState,
              lhs.layoutStyle == rhs.layoutStyle,
              lhs.showsComposeQuickKeys == rhs.showsComposeQuickKeys
        else {
            return false
        }

        return lhs.initialText == rhs.initialText
            && lhs.statusText == rhs.statusText
            && lhs.helperStatusText == rhs.helperStatusText
            && lhs.showsCompactStatusText == rhs.showsCompactStatusText
    }
}

struct RemoteInputDockStatusLineState: Equatable, Sendable {
    var text: String

    static let focusedStatusText = "Ready to compose locally"

    init?(
        snapshot: NaruRemoteAppSnapshot,
        isLiveSession: Bool,
        isComposeFieldFocused: Bool
    ) {
        guard isLiveSession, !snapshot.directKeystrokeMode.isActive else {
            return nil
        }

        if isComposeFieldFocused {
            // Focused Compose is a UIKit-owned transaction. Keep status
            // chrome outside the equatable input host so clearing a stale
            // send result, helper status, or stream quality update cannot
            // repaint the active UITextView bridge.
            self.text = Self.focusedStatusText
            return
        }

        let statusText = snapshot.inputStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if snapshot.latestInjectionAttempt != nil, !statusText.isEmpty {
            self.text = statusText
            return
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
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
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
    var onTapDirectKey: (DirectKey) -> Void
    var onHardwareKey: (UInt32, Set<DirectKeystrokeModifier>, Bool) -> Void
    var onComposeQuickKey: (ComposeQuickKey) -> Void
    var onDismissDirectModeWarning: () -> Void
    var onComposeFocusChange: (Bool) -> Void

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
            showsComposeQuickKeys: state.showsComposeQuickKeys,
            onToggleDirectMode: onToggleDirectMode,
            onTapDirectKey: onTapDirectKey,
            onHardwareKey: onHardwareKey,
            onComposeQuickKey: onComposeQuickKey,
            onDismissDirectModeWarning: onDismissDirectModeWarning,
            onComposeFocusChange: onComposeFocusChange
        )
    }
}

private struct SessionViewportFrameBridge: View {
    let model: NaruRemoteAppModel
    let snapshot: NaruRemoteAppSnapshot
    @ObservedObject var frameStore: SessionFrameStore
    @ObservedObject var trackpadCursorStore: TrackpadCursorStore
    let fillsAvailableHeight: Bool

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
            onDisconnect: snapshot.selectedProfile == nil ? nil : { model.disconnect() },
            onStartPiPWatch: model.canStartPiPWatch ? { model.startPiPWatch() } : nil,
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
            onViewportInteractionChange: { isActive, frameStrategy in
                model.setViewportInteractionActive(isActive, frameStrategy: frameStrategy)
            },
            onViewportRedrawDiagnostics: { diagnostics in
                model.recordViewportRedrawDiagnostics(diagnostics)
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
