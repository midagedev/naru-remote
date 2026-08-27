import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// End-to-end tests for bounded auto-reconnect on a streaming
/// connection drop.  All network behavior is driven by a recording
/// `FlakyStreamingConnector` whose framebuffer pump can be told to
/// throw at deterministic points — no real sockets are touched.
@MainActor
final class NaruRemoteAppReconnectTests: XCTestCase {
    /// Short, snappy policy so the tests do not block the runner.
    /// 50ms initial / 100ms cap keeps the whole exhaustion test
    /// under ~1s.
    private static let testPolicy = ReconnectPolicy(
        maxAttempts: 3,
        initialBackoff: .milliseconds(50),
        maxBackoff: .milliseconds(100)
    )

    /// Wait for the reconnect to actually land instead of sleeping a fixed
    /// wall-clock budget and hoping. A flat `Task.sleep(400ms)` here failed once
    /// on a loaded machine (2026-08-21 TestFlight gate run: session requests
    /// read 1, not 2) while passing every time on an idle one — the assertion
    /// was sound, the wait was not. Returns as soon as the condition holds;
    /// the deadline only bounds a genuine failure.
    ///
    /// And when the deadline is reached, it **fails**. It used to fall out of
    /// the loop and return, so the same flake came back on the build-13 gate
    /// run wearing a different face: `testReconnectAttemptsUseSameProfileAnd-
    /// CredentialRef` announced `("1") is not equal to ("2")` — a message about
    /// the reconnect using the wrong profile, when what had happened is that
    /// the reconnect had not happened yet. A wait that gives up quietly does
    /// not make a test flaky; it makes a flaky test lie about why.
    private func waitFor(
        _ condition: @escaping () -> Bool,
        _ description: String = "the awaited state",
        timeout: Duration = .seconds(10),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        // One last look: the loop can exit at the deadline in the instant
        // before the condition becomes true.
        guard condition() else {
            XCTFail(
                "Timed out after \(timeout) waiting for \(description)",
                file: file,
                line: line
            )
            return
        }
    }

    // MARK: - Auto-reconnect succeeds

    func testModelAutoReconnectsAfterStreamDrop() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FlakyStreamingConnector(width: 1, height: 1, name: "Desk")
        // First stream: deliver one frame, then throw.
        connector.programFrame()
        connector.programFailure()
        // Reconnect: deliver a frame.
        connector.programFrame()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 2, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        // Wait for the frame accounting this test asserts, not just for the
        // reconnect to be requested. Waiting on the request count alone is a
        // proxy: it went green while the post-reconnect frames were still being
        // counted, and the delivered-frame assertion read 1 instead of 3 on a
        // loaded runner (2026-08-21) while passing on an idle one.
        try await waitFor({
            connector.sessionRequests.count >= 2
                && model.snapshot.sessionStreamStats.deliveredFrameCount >= 3
        }, "a reconnect plus the three frames this test counts")

        // Two streaming connects total: the original + one
        // reconnect.  The reconnect uses the same host/port and the
        // same credential as the original.
        XCTAssertEqual(connector.sessionRequests.count, 2)
        XCTAssertTrue(connector.sessionRequests.allSatisfy { $0.host == "desk.tailnet.ts.net" })
        XCTAssertTrue(connector.recordedCredentials.allSatisfy { $0 == .none })

