import Foundation
import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 011 — simplified input UX, app-model surface:
///
/// - Type (type-through) is promoted to the default dock mode the first
///   time a fresh session reaches `.active` (US1, founder D3).
/// - The promotion is one-shot per session and never overrides an explicit
///   user mode choice.
/// - Accessory strip keys (US2) emit through the shared `KeystrokeEmitter`
///   path and wrap armed sticky modifiers exactly like the retired Direct
///   soft keyboard (⌃ arm + key → `Ctrl down → key down → key up → Ctrl up`).
@MainActor
final class SimplifiedInputUxModelTests: XCTestCase {

    private var connector: SimplifiedInputConnector!

    override func setUp() {
        super.setUp()
        connector = SimplifiedInputConnector(width: 80, height: 60, name: "Desk")
    }

    // MARK: - US1 — Type default on session activation

    func testFreshSessionActivationPromotesTypeModeOnce() async throws {
        let model = try await makeConnectedModel(connector: connector)
        XCTAssertEqual(
            model.remoteInputDockMode,
            .live,
            "A fresh active session must start in Type (type-through) mode (spec 011 US1)."
        )

        // User opts back to Compose; further frames must not flip it again
        // (the promotion is one-shot per session).
        model.setRemoteInputDockMode(.compose)
        XCTAssertEqual(model.remoteInputDockMode, .compose)
        connector.programExtraFrame()
        try await waitFor { model.snapshot.session?.hasReceivedFrame == true }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(
            model.remoteInputDockMode,
            .compose,
            "Post-activation frames must never override the user's mode choice."
        )
    }

    func testExplicitPreActivationChoiceSuppressesTypeDefault() async throws {
        let connector: SimplifiedInputConnector = self.connector
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        // The user picks Compose BEFORE the first frame lands.
        model.setRemoteInputDockMode(.compose)
        await model.connectSelectedProfile()
        try await waitFor { model.snapshot.session?.state == .active }

        XCTAssertEqual(
            model.remoteInputDockMode,
            .compose,
            "An explicit user choice must suppress the Type default promotion."
        )
    }

    // MARK: - US2 — accessory strip emission

    func testAccessoryKeyEmitsKeysymAndConsumesArmedStickyModifier() async throws {
        let model = try await makeConnectedModel(connector: connector)

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .armed,
            "Strip modifier tap must arm Control."
        )

        await model.sendAccessoryKey(.escape)
        try await waitFor {
            connector.recordedKeyEvents.map(\.keysym).contains(KeysymMapping.keysym(for: .escape))
        }

        let escapeEvents = connector.recordedKeyEvents.filter {
            $0.keysym == KeysymMapping.keysym(for: .escape)
        }
        XCTAssertEqual(escapeEvents.map(\.isDown), [true, false])

