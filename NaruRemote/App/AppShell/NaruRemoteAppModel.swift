import Combine
import Foundation
import NaruRemoteCore

@MainActor
public final class NaruRemoteAppModel: ObservableObject {
    @Published public private(set) var profiles: [ConnectionProfile]
    @Published public var selectedProfileID: ConnectionProfile.ID?
    @Published public private(set) var session: RemoteSession?
    @Published public private(set) var diagnosticRun: ConnectionDiagnosticRun?
    @Published public private(set) var composeDraft: ComposeDraft?
    @Published public private(set) var latestInjectionAttempt: TextInjectionAttempt?
    @Published public private(set) var pipWatchSession: PiPWatchSession?
    @Published public private(set) var latestFramebuffer: RFBRawFramebuffer?
    /// Damage rectangles paired with `latestFramebuffer`.  Populated
    /// whenever a streaming frame arrives from a damage-tracking pump
    /// source (`RFBFramePumpFrame.dirtyRectangles`); cleared on
    /// disconnect, profile changes, and full-frame fallback paths so
    /// the renderer falls back to a full-frame upload when the pairing
    /// no longer applies.
    @Published public private(set) var latestFrameDirtyRectangles: [RFBFrameDamageRect]?
    /// Pending remote→local clipboard review.  Set when an incoming
    /// `ServerCutText` payload arrives on the active connection,
    /// cleared on Accept, Dismiss, or profile change.  See
    /// `IncomingClipboardBanner`.
    @Published public private(set) var pendingIncomingClipboard: IncomingClipboardReview?
    /// App-level user preferences (e.g. onboarding-checklist
    /// dismissal).  Loaded eagerly in `init` and re-published on
    /// every update through `dismissOnboardingChecklist()`.
    @Published public private(set) var appSettings: AppSettings

    private let connectorFactory: @Sendable () -> RFBFirstFrameConnecting
    private let frameStreamConfiguration: RFBFramePumpConfiguration
    private let profileStore: ConnectionProfileStore?
    private let credentialStore: ConnectionCredentialStoreProtocol?
    private let settingsPersistence: AppSettingsPersisting?
    private let pipWatchController: (any PiPWatchControlling)?
    private let localClipboardWriter: (any LocalClipboardWriting)?
    private let incomingClipboardReceiveTimeout: TimeInterval
    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    public let pipLayerHost: PiPLayerHost
    #endif
    private var activeTextClient: RemoteClipboardTextClient?
    private var activeFramePump: RFBFramePump?
    private var activeFrameStreamTask: Task<Void, Never>?
    private var activeFrameStreamID: UUID?
    private var activeIncomingClipboardTask: Task<Void, Never>?
    @Published public private(set) var profilePersistenceError: String?
    /// Most recent `AppSettingsPersisting` failure, if any.  We do
    /// not crash on settings persistence errors — settings are
    /// non-critical and a stale in-memory `appSettings` is still
    /// safe to use until the next launch.  See ROADMAP Phase 7.
    @Published public private(set) var settingsPersistenceError: String?

