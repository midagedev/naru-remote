import CoreGraphics
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 042, FR-009 (P5 behaviour parity): "Pinch, pan, double-tap zoom, and
/// trackpad gestures over the helper-video preview go through the same
/// `ViewportTransform` path as the Metal framebuffer view."
///
/// Founder report 2026-09-07 (iPhone 15 Pro Max, helper-video session,
/// trackpad mode): "줌인 같은 기본적인 제스쳐도 안되네" — pinch dead over the
/// helper-video preview while the same gesture works in VNC sessions.
///
/// ## Contract ↔ assertion table (FR-009 → tests)
///
/// | FR-009 clause | Test | Status this round |
/// |---|---|---|
/// | The preview branch that renders while helper video is primary must own a
///   gesture surface at all (pinch/pan/tap), including before the RFB
///   handshake delivers a framebuffer or coordinate space. |
///   `testHelperVideoPrimaryKeepsGestureCapablePreviewStateWhileRFBHandshakeIsPending`
///   asserts the model state the view branches on
///   (`latestFramebuffer`/`inputCoordinateSpace`) is never both `nil` while
///   `visualTransportMode == .helperVideo` and the stream is healthy. Today
///   both ARE nil in that window and `helperVideoLayerPreviewWithoutFramebuffer()`
///   (SessionViewportView.swift:2014) installs its input overlay only
///   `if let inputCoordinateSpace` (line 2023) — zero gesture surfaces. |
///   **FAILING — the deliverable; Round D turns it green.** |
/// | Once VNC frames flow, the helper-video session keeps the framebuffer the
///   hot input overlay needs (`sampleBufferLayerPreview` at
///   SessionViewportView.swift:1877 installs `MetalFramebufferInputOverlayView`
///   whose `UIPinchGestureRecognizer` reaches `applyZoomScale`). |
///   `testSteadyHelperVideoPrimarySessionKeepsFramebufferAndInputCoordinateSpace` |
///   Passing — pins the steady state Round D must not regress. |
/// | The device-shaped branch decision picks the Metal hot input overlay for a
///   helper-video session in BOTH pointer modes (the selector has no
///   pointer-mode input, so the gesture loss is not a pointer-mode gate). |
///   `testDeviceShapedHelperVideoSessionSelectsMetalHotInputOverlayInBothPointerModes` |
///   Passing — mirrors `SessionViewportViewGeometryTests`. |
/// | Geometry evidence for §R2: the unconditional
///   `.aspectRatio(…, .fit)` on the helper preview (SessionViewportView.swift:1933)
///   shrinks the display layer and its hot gesture overlay to the fit band in
///   the hero session (`fillsAvailableHeight: true`, NaruRemoteAppShell.swift:544),
///   unlike the Metal path which skips the aspect fit when filling
///   (SessionViewportView.swift:2181-2188). |
///   `testHeroContainerFitBandShrinksHelperPreviewGestureSurface` computes the
///   founder's band with the view's own `aspectFitSize`. |
///   Passing — documents the band; the layout fix is Round D's. |
///
/// The UIKit-level pinch wiring itself (`MetalFramebufferHostingView`
/// installs `UIPinchGestureRecognizer` unconditionally, MetalFramebufferView.swift:978-1025)
/// is shared with the working VNC path and is not unit-reachable from macOS
/// `swift test`; see §R2 in specs/042-vnc-first-helper-optional/research.md.

private let helperVideoSecretRef = "helper-video-token:desk"
private let pairingFingerprint = "sha256:helper-video"

@MainActor
final class HelperVideoPreviewGestureTests: XCTestCase {
    // MARK: FR-009 — the failing deliverable

