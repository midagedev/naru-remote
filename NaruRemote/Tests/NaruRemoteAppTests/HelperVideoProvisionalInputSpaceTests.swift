import NaruRemoteCore
@testable import NaruRemoteApp
import XCTest

/// Spec 042 FR-009 (Round D): the provisional input coordinate space and the
/// hero-mode gesture surface for the helper-video preview.
///
/// | Contract | Assertion |
/// |----------|-----------|
/// | While helper video is healthy primary and the RFB handshake is still
///   pending, the model adopts the decoder's cached format dimensions as a
///   *provisional* input coordinate space so the viewport has a gesture
///   surface over a playing video (§R2 cause 2). |
///   `testServerInitReplacesProvisionalSpaceAndRescalesTrackpadCursor` —
///   while the connect is gated: `inputCoordinateSpace == 960×624` and the
///   trackpad cursor is centered in it (480, 312). |
/// | When `ServerInit` lands it *replaces* the provisional space, and the
///   visible trackpad cursor is rescaled proportionally (960×624 → 3024×1964
///   maps (480, 312) → (1512, 982)), published once, then left alone — a
///   later resize must never teleport a user-positioned cursor. |
///   Same test — after the gate releases: space 3024×1964, cursor
///   (1512, 982) ± 1 px, and unchanged after a settle window. |
/// | The pure rescale mapping rounds and clamps into the new bounds. |
///   `testRescaledTrackpadCursorPositionMapsProportionally` — the spec
///   vectors plus an out-of-bounds clamp case. |
/// | The helper/PiP sample-buffer preview's gesture surface follows the
///   caller's frame, not the aspect-fit band (§R2 cause 1: the unconditional
///   `.aspectRatio(…, .fit)` shrank the layer and its hot input overlay in
///   hero mode). |
///   `testHelperPreviewGestureSurfaceFillsContainerInHeroMode` —
///   `helperPreviewGestureSurfaceSize(usesViewportFrame: true)` == container
///   size; `false` == `aspectFitSize` (the pre-042 band). |
@MainActor
final class HelperVideoProvisionalInputSpaceTests: XCTestCase {

    private let helperVideoSecretRef = "helper-video-token:desk"
    private let pairingFingerprint = "sha256:helper-video"

    // MARK: - Provisional space → ServerInit handoff

