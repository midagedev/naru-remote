import NaruRemoteCore
import SwiftUI

public struct NaruRemoteAppShell: View {
    @StateObject private var model: NaruRemoteAppModel
    @State private var preferredCompactColumn = NavigationSplitViewColumn.detail
    @State private var showsProfileEditor = false
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
    /// Build version label used in the diagnostic share-text header.
    /// The iOS app entry passes
    /// `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`;
    /// previews / tests pass `nil` and the formatter renders "n/a".
    private let buildVersion: String?

    public init(snapshot: NaruRemoteAppSnapshot, buildVersion: String? = nil) {
        self._model = StateObject(wrappedValue: NaruRemoteAppModel(snapshot: snapshot))
        self.buildVersion = buildVersion
    }

    public init(model: NaruRemoteAppModel, buildVersion: String? = nil) {
        self._model = StateObject(wrappedValue: model)
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
        SessionViewportView(
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            session: snapshot.session,
            framebuffer: snapshot.latestFramebuffer,
            frameDirtyRectangles: snapshot.latestFrameDirtyRectangles,
            serverCursor: snapshot.latestServerCursor,
            isPiPWatchAvailable: model.canStartPiPWatch,
            pipWatchStatusText: model.pipWatchStatusText,
            isPiPWatching: snapshot.pipWatchSession?.state == .watching,
            pointerControlMode: model.pointerControlMode,
            trackpadCursor: model.trackpadCursor,
            pipLayerHost: model.pipLayerHost,
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
            onTrackpadGesture: { gesture, size in
                model.handleTrackpadGesture(gesture, viewSize: size)
            },
            onTogglePointerMode: {
                model.togglePointerControlMode()
            },
            connectionQuality: model.connectionQuality,
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

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            ProfileListView(
                profiles: snapshot.profiles,
                selectedProfileID: snapshot.selectedProfile?.id,
                verdicts: snapshot.lastDiagnosticVerdict,
                onSelect: model.selectProfile(id:),
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
            Group {
                if isEmptyHome {
                    EmptyHomeView(onAddProfile: { showsProfileEditor = true })
                } else if isLiveSession {
                    sessionViewport(fillsAvailableHeight: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            sessionViewport(fillsAvailableHeight: false)

                            DiagnosticSummaryView(
                                rows: snapshot.diagnosticRows,
                                shareTextProvider: { [buildVersion] in
                                    model.makeDiagnosticExport()
                                        .renderShareText(buildVersion: buildVersion)
                                }
                            )
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
                if !isEmptyHome {
                    VStack(spacing: 0) {
                        IncomingClipboardBanner(
                            review: model.pendingIncomingClipboard,
                            onAccept: { model.acceptIncomingClipboard() },
                            onDismiss: { model.dismissIncomingClipboard() }
                        )

                        RemoteInputDockView(
                            initialText: snapshot.composeDraft?.text ?? "",
                            statusText: snapshot.inputStatusText,
                            onSend: { model.sendComposedText($0) },
                            directKeystrokeMode: snapshot.directKeystrokeMode,
                            stickyModifierState: snapshot.stickyModifierState,
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
                            onDismissDirectModeWarning: { model.dismissDirectModeEntryWarning() },
                            onComposeFocusChange: { focused in
                                composeFieldFocused = focused
                            }
                        )
                    }
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
            .accessibilityIdentifier("naru.app.detail")
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
                onSave: { profile, password in
                    Task { await model.addProfile(profile, password: password) }
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
                onSave: { profile, password in
                    Task { await model.editProfile(profile, password: password) }
                }
            )
        }
        .task {
            await model.loadStoredProfiles()
            await model.loadStoredSettings()
        }
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