    /// FR-009: while helper video is the primary visual transport with a
    /// healthy stream, the session viewport must render a gesture-capable
    /// preview. The view picks its preview branch from
    /// `frameState.framebuffer` (SessionViewportView.swift:676) and the
    /// no-framebuffer helper branch installs gestures only when
    /// `inputCoordinateSpace` is non-nil (line 2023). Helper video is
    /// selected before the RFB connect even starts
    /// (NaruRemoteAppModel.startHelperVideoStreamIfConfigured at
    /// NaruRemoteAppModel.swift:3838 runs before `startFrameStream`), so the
    /// both-nil window is reachable live UI state — and it is exactly the
    /// state in which pinch, pan, and tap are all dead over a playing video.
    func testHelperVideoPrimaryKeepsGestureCapablePreviewStateWhileRFBHandshakeIsPending() async throws {
        let connectGate = GatedStreamingConnector.ConnectGate()
        let connector = GatedStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            connectGate: connectGate
        )
        let model = Self.makeModel(
            connector: connector,
            renderer: Self.displayableKeyframeRenderer()
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
        // The RFB handshake is still gated, so no framebuffer can exist yet —
        // this is the state under test. (Round E-inv also asserted
        // `inputCoordinateSpace == nil` here as a precondition; Round D's fix
        // is precisely a provisional coordinate space in this window, so that
        // precondition contradicted the assertion below and was dropped by the
        // lead on 2026-09-07. The pending-connect gate is the precondition
        // that matters.)
        XCTAssertTrue(connectGate.hasEntered, "The RFB connect must still be pending for this state to be the one under test.")
        XCTAssertNil(model.snapshot.latestFramebuffer)

        // FR-009: a healthy helper-video-primary session must expose a
        // gesture-capable preview — at least one of the two inputs the
        // viewport needs to install an input surface (a framebuffer for
        // `sampleBufferLayerPreview` + hot overlay, or a coordinate space for
        // `helperVideoInputOverlay`). Both nil renders
        // `helperVideoLayerPreviewWithoutFramebuffer()` with no input overlay
        // at all: pinch, pan, double-tap, and trackpad gestures are dead.
        XCTAssertTrue(
            model.snapshot.latestFramebuffer != nil || model.snapshot.inputCoordinateSpace != nil,
            "FR-009 violated: helper video is the healthy primary visual transport but the session viewport has no gesture-capable preview state (latestFramebuffer == nil && inputCoordinateSpace == nil), so helperVideoLayerPreviewWithoutFramebuffer renders without any input overlay."
        )
    }

    // MARK: FR-009 — steady-state pins (passing)

