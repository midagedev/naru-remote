import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class NaruRemoteAppModelTests: XCTestCase {
    func testModelAddsProfileAndCreatesSessionDraft() throws {
        let model = NaruRemoteAppModel()
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        model.addProfile(profile)

        XCTAssertEqual(model.snapshot.selectedProfile, profile)
        XCTAssertEqual(model.snapshot.session?.profileID, profile.id)
        XCTAssertEqual(model.snapshot.composeDraft?.sessionID, model.snapshot.session?.id)
    }

    func testModelLoadsProfilesFromStoreOnLaunch() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try ConnectionProfileStore(persistence: persistence)

        let model = NaruRemoteAppModel(profileStore: store)

        XCTAssertEqual(model.snapshot.profiles, [profile])
        XCTAssertEqual(model.snapshot.selectedProfile, profile)
    }

    func testModelPersistsAddedProfileToStore() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        model.addProfile(profile)

        XCTAssertEqual(try ConnectionProfileStore(persistence: persistence).allProfiles(), [profile])
        XCTAssertNil(model.profilePersistenceError)
    }

    func testModelSavesProfilePasswordInCredentialStoreAndKeepsOnlyReferenceInProfile() throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        model.addProfile(profile, password: "secret")

        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)
        XCTAssertEqual(savedProfile.host, "desk.tailnet.ts.net")
        XCTAssertEqual(try credentialStore.password(for: credentialRef), "secret")
        XCTAssertFalse(credentialRef.contains("secret"))
        XCTAssertNil(model.profilePersistenceError)
    }

    func testModelUsesStoredVNCPasswordForStreamingConnection() async throws {
        let credentialRef = "vnc-password:test"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: credentialRef
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [credentialRef: "secret"])
        let framebuffer = RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 10, green: 0, blue: 0))
        let connector = FakeStreamingConnector(width: 1, height: 1, name: "Desk", framebuffer: framebuffer)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.credentials, [.vncPassword("secret")])
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
    }

    func testModelFailsSafelyWhenProfileCredentialReferenceCannotBeLoaded() throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: "vnc-password:missing"
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 10, green: 0, blue: 0))
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: InMemoryConnectionCredentialStore(),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()

        XCTAssertEqual(connector.sessionRequests, [])
        XCTAssertEqual(model.snapshot.session?.state, .failed)
        XCTAssertEqual(model.snapshot.diagnosticRun?.firstFailedStage?.stage, .authentication)
        XCTAssertNil(model.snapshot.latestFramebuffer)
    }

    func testModelConnectsSelectedProfileThroughConnector() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.requests, [FakeFirstFrameConnector.Request(host: "desk.tailnet.ts.net", port: 5900)])
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Connected")
        XCTAssertEqual(model.snapshot.diagnosticRun?.firstFailedStage, nil)
        XCTAssertEqual(model.snapshot.diagnosticRun?.stages.last?.stage, .firstFrame)
    }

    func testModelConnectsStreamingClientAndStoresFirstFramebuffer() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = FakeStreamingConnector(width: 2, height: 1, name: "Desk", framebuffer: framebuffer)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.sessionRequests, [FakeFirstFrameConnector.Request(host: "desk.tailnet.ts.net", port: 5900)])
        XCTAssertEqual(connector.frameUpdateRequests, [false])
        XCTAssertEqual(model.snapshot.latestFramebuffer, framebuffer)
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Connected")
        XCTAssertEqual(model.snapshot.diagnosticRun?.stages.last?.safeDetail, "2x1 remote framebuffer is available.")
    }

    func testModelKeepsStreamingFramesAfterFirstFramebuffer() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(connector.frameUpdateRequests, [false, true])
        XCTAssertEqual(model.snapshot.latestFramebuffer, secondFramebuffer)
        XCTAssertEqual(model.snapshot.session?.state, .active)
    }

    func testModelCancelsFrameStreamAndClearsFramebufferWhenProfileChanges() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [framebuffer, framebuffer]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [first, second], selectedProfileID: first.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0.05),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNotNil(model.snapshot.latestFramebuffer)

        model.selectProfile(id: second.id)

        XCTAssertEqual(model.snapshot.selectedProfile, second)
        XCTAssertEqual(model.snapshot.session?.profileID, second.id)
        XCTAssertNil(model.snapshot.latestFramebuffer)
        XCTAssertNil(model.snapshot.diagnosticRun)
    }

    func testModelStartsPiPWatchWhenActiveFrameExists() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: FakePiPWatchController()
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 101))

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .watching)
        XCTAssertEqual(model.snapshot.pipWatchSession?.inputPolicy, .watchOnly)
        XCTAssertEqual(model.snapshot.pipWatchSession?.lastFrame?.width, 2)
        XCTAssertEqual(model.snapshot.pipWatchSession?.lastFrame?.height, 1)
        XCTAssertEqual(model.snapshot.pipWatchStatusText, "Watching in PiP")
    }

    func testModelStartsSystemPiPControllerWhenActiveFrameExists() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: pipController
        )

        XCTAssertTrue(model.canStartPiPWatch)

        model.startPiPWatch(at: Date(timeIntervalSince1970: 101))

        XCTAssertEqual(pipController.prepareCount, 1)
        XCTAssertEqual(pipController.startCount, 1)
        XCTAssertEqual(pipController.enqueuedFramebuffers, [framebuffer])
        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .watching)
    }

    func testModelReportsPiPUnavailableWhenSystemPiPIsUnsupported() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipController = FakePiPWatchController(isSupported: false)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: RFBRawFramebuffer(width: 1, height: 1)
            ),
            pipWatchController: pipController
        )

        XCTAssertFalse(model.canStartPiPWatch)
        XCTAssertEqual(model.pipWatchStatusText, "PiP unavailable on device")

        model.startPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .unavailable)
        XCTAssertEqual(model.snapshot.pipWatchSession?.safeMessage, "System PiP is unavailable on this device.")
        XCTAssertEqual(pipController.enqueuedFramebuffers, [])
    }

    func testModelFailsPiPWatchWhenInitialFrameCannotBeRendered() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipController = FakePiPWatchController(enqueueError: FakePiPWatchError.renderFailed)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: RFBRawFramebuffer(width: 1, height: 1)
            ),
            pipWatchController: pipController
        )

        model.startPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .failed)
        XCTAssertEqual(model.snapshot.pipWatchSession?.safeMessage, "PiP frame could not be rendered.")
        XCTAssertEqual(pipController.startCount, 0)
    }

    func testModelReportsPiPUnavailableWithoutReceivedFrame() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session
            )
        )

        model.startPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .unavailable)
        XCTAssertEqual(
            model.snapshot.pipWatchSession?.safeMessage,
            "PiP Watch is available after a remote frame is active."
        )
    }

    func testModelRefreshesAndStopsPiPWatchSession() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: FakePiPWatchController()
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        model.refreshPiPWatchStaleness(now: Date(timeIntervalSince1970: 109))

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .stale)
        XCTAssertEqual(model.snapshot.pipWatchStatusText, "PiP frame stale")

        model.stopPiPWatch()

        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .stopped)
        XCTAssertEqual(model.snapshot.pipWatchStatusText, "PiP Watch ready")
    }

    func testModelSendsComposedTextThroughActiveRFBTextClientAfterConnect() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FakeFirstFrameConnector(width: 1440, height: 900, name: "Desk")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(50))

        model.sendComposedText("한글과 English 😊", pasteCommand: .controlV)

        XCTAssertEqual(connector.clipboardPayloads, ["한글과 English 😊"])
        XCTAssertEqual(connector.pasteCommands, [.controlV])
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .unknown)
        XCTAssertEqual(model.snapshot.composeDraft?.text, "한글과 English 😊")
    }

    func testModelRetainsComposedTextWhenSendHasNoActiveConnection() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id)
            )
        )

        model.sendComposedText("로컬에 남아야 하는 문장")

        XCTAssertEqual(model.snapshot.composeDraft?.text, "로컬에 남아야 하는 문장")
        XCTAssertEqual(model.snapshot.composeDraft?.sendState, .failed)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt?.status, .failed)
    }

    func testModelEnqueuesStreamingFramesToActivePiPController() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let firstFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let secondFramebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 20, green: 0, blue: 0)
        )
        let connector = FakeStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0.05),
            connectorFactory: { connector },
            pipWatchController: pipController
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(40))
        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(pipController.enqueuedFramebuffers, [firstFramebuffer, secondFramebuffer])
        XCTAssertEqual(model.snapshot.pipWatchSession?.lastFrame?.changeActivity, .high)
    }

    func testHandleOnboardingActionPrivateTargetPresentsProfileEditor() {
        let model = NaruRemoteAppModel()
        var presentCount = 0

        model.handleOnboardingAction(.privateTarget) {
            presentCount += 1
        }

        XCTAssertEqual(presentCount, 1)
        XCTAssertNil(model.snapshot.diagnosticRun)
    }

    func testHandleOnboardingActionDiagnosticsRunsChecksWhenProfileSelected() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id)
        )
        var presentCount = 0

        model.handleOnboardingAction(.diagnostics) {
            presentCount += 1
        }

        XCTAssertEqual(presentCount, 0)
        XCTAssertEqual(model.snapshot.diagnosticRun?.profileID, profile.id)
    }

    func testHandleOnboardingActionDiagnosticsFallsBackToProfileEditorWhenNoProfile() {
        let model = NaruRemoteAppModel()
        var presentCount = 0

        model.handleOnboardingAction(.diagnostics) {
            presentCount += 1
        }

        XCTAssertEqual(presentCount, 1)
        XCTAssertNil(model.snapshot.diagnosticRun)
    }

    func testHandleOnboardingActionPiPWatchStartsWhenAvailable() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 2,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let pipController = FakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: pipController
        )

        model.handleOnboardingAction(.pipWatch) {
            XCTFail("PiP watch action should not request the profile editor.")
        }

        XCTAssertEqual(pipController.startCount, 1)
        XCTAssertEqual(model.snapshot.pipWatchSession?.state, .watching)
    }

    func testHandleOnboardingActionPiPWatchIsNoopWhenUnavailable() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id)
        )

        model.handleOnboardingAction(.pipWatch) {
            XCTFail("PiP watch action should not request the profile editor.")
        }

        XCTAssertNil(model.snapshot.pipWatchSession)
    }

    func testHandleOnboardingActionComposeIsNoop() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id)
        )

        model.handleOnboardingAction(.compose) {
            XCTFail("Compose action should not request the profile editor.")
        }

        XCTAssertNil(model.snapshot.diagnosticRun)
        XCTAssertNil(model.snapshot.pipWatchSession)
    }
}