        // Successful frame after reconnect → state back to .active
        // and the attempt counter has been reset.
        XCTAssertEqual(model.snapshot.session?.state, .active)
        XCTAssertEqual(model.snapshot.sessionStreamStats.deliveredFrameCount, 3)
        XCTAssertEqual(model.snapshot.sessionStreamStats.contentFrameCount, 3)
        XCTAssertEqual(model.snapshot.sessionStreamStats.emptyUpdateCount, 0)
    }

    func testReconnectAttemptsUseSameProfileAndCredentialRef() async throws {
        let credentialRef = "vnc-password:reconnect"
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: credentialRef
        )
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [credentialRef: "secret"])
        let connector = FlakyStreamingConnector(width: 1, height: 1, name: "Desk")
        connector.programFrame()
        connector.programFailure()
        connector.programFrame()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            credentialStore: credentialStore,
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 4, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await waitFor({ connector.sessionRequests.count >= 2 }, "a second session request")

        XCTAssertEqual(connector.sessionRequests.count, 2)
        // Same host + same credential on every attempt.  The
        // credential store is consulted exactly once at the
        // user-initiated `connectSelectedProfile()` boundary; the
        // reconnect path replays the credential captured at the
        // first stream start, NOT a fresh keychain read.
        XCTAssertTrue(connector.sessionRequests.allSatisfy { $0.host == "desk.tailnet.ts.net" })
        XCTAssertTrue(connector.recordedCredentials.allSatisfy { $0 == .vncPassword("secret") })
    }

    func testFrameAfterReconnectResetsAttemptCounter() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FlakyStreamingConnector(width: 1, height: 1, name: "Desk")
        // 1st stream: frame, fail
        connector.programFrame()
        connector.programFailure()
        // 1st reconnect: frame (resets counter), then later fail
        connector.programFrame()
        connector.programFailure()
        // 2nd reconnect: frame
        connector.programFrame()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 6, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await waitFor({
            connector.sessionRequests.count >= 3 && model.snapshot.session?.state == .active
        }, "three session requests and an active session")

        // Three connects total (initial + two reconnects).  Both
        // drops were within the policy budget because each fresh
        // frame reset the counter to 0, so neither drop exhausted
        // the budget.
        XCTAssertEqual(connector.sessionRequests.count, 3)
        XCTAssertEqual(model.snapshot.session?.state, .active)
    }

    // MARK: - User cancellation paths

    func testUserDisconnectDuringReconnectCancelsPendingSleep() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FlakyStreamingConnector(width: 1, height: 1, name: "Desk")
        connector.programFrame()
        connector.programFailure()
        // If the reconnect were to fire, it would ask for another
        // frame.  We program one but expect it to never be served.
        connector.programFrame()

        let policy = ReconnectPolicy(
            maxAttempts: 3,
            initialBackoff: .milliseconds(400),
            maxBackoff: .seconds(1)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 4, frameInterval: 0),
            reconnectPolicy: policy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        // Wait long enough for the first frame + failure to land,
        // but well under the 400ms backoff.
        try await Task.sleep(for: .milliseconds(150))

        // We should now be in the reconnect window.
        if case .reconnecting = model.snapshot.session?.state {
            // ok
        } else {
            XCTFail("Expected .reconnecting, got \(String(describing: model.snapshot.session?.state))")
        }

        let connectsBeforeDisconnect = connector.sessionRequests.count
        XCTAssertEqual(connectsBeforeDisconnect, 1, "No second connect should have fired yet.")

        // User-initiated disconnect cancels the pending sleep.
        model.disconnect()
        XCTAssertEqual(model.snapshot.session?.state, .closed)

        // Wait past the original backoff window — no second connect
        // attempt must fire.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(connector.sessionRequests.count, 1)
        XCTAssertEqual(model.snapshot.session?.state, .closed)
    }

    func testProfileChangeDuringReconnectCancelsAndDoesNotContinueOnOldProfile() async throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        let connector = FlakyStreamingConnector(width: 1, height: 1, name: "Desk")
        connector.programFrame()
        connector.programFailure()
        connector.programFrame()

        let policy = ReconnectPolicy(
            maxAttempts: 3,
            initialBackoff: .milliseconds(400),
            maxBackoff: .seconds(1)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [first, second],
                selectedProfileID: first.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 4, frameInterval: 0),
            reconnectPolicy: policy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(150))

        if case .reconnecting = model.snapshot.session?.state {
            // ok
        } else {
            XCTFail("Expected .reconnecting before profile change.")
        }
        let connectsBeforeProfileChange = connector.sessionRequests.count

        model.selectProfile(id: second.id)

        try await Task.sleep(for: .milliseconds(500))

        // No additional connect against `desk.tailnet.ts.net`
        // landed after the profile switch.  (`selectProfile` does
        // not auto-connect to the new profile; user has to tap
        // Connect again.)
        XCTAssertEqual(connector.sessionRequests.count, connectsBeforeProfileChange)
        XCTAssertEqual(model.snapshot.session?.profileID, second.id)
        // The new profile's session is in its initial connecting
        // placeholder, NOT inheriting the old profile's reconnect
        // state.
        if case .reconnecting = model.snapshot.session?.state {
            XCTFail("New profile session must not be reconnecting.")
        }
    }

    // MARK: - Exhaustion + safe-catalog diagnostic

    func testExhaustionProducesSafeCatalogDiagnosticFailure() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = FlakyStreamingConnector(width: 1, height: 1, name: "Desk")
        // Initial frame, then every reconnect fails immediately.
        connector.programFrame()
        connector.programFailure()
        connector.programFailure()
        connector.programFailure()
        connector.programFailure()

        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 6, frameInterval: 0),
            reconnectPolicy: Self.testPolicy,
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        // Wait long enough for the full retry budget to elapse.
        try await Task.sleep(for: .milliseconds(1200))

        // After exhausting the policy, the session is in a
        // terminal `.failed` state with the catalog HUD message.
        XCTAssertEqual(model.snapshot.session?.state, .failed)
        XCTAssertEqual(model.snapshot.session?.hudMessage, "Connection lost. Please reconnect.")

        // The diagnostic run carries a safe-catalog failure — NOT a
        // raw error string.  See `NaruRemoteAppModel.handleStreamFailure`.
        let firstFailed = try XCTUnwrap(model.snapshot.diagnosticRun?.firstFailedStage)
        XCTAssertEqual(firstFailed.safeTitle, "Connection lost")
        XCTAssertEqual(firstFailed.safeDetail, "The remote frame stream stopped responding.")
        XCTAssertEqual(firstFailed.nextAction, "Check the remote computer and reconnect.")

        // Constitution §IV: the diagnostic export must remain
        // opaque after the reconnect cycle.  The share text is
        // built from `DiagnosticExportSafeDetailCatalog` only —
        // never the raw model error text — so the rendering must
        // contain the catalog stage label and must NOT leak the
        // hostname, the policy timing, or any composed text.
        let export = model.makeDiagnosticExport()
        let rendered = export.renderShareText(buildVersion: nil)
        XCTAssertFalse(rendered.contains("desk.tailnet.ts.net"), "Export must not leak hostnames.")
        // The catalog detail for a firstFrame stage failure.
        XCTAssertTrue(
            rendered.contains("Remote frame receive stage."),
            "Export must include the safe-catalog stage description; got: \(rendered)"
        )
        // Defensive: no raw error type names from the fake.
        XCTAssertFalse(rendered.contains("FlakyConnectorError"))
        XCTAssertFalse(rendered.contains("programmedFailure"))
    }
}

