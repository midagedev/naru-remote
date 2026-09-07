import CoreGraphics
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 042 FR-007 (phone side, Round D): the helper-video start request
/// carries the phone's pointer mode, and a mid-session pointer-mode toggle
/// restarts the helper stream so the new request carries the new mode
/// (research §R1: no wire message for a live switch — `updateConfiguration`
/// is unverified — so the restart through the start path is the delivery
/// mechanism).
///
/// ## Contract ↔ assertion table
///
/// | Contract | Assertion |
/// |----------|-----------|
/// | The start request body carries the phone's pointer mode; the
///   product default is `.trackpad`. |
///   `testToggleRestartsHelperStreamWithNewPointerMode` — first recorded
///   request body has `pointerMode == .trackpad`. |
/// | A toggle during a healthy helper-video primary session restarts the
///   stream with the OTHER mode. |
///   Same test — after `togglePointerControlMode()` a second request body
///   is recorded with `pointerMode == .directTouch`, and the stream goes
///   healthy again as helper-video primary. |
/// | The restart is a user choice, not a failure: no fallback notice at
///   any point, no fallback-bucket bump. |
///   Same test — `helperVideoFallbackNotice == nil` before / immediately
///   after the toggle / after the restart; `fallbackCountBucket` `.none`
///   before and after. |
/// | The open event stream stays open until cancelled, which is what
///   keeps the stream task alive between the initial healthy state and
///   the toggle (the production shape — a live stream does not end after
///   its first keyframe). |
///   `NeverFinishingOpenStreamRecorder` yields the start response and
///   access units but never finishes the continuation. |
@MainActor
final class HelperVideoPointerModeStartRequestTests: XCTestCase {

    private let helperVideoSecretRef = "helper-video-token:desk"
    private let pairingFingerprint = "sha256:helper-video"

    func testToggleRestartsHelperStreamWithNewPointerMode() async throws {
        let recorder = NeverFinishingOpenStreamRecorder()
        let model = Self.makeModel(recorder: recorder)
        defer {
            model.disconnect()
        }

        // Product default: trackpad (PointerControlMode.productDefault).
        await model.connectSelectedProfile()
        try await waitUntil {
            model.snapshot.helperVideoStreamHealth.state == .healthy
                && model.snapshot.visualTransportMode == .helperVideo
        }
        XCTAssertEqual(recorder.requestBodies.map(\.pointerMode), [.trackpad])
        XCTAssertNil(model.snapshot.helperVideoFallbackNotice)
        XCTAssertEqual(model.snapshot.helperVideoStreamHealth.fallbackCountBucket, .none)

        // Trackpad → direct touch: the running stream restarts so the new
        // start request tells the helper the new mode (research §R1).
        model.togglePointerControlMode()
        XCTAssertEqual(model.pointerControlMode, .directTouch)
        // Immediately after the toggle: no notice armed by the stop half.
        XCTAssertNil(model.snapshot.helperVideoFallbackNotice)

        try await waitUntil {
            recorder.requestBodies.count >= 2
        }
        XCTAssertEqual(
            recorder.requestBodies.map(\.pointerMode),
            [.trackpad, .directTouch],
            "The restart must send a second start request carrying the new pointer mode."
        )

        // The restarted stream is healthy primary again, and the restart
        // recorded no failure anywhere: no notice, no fallback bucket.
        try await waitUntil {
            model.snapshot.helperVideoStreamHealth.state == .healthy
                && model.snapshot.visualTransportMode == .helperVideo
        }
        XCTAssertNil(model.snapshot.helperVideoFallbackNotice)
        XCTAssertEqual(model.snapshot.helperVideoStreamHealth.fallbackCountBucket, .none)
    }

    // MARK: - Fixtures

    private static func makeModel(
        recorder: NeverFinishingOpenStreamRecorder
    ) -> NaruRemoteAppModel {
        let profile = try! ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video"
            )
        )
        return NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: ["helper-video-token:desk": "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            streamConnectorFactory: { _, _ in
                ImmediateConnector(
                    framebuffer: RFBRawFramebuffer(
                        width: 2,
                        height: 1,
                        fill: RFBColor(red: 10, green: 20, blue: 30)
                    )
                )
            },
            helperVideoOpenStream: { _, _, pairingFingerprint, requestBody in
                recorder.open(
                    pairingFingerprint: pairingFingerprint,
                    requestBody: requestBody
                )
            },
            helperVideoRendererFactory: {
                PointerModeFakeHelperVideoRenderer(displayableSequences: [1])
            }
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<120 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition.", file: file, line: line)
    }
}

/// Records every start request body and returns an event stream that
/// delivers an accepted start response plus a displayable keyframe, then
/// stays open — the production shape (a live stream keeps running after
/// its first frame), and what keeps the helper stream task alive until a
/// cancel (the restart) ends it.
private final class NeverFinishingOpenStreamRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [HelperVideoStartStreamRequestBody] = []

    var requestBodies: [HelperVideoStartStreamRequestBody] {
        lock.withLock { bodies }
    }

    func open(
        pairingFingerprint: String,
        requestBody: HelperVideoStartStreamRequestBody
    ) -> HelperVideoStreamNetworkEvents {
        lock.withLock { bodies.append(requestBody) }
        return HelperVideoStreamNetworkEvents { continuation in
            continuation.yield(.startResponse(
                HelperVideoWireEnvelope(
                    messageType: .startStream,
                    profileFingerprint: pairingFingerprint,
                    body: HelperVideoStartStreamResponseBody(
                        result: .accepted,
                        streamDescriptor: HelperVideoStreamDescriptor()
                    )
                )
            ))
            continuation.yield(.accessUnit(
                HelperVideoDecodedFrame(
                    envelope: HelperVideoWireEnvelope(
                        messageType: .videoAccessUnit,
                        profileFingerprint: pairingFingerprint,
                        body: HelperVideoAccessUnitBody(sequence: 1, kind: .keyframe)
                    ),
                    binaryPayload: Data([0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21])
                )
            ))
            // Deliberately no `finish()`: the stream stays open until the
            // task running it is cancelled.
        }
    }
}

/// Minimal `HelperVideoAccessUnitRendering` fake (mirrors the gate file's
/// `GestureFakeHelperVideoRenderer`, which is `private` to its file).
private final class PointerModeFakeHelperVideoRenderer: HelperVideoAccessUnitRendering {
    private let displayableSequences: Set<Int>

    init(displayableSequences: Set<Int>) {
        self.displayableSequences = displayableSequences
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        displayableSequences.contains(decoded.envelope.body.sequence)
    }

    func flush() async {}

    func cachedFormatDimensions() async -> RemoteFramebufferCoordinateSpace? {
        nil
    }
}

/// Immediate (ungated) `RFBStreamingClient` for the VNC connect.
private final class ImmediateConnector: RFBStreamingClient {
    private let framebuffer: RFBRawFramebuffer

    init(framebuffer: RFBRawFramebuffer) {
        self.framebuffer = framebuffer
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: framebuffer.width, height: framebuffer.height)
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
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
        RFBServerInit(
            width: framebuffer.width,
            height: framebuffer.height,
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

    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer {
        framebuffer
    }

    func setClipboardText(_ text: String) throws {}

    func sendPasteCommand(_ command: PasteCommand) throws {}

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {}

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {}
}