private enum FakePiPWatchError: Error {
    case renderFailed
}

@MainActor
private final class FakePiPWatchController: PiPWatchControlling {
    let isSupported: Bool
    let enqueueError: Error?
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var enqueuedFramebuffers: [RFBRawFramebuffer] = []

    init(isSupported: Bool = true, enqueueError: Error? = nil) {
        self.isSupported = isSupported
        self.enqueueError = enqueueError
    }

    func prepare() -> Bool {
        prepareCount += 1
        return isSupported
    }

    func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
        if let enqueueError {
            throw enqueueError
        }
        enqueuedFramebuffers.append(framebuffer)
    }

    func start() -> Bool {
        startCount += 1
        return isSupported
    }

    func stop() {
        stopCount += 1
    }
}

private final class FakeFirstFrameConnector: RFBFirstFrameConnecting, RemoteClipboardTextClient, @unchecked Sendable {
    struct Request: Equatable {
        let host: String
        let port: UInt16
    }

    private let lock = NSLock()
    private let width: Int
    private let height: Int
    private let name: String
    private var recordedRequests: [Request] = []
    private var recordedClipboardPayloads: [String] = []
    private var recordedPasteCommands: [PasteCommand] = []

    init(width: Int, height: Int, name: String) {
        self.width = width
        self.height = height
        self.name = name
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    var clipboardPayloads: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedClipboardPayloads
    }

