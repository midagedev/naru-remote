import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Tests for the user-initiated `disconnect()` path that the
/// session-viewport "Disconnect" button surfaces.  Coverage:
///
/// 1. Disconnect during active streaming — torn-down state, frame
///    cleared, latch set, profile retained.
/// 2. Disconnect during the bounded auto-reconnect window — pending
///    sleep cancelled, no further connector calls.
/// 3. Disconnect with no active session — silent no-op.
/// 4. Constitution §IV: diagnostic export remains opaque after
///    disconnect (no leaked hostnames or raw error text).
@MainActor
final class NaruRemoteAppDisconnectTests: XCTestCase {
    /// Snappy reconnect policy so the reconnect-window test does
    /// not block the suite while still leaving enough backoff for
    /// disconnect to land mid-sleep.
    private static let testPolicy = ReconnectPolicy(
        maxAttempts: 3,
        initialBackoff: .milliseconds(400),
        maxBackoff: .seconds(1)
    )

    // MARK: - 1. Streaming → disconnect

    func testDisconnectDuringStreamingClearsSessionAndStopsFrameStream() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net"
        )
        let connector = DisconnectFakeConnector(width: 1, height: 1, name: "Desk")
        // Deliver a steady stream of frames — the test will yank
        // the rug out from under it via `disconnect()`.
        connector.programFrame()
        connector.programFrame()
        connector.programFrame()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 6, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        // Wait long enough for at least one frame to land so the
        // session is unambiguously in `.active`.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertNotNil(model.latestFramebuffer)
        XCTAssertFalse(model.explicitlyDisconnected)

        let connectsAtDisconnect = connector.sessionRequests.count

        model.disconnect()

        // Profile retention: the user disconnected from a session,
        // not from a profile.  The selection and the persisted
        // profile list both survive.
        XCTAssertEqual(model.selectedProfile?.id, profile.id)
        XCTAssertEqual(model.snapshot.profiles.count, 1)
        // Terminal disconnected state.
        XCTAssertEqual(model.snapshot.session?.state, .closed)
        // Stale pixels are gone.
        XCTAssertNil(model.latestFramebuffer)
        XCTAssertNil(model.latestFrameDirtyRectangles)
        // Latch is set so a late-firing stream failure cannot
        // resuscitate the session behind the user's back.
        XCTAssertTrue(model.explicitlyDisconnected)

        // Wait past any reasonable backoff window — no further
        // connector calls should fire because the latch blocks
        // auto-reconnect.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(connector.sessionRequests.count, connectsAtDisconnect)
        XCTAssertEqual(model.snapshot.session?.state, .closed)
    }

    // MARK: - 2. Reconnecting → disconnect

    func testDisconnectDuringReconnectingCancelsPendingRetry() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net"
        )
        let connector = DisconnectFakeConnector(width: 1, height: 1, name: "Desk")
        // First stream: deliver one frame, then drop.
        connector.programFrame()
        connector.programFailure()
        // If the reconnect were to fire, it would need a fresh
        // frame.  Programming one lets us assert the count of
        // requests AFTER disconnect to prove no reconnect ran.
        connector.programFrame()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 4, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        // Wait long enough for the first frame + failure to land,
        // but well under the 400ms initial backoff.
        try await Task.sleep(for: .milliseconds(150))

        // We should now be sleeping the policy backoff.
        guard case .reconnecting = model.snapshot.session?.state else {
            XCTFail("Expected .reconnecting, got \(String(describing: model.snapshot.session?.state))")
            return
        }
        let connectsBeforeDisconnect = connector.sessionRequests.count
        XCTAssertEqual(connectsBeforeDisconnect, 1, "No second connect should have fired yet.")

        model.disconnect()

        // Terminal disconnected state.
        XCTAssertEqual(model.snapshot.session?.state, .closed)
        XCTAssertTrue(model.explicitlyDisconnected)
        // Wait past the original backoff window — no second
        // connect attempt may fire.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(
            connector.sessionRequests.count,
            connectsBeforeDisconnect,
            "Disconnect during reconnect window must cancel the pending retry."
        )
        XCTAssertEqual(model.snapshot.session?.state, .closed)
    }

    // MARK: - 3. Idle → disconnect (no-op)

    func testDisconnectWithNoActiveSessionIsNoOp() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net"
        )
        let connector = DisconnectFakeConnector(width: 1, height: 1, name: "Desk")

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        // No `connectSelectedProfile()` call: the session has never
        // been opened.
        XCTAssertNil(model.snapshot.session)
        XCTAssertNil(model.latestFramebuffer)
        XCTAssertFalse(model.explicitlyDisconnected)

        model.disconnect()

        // The latch flips because the user did invoke disconnect,
        // but no session existed to mutate and no connector calls
        // are made.
        XCTAssertTrue(model.explicitlyDisconnected)
        XCTAssertNil(model.snapshot.session)
        XCTAssertNil(model.latestFramebuffer)
        XCTAssertEqual(connector.sessionRequests.count, 0)
        // Selected profile still selected.
        XCTAssertEqual(model.selectedProfile?.id, profile.id)
    }

    // MARK: - 4. Constitution §IV: opaque diagnostic export

    func testDiagnosticExportRemainsOpaqueAfterDisconnect() async throws {
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net"
        )
        let connector = DisconnectFakeConnector(width: 1, height: 1, name: "Desk")
        connector.programFrame()
        connector.programFrame()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 4, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(150))

        model.disconnect()

        // The shared safe-detail export rule applies regardless of
        // how the session ended (constitution §IV).  No hostnames,
        // no raw error type names.
        let export = model.makeDiagnosticExport()
        let rendered = export.renderShareText(buildVersion: nil)
        XCTAssertFalse(
            rendered.contains("desk.tailnet.ts.net"),
            "Diagnostic export must not leak hostnames after disconnect."
        )
        XCTAssertFalse(
            rendered.contains("DisconnectFakeConnectorError"),
            "Diagnostic export must not leak fake-connector error type names."
        )
    }
}

