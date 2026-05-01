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

    public init(snapshot: NaruRemoteAppSnapshot) {
        self._model = StateObject(wrappedValue: NaruRemoteAppModel(snapshot: snapshot))
    }

    public init(model: NaruRemoteAppModel) {
        self._model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        let snapshot = model.snapshot
        // Derived from app state instead of `@State`: a fresh
        // launch with a `dismissed` flag in settings should keep
        // the checklist hidden, and the dismiss button only
        // needs to flip the persisted flag — re-render handles
        // the rest.
        let showsOnboardingGuide = !snapshot.onboardingGuide.isComplete
            && !model.appSettings.dismissedOnboardingChecklist

        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            ProfileListView(
                profiles: snapshot.profiles,
                selectedProfileID: snapshot.selectedProfile?.id,
                onSelect: model.selectProfile(id:),
                onEdit: { profile in
                    editingProfile = EditingProfile(
                        profile: profile,
                        hasExistingCredential: profile.credentialRef != nil
                    )
                },
                onDelete: { id in
                    model.deleteProfile(id: id)
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
                            onDismiss: { model.dismissOnboardingChecklist() },
                            onAction: { stepID in
                                model.handleOnboardingAction(stepID) {
                                    showsProfileEditor = true
                                }
                            }
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
                        onConnect: snapshot.selectedProfile == nil ? nil : { model.connectSelectedProfile() },
                        onStartPiPWatch: model.canStartPiPWatch ? { model.startPiPWatch() } : nil
                    )

                    DiagnosticSummaryView(rows: snapshot.diagnosticRows)
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
                        onSend: { model.sendComposedText($0) }
                    )
                }
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.96))
            .accessibilityIdentifier("naru.app.detail")
        }
        .sheet(isPresented: $showsProfileEditor) {
            ProfileEditorView { profile, password in
                model.addProfile(profile, password: password)
            }
        }
        .sheet(item: $editingProfile) { editing in
            ProfileEditorView(
                editing: editing.profile,
                hasExistingCredential: editing.hasExistingCredential
            ) { profile, password in
                model.editProfile(profile, password: password)
            }
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
