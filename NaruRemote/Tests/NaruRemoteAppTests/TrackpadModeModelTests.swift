import Foundation
import os
import XCTest
@testable import NaruRemoteApp
import NaruRemoteCore

/// Model-level coverage for the Google-Remote-Desktop-style trackpad
/// mode wiring (spec 003 Stage B, T014).  The pure decision logic lives
/// in `NaruRemoteCore` and is unit-tested there; these cases prove the
/// app model's published state + dispatch behaves: the product default,
/// the toggle's cursor centering/decentering, the disconnect reset, and
/// the no-session no-op.  Uses a local pointer-capturing streaming
/// connector so a trackpad click can be observed on the (fake) wire.
@MainActor
final class TrackpadModeModelTests: XCTestCase {
    private func makeModel(
        connector: TrackpadPointerCapturingConnector
    ) throws -> NaruRemoteAppModel {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        return NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )
    }

    private func connect(_ model: NaruRemoteAppModel) async throws {
        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(120))
    }

    func testDefaultPointerControlModeIsDirectTouch() {
        let model = NaruRemoteAppModel()
        XCTAssertEqual(model.pointerControlMode, .directTouch)
        XCTAssertEqual(model.pointerControlMode, .productDefault)
        XCTAssertFalse(model.trackpadCursor.isVisible)
    }

    func testToggleIntoTrackpadCentersAndShowsCursor() async throws {
        let connector = TrackpadPointerCapturingConnector(width: 200, height: 100)
        let model = try makeModel(connector: connector)
        try await connect(model)

        model.togglePointerControlMode()

        XCTAssertEqual(model.pointerControlMode, .trackpad)
        XCTAssertTrue(model.trackpadCursor.isVisible)
        // Centered on the live 200x100 framebuffer.
        XCTAssertEqual(model.trackpadCursor.position, CGPoint(x: 100, y: 50))
    }

    func testToggleBackToDirectTouchHidesCursor() async throws {
        let connector = TrackpadPointerCapturingConnector(width: 200, height: 100)
        let model = try makeModel(connector: connector)
        try await connect(model)

        model.togglePointerControlMode()
        XCTAssertTrue(model.trackpadCursor.isVisible)

        model.togglePointerControlMode()
        XCTAssertEqual(model.pointerControlMode, .directTouch)
        XCTAssertFalse(model.trackpadCursor.isVisible)
    }

    func testToggleWithoutFramebufferCentersOnDefaultSize() {
        // No connect → no framebuffer.  Toggle must not crash and must
        // still show a centered cursor on the default size.
        let model = NaruRemoteAppModel()
        model.togglePointerControlMode()
        XCTAssertEqual(model.pointerControlMode, .trackpad)
        XCTAssertTrue(model.trackpadCursor.isVisible)
    }

    func testDisconnectResetsPointerModeAndCursor() async throws {
        let connector = TrackpadPointerCapturingConnector(width: 200, height: 100)
        let model = try makeModel(connector: connector)
        try await connect(model)

        model.togglePointerControlMode()
        XCTAssertEqual(model.pointerControlMode, .trackpad)
        XCTAssertTrue(model.trackpadCursor.isVisible)

        model.disconnect()

        XCTAssertEqual(model.pointerControlMode, .directTouch)
        XCTAssertFalse(model.trackpadCursor.isVisible)
    }

    func testHandleTrackpadGestureWithNoSessionIsNoOp() {
        // No session / no framebuffer: dispatch must be a clean no-op.
        let model = NaruRemoteAppModel()
        let before = model.trackpadCursor

        model.handleTrackpadGesture(
            .tap(viewPoint: CGPoint(x: 10, y: 10)),
            viewSize: CGSize(width: 200, height: 100)
        )

        // Cursor unchanged, no crash, still hidden.
        XCTAssertEqual(model.trackpadCursor, before)
        XCTAssertFalse(model.trackpadCursor.isVisible)
    }

    func testTrackpadTapDispatchesClickAtCursor() async throws {
        let connector = TrackpadPointerCapturingConnector(width: 200, height: 100)
        let model = try makeModel(connector: connector)
        try await connect(model)

        model.togglePointerControlMode()
        // Cursor centered at (100, 50).  Tap clicks at the CURSOR, not
        // the touch point (003 FR-008).
        model.handleTrackpadGesture(
            .tap(viewPoint: CGPoint(x: 5, y: 5)),
            viewSize: CGSize(width: 200, height: 100)
        )
        try await waitForPointerEvents(connector, count: 2)

        let events = connector.recordedPointerEvents
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].mask, 0x01)
        XCTAssertEqual(events[0].x, 100)
        XCTAssertEqual(events[0].y, 50)
        XCTAssertEqual(events[1].mask, 0x00)
        XCTAssertEqual(events[1].x, 100)
        XCTAssertEqual(events[1].y, 50)
    }

    func testTrackpadDragMovesRemotePointerWithoutButtonPress() async throws {
        let connector = TrackpadPointerCapturingConnector(width: 200, height: 100)
        let model = try makeModel(connector: connector)
        try await connect(model)

        model.togglePointerControlMode()
        let start = model.trackpadCursor.position

        model.handleTrackpadGesture(
            .dragChanged(
                viewPoint: CGPoint(x: 120, y: 60),
                translation: CGSize(width: 20, height: 10)
            ),
            viewSize: CGSize(width: 200, height: 100)
        )
        try await waitForPointerEvents(connector, count: 1)

        XCTAssertNotEqual(model.trackpadCursor.position, start)
        let event = try XCTUnwrap(connector.recordedPointerEvents.first)
        XCTAssertEqual(event.mask, 0x00)
        XCTAssertEqual(event.x, 120)
        XCTAssertEqual(event.y, 60)
    }

    func testTrackpadDragUsesZoomedTransformAndReturnsAutoPan() async throws {
        let connector = TrackpadPointerCapturingConnector(width: 200, height: 100)
        let model = try makeModel(connector: connector)
        try await connect(model)

        model.togglePointerControlMode()
        let zoomed = ViewportTransform(
            framebufferSize: CGSize(width: 200, height: 100),
            viewSize: CGSize(width: 200, height: 100),
            zoomScale: 2,
            panOffset: .zero
        )

        let updated = try XCTUnwrap(
            model.handleTrackpadGesture(
                .dragChanged(
                    viewPoint: CGPoint(x: 190, y: 50),
                    translation: CGSize(width: 100, height: 0)
                ),
                transform: zoomed
            )
        )

        XCTAssertEqual(model.trackpadCursor.position.x, 150, accuracy: 1e-6)
        XCTAssertEqual(model.trackpadCursor.position.y, 50, accuracy: 1e-6)
        XCTAssertEqual(updated.zoomScale, 2, accuracy: 1e-6)
        XCTAssertEqual(updated.panOffset.width, -48, accuracy: 1e-6)
        XCTAssertEqual(updated.panOffset.height, 0, accuracy: 1e-6)
        try await waitForPointerEvents(connector, count: 1)
        let event = try XCTUnwrap(connector.recordedPointerEvents.first)
        XCTAssertEqual(event.mask, 0x00)
        XCTAssertEqual(event.x, 150)
        XCTAssertEqual(event.y, 50)
    }

    private func waitForPointerEvents(
        _ connector: TrackpadPointerCapturingConnector,
        count: Int,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connector.recordedPointerEvents.count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) pointer events; got \(connector.recordedPointerEvents.count)")
    }
}

