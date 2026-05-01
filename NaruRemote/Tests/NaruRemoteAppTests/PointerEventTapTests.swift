import Foundation
import NaruRemoteApp
import NaruRemoteCore
import XCTest

@MainActor
final class PointerEventTapTests: XCTestCase {
    func testFramebufferCoordinateMapsAspectFitForFourByThreeFramebuffer() {
        // 100x100 view, 1024x768 (4:3) framebuffer.
        // View aspect = 1.0, texture aspect = 1.333… → fit by width:
        //   fitWidth = 100, fitHeight = 75, originY = 12.5.
        // (50, 50) view  → (50, 37.5) within fit rect → (512, 384) fb.
        let mapped = NaruRemoteAppModel.framebufferCoordinate(
            forViewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            framebufferWidth: 1024,
            framebufferHeight: 768
        )
        XCTAssertEqual(mapped?.x, 512)
        XCTAssertEqual(mapped?.y, 384)
    }

    func testFramebufferCoordinateReturnsNilForLetterboxBand() {
        // Same 100x100 view with a 1024x768 framebuffer leaves
        // letterbox bands at y < 12.5 and y > 87.5. A tap at y=5 falls
        // inside the band and must NOT synthesize a click at a clamped
        // edge pixel.
        let topBand = NaruRemoteAppModel.framebufferCoordinate(
            forViewPoint: CGPoint(x: 50, y: 5),
            viewSize: CGSize(width: 100, height: 100),
            framebufferWidth: 1024,
            framebufferHeight: 768
        )
        XCTAssertNil(topBand)

        let bottomBand = NaruRemoteAppModel.framebufferCoordinate(
            forViewPoint: CGPoint(x: 50, y: 95),
            viewSize: CGSize(width: 100, height: 100),
            framebufferWidth: 1024,
            framebufferHeight: 768
        )
        XCTAssertNil(bottomBand)
    }

    func testFramebufferCoordinateReturnsNilForPillarboxBand() {
        // Tall view, wider framebuffer flipped: 100x100 view,
        // 768x1024 framebuffer (3:4). Fit by height now:
        //   fitHeight = 100, fitWidth = 75, originX = 12.5.
        // x=5 falls in the left pillarbox band.
        let leftBand = NaruRemoteAppModel.framebufferCoordinate(
            forViewPoint: CGPoint(x: 5, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            framebufferWidth: 768,
            framebufferHeight: 1024
        )
        XCTAssertNil(leftBand)
    }

    func testFramebufferCoordinateClampsExactCornerToLastValidPixel() {
        // Tap exactly on the right/bottom edge of the fit rect must
        // map to the last valid pixel (width-1, height-1) — never to
        // width/height which would be out-of-range for a UInt16 pixel
        // index on edge frames.
        let mapped = NaruRemoteAppModel.framebufferCoordinate(
            forViewPoint: CGPoint(x: 100, y: 87.5),
            viewSize: CGSize(width: 100, height: 100),
            framebufferWidth: 1024,
            framebufferHeight: 768
        )
        XCTAssertEqual(mapped?.x, 1023)
        XCTAssertEqual(mapped?.y, 767)
    }

    func testFramebufferCoordinateReturnsNilForDegenerateInputs() {
        XCTAssertNil(
            NaruRemoteAppModel.framebufferCoordinate(
                forViewPoint: .zero,
                viewSize: .zero,
                framebufferWidth: 1024,
                framebufferHeight: 768
            )
        )
        XCTAssertNil(
            NaruRemoteAppModel.framebufferCoordinate(
                forViewPoint: .zero,
                viewSize: CGSize(width: 100, height: 100),
                framebufferWidth: 0,
                framebufferHeight: 768
            )
        )
    }

    func testSendTapAtSendsButtonDownAndUpThroughActiveStreamingClient() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1024,
            height: 768,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = PointerCapturingStreamingConnector(
            width: 1024,
            height: 768,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertNotNil(model.snapshot.latestFramebuffer)

        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await waitForPointerEvents(connector, count: 2)

        let events = connector.recordedPointerEvents
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].mask, 0x01)
        XCTAssertEqual(events[0].x, 512)
        XCTAssertEqual(events[0].y, 384)
        XCTAssertEqual(events[1].mask, 0x00)
        XCTAssertEqual(events[1].x, 512)
        XCTAssertEqual(events[1].y, 384)
    }

    func testSendTapAtIsNoOpWithoutActiveSession() {
        let model = NaruRemoteAppModel()
        // No frame, no streaming pointer client. Must not throw and
        // must produce no observable side effect on the snapshot.
        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        XCTAssertNil(model.snapshot.latestFramebuffer)
        XCTAssertNil(model.snapshot.session)
    }

    func testSendTapAtIsNoOpForLetterboxBand() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1024,
            height: 768,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = PointerCapturingStreamingConnector(
            width: 1024,
            height: 768,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        // y=5 falls in the top letterbox band — a tap there must NOT
        // synthesize a clamped edge click.
        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 5),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.recordedPointerEvents.count, 0)
    }

    func testSendTapAtDoesNotChangeDiagnosticExportSafeCatalog() async throws {
        // Constitution §IV: pointer coordinates must not leak into the
        // diagnostic safe-detail catalog. The export rendered before
        // and after a tap event must be identical.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1024,
            height: 768,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = PointerCapturingStreamingConnector(
            width: 1024,
            height: 768,
            name: "Desk",
            framebuffer: framebuffer
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))

        let exportBefore = model.makeDiagnosticExport().renderShareText(buildVersion: "test")

        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await waitForPointerEvents(connector, count: 2)

        let exportAfter = model.makeDiagnosticExport().renderShareText(buildVersion: "test")
        XCTAssertEqual(exportAfter, exportBefore)
    }

    private func waitForPointerEvents(
        _ connector: PointerCapturingStreamingConnector,
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
/// for the pointer-click tests. Otherwise mirrors the
/// `FakeStreamingConnector` used elsewhere — kept private to this
/// file so the existing tests stay structurally unchanged.
private final class PointerCapturingStreamingConnector: RFBStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private let width: Int
    private let height: Int
    private let name: String
    private var framebuffers: [RFBRawFramebuffer]
    private var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []

    init(width: Int, height: Int, name: String, framebuffer: RFBRawFramebuffer) {
        self.width = width
        self.height = height
        self.name = name
        self.framebuffers = [framebuffer, framebuffer, framebuffer]
    }

    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var recordedPointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPointerEventsList
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

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        lock.withLock {
            recordedPointerEventsList.append((buttonMask, x, y))
        }
    }
}