    /// The founder's steady session (research: nettop showed helper video and
    /// screensharingd both streaming) has VNC frames flowing, so the viewport
    /// takes the framebuffer branch and `sampleBufferLayerPreview` installs
    /// the hot input overlay. Pin that the model keeps feeding that branch:
    /// helper-video primary must not stop the framebuffer/coordinate space
    /// from being available for the preview and its gestures.
    func testSteadyHelperVideoPrimarySessionKeepsFramebufferAndInputCoordinateSpace() async throws {
        let connector = GatedStreamingConnector(
            width: 2,
            height: 1,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 2,
                height: 1,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            connectGate: nil
        )
        let model = Self.makeModel(
            connector: connector,
            renderer: Self.displayableKeyframeRenderer()
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()
        try await waitUntil {
            model.snapshot.helperVideoStreamHealth.state == .healthy
        }
        XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
        try await waitUntil {
            model.snapshot.latestFramebuffer != nil
        }
        try await waitUntil {
            model.snapshot.inputCoordinateSpace != nil
        }
        XCTAssertEqual(model.snapshot.visualTransportMode, .helperVideo)
    }

    /// The branch decision for a device-shaped session (Metal supported, not
    /// PiP watching, helper video primary) selects the Metal hot input overlay
    /// in both pointer modes — the overlay that carries the shared
    /// `UIPinchGestureRecognizer` wiring. The gesture loss therefore cannot be
    /// a pointer-mode gate; Round D's fix belongs in the preview layout, not
    /// the selectors.
    func testDeviceShapedHelperVideoSessionSelectsMetalHotInputOverlayInBothPointerModes() {
        for pointerControlMode in PointerControlMode.allCases {
            XCTAssertTrue(
                SessionViewportView.usesMetalHotInputOverlay(
                    isPiPWatching: false,
                    usesHelperVideoPrimaryPreview: true,
                    metalFramebufferInputSupported: true
                ),
                "Pointer mode \(pointerControlMode) must not gate the hot input overlay."
            )
            XCTAssertFalse(
                SessionViewportView.usesSwiftUITrackpadInputOverlay(
                    isPiPWatching: false,
                    usesHelperVideoPrimaryPreview: true,
                    pointerControlMode: pointerControlMode,
                    metalFramebufferInputSupported: true
                )
            )
        }
        XCTAssertFalse(
            SessionViewportView.usesMetalHotInputOverlay(
                isPiPWatching: true,
                usesHelperVideoPrimaryPreview: true,
                metalFramebufferInputSupported: true
            ),
            "PiP watch is watch-only and must keep the input overlay off."
        )
    }

    /// Geometry evidence for §R2 (not a layout gate — the fix is Round D's):
    /// the helper preview applies `.aspectRatio(aspectRatio, .fit)`
    /// unconditionally, so in the hero session the display layer AND its hot
    /// gesture overlay shrink to this band while the Metal VNC preview fills
    /// the whole surface. Founder geometry: VNC ServerInit 3024×1964
    /// (research.md), iPhone 15 Pro Max hero container ~430×812 points.
    func testHeroContainerFitBandShrinksHelperPreviewGestureSurface() {
        let heroContainer = CGSize(width: 430, height: 812)
        let aspectRatio = CGFloat(3024) / CGFloat(1964)
        let band = SessionViewportView.aspectFitSize(
            aspectRatio: aspectRatio,
            containerSize: heroContainer
        )
        XCTAssertEqual(band.width, heroContainer.width, accuracy: 0.5)
        XCTAssertEqual(band.height, 279, accuracy: 1)
        // The VNC Metal path in hero mode proposes the full container to the
        // gesture surface (no aspect fit): ~2.9x the hit area.
        XCTAssertGreaterThan(
            heroContainer.width * heroContainer.height / (band.width * band.height),
            2.5
        )
    }

    // MARK: - Fixtures

    private static func makeModel(
        connector: GatedStreamingConnector,
        renderer: GestureFakeHelperVideoRenderer
    ) -> NaruRemoteAppModel {
        let profile = try! ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoSecretRef,
                pairingFingerprint: pairingFingerprint
            )
        )
        return NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [helperVideoSecretRef: "helper-video-secret"]
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 3, frameInterval: 0),
            streamConnectorFactory: { _, _ in connector },
            helperVideoStartStream: { _, _, _, _, _ in
                helperVideoStartResult(
                    accessUnits: [
                        helperVideoAccessUnit(sequence: 0, kind: .parameterSet),
                        helperVideoAccessUnit(sequence: 1, kind: .keyframe)
                    ]
                )
            },
            helperVideoRendererFactory: { renderer }
        )
    }

    private static func displayableKeyframeRenderer() -> GestureFakeHelperVideoRenderer {
        GestureFakeHelperVideoRenderer(displayableSequences: [1])
    }

    private nonisolated static func helperVideoStartResult(
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: pairingFingerprint,
                body: HelperVideoStartStreamResponseBody(
                    result: .accepted,
                    streamDescriptor: HelperVideoStreamDescriptor()
                )
            ),
            accessUnits: accessUnits
        )
    }

    private nonisolated static func helperVideoAccessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: pairingFingerprint,
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

/// Minimal `HelperVideoAccessUnitRendering` fake mirroring the file-private
/// `AppModelFakeHelperVideoRenderer` in NaruRemoteAppModelTests.swift (that
/// one is `private` to its file and cannot be imported).
private final class GestureFakeHelperVideoRenderer: HelperVideoAccessUnitRendering {
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

    /// Spec 042 FR-009: the geometry the production H264 renderer reports
    /// from its cached SPS format dimensions. 960×624 is the helper's
    /// encoded size for the founder's 3024×1964 display (research.md §R2),
    /// so the provisional coordinate space it stands up matches the real
    /// handoff the rescale test exercises.
    func cachedFormatDimensions() async -> RemoteFramebufferCoordinateSpace? {
        RemoteFramebufferCoordinateSpace(width: 960, height: 624)
    }
}

/// Minimal gated `RFBStreamingClient` mirroring the file-private
/// `FakeStreamingConnector` + `SynchronousConnectGate` in
/// NaruRemoteAppModelTests.swift (both `private` to that file). The gate lets
/// a test hold the RFB handshake pending while helper video goes healthy —
/// the connect order the production model really uses
/// (`startHelperVideoStreamIfConfigured` before `startFrameStream`).
private final class GatedStreamingConnector: RFBStreamingClient {
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
    private let name: String
    private let framebuffer: RFBRawFramebuffer
    private let connectGate: ConnectGate?

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffer: RFBRawFramebuffer,
        connectGate: ConnectGate?
    ) {
        self.width = width
        self.height = height
        self.name = name
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
            name: name
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