    public init(
        snapshot: NaruRemoteAppSnapshot = NaruRemoteAppSnapshot(),
        profileStore: ConnectionProfileStore? = nil,
        credentialStore: ConnectionCredentialStoreProtocol? = nil,
        settingsPersistence: AppSettingsPersisting? = nil,
        frameStreamConfiguration: RFBFramePumpConfiguration = RFBFramePumpConfiguration(
            requestTimeout: 3,
            frameInterval: 0.25
        ),
        connectorFactory: @escaping @Sendable () -> RFBFirstFrameConnecting = { RFBNetworkClient() },
        pipWatchController: (any PiPWatchControlling)? = nil,
        localClipboardWriter: (any LocalClipboardWriting)? = nil,
        incomingClipboardReceiveTimeout: TimeInterval = 30
    ) {
        let storedProfiles = profileStore?.allProfiles() ?? []
        let initialProfiles = snapshot.profiles.isEmpty ? storedProfiles : snapshot.profiles

        // Settings are non-critical: a load failure falls back to
        // defaults rather than throwing from `init`.  The error is
        // observable through `settingsPersistenceError` so the
        // shell can surface it if needed.  See ROADMAP Phase 7.
        let loadedSettings: AppSettings
        let loadError: String?
        if let settingsPersistence {
            do {
                loadedSettings = try settingsPersistence.load()
                loadError = nil
            } catch {
                loadedSettings = AppSettings()
                loadError = "Settings could not be loaded on this device."
            }
        } else {
            loadedSettings = AppSettings()
            loadError = nil
        }

        self.profiles = initialProfiles
        self.selectedProfileID = snapshot.selectedProfileID ?? initialProfiles.first?.id
        self.session = snapshot.session
        self.diagnosticRun = snapshot.diagnosticRun
        self.composeDraft = snapshot.composeDraft
        self.latestInjectionAttempt = snapshot.latestInjectionAttempt
        self.pipWatchSession = snapshot.pipWatchSession
        self.latestFramebuffer = snapshot.latestFramebuffer
        self.latestFrameDirtyRectangles = snapshot.latestFrameDirtyRectangles
        self.appSettings = loadedSettings
        self.settingsPersistenceError = loadError
        self.profileStore = profileStore
        self.credentialStore = credentialStore
        self.settingsPersistence = settingsPersistence
        self.frameStreamConfiguration = frameStreamConfiguration
        self.connectorFactory = connectorFactory
        self.pipWatchController = pipWatchController
        self.localClipboardWriter = localClipboardWriter
        self.incomingClipboardReceiveTimeout = incomingClipboardReceiveTimeout
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        self.pipLayerHost = PiPLayerHost()
        #endif
    }

    /// Persists "user dismissed the first-run onboarding
    /// checklist" so the section stays hidden across launches.
    /// A persistence error is captured in
    /// `settingsPersistenceError` rather than thrown — the
    /// in-memory flag still flips so the current session honors
    /// the dismissal.
    public func dismissOnboardingChecklist() {
        var updated = appSettings
        updated.dismissedOnboardingChecklist = true
        appSettings = updated
        settingsPersistenceError = nil

        guard let settingsPersistence else {
            return
        }

        do {
            try settingsPersistence.save(updated)
        } catch {
            settingsPersistenceError = "Settings could not be saved on this device."
        }
    }

    public var snapshot: NaruRemoteAppSnapshot {
        NaruRemoteAppSnapshot(
            profiles: profiles,
            selectedProfileID: selectedProfileID,
            session: session,
            diagnosticRun: diagnosticRun,
            composeDraft: composeDraft,
            latestInjectionAttempt: latestInjectionAttempt,
            pipWatchSession: pipWatchSession,
            latestFramebuffer: latestFramebuffer,
            latestFrameDirtyRectangles: latestFrameDirtyRectangles
        )
    }

    public var selectedProfile: ConnectionProfile? {
        snapshot.selectedProfile
    }

    public var canStartPiPWatch: Bool {
        snapshot.isPiPWatchAvailable && (pipWatchController?.isSupported ?? false)
    }

    public var pipWatchStatusText: String {
        if pipWatchSession != nil {
            return snapshot.pipWatchStatusText
        }

        guard snapshot.isPiPWatchAvailable else {
            return snapshot.pipWatchStatusText
        }

        guard let pipWatchController else {
            return "PiP renderer pending"
        }

        return pipWatchController.isSupported ? snapshot.pipWatchStatusText : "PiP unavailable on device"
    }

    public func selectProfile(id: ConnectionProfile.ID) {
        if selectedProfileID != id {
            stopFrameStream()
            stopIncomingClipboardReceive()
            pendingIncomingClipboard = nil
            activeTextClient = nil
            latestFramebuffer = nil
            latestFrameDirtyRectangles = nil
            diagnosticRun = nil
            latestInjectionAttempt = nil
            clearPiPWatchSession()
            let newSession = RemoteSession(profileID: id)
            session = newSession
            composeDraft = ComposeDraft(sessionID: newSession.id)
        }
        selectedProfileID = id
    }