        // The wire envelope wraps the armed modifier: Ctrl down before the
        // key, Ctrl up after (byte-identical to the retired Direct path).
        let controlEvents = connector.recordedKeyEvents.filter {
            $0.keysym == KeysymMapping.keysym(for: .controlLeft)
        }
        XCTAssertEqual(
            controlEvents.map(\.isDown),
            [true, false],
            "Armed Ctrl must wrap the strip emission."
        )
        if let controlDown = controlEvents.first(where: { $0.isDown }),
           let escapeDown = escapeEvents.first(where: { $0.isDown }) {
            XCTAssertLessThan(
                connector.indexOfKeyEvent(controlDown),
                connector.indexOfKeyEvent(escapeDown),
                "Ctrl down must precede the key down."
            )
        }

        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .idle,
            "Armed modifiers must release after a non-modifier strip emission."
        )
    }

    func testLockedStickyModifierSurvivesStripEmission() async throws {
        let model = try await makeConnectedModel(connector: connector)

        // Double-tap inside the 400 ms window → locked.
        await model.tapDirectKey(.modifier(.shift))
        await model.tapDirectKey(.modifier(.shift))
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .locked)

        await model.sendAccessoryKey(.tab)
        try await waitFor {
            connector.recordedKeyEvents.map(\.keysym).contains(KeysymMapping.keysym(for: .tab))
        }

        XCTAssertEqual(
            model.stickyModifierState.slot(for: .shift),
            .locked,
            "Locked modifiers persist across strip emissions."
        )
    }

    func testAccessoryKeyDropsSilentlyWithoutActiveSession() async throws {
        let connector: SimplifiedInputConnector = self.connector
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.sendAccessoryKey(.escape)
        XCTAssertTrue(
            connector.recordedKeyEvents.isEmpty,
            "Strip keys must not emit without an active session."
        )
    }

    // MARK: - Spec 015 — accessory panel state

    /// FR-004. The flag lives on the model, not in the dock view, because the
    /// compose-reveal placement swap recreates that view mid-session — view
    /// `@State` would collapse the panel under the user's finger. The model is
    /// also where "collapsed for each new session" can be true without
    /// persisting anything to disk.
    func testAccessoryPanelStartsCollapsedAndTogglesFromTheModel() async throws {
        let model = try await makeConnectedModel(connector: connector)

        XCTAssertFalse(
            model.isRemoteInputAccessoryPanelExpanded,
            "The founder asked for the special keys hidden by default — one row above the keyboard."
        )
        XCTAssertFalse(
            model.snapshot.isRemoteInputAccessoryPanelExpanded,
            "The dock renders off the snapshot, so the flag has to reach it there."
        )

        model.setRemoteInputAccessoryPanelExpanded(true)
        XCTAssertTrue(model.snapshot.isRemoteInputAccessoryPanelExpanded)

        // Idempotent: re-asserting the same state is not a toggle. The
        // prelock hook taught this lesson once already — a hook that
        // re-applied its input walked the sticky modifier past `locked`.
        model.setRemoteInputAccessoryPanelExpanded(true)
        XCTAssertTrue(model.snapshot.isRemoteInputAccessoryPanelExpanded)

        model.setRemoteInputAccessoryPanelExpanded(false)
        XCTAssertFalse(model.snapshot.isRemoteInputAccessoryPanelExpanded)
    }

    /// FR-004's other half: a new session starts collapsed, so the row the
    /// user meets when they connect is one row.
    func testAccessoryPanelCollapsesWhenTheSessionRestarts() async throws {
        let model = try await makeConnectedModel(connector: connector)
        model.setRemoteInputAccessoryPanelExpanded(true)
        XCTAssertTrue(model.isRemoteInputAccessoryPanelExpanded)

        model.disconnect()
        XCTAssertFalse(
            model.isRemoteInputAccessoryPanelExpanded,
            "Session teardown resets the panel with the rest of the per-session Live state."
        )
    }

    // MARK: - Helpers

    private func makeConnectedModel(
        connector: SimplifiedInputConnector
    ) async throws -> NaruRemoteAppModel {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )
        await model.connectSelectedProfile()
        try await waitFor { model.snapshot.session?.state == .active }
        return model
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }
}

/// Minimal polling fake mirroring the routing-test connector surface:
/// serves frames on request and records wire key events in order so tests
/// can assert modifier wrapping.
private final class SimplifiedInputConnector: RFBStreamingClient, @unchecked Sendable {
    private struct Recording {
        var keyEvents: [(keysym: UInt32, isDown: Bool)] = []
        var framebuffers: [RFBRawFramebuffer]
        var requestedFrameCount = 0
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String

    init(width: Int, height: Int, name: String) {
        let framebuffer = RFBRawFramebuffer(
            width: width,
            height: height,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        self.width = width
        self.height = height
        self.name = name
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(framebuffers: [framebuffer, framebuffer, framebuffer])
        )
    }

    var recordedKeyEvents: [(keysym: UInt32, isDown: Bool)] {
        recording.withLock { $0.keyEvents }
    }

    func indexOfKeyEvent(_ event: (keysym: UInt32, isDown: Bool)) -> Int {
        recording.withLock { recording in
            recording.keyEvents.firstIndex {
                $0.keysym == event.keysym && $0.isDown == event.isDown
            } ?? -1
        }
    }

    /// Serve one more frame so a test can deliver post-activation activity.
    func programExtraFrame() {
        recording.withLock { state in
            state.framebuffers.append(
                RFBRawFramebuffer(
                    width: width,
                    height: height,
                    fill: RFBColor(red: 10, green: 20, blue: 30)
                )
            )
        }
    }

    var state: RFBClientState { .receivingFrames }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    func connectNoAuthFirstFrame(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(host: String, port: UInt16, credential: RFBConnectionCredential, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(host: String, port: UInt16, credential: RFBConnectionCredential, timeout: TimeInterval) throws -> RFBServerInit {
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
            name: name
        )
    }

    func requestRawFramebufferUpdate(incremental: Bool, timeout: TimeInterval) throws -> RFBRawFramebuffer {
        let framebuffer = recording.withLock { state -> RFBRawFramebuffer? in
            state.requestedFrameCount += 1
            return state.framebuffers.isEmpty ? nil : state.framebuffers.removeFirst()
        }
        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return framebuffer
    }

    func setClipboardText(_ text: String) throws {}

    func sendPasteCommand(_ command: PasteCommand) throws {}

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {}

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        recording.withLock { $0.keyEvents.append((keysym, isDown)) }
    }
}
