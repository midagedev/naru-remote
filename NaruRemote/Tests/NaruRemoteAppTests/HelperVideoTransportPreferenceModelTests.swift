import CoreGraphics
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 042 FR-006 (Round D): the per-profile screen-source pin.
/// `.vncOnly` is a user choice, not a failure — connecting such a profile
/// must stay on the VNC framebuffer transport, never start helper video,
/// record no bootstrap state, and show no fallback notice.
///
/// ## Contract ↔ assertion table
///
/// | Contract | Assertion |
/// |----------|-----------|
/// | A `.vncOnly` profile's connect keeps the visual transport on VNC. |
///   `testVncOnlyProfileConnectsOnVNCAndNeverStartsHelperVideo` — after
///   connect + first frame: `visualTransportMode == .vncFramebuffer`. |
/// | The pin is a choice, not a failure: no fallback notice, no recorded
///   profile state mutation. |
///   Same test — `helperVideoFallbackNotice == nil`,
///   `snapshot.helperVideoProfileState[id]` unchanged (nil → nil; the
///   private `helperVideoState(for:)` derives from the profile when
///   nothing is stored, so its availability is unchanged with it). |
/// | The helper start closure is never invoked for a `.vncOnly` profile. |
///   Same test — `startCounter.count == 0`. |
/// | `.automatic` keeps the pre-042 behaviour — the control that earns the
///   zero above. |
///   `testAutomaticProfileStillStartsHelperVideo` — start closure invoked,
///   transport `== .helperVideo` once healthy. |
@MainActor
final class HelperVideoTransportPreferenceModelTests: XCTestCase {

    private let helperVideoSecretRef = "helper-video-token:desk"
    private let pairingFingerprint = "sha256:helper-video"

    // MARK: - .vncOnly

    func testVncOnlyProfileConnectsOnVNCAndNeverStartsHelperVideo() async throws {
        let startCounter = StartInvocationCounter()
        let profileID = UUID()
        let model = Self.makeModel(
            profileID: profileID,
            transportPreference: .vncOnly,
            startCounter: startCounter
        )
        defer {
            model.disconnect()
        }

        // No stored profile state before the connect.
        XCTAssertNil(model.snapshot.helperVideoProfileState[profileID])

        await model.connectSelectedProfile()
        try await waitUntil {
            model.snapshot.latestFramebuffer != nil
        }

        XCTAssertEqual(
            model.snapshot.visualTransportMode,
            .vncFramebuffer,
            "A .vncOnly profile must stay on the VNC visual transport."
        )
        XCTAssertNil(
            model.snapshot.helperVideoFallbackNotice,
            "Being on VNC is the .vncOnly user's choice, not a fallback."
        )
        // No bootstrap-state mutation: nothing was stored for the profile,
        // so the derived availability is exactly what it was before.
        XCTAssertNil(model.snapshot.helperVideoProfileState[profileID])
        XCTAssertEqual(
            startCounter.count,
            0,
            "The helper-video start closure must never run for a .vncOnly profile."
        )
    }

    // MARK: - .automatic control

    func testAutomaticProfileStillStartsHelperVideo() async throws {
        let startCounter = StartInvocationCounter()
        let profileID = UUID()
        let model = Self.makeModel(
            profileID: profileID,
            transportPreference: .automatic,
            startCounter: startCounter
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        try await waitUntil {
            model.snapshot.helperVideoStreamHealth.state == .healthy
        }

        XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
        XCTAssertGreaterThanOrEqual(startCounter.count, 1)
    }

    // MARK: - Fixtures

    private static func makeModel(
        profileID: UUID,
        transportPreference: HelperVideoTransportPreference,
        startCounter: StartInvocationCounter
    ) -> NaruRemoteAppModel {
        let profile = try! ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: "helper-video-token:desk",
                pairingFingerprint: "sha256:helper-video",
                transportPreference: transportPreference
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
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 3, frameInterval: 0),
            streamConnectorFactory: { _, _ in
                ImmediateStreamingConnector(
                    width: 3024,
                    height: 1964,
                    framebuffer: RFBRawFramebuffer(
                        width: 3024,
                        height: 1964,
                        fill: RFBColor(red: 10, green: 20, blue: 30)
                    )
                )
            },
            helperVideoStartStream: { _, _, _, _, _ in
                startCounter.record()
                return startResult(
                    accessUnits: [
                        accessUnit(sequence: 0, kind: .parameterSet),
                        accessUnit(sequence: 1, kind: .keyframe)
                    ]
                )
            },
            helperVideoRendererFactory: {
                TransportFakeHelperVideoRenderer(displayableSequences: [1])
            }
        )
    }

    private nonisolated static func startResult(
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoStartStreamResponseBody(
                    result: .accepted,
                    streamDescriptor: HelperVideoStreamDescriptor()
                )
            ),
            accessUnits: accessUnits
        )
    }

    private nonisolated static func accessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: "sha256:helper-video",
                body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
            ),
            binaryPayload: Data([0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21])
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

/// Thread-safe invocation counter for the `@Sendable` start closure.
private final class StartInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    var count: Int {
        lock.withLock { invocations }
    }

    func record() {
        lock.withLock { invocations += 1 }
    }
}

/// Minimal `HelperVideoAccessUnitRendering` fake (mirrors the gate file's
/// `GestureFakeHelperVideoRenderer`, which is `private` to its file).
private final class TransportFakeHelperVideoRenderer: HelperVideoAccessUnitRendering {
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

/// Immediate (ungated) `RFBStreamingClient` for the VNC path — mirrors the
/// gate file's `GatedStreamingConnector` with no gate.
private final class ImmediateStreamingConnector: RFBStreamingClient {
    private let width: Int
    private let height: Int
    private let framebuffer: RFBRawFramebuffer

    init(width: Int, height: Int, framebuffer: RFBRawFramebuffer) {
        self.width = width
        self.height = height
        self.framebuffer = framebuffer
    }

    var state: RFBClientState {
        .receivingFrames
    }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
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