/// Streaming-capable fake that records every `sendPointerEvent` call
/// for the trackpad-mode tests.  Mirrors the recorder used in
/// `PointerEventTapTests` but kept private to this file so the existing
/// suite stays structurally unchanged.
private final class TrackpadPointerCapturingConnector: RFBStreamingClient {
    private struct Recording {
        var framebuffers: [RFBRawFramebuffer]
        var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        let framebuffer = RFBRawFramebuffer(
            width: width,
            height: height,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(framebuffers: [framebuffer, framebuffer, framebuffer])
        )
    }

    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? { RFBFrameMetadata(width: width, height: height) }

    var recordedPointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] {
        recording.withLock { $0.recordedPointerEventsList }
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
            name: "Desk"
        )
    }

    func requestRawFramebufferUpdate(incremental: Bool, timeout: TimeInterval) throws -> RFBRawFramebuffer {
        let framebuffer = recording.withLock { state -> RFBRawFramebuffer? in
            state.framebuffers.isEmpty ? nil : state.framebuffers.removeFirst()
        }
        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return framebuffer
    }

    func setClipboardText(_ text: String) throws {}
    func sendPasteCommand(_ command: PasteCommand) throws {}

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        recording.withLock { state in
            state.recordedPointerEventsList.append((buttonMask, x, y))
        }
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {}
}
