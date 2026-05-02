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
    /// `RemoteInputDockView`.  When true, the iOS keyboard is up
    /// and `OnboardingGuideView` is rendered in its compact
    /// 1-line summary form (UX punch-list #009).
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

    public var body: some View {
        let snapshot = model.snapshot
        // Derived from app state instead of `@State`: a fresh
        // launch with a `dismissed` flag in settings should keep
        // the checklist (and its successor affirmation) hidden,
        // and the dismiss buttons only need to flip the persisted
        // flag — re-render handles the rest.
        let showsOnboardingGuide = model.showsOnboardingGuide
        let showsOnboardingReady = model.showsOnboardingReady

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
            ScrollView {
                VStack(spacing: 0) {
                    if showsOnboardingGuide {
                        OnboardingGuideView(
                            guide: snapshot.onboardingGuide,
                            isCompact: composeFieldFocused,
                            onDismiss: { Task { await model.dismissOnboardingChecklist() } },
                            onAction: { stepID in
                                model.handleOnboardingAction(stepID) {
                                    showsProfileEditor = true
                                }
                            }
                        )
                    } else if showsOnboardingReady {
                        OnboardingReadyView(
                            onDismiss: { Task { await model.dismissOnboardingChecklist() } }
                        )
                    }

                    SessionViewportView(
                        title: snapshot.title,
                        subtitle: snapshot.subtitle,
                        session: snapshot.session,
                        framebuffer: snapshot.latestFramebuffer,
                        frameDirtyRectangles: snapshot.latestFrameDirtyRectangles,
                        isPiPWatchAvailable: model.canStartPiPWatch,
                        pipWatchStatusText: model.pipWatchStatusText,
                        isPiPWatching: snapshot.pipWatchSession?.state == .watching,
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
                        }
                    )

                    DiagnosticSummaryView(
                        rows: snapshot.diagnosticRows,
                        shareTextProvider: { [buildVersion] in
                            model.makeDiagnosticExport()
                                .renderShareText(buildVersion: buildVersion)
                        }
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
            // Session-level "Direct mode" HUD badge (FR-010 second
            // sentence).  Sits in the detail column's top safe-area
            // inset so the cue stays visible even when the keyboard
            // is collapsed or hidden by another sheet.  Uses a
            // distinct accessibility id from the dock badge so
            // XCUITests can target the two independently.
            .safeAreaInset(edge: .top, spacing: 0) {
                if snapshot.directKeystrokeMode.isActive {
                    HStack {
                        Spacer()
                        DirectModeBadge(
                            isVisible: true,
                            accessibilityID: "naru.direct.badge.hud"
                        )
                        .padding(.trailing, 12)
                        .padding(.top, 4)
                    }
                    .background(Color.clear)
                }
            }
            .background(NaruColors.canvas)
            .accessibilityIdentifier("naru.app.detail")
        }
        .sheet(isPresented: $showsProfileEditor) {
            ProfileEditorView { profile, password in
                Task { await model.addProfile(profile, password: password) }
            }
        }
        .sheet(item: $editingProfile) { editing in
            ProfileEditorView(
                editing: editing.profile,
                hasExistingCredential: editing.hasExistingCredential
            ) { profile, password in
                Task { await model.editProfile(profile, password: password) }
            }
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