    func testServerInitReplacesProvisionalSpaceAndRescalesTrackpadCursor() async throws {
        let connectGate = GatedConnectConnector.ConnectGate()
        let connector = GatedConnectConnector(
            width: 3024,
            height: 1964,
            framebuffer: RFBRawFramebuffer(
                width: 3024,
                height: 1964,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            connectGate: connectGate
        )
        let model = Self.makeModel(
            connector: connector,
            renderer: ProvisionedFakeHelperVideoRenderer(
                displayableSequences: [1],
                formatWidth: 960,
                formatHeight: 624
            )
        )
        defer {
            connectGate.release()
            model.disconnect()
        }

        await model.connectSelectedProfile()
        try await waitUntil {
            model.snapshot.helperVideoStreamHealth.state == .healthy
        }
        XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)

        // Provisional window: the handshake is still gated, so the model has
        // the decoder's geometry standing in for `ServerInit`.
        XCTAssertTrue(
            connectGate.hasEntered,
            "The RFB connect must still be pending for the provisional window to be the state under test."
        )
        XCTAssertEqual(model.snapshot.inputCoordinateSpace?.width, 960)
        XCTAssertEqual(model.snapshot.inputCoordinateSpace?.height, 624)
        // Trackpad is the default pointer mode, so the cursor was centered in
        // the provisional space the moment it was adopted.
        XCTAssertEqual(model.trackpadCursor.position.x, 480, accuracy: 1)
        XCTAssertEqual(model.trackpadCursor.position.y, 312, accuracy: 1)
        XCTAssertTrue(model.trackpadCursor.isVisible)

        // ServerInit lands with the real display geometry.
        connectGate.release()
        try await waitUntil {
            model.snapshot.inputCoordinateSpace?.width == 3024
        }
        XCTAssertEqual(model.snapshot.inputCoordinateSpace?.height, 1964)
        // Proportional rescale: (480, 312) × (3024/960, 1964/624) = (1512, 982).
        XCTAssertEqual(model.trackpadCursor.position.x, 1512, accuracy: 1)
        XCTAssertEqual(model.trackpadCursor.position.y, 982, accuracy: 1)

        // Published once: after a settle window the cursor must not have been
        // moved again (no second rescale, no recentering teleport).
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.trackpadCursor.position.x, 1512, accuracy: 1)
        XCTAssertEqual(model.trackpadCursor.position.y, 982, accuracy: 1)
    }

    // MARK: - Pure rescale mapping

    func testRescaledTrackpadCursorPositionMapsProportionally() {
        let provisional = RemoteFramebufferCoordinateSpace(width: 960, height: 624)!
        let serverInit = RemoteFramebufferCoordinateSpace(width: 3024, height: 1964)!

        let rescaled = NaruRemoteAppModel.rescaledTrackpadCursorPosition(
            CGPoint(x: 480, y: 312),
            from: provisional,
            to: serverInit
        )
        XCTAssertEqual(rescaled.x, 1512, accuracy: 1)
        XCTAssertEqual(rescaled.y, 982, accuracy: 1)

        // The origin maps to itself; the far provisional corner maps
        // proportionally (959 × 3024/960 = 3020.85 → 3021 — the scale is
        // not 1:1, so the last provisional pixel is not the last real one).
        let origin = NaruRemoteAppModel.rescaledTrackpadCursorPosition(
            .zero,
            from: provisional,
            to: serverInit
        )
        XCTAssertEqual(origin, .zero)
        let farCorner = NaruRemoteAppModel.rescaledTrackpadCursorPosition(
            CGPoint(x: 959, y: 623),
            from: provisional,
            to: serverInit
        )
        XCTAssertEqual(farCorner.x, 3021, accuracy: 1)
        XCTAssertEqual(farCorner.y, 1961, accuracy: 1)

        // Degenerate input clamps into the new bounds instead of escaping.
        let clamped = NaruRemoteAppModel.rescaledTrackpadCursorPosition(
            CGPoint(x: 5000, y: -40),
            from: provisional,
            to: serverInit
        )
        XCTAssertEqual(clamped.x, 3023)
        XCTAssertEqual(clamped.y, 0)
    }

    // MARK: - Hero-mode gesture surface geometry

    func testHelperPreviewGestureSurfaceFillsContainerInHeroMode() {
        // Founder geometry (research.md §R2): iPhone 15 Pro Max hero container
        // with the 3024×1964 desktop aspect.
        let heroContainer = CGSize(width: 430, height: 812)
        let aspectRatio = CGFloat(3024) / CGFloat(1964)

        // Hero mode: the caller frames the preview to the container, and the
        // gesture surface must cover it — the layer letterboxes its video
        // internally, so pinching anywhere over the video works.
        XCTAssertEqual(
            SessionViewportView.helperPreviewGestureSurfaceSize(
                usesViewportFrame: true,
                aspectRatio: aspectRatio,
                containerSize: heroContainer
            ),
            heroContainer
        )

        // Non-hero (and the pinned PiP call site): the surface is the
        // aspect-fit band, unchanged from pre-042 geometry.
        XCTAssertEqual(
            SessionViewportView.helperPreviewGestureSurfaceSize(
                usesViewportFrame: false,
                aspectRatio: aspectRatio,
                containerSize: heroContainer
            ),
            SessionViewportView.aspectFitSize(aspectRatio: aspectRatio, containerSize: heroContainer)
        )
        // The band is genuinely smaller than the container (the defect's
        // magnitude, ~2.9x hit area — matches the §R2 evidence test).
        let band = SessionViewportView.aspectFitSize(
            aspectRatio: aspectRatio,
            containerSize: heroContainer
        )
        XCTAssertLessThan(band.height, heroContainer.height)
    }

    // MARK: - Fixtures

    private static func makeModel(
        connector: GatedConnectConnector,
        renderer: ProvisionedFakeHelperVideoRenderer
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
            // maxFrames 0: the connect (ServerInit) happens, then the pump
            // exits before delivering frames — the handoff under test is the
            // space/cursor exchange, not frame compositing.
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 0, frameInterval: 0),
            streamConnectorFactory: { _, _ in connector },
            helperVideoStartStream: { _, _, _, _, _ in
                Self.startResult(
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe)
                    ]
                )
            },
            helperVideoRendererFactory: { renderer }
        )
    }

    private nonisolated static func startResult(
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
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

/// Renderer fake reporting explicit decoded-format dimensions (spec 042
/// FR-009). Mirrors the gate file's `GestureFakeHelperVideoRenderer`, which
/// is `private` to that file.
private final class ProvisionedFakeHelperVideoRenderer: HelperVideoAccessUnitRendering {
    private let displayableSequences: Set<Int>
    private let formatWidth: Int
    private let formatHeight: Int

    init(displayableSequences: Set<Int>, formatWidth: Int, formatHeight: Int) {
        self.displayableSequences = displayableSequences
        self.formatWidth = formatWidth
        self.formatHeight = formatHeight
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        displayableSequences.contains(decoded.envelope.body.sequence)
    }

    func flush() async {}

    func cachedFormatDimensions() async -> RemoteFramebufferCoordinateSpace? {
        RemoteFramebufferCoordinateSpace(width: formatWidth, height: formatHeight)
    }
}

/// Minimal gated `RFBStreamingClient` mirroring the gate file's
/// `GatedStreamingConnector` (also `private` to its file). Holds the RFB
/// handshake pending while helper video goes healthy.
private final class GatedConnectConnector: RFBStreamingClient {
    final class ConnectGate: @unchecked Sendable {
        private let lock = NSLock()
        private let releaseSemaphore = DispatchSemaphore(value: 0)
        private var entered = false
        private var released = false

        var hasEntered: Bool {
            lock.withLock { entered }
        }

        func waitWhileClosed() {
            let shouldWait = lock.withLock {
                entered = true
                return !released
            }
            if shouldWait {
                releaseSemaphore.wait()
            }
        }

        func release() {
            let shouldSignal = lock.withLock {
                guard !released else {
                    return false
                }
                released = true
                return true
            }
            if shouldSignal {
                releaseSemaphore.signal()
            }
        }
    }

    private let width: Int
    private let height: Int
    private let framebuffer: RFBRawFramebuffer
    private let connectGate: ConnectGate?

    init(
        width: Int,
        height: Int,
        framebuffer: RFBRawFramebuffer,
        connectGate: ConnectGate?
    ) {
        self.width = width
        self.height = height
        self.framebuffer = framebuffer
        self.connectGate = connectGate
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
        connectGate?.waitWhileClosed()
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
