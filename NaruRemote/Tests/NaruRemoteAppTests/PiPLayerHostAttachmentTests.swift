import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
import CoreMedia
import CoreVideo

@MainActor
final class PiPLayerHostAttachmentTests: XCTestCase {
    // MARK: - Layer host attachment lifecycle

    func testModelCreatesLayerHostOnInit() {
        let model = NaruRemoteAppModel()

        // The host's display layer must be a real
        // AVSampleBufferDisplayLayer that the SwiftUI representable can
        // attach to its UIView's layer hierarchy.
        XCTAssertNotNil(model.pipLayerHost.layer)
    }

    func testStartPiPWatchAttachesLayerHostToHostAttachingController() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let framebuffer = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let pipController = FakeLayerHostAttachingController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: framebuffer
            ),
            pipWatchController: pipController
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 101))

        XCTAssertEqual(pipController.attachedLayerHosts.count, 1)
        XCTAssertTrue(pipController.attachedLayerHosts.first === model.pipLayerHost)
        XCTAssertEqual(
            pipController.prepareCount,
            0,
            "Host-aware prepare(layerHost:) must be preferred over the bare prepare()."
        )
        XCTAssertEqual(pipController.prepareWithHostCount, 1)
    }

    func testStartPiPWatchFallsBackToBarePrepareWhenControllerCannotAttach() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipController = LegacyFakePiPWatchController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: RFBRawFramebuffer(width: 1, height: 1)
            ),
            pipWatchController: pipController
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 101))

        XCTAssertEqual(pipController.prepareCount, 1)
        XCTAssertEqual(pipController.startCount, 1)
    }

    // MARK: - Frame forwarding ordering

    func testStreamingFramesAreForwardedThroughLayerHostBeforeReachingController() async throws {
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
        let connector = FakeStreamingFramebufferConnector(
            width: 1,
            height: 1,
            framebuffers: [firstFramebuffer, secondFramebuffer]
        )
        let pipController = FakeLayerHostAttachingController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0.05),
            connectorFactory: { connector },
            pipWatchController: pipController
        )

        model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(40))
        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        try await Task.sleep(for: .milliseconds(120))

        // The controller observes both frames after the model has
        // already enqueued them into the layer host — the model writes
        // every streamed frame into its `pipLayerHost` first and then
        // notifies the attached controller.
        XCTAssertEqual(pipController.enqueuedFramebuffers, [firstFramebuffer, secondFramebuffer])
        XCTAssertEqual(pipController.attachedLayerHosts.count, 1)
        XCTAssertTrue(pipController.attachedLayerHosts.first === model.pipLayerHost)
    }

    // MARK: - Cancellation on profile change

    func testProfileChangeStopsControllerAndClearsPiPSession() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        let initialFrame = RFBRawFramebuffer(
            width: 1,
            height: 1,
            fill: RFBColor(red: 10, green: 0, blue: 0)
        )
        let pipController = FakeLayerHostAttachingController()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [first, second],
                selectedProfileID: first.id,
                session: RemoteSession(
                    profileID: first.id,
                    state: .active,
                    lastFrameAt: Date(timeIntervalSince1970: 100)
                ),
                latestFramebuffer: initialFrame
            ),
            pipWatchController: pipController
        )

        model.startPiPWatch(at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(pipController.startCount, 1)

        model.selectProfile(id: second.id)

        XCTAssertEqual(model.snapshot.selectedProfile, second)
        XCTAssertNil(model.snapshot.pipWatchSession)
        XCTAssertEqual(
            pipController.stopCount,
            1,
            "Switching profiles must stop the PiP controller so the next session does not double-render."
        )
    }
}

// MARK: - Test fakes

@MainActor
private final class FakeLayerHostAttachingController: PiPWatchControlling, PiPWatchLayerHostAttaching {
    let isSupported: Bool
    private(set) var prepareCount = 0
    private(set) var prepareWithHostCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var enqueuedFramebuffers: [RFBRawFramebuffer] = []
    private(set) var attachedLayerHosts: [PiPLayerHost] = []

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    func prepare() -> Bool {
        prepareCount += 1
        return isSupported
    }

    func prepare(layerHost: PiPLayerHost) -> Bool {
        prepareWithHostCount += 1
        attachedLayerHosts.append(layerHost)
        return isSupported
    }

    func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
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

@MainActor
private final class LegacyFakePiPWatchController: PiPWatchControlling {
    let isSupported: Bool
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var enqueuedFramebuffers: [RFBRawFramebuffer] = []

    init(isSupported: Bool = true) {
        self.isSupported = isSupported
    }

    func prepare() -> Bool {
        prepareCount += 1
        return isSupported
    }

    func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
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

private final class FakeStreamingFramebufferConnector: RFBStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private let width: Int
    private let height: Int
    private var framebuffers: [RFBRawFramebuffer]

    init(width: Int, height: Int, framebuffers: [RFBRawFramebuffer]) {
        self.width = width
        self.height = height
        self.framebuffers = framebuffers
    }

    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? { RFBFrameMetadata(width: width, height: height) }

    func connectNoAuthFirstFrame(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        RFBServerInit(
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
            name: "FakeStreaming"
        )
    }

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        lock.lock()
        let framebuffer = framebuffers.isEmpty ? nil : framebuffers.removeFirst()
        lock.unlock()

        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return framebuffer
    }

    func setClipboardText(_ text: String) throws {}
    func sendPasteCommand(_ command: PasteCommand) throws {}
}
#endif