// MARK: - Helpers

/// Recording streaming connector that lets tests interleave
/// frames and failures in the order the model will request them.
/// Each `programFrame()` queues one successful framebuffer; each
/// `programFailure()` queues one throw on the next
/// `requestRawFramebufferUpdate` call.
private final class FlakyStreamingConnector: RFBStreamingClient {
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
        var recordedClipboardPayloads: [String] = []
        var recordedPasteCommands: [PasteCommand] = []
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

    var recordedCredentials: [RFBConnectionCredential] {
        recording.withLock { $0.recordedCredentialsList }
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
                throw FlakyConnectorError.programmedFailure
            case .none:
                // Out of programmed steps: repeat the last delivered
                // frame so a stream that has drained its scripted
                // failures keeps quietly streaming.  Tests assert on
                // the count of `sessionRequests` and on
                // `session.state` to verify reconnect behavior.  If no
                // frame was ever delivered, throw so the test does not
                // silently spin.
                guard let lastFramebuffer = state.lastDeliveredFramebuffer else {
                    throw FlakyConnectorError.programmedFailure
                }
                return lastFramebuffer
            }
        }
    }

    func setClipboardText(_ text: String) throws {
        recording.withLock { state in
            state.recordedClipboardPayloads.append(text)
        }
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        recording.withLock { state in
            state.recordedPasteCommands.append(command)
        }
    }

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        // Pointer events are out of scope for reconnect tests.
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        // Key events are out of scope for reconnect tests.
    }
}

private enum FlakyConnectorError: Error {
    case programmedFailure
}