// MARK: - Helpers

/// Recording streaming connector parallel to the one in
/// `NaruRemoteAppReconnectTests`.  We keep this fake local to the
/// disconnect test file (rather than promoting a shared helper) so
/// changes to either suite's failure-injection vocabulary cannot
/// silently shift the other suite's assertions.
private final class DisconnectFakeConnector: RFBStreamingClient {
    struct ConnectRequest: Equatable {
        let host: String
        let port: UInt16
    }

    fileprivate enum Step {
        case frame(RFBRawFramebuffer)
        case failure
    }

    fileprivate struct Recording {
        var steps: [Step] = []
        var recordedSessionRequests: [ConnectRequest] = []
        var recordedCredentialsList: [RFBConnectionCredential] = []
        var lastDeliveredFramebuffer: RFBRawFramebuffer?
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String

    init(width: Int, height: Int, name: String) {
        self.width = width
        self.height = height
        self.name = name
        self.recording = OSAllocatedUnfairLock(initialState: Recording())
    }

    func programFrame() {
        recording.withLock { state in
            state.steps.append(
                .frame(
                    RFBRawFramebuffer(
                        width: width,
                        height: height,
                        fill: RFBColor(red: 10, green: 0, blue: 0)
                    )
                )
            )
        }
    }

    func programFailure() {
        recording.withLock { state in
            state.steps.append(.failure)
        }
    }

    var sessionRequests: [ConnectRequest] {
        recording.withLock { $0.recordedSessionRequests }
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
        recording.withLock { state in
            state.recordedSessionRequests.append(ConnectRequest(host: host, port: port))
            state.recordedCredentialsList.append(credential)
        }
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
        try recording.withLock { state -> RFBRawFramebuffer in
            let next = state.steps.isEmpty ? nil : state.steps.removeFirst()
            switch next {
            case .frame(let framebuffer):
                state.lastDeliveredFramebuffer = framebuffer
                return framebuffer
            case .failure:
                throw DisconnectFakeConnectorError.programmedFailure
            case .none:
                // Out of programmed steps: repeat the last delivered
                // frame so the stream keeps producing without
                // unintentionally exhausting the policy.  If we have
                // never delivered a frame, throw so the test does not
                // silently spin.
                guard let lastFramebuffer = state.lastDeliveredFramebuffer else {
                    throw DisconnectFakeConnectorError.programmedFailure
                }
                return lastFramebuffer
            }
        }
    }

    func setClipboardText(_ text: String) throws {
        // No clipboard surface is exercised by the disconnect tests.
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        // No paste surface is exercised by the disconnect tests.
    }

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        // No pointer surface is exercised by the disconnect tests.
    }
}

private enum DisconnectFakeConnectorError: Error {
    case programmedFailure
}