    var pasteCommands: [PasteCommand] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPasteCommands
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        lock.lock()
        recordedRequests.append(Request(host: host, port: port))
        lock.unlock()

        return RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func setClipboardText(_ text: String) throws {
        lock.lock()
        recordedClipboardPayloads.append(text)
        lock.unlock()
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        lock.lock()
        recordedPasteCommands.append(command)
        lock.unlock()
    }
}

private final class FakeStreamingConnector: RFBStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private let width: Int
    private let height: Int
    private let name: String
    private var framebuffers: [RFBRawFramebuffer]
    private var recordedSessionRequests: [FakeFirstFrameConnector.Request] = []
    private var recordedFrameUpdateRequests: [Bool] = []
    private var recordedCredentials: [RFBConnectionCredential] = []
    private var recordedClipboardPayloads: [String] = []
    private var recordedPasteCommands: [PasteCommand] = []

    init(width: Int, height: Int, name: String, framebuffer: RFBRawFramebuffer) {
        self.width = width
        self.height = height
        self.name = name
        self.framebuffers = [framebuffer]
    }

    init(width: Int, height: Int, name: String, framebuffers: [RFBRawFramebuffer]) {
        self.width = width
        self.height = height
        self.name = name
        self.framebuffers = framebuffers
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var sessionRequests: [FakeFirstFrameConnector.Request] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSessionRequests
    }

    var frameUpdateRequests: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return recordedFrameUpdateRequests
    }

    var credentials: [RFBConnectionCredential] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCredentials
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectFirstFrame(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        lock.lock()
        recordedSessionRequests.append(FakeFirstFrameConnector.Request(host: host, port: port))
        recordedCredentials.append(credential)
        lock.unlock()

        return RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        lock.lock()
        recordedFrameUpdateRequests.append(incremental)
        let framebuffer = framebuffers.isEmpty ? nil : framebuffers.removeFirst()
        lock.unlock()

        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }

        return framebuffer
    }

    func setClipboardText(_ text: String) throws {
        lock.lock()
        recordedClipboardPayloads.append(text)
        lock.unlock()
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        lock.lock()
        recordedPasteCommands.append(command)
        lock.unlock()
    }
}