    public func addProfile(_ profile: ConnectionProfile, password: String? = nil) {
        profilePersistenceError = nil
        var profileToSave = profile
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedPassword, !trimmedPassword.isEmpty {
            guard let credentialStore else {
                profilePersistenceError = "Password could not be saved on this device."
                return
            }

            let credentialRef = profileToSave.credentialRef ?? Self.credentialReference(for: profileToSave.id)
            do {
                try credentialStore.savePassword(trimmedPassword, for: credentialRef)
                profileToSave.credentialRef = credentialRef
            } catch {
                profilePersistenceError = "Password could not be saved on this device."
                return
            }
        }

        if let index = profiles.firstIndex(where: { $0.id == profileToSave.id }) {
            profiles[index] = profileToSave
        } else {
            profiles.append(profileToSave)
        }

        do {
            try profileStore?.save(profileToSave)
        } catch {
            profilePersistenceError = "Profile could not be saved on this device."
        }

        selectedProfileID = profileToSave.id
        if session == nil || session?.profileID != profileToSave.id {
            stopFrameStream()
            stopIncomingClipboardReceive()
            pendingIncomingClipboard = nil
            let newSession = RemoteSession(profileID: profileToSave.id)
            session = newSession
            composeDraft = ComposeDraft(sessionID: newSession.id)
            diagnosticRun = nil
            latestInjectionAttempt = nil
            clearPiPWatchSession()
            latestFramebuffer = nil
            latestFrameDirtyRectangles = nil
            activeTextClient = nil
        }
    }

    public func runConnectionChecks() {
        guard let profile = selectedProfile else {
            return
        }

        diagnosticRun = ConnectionDiagnosticRun(
            profileID: profile.id,
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .running,
                    safeTitle: "Checking VNC port",
                    safeDetail: "Attempting a TCP/RFB first-frame check."
                )
            ]
        )
    }

    private func connectionCredential(for profile: ConnectionProfile) throws -> RFBConnectionCredential {
        guard let credentialRef = profile.credentialRef else {
            return .none
        }

        guard let password = try credentialStore?.password(for: credentialRef),
              !password.isEmpty
        else {
            throw AppCredentialError.passwordMissing
        }

        return .vncPassword(password)
    }

    private func credentialFailureDiagnosticRun(profile: ConnectionProfile) -> ConnectionDiagnosticRun {
        ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .authentication,
                    status: .failed,
                    safeTitle: "Credential unavailable",
                    safeDetail: "Saved VNC password could not be loaded from this device.",
                    nextAction: "Update the profile password."
                )
            ]
        )
    }

    private static func credentialReference(for profileID: ConnectionProfile.ID) -> String {
        "vnc-password:\(profileID.uuidString)"
    }

    public func connectSelectedProfile() {
        guard let profile = selectedProfile else {
            return
        }

        runConnectionChecks()
        var nextSession = RemoteSession(
            profileID: profile.id,
            state: .connecting,
            hudMessage: "Connecting to \(profile.endpoint)"
        )
        session = nextSession
        composeDraft = ComposeDraft(sessionID: nextSession.id)

        let credential: RFBConnectionCredential
        do {
            credential = try connectionCredential(for: profile)
        } catch {
            nextSession.markFailed("Credential unavailable")
            session = nextSession
            activeTextClient = nil
            latestFramebuffer = nil
            latestFrameDirtyRectangles = nil
            diagnosticRun = credentialFailureDiagnosticRun(profile: profile)
            return
        }

        let connector = connectorFactory()
        stopFrameStream()
        stopIncomingClipboardReceive()
        pendingIncomingClipboard = nil
        if let streamingClient = connector as? any RFBStreamingClient {
            startFrameStream(
                streamingClient,
                profile: profile,
                session: nextSession,
                credential: credential
            )
            return
        }

        Task {
            do {
                let connectionResult = try await Task.detached {
                    try Self.connectAndReadFirstFrame(
                        connector: connector,
                        host: profile.host,
                        port: UInt16(profile.port),
                        credential: credential,
                        timeout: 3
                    )
                }.value

                nextSession.markFirstFrameReceived(at: connectionResult.frameCapturedAt)
                latestFramebuffer = connectionResult.framebuffer
                // Single-shot first-frame path has no damage history.
                latestFrameDirtyRectangles = nil
                let textClient = connector as? RemoteClipboardTextClient
                activeTextClient = textClient
                if textClient != nil {
                    startIncomingClipboardReceive(receive: Self.makeReceive(connector: connector))
                }
                session = nextSession
                diagnosticRun = ConnectionDiagnosticRun(
                    profileID: profile.id,
                    finishedAt: Date(),
                    stages: [
                        DiagnosticStageResult(
                            stage: .dns,
                            status: .passed,
                            safeTitle: "Profile ready",
                            safeDetail: "Private profile is selected."
                        ),
                        DiagnosticStageResult(
                            stage: .tcp,
                            status: .passed,
                            safeTitle: "VNC port reached",
                            safeDetail: "TCP connection succeeded."
                        ),
                        DiagnosticStageResult(
                            stage: .rfbHandshake,
                            status: .passed,
                            safeTitle: "VNC handshake complete",
                            safeDetail: "RFB no-auth first-frame path completed."
                        ),
                        DiagnosticStageResult(
                            stage: .firstFrame,
                            status: .passed,
                            safeTitle: "First frame received",
                            safeDetail: "\(connectionResult.serverInit.width)x\(connectionResult.serverInit.height) remote framebuffer is available."
                        )
                    ]
                )
            } catch {
                activeTextClient = nil
                stopIncomingClipboardReceive()
                latestFramebuffer = nil
                latestFrameDirtyRectangles = nil
                nextSession.markFailed("Connection failed")
                session = nextSession
                diagnosticRun = ConnectionDiagnosticRun(
                    profileID: profile.id,
                    finishedAt: Date(),
                    stages: [
                        DiagnosticStageResult(
                            stage: .dns,
                            status: .passed,
                            safeTitle: "Profile ready",
                            safeDetail: "Private profile is selected."
                        ),
                        DiagnosticStageResult(
                            stage: .rfbHandshake,
                            status: .failed,
                            safeTitle: "VNC handshake failed",
                            safeDetail: "The selected host did not complete the MVP no-auth first-frame path.",
                            nextAction: "Check host, port, VNC server, and security settings."
                        )
                    ]
                )
            }
        }
    }

    private func startFrameStream(
        _ streamingClient: any RFBStreamingClient,
        profile: ConnectionProfile,
        session pendingSession: RemoteSession,
        credential: RFBConnectionCredential
    ) {
        let streamID = UUID()
        let pump = RFBFramePump(source: streamingClient)
        let configuration = frameStreamConfiguration
        activeFrameStreamID = streamID
        activeFramePump = pump

        activeFrameStreamTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let serverInit = try await Task.detached {
                    try streamingClient.connectSession(
                        host: profile.host,
                        port: UInt16(profile.port),
                        credential: credential,
                        timeout: configuration.requestTimeout
                    )
                }.value

                guard isCurrentStream(streamID, sessionID: pendingSession.id, profileID: profile.id) else {
                    return
                }

                activeTextClient = streamingClient
                startIncomingClipboardReceive(receive: Self.makeReceive(streamingClient: streamingClient))

                while shouldRequestAnotherFrame(configuration: configuration, pump: pump) {
                    if Task.isCancelled {
                        pump.cancel()
                        return
                    }

                    let requestTimeout = configuration.requestTimeout
                    let maybeFrame = try await Task.detached {
                        try pump.nextFrame(requestTimeout: requestTimeout)
                    }.value
                    guard let frame = maybeFrame else {
                        return
                    }

                    guard isCurrentStream(streamID, sessionID: pendingSession.id, profileID: profile.id) else {
                        pump.cancel()
                        return
                    }

                    applyStreamFrame(
                        frame,
                        serverInit: serverInit,
                        profile: profile,
                        sessionID: pendingSession.id,
                        streamID: streamID
                    )

                    if configuration.frameInterval > 0 {
                        try await Task.sleep(for: .seconds(configuration.frameInterval))
                    }
                }
            } catch is CancellationError {
                pump.cancel()
            } catch {
                handleStreamFailure(
                    profile: profile,
                    sessionID: pendingSession.id,
                    streamID: streamID
                )
            }
        }
    }

    private func shouldRequestAnotherFrame(
        configuration: RFBFramePumpConfiguration,
        pump: RFBFramePump
    ) -> Bool {
        guard let maxFrames = configuration.maxFrames else {
            return true
        }

        return pump.deliveredFrameCount < maxFrames
    }

    private func applyStreamFrame(
        _ frame: RFBFramePumpFrame,
        serverInit: RFBServerInit,
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        streamID: UUID
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profile.id) else {
            return
        }

        var updatedSession = session ?? RemoteSession(profileID: profile.id)
        updatedSession.markFirstFrameReceived(at: frame.capturedAt)
        latestFramebuffer = frame.framebuffer
        // Only forward damage rectangles for incremental frames.  The
        // first frame in a stream is non-incremental and the renderer
        // must perform a full upload (its texture has just been
        // allocated for these dimensions); pass nil so the dirty-rect
        // path is bypassed for that frame.
        latestFrameDirtyRectangles = frame.isIncremental ? frame.dirtyRectangles : nil
        session = updatedSession
        forwardFrameToLayerHost(frame.framebuffer)
        updatePiPWatchFrameIfNeeded(
            framebuffer: frame.framebuffer,
            sessionID: updatedSession.id,
            capturedAt: frame.capturedAt,
            changeActivity: frame.changeActivity
        )

        if frame.sequence == 1 {
            diagnosticRun = ConnectionDiagnosticRun(
                profileID: profile.id,
                finishedAt: Date(),
                stages: [
                    DiagnosticStageResult(
                        stage: .dns,
                        status: .passed,
                        safeTitle: "Profile ready",
                        safeDetail: "Private profile is selected."
                    ),
                    DiagnosticStageResult(
                        stage: .tcp,
                        status: .passed,
                        safeTitle: "VNC port reached",
                        safeDetail: "TCP connection succeeded."
                    ),
                    DiagnosticStageResult(
                        stage: .rfbHandshake,
                        status: .passed,
                        safeTitle: "VNC handshake complete",
                        safeDetail: "RFB streaming path completed."
                    ),
                    DiagnosticStageResult(
                        stage: .firstFrame,
                        status: .passed,
                        safeTitle: "First frame received",
                        safeDetail: "\(serverInit.width)x\(serverInit.height) remote framebuffer is available."
                    )
                ]
            )
        }
    }

    private func handleStreamFailure(
        profile: ConnectionProfile,
        sessionID: RemoteSession.ID,
        streamID: UUID
    ) {
        guard isCurrentStream(streamID, sessionID: sessionID, profileID: profile.id) else {
            return
        }

        activeTextClient = nil
        stopIncomingClipboardReceive()

        var updatedSession = session ?? RemoteSession(profileID: profile.id)
        if updatedSession.hasReceivedFrame {
            updatedSession.state = .degraded
            updatedSession.hudMessage = "Frame stream interrupted"
            updatedSession.lastError = "Frame stream interrupted"
            session = updatedSession
            return
        }

        updatedSession.markFailed("Connection failed")
        latestFramebuffer = nil
        latestFrameDirtyRectangles = nil
        session = updatedSession
        diagnosticRun = ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .rfbHandshake,
                    status: .failed,
                    safeTitle: "VNC handshake failed",
                    safeDetail: "The selected host did not complete the MVP frame stream path.",
                    nextAction: "Check host, port, VNC server, and security settings."
                )
            ]
        )
    }

    private func isCurrentStream(
        _ streamID: UUID,
        sessionID: RemoteSession.ID,
        profileID: ConnectionProfile.ID
    ) -> Bool {
        activeFrameStreamID == streamID &&
            session?.id == sessionID &&
            selectedProfileID == profileID
    }

    private func stopFrameStream() {
        activeFrameStreamTask?.cancel()
        activeFramePump?.cancel()
        activeFrameStreamTask = nil
        activeFramePump = nil
        activeFrameStreamID = nil
    }

    /// Begin a long-lived receive loop that pulls `ServerCutText`
    /// payloads off the active connection and surfaces each one as a
    /// pending review the user must Accept before the local
    /// pasteboard is touched.
    ///
    /// Behavior on a payload arriving while a previous review is
    /// still pending: REPLACE the previous review with the latest
    /// arrival.  A queue could leak older context across user
    /// attention shifts; replacing keeps the visible review aligned
    /// with the most recent remote copy.
    private func startIncomingClipboardReceive(receive: @escaping @Sendable (TimeInterval) -> IncomingClipboardReceiveResult) {
        stopIncomingClipboardReceive()

        let timeout = incomingClipboardReceiveTimeout

        activeIncomingClipboardTask = Task { [weak self] in
            while !Task.isCancelled {
                let result = await Task.detached {
                    receive(timeout)
                }.value

                if Task.isCancelled {
                    return
                }

                guard let self else {
                    return
                }

                switch result {
                case .text(let text):
                    self.recordIncomingClipboard(text)
                case .unsupported:
                    return
                case .transientError:
                    continue
                }
            }
        }
    }

    private func stopIncomingClipboardReceive() {
        activeIncomingClipboardTask?.cancel()
        activeIncomingClipboardTask = nil
    }

    /// Builds a `Sendable` receive closure for the long-lived
    /// `RFBStreamingClient` path.  Captures only the Sendable
    /// streaming client so the closure can cross actor boundaries
    /// into a detached task.
    nonisolated private static func makeReceive(
        streamingClient: any RFBStreamingClient
    ) -> @Sendable (TimeInterval) -> IncomingClipboardReceiveResult {
        return { timeout in
            do {
                let text = try streamingClient.receiveServerCutText(timeout: timeout)
                return .text(text)
            } catch let error as TextInjectionError {
                if case .clipboardUnavailable = error {
                    return .unsupported
                }
                return .transientError
            } catch {
                return .transientError
            }
        }
    }

    /// Builds a `Sendable` receive closure for the legacy
    /// first-frame connector path.  The receive surface is optional
    /// on this protocol, so the closure short-circuits to
    /// `.unsupported` when the connector does not adopt
    /// `RemoteClipboardTextClient`.
    nonisolated private static func makeReceive(
        connector: any RFBFirstFrameConnecting
    ) -> @Sendable (TimeInterval) -> IncomingClipboardReceiveResult {
        return { timeout in
            guard let textClient = connector as? RemoteClipboardTextClient else {
                return .unsupported
            }
            do {
                let text = try textClient.receiveServerCutText(timeout: timeout)
                return .text(text)
            } catch let error as TextInjectionError {
                if case .clipboardUnavailable = error {
                    return .unsupported
                }
                return .transientError
            } catch {
                return .transientError
            }
        }
    }

    /// Surfaces a fresh `ServerCutText` arrival as a pending review.
    /// Public so deterministic tests can drive the receive surface
    /// without spinning the live receive loop.  Discards empty
    /// payloads — the protocol allows them but they would render an
    /// empty banner with no useful preview.
    public func recordIncomingClipboard(_ text: String, at date: Date = Date()) {
        guard !text.isEmpty else {
            return
        }
        // REPLACE policy: a newer arrival supersedes a still-pending
        // older review.  See `startIncomingClipboardReceive` for
        // rationale.
        pendingIncomingClipboard = IncomingClipboardReview(text: text, arrivedAt: date)
    }

    /// User reviewed the preview and accepted the remote copy.
    /// Writes the *full* text through the injected
    /// `LocalClipboardWriting` boundary and clears the review.
    public func acceptIncomingClipboard() {
        guard let review = pendingIncomingClipboard else {
            return
        }
        localClipboardWriter?.write(review.text)
        pendingIncomingClipboard = nil
    }

    /// User dismissed the review.  Nothing is written to the local
    /// pasteboard.  The full `text` is dropped on the floor.
    public func dismissIncomingClipboard() {
        pendingIncomingClipboard = nil
    }

    nonisolated private static func connectAndReadFirstFrame(
        connector: any RFBFirstFrameConnecting,
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> ConnectionResult {
        if let streamingClient = connector as? any RFBStreamingClient {
            let serverInit = try streamingClient.connectSession(
                host: host,
                port: port,
                credential: credential,
                timeout: timeout
            )
            let pump = RFBFramePump(source: streamingClient)
            var firstFrame: RFBFramePumpFrame?
            _ = try pump.run(
                configuration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: timeout)
            ) { frame in
                firstFrame = frame
                return .stop
            }

            guard let firstFrame else {
                throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
            }

            return ConnectionResult(
                serverInit: serverInit,
                framebuffer: firstFrame.framebuffer,
                frameCapturedAt: firstFrame.capturedAt
            )
        }

        let serverInit: RFBServerInit
        if let authenticatedConnector = connector as? any RFBAuthenticatedFirstFrameConnecting {
            serverInit = try authenticatedConnector.connectFirstFrame(
                host: host,
                port: port,
                credential: credential,
                timeout: timeout
            )
        } else {
            guard credential == .none else {
                throw RFBNetworkClientError.authenticationRequired([RFBSecurityType.vncAuthentication.rawValue])
            }

            serverInit = try connector.connectNoAuthFirstFrame(
                host: host,
                port: port,
                timeout: timeout
            )
        }

        return ConnectionResult(
            serverInit: serverInit,
            framebuffer: nil,
            frameCapturedAt: Date()
        )
    }

    public func handleOnboardingAction(
        _ id: OnboardingStepID,
        presentProfileEditor: () -> Void
    ) {
        switch id {
        case .privateTarget:
            presentProfileEditor()
        case .diagnostics:
            guard selectedProfile != nil else {
                presentProfileEditor()
                return
            }
            runConnectionChecks()
        case .compose:
            break
        case .pipWatch:
            guard canStartPiPWatch else {
                return
            }
            startPiPWatch()
        }
    }

    public func sendComposedText(_ text: String, pasteCommand: PasteCommand = .commandV) {
        guard var draft = composeDraft else {
            return
        }

        draft.updateText(text)

        guard let activeTextClient else {
            let now = Date()
            let message = TextInjectionError
                .clipboardUnavailable("Connect to a remote session before sending text.")
                .localizedDescription
            draft.markFailed(reason: message, at: now)
            composeDraft = draft
            latestInjectionAttempt = TextInjectionAttempt(
                draftID: draft.id,
                sessionID: draft.sessionID,
                path: .vncClipboardPaste,
                startedAt: now,
                finishedAt: now,
                status: .failed,
                safeMessage: message
            )
            return
        }

        let attempt = TextInjectionAdapter().send(
            draft: &draft,
            via: activeTextClient,
            pasteCommand: pasteCommand
        )
        composeDraft = draft
        latestInjectionAttempt = attempt
    }

    public func startPiPWatch(at date: Date = Date()) {
        guard let session else {
            return
        }

        var watchSession = PiPWatchSession(sessionID: session.id)
        watchSession.prepare(
            from: session,
            profileAllowsPiPWatch: selectedProfile?.allowsPiPWatch ?? true,
            at: date
        )

        guard watchSession.state == .preparing else {
            pipWatchSession = watchSession
            return
        }

        guard let latestFramebuffer else {
            watchSession.fail("PiP frame is unavailable.")
            pipWatchSession = watchSession
            return
        }

        guard let pipWatchController else {
            watchSession.fail("PiP renderer is unavailable in this build.")
            pipWatchSession = watchSession
            return
        }

        guard pipWatchController.isSupported, prepareController(pipWatchController) else {
            watchSession.markUnavailable("System PiP is unavailable on this device.")
            pipWatchSession = watchSession
            return
        }

        do {
            forwardFrameToLayerHost(latestFramebuffer)
            try pipWatchController.enqueue(latestFramebuffer)
        } catch {
            watchSession.fail("PiP frame could not be rendered.")
            pipWatchSession = watchSession
            return
        }

        guard pipWatchController.start() else {
            watchSession.fail("PiP start request could not be delivered.")
            pipWatchSession = watchSession
            return
        }

        watchSession.markWatching(
            frame: PiPFrameSnapshot(
                width: latestFramebuffer.width,
                height: latestFramebuffer.height,
                capturedAt: session.lastFrameAt ?? date,
                changeActivity: .moderate
            )
        )
        pipWatchSession = watchSession
    }

    public func stopPiPWatch() {
        guard var pipWatchSession else {
            return
        }

        pipWatchController?.stop()
        pipWatchSession.stop()
        self.pipWatchSession = pipWatchSession
    }

    public func refreshPiPWatchStaleness(now: Date = Date()) {
        guard var pipWatchSession else {
            return
        }

        pipWatchSession.refreshStaleness(now: now)
        self.pipWatchSession = pipWatchSession
    }

    private func updatePiPWatchFrameIfNeeded(
        framebuffer: RFBRawFramebuffer,
        sessionID: RemoteSession.ID,
        capturedAt: Date,
        changeActivity: PiPFrameChangeActivity
    ) {
        guard var pipWatchSession,
              pipWatchSession.sessionID == sessionID,
              pipWatchSession.state == .watching || pipWatchSession.state == .stale || pipWatchSession.state == .preparing
        else {
            return
        }

        guard let pipWatchController else {
            pipWatchSession.fail("PiP renderer is unavailable in this build.")
            self.pipWatchSession = pipWatchSession
            return
        }

        do {
            try pipWatchController.enqueue(framebuffer)
        } catch {
            pipWatchSession.fail("PiP frame could not be rendered.")
            self.pipWatchSession = pipWatchSession
            return
        }

        pipWatchSession.markWatching(
            frame: PiPFrameSnapshot(
                width: framebuffer.width,
                height: framebuffer.height,
                capturedAt: capturedAt,
                changeActivity: changeActivity
            )
        )
        self.pipWatchSession = pipWatchSession
    }

    private func clearPiPWatchSession() {
        pipWatchController?.stop()
        pipWatchSession = nil
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        pipLayerHost.flush()
        #endif
    }

    /// Streams a freshly arrived framebuffer into the shared
    /// `PiPLayerHost`.  This is the single sink that drives both the
    /// in-app `PiPSampleBufferDisplayLayerView` and any attached system
    /// PiP controller — a render failure is intentionally swallowed
    /// here because failures specific to the active PiP session are
    /// surfaced through `updatePiPWatchFrameIfNeeded`.
    private func forwardFrameToLayerHost(_ framebuffer: RFBRawFramebuffer) {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        do {
            _ = try pipLayerHost.enqueue(framebuffer)
        } catch {
            // The PiP-session bookkeeping will surface a render failure
            // through `updatePiPWatchFrameIfNeeded` when a session is
            // active.  Outside an active session, dropping the frame
            // is acceptable.
        }
        #endif
    }

    private func prepareController(_ controller: any PiPWatchControlling) -> Bool {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        if let attaching = controller as? any PiPWatchLayerHostAttaching {
            return attaching.prepare(layerHost: pipLayerHost)
        }
        #endif
        return controller.prepare()
    }
}

private struct ConnectionResult: Sendable {
    let serverInit: RFBServerInit
    let framebuffer: RFBRawFramebuffer?
    let frameCapturedAt: Date
}

private enum AppCredentialError: Error {
    case passwordMissing
}

/// Outcome of one attempt to receive a `ServerCutText` payload from
/// the remote computer.  The receive loop translates throws into
/// these tagged cases so the long-running task does not log raw
/// error strings (constitution §IV: never store user-entered or
/// remote-content-bearing strings in logs by default).
enum IncomingClipboardReceiveResult: Sendable {
    case text(String)
    /// The active client does not support `ServerCutText` — exit
    /// the receive loop entirely.
    case unsupported
    /// A timeout, decode error, or other recoverable failure —
    /// keep the loop alive and try again on the next iteration.
    case transientError
}
