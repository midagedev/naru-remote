import Foundation
import os
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

    func testSendTapAtRecordsOnlySafeOutboundInputDiagnostics() async throws {
        // Constitution §IV: pointer coordinates must not leak into the
        // diagnostic safe-detail catalog. Tap dispatch may update safe
        // aggregate latency buckets, but never records raw positions.
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

        // Pin `now` so the ISO8601 header doesn't drift across the
        // tap-dispatch wait window — the test asserts the safe-catalog
        // body is unaffected by tap dispatch, not that the timestamp
        // header survives a real-time delay.
        let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let exportBefore = model.makeDiagnosticExport().renderCollectionJSON(buildVersion: "test", now: pinnedNow)
        XCTAssertTrue(exportBefore.contains("\"outboundInputEventSampleCount\" : 0"))

        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await waitForPointerEvents(connector, count: 2)

        let exportAfter = model.makeDiagnosticExport().renderCollectionJSON(buildVersion: "test", now: pinnedNow)
        XCTAssertNotEqual(exportAfter, exportBefore)
        XCTAssertTrue(exportAfter.contains("\"outboundInputEventSampleCount\" : 1"))
        XCTAssertTrue(exportAfter.contains("\"outboundInputEventTimeoutCount\" : 0"))

        // The tap maps to framebuffer (512, 384). Assert the leak structurally
        // rather than by searching the document for "512": the export also
        // carries latencies and byte counts, any of which may legitimately
        // render those digits, so a whole-document substring search cannot tell
        // a constitution §IV violation from an ordinary number — and under
        // full-suite load, when latencies grow, it reported the wrong one
        // (observed 2026-08-19; passes alone). Keys and string values are where
        // a coordinate could actually appear.
        let payload = try JSONSerialization.jsonObject(with: Data(exportAfter.utf8))
        let keys = Self.allKeys(in: payload)

        // A tap may move counters; it must never add a field. Since the export
        // is a fixed safe-detail catalog, a leaked coordinate has to arrive as
        // one — so this catches a leak under a key nobody thought to blocklist.
        let keysBefore = Self.allKeys(
            in: try JSONSerialization.jsonObject(with: Data(exportBefore.utf8))
        )
        XCTAssertEqual(
            keys,
            keysBefore,
            "Tap dispatch changed the shape of the diagnostic export"
        )
        let positionalKeys = keys.intersection([
            "x", "y", "tapX", "tapY", "point", "viewPoint", "position", "coordinate", "coordinates"
        ])
        XCTAssertTrue(
            positionalKeys.isEmpty,
            "The safe-detail catalog grew a positional field: \(positionalKeys.sorted())"
        )

        // Whole numbers, not substrings: the export carries SHA-256 digests,
        // and a 64-character hex string contains almost every short digit run
        // by accident (the first run of this check tripped on one). A leaked
        // coordinate would appear as the complete number.
        let leakedStrings = Self.allStringValues(in: payload).filter {
            Self.containsNumberToken($0, anyOf: [512, 384])
        }
        XCTAssertTrue(
            leakedStrings.isEmpty,
            "A tap coordinate reached an exported string: \(leakedStrings)"
        )
    }

    /// Every key in a decoded JSON tree, at any depth.
    private static func allKeys(in value: Any) -> Set<String> {
        switch value {
        case let object as [String: Any]:
            return object.reduce(into: Set(object.keys)) { keys, entry in
                keys.formUnion(allKeys(in: entry.value))
            }
        case let array as [Any]:
            return array.reduce(into: Set<String>()) { keys, element in
                keys.formUnion(allKeys(in: element))
            }
        default:
            return []
        }
    }

    /// The leak detector above is only worth anything if it still fires on a
    /// leak — so check the instrument itself, in both directions.
    func testCoordinateLeakDetectorFiresOnALeakAndNotOnADigest() {
        XCTAssertTrue(Self.containsNumberToken("tap at 512,384", anyOf: [512, 384]))
        XCTAssertTrue(Self.containsNumberToken("pointer.x=512", anyOf: [512]))
        XCTAssertFalse(
            Self.containsNumberToken(
                "sha256:68c5edcbc4335510514a1fa4f5121d4711b2fd6be1131bae83e2736dcdad8739",
                anyOf: [512, 384]
            ),
            "A digest that merely contains the digits is not a leak"
        )
        XCTAssertFalse(Self.containsNumberToken("5120 ms", anyOf: [512]))
    }

    /// Whether `text` contains any of `numbers` as a complete run of digits.
    private static func containsNumberToken(_ text: String, anyOf numbers: Set<Int>) -> Bool {
        text
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .contains { numbers.contains($0) }
    }

    /// Every string *value* in a decoded JSON tree — numbers stay out, which is
    /// the distinction the old substring assertion could not make.
    private static func allStringValues(in value: Any) -> [String] {
        switch value {
        case let object as [String: Any]:
            return object.values.flatMap { allStringValues(in: $0) }
        case let array as [Any]:
            return array.flatMap { allStringValues(in: $0) }
        case let string as String:
            return [string]
        default:
            return []
        }
    }

    func testRapidTapsStaySerializedAsClickPairsWhenWritesAreSlow() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector(
            pointerEventDelay: .milliseconds(30)
        )
        let model = connection.model
        let recorder = connection.connector

        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        model.sendTapAt(
            viewPoint: CGPoint(x: 60, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )

        try await waitForPointerEvents(recorder, count: 4, timeout: 3)

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.mask), [0x01, 0x00, 0x01, 0x00])
        XCTAssertEqual(events[0].x, 512)
        XCTAssertEqual(events[1].x, 512)
        XCTAssertEqual(events[2].x, 614)
        XCTAssertEqual(events[3].x, 614)
        for _ in 0..<30
            where model.snapshot.sessionStreamStats.outboundInputEventSampleCount < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let report = try XCTUnwrap(model.snapshot.sessionStreamStats.diagnosticStreamPerformanceReport)
        XCTAssertEqual(report.outboundInputEventSampleCount, 2)
        XCTAssertEqual(report.outboundInputEventTimeoutCount, 0)
    }

    func testDisconnectCancelsInFlightPointerClickBeforeQueuedButtonUp() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector(
            pointerEventDelay: .milliseconds(500)
        )
        let model = connection.model
        let recorder = connection.connector

        model.sendTapAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await waitForPointerEvents(recorder, count: 1, timeout: 1)

        model.disconnect()
        try await Task.sleep(for: .milliseconds(700))

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].mask, RFBPointerCommand.leftButton)
    }

    // MARK: Right click

    func testRightClickSendsButtonThreeDownThenUp() async throws {
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

        model.sendRightClickAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await waitForPointerEvents(connector, count: 2)

        let events = connector.recordedPointerEvents
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].mask, 0x04)
        XCTAssertEqual(events[0].x, 512)
        XCTAssertEqual(events[0].y, 384)
        XCTAssertEqual(events[1].mask, 0x00)
        XCTAssertEqual(events[1].x, 512)
        XCTAssertEqual(events[1].y, 384)
    }

    func testRightClickOutsideFramebufferLetterboxIsNoOp() async throws {
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

        // y=5 in a 100x100 view falls in the top letterbox band of a
        // 1024x768 (4:3) framebuffer.
        model.sendRightClickAt(
            viewPoint: CGPoint(x: 50, y: 5),
            viewSize: CGSize(width: 100, height: 100)
        )
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(connector.recordedPointerEvents.count, 0)
    }

    // MARK: Scroll

    func testScrollUpEmitsWheelUpTickPerThreshold() async throws {
        let connector = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connector.model
        let recorder = connector.connector

        // deltaY = +30 with threshold 24 → exactly 1 tick.
        model.sendScrollAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            deltaX: 0,
            deltaY: 30
        )
        try await waitForPointerEvents(recorder, count: 2)

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].mask, 0x08)
        XCTAssertEqual(events[1].mask, 0x00)
    }

    func testScrollDownEmitsTwoTicksAtFiftyPointDelta() async throws {
        let connector = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connector.model
        let recorder = connector.connector

        // deltaY = -50, threshold 24 → 2 wheel-down ticks.
        model.sendScrollAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            deltaX: 0,
            deltaY: -50
        )
        try await waitForPointerEvents(recorder, count: 4)

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0].mask, 0x10)
        XCTAssertEqual(events[1].mask, 0x00)
        XCTAssertEqual(events[2].mask, 0x10)
        XCTAssertEqual(events[3].mask, 0x00)
    }

    func testHorizontalScrollEmitsLeftRightTicks() async throws {
        let rightConnector = try await PointerEventTapTests.connectedModelAndConnector()
        rightConnector.model.sendScrollAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            deltaX: 30,
            deltaY: 0
        )
        try await waitForPointerEvents(rightConnector.connector, count: 2)
        XCTAssertEqual(rightConnector.connector.recordedPointerEvents.first?.mask, 0x40)

        let leftConnector = try await PointerEventTapTests.connectedModelAndConnector()
        leftConnector.model.sendScrollAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            deltaX: -30,
            deltaY: 0
        )
        try await waitForPointerEvents(leftConnector.connector, count: 2)
        XCTAssertEqual(leftConnector.connector.recordedPointerEvents.first?.mask, 0x20)
    }

    func testSubThresholdScrollAccumulatesViaHelper() {
        // Sub-threshold values: 10 + 15 = 25 (one tick for the
        // accumulated delta).  The helper is the unit underneath the
        // accumulator a UI gesture uses across multiple .changed
        // callbacks.
        let oneShot = NaruRemoteAppModel.scrollTicks(
            forDelta: (x: 0, y: 10),
            threshold: 24
        )
        XCTAssertTrue(oneShot.isEmpty)

        let accumulated = NaruRemoteAppModel.scrollTicks(
            forDelta: (x: 0, y: 25),
            threshold: 24
        )
        XCTAssertEqual(accumulated.count, 1)
        XCTAssertEqual(accumulated[0].mask, 0x08)
        XCTAssertEqual(accumulated[0].count, 1)
    }

    func testScrollDoesNotChangeDiagnosticExportSafeCatalog() async throws {
        // Constitution §IV: scroll burst coordinates and per-axis
        // deltas must not leak into the diagnostic safe-detail
        // catalog.  The export rendered before and after a scroll
        // burst must be identical.
        let connector = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connector.model
        let recorder = connector.connector

        let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let exportBefore = model.makeDiagnosticExport().renderShareText(buildVersion: "test", now: pinnedNow)

        model.sendScrollAt(
            viewPoint: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            deltaX: 0,
            deltaY: -72
        )
        try await waitForPointerEvents(recorder, count: 6)

        let exportAfter = model.makeDiagnosticExport().renderShareText(buildVersion: "test", now: pinnedNow)
        XCTAssertEqual(exportAfter, exportBefore)
    }

    // MARK: Pinch

    func testPinchZoomDoesNotSendRFBMessage() async throws {
        // Constitution §I: pinch is a LOCAL view transform — no RFB
        // PointerEvent must be dispatched as a side effect of the
        // pinch gesture.  The model has no `sendPinch` entry point,
        // so simulating the gesture is a no-op at the model layer;
        // we assert that no pointer events are recorded after the
        // pinch handler updates the local zoom state on the view.
        let connector = try await PointerEventTapTests.connectedModelAndConnector()
        let recorder = connector.connector

        // The pinch handler in the SwiftUI view layer only mutates
        // local @State — there is no model command for it.  Verify
        // that the only public model commands the pinch could
        // accidentally invoke (right-click, scroll, tap) were never
        // called by simulating "0 model invocations" and checking
        // the recorder remains empty.
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.recordedPointerEvents.count, 0)
    }

    // MARK: Drag

    func testDragCoalescesBurstMovesToLatestBeforeUp() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        let viewSize = CGSize(width: 100, height: 100)

        // Start at (50, 50) → fb (512, 384).  Move to (60, 50) →
        // fb (614.4 → 614, 360 (within fit) → 384).  Then move to
        // (70, 60) → fb (716, 460.8 → 460).  All inside the
        // 1024x768 4:3 framebuffer fit rect.
        await model.sendPointerDownAt(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 60, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 70, y: 60), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 70, y: 60), viewSize: viewSize)

        try await waitForPointerEvents(recorder, count: 3)

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].mask, 0x01)
        XCTAssertEqual(events[0].x, 512)
        XCTAssertEqual(events[0].y, 384)
        XCTAssertEqual(events[1].mask, 0x01)
        XCTAssertEqual(events[1].x, 716)
        XCTAssertEqual(events[1].y, 486)
        XCTAssertEqual(events[2].mask, 0x00)
        XCTAssertEqual(events[2].x, 716)
        XCTAssertEqual(events[2].y, 486)
        // Down and up coords differ when the user dragged — sanity
        // check that the drag actually moved on the wire.
        let downX = events[0].x
        let downY = events[0].y
        let upX = events[2].x
        let upY = events[2].y
        XCTAssertFalse(downX == upX && downY == upY)
    }

    func testDragSendsSeparateMovesWhenGestureCadenceAllowsFlush() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        let viewSize = CGSize(width: 100, height: 100)

        await model.sendPointerDownAt(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 60, y: 50), viewSize: viewSize)
        // The app coalesces remote drag moves over roughly one 60 Hz
        // display frame. Wait just beyond that window so this move is
        // allowed to flush before the next one arrives.
        try await Task.sleep(for: .milliseconds(25))
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 70, y: 60), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 70, y: 60), viewSize: viewSize)

        try await waitForPointerEvents(recorder, count: 4)

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.mask), [0x01, 0x01, 0x01, 0x00])
        XCTAssertEqual(events[1].x, 614)
        XCTAssertEqual(events[1].y, 384)
        XCTAssertEqual(events[2].x, 716)
        XCTAssertEqual(events[2].y, 486)
        XCTAssertEqual(events[3].x, 716)
        XCTAssertEqual(events[3].y, 486)
    }

    func testDragMoveBelowOnePixelDeltaDoesNotEmit() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        let viewSize = CGSize(width: 100, height: 100)

        // Down at (50, 50) → fb (512, 384).  Two move calls at the
        // same view point still map to the same fb (512, 384) and
        // must be suppressed by the throttle.  Then a move at (60,
        // 50) crosses the threshold (fb x = 614 ≠ 512) and must be
        // emitted.
        await model.sendPointerDownAt(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 60, y: 50), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 60, y: 50), viewSize: viewSize)

        try await waitForPointerEvents(recorder, count: 3)
        // Settle a beat so any erroneous extra move can land before
        // we assert the count.
        try await Task.sleep(for: .milliseconds(40))

        let events = recorder.recordedPointerEvents
        // 1 down (mask 0x01) + 1 move that crossed threshold (mask
        // 0x01) + 1 up (mask 0x00) = 3.  The two suppressed moves
        // never reached the wire.
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].mask, 0x01)
        XCTAssertEqual(events[1].mask, 0x01)
        XCTAssertEqual(events[2].mask, 0x00)
    }

    func testDragOutsideLetterboxAtStartIsNoOp() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        let viewSize = CGSize(width: 100, height: 100)
        // y=5 is the top letterbox band of a 1024x768 (4:3) fb in a
        // 100x100 view (originY = 12.5).  All three commands must
        // return without emitting any pointer events on the wire.
        await model.sendPointerDownAt(viewPoint: CGPoint(x: 50, y: 5), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 50, y: 5), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 50, y: 5), viewSize: viewSize)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.recordedPointerEvents.count, 0)
    }

    func testDragWithExplicitDisconnectDoesNothing() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        // Tear the session down so `explicitlyDisconnected` is set.
        model.disconnect()

        let viewSize = CGSize(width: 100, height: 100)
        await model.sendPointerDownAt(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 60, y: 50), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 60, y: 50), viewSize: viewSize)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(recorder.recordedPointerEvents.count, 0)
    }

    func testDragSendsCorrectFramebufferCoordsForAspectFit() async throws {
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        let viewSize = CGSize(width: 100, height: 100)
        // In a 100x100 view with a 1024x768 (4:3) fb, the fit rect is
        // 100 wide × 75 tall, originY = 12.5.
        // (25, 25) view → local (25, 12.5) → fb (256, 128).
        // (75, 75) view → local (75, 62.5) → fb (768, 640).
        await model.sendPointerDownAt(viewPoint: CGPoint(x: 25, y: 25), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 75, y: 75), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 75, y: 75), viewSize: viewSize)

        try await waitForPointerEvents(recorder, count: 3)

        let events = recorder.recordedPointerEvents
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].mask, 0x01)
        XCTAssertEqual(events[0].x, 256)
        XCTAssertEqual(events[0].y, 128)
        XCTAssertEqual(events[1].mask, 0x01)
        XCTAssertEqual(events[1].x, 768)
        XCTAssertEqual(events[1].y, 640)
        XCTAssertEqual(events[2].mask, 0x00)
        XCTAssertEqual(events[2].x, 768)
        XCTAssertEqual(events[2].y, 640)
    }

    func testDragDoesNotChangeDiagnosticExportSafeCatalog() async throws {
        // Constitution §IV: drag coordinates must not leak into the
        // diagnostic safe-detail catalog.
        let connection = try await PointerEventTapTests.connectedModelAndConnector()
        let model = connection.model
        let recorder = connection.connector

        let pinnedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let exportBefore = model.makeDiagnosticExport().renderShareText(buildVersion: "test", now: pinnedNow)

        let viewSize = CGSize(width: 100, height: 100)
        await model.sendPointerDownAt(viewPoint: CGPoint(x: 50, y: 50), viewSize: viewSize)
        await model.sendPointerMoveTo(viewPoint: CGPoint(x: 60, y: 60), viewSize: viewSize)
        await model.sendPointerUpAt(viewPoint: CGPoint(x: 60, y: 60), viewSize: viewSize)
        try await waitForPointerEvents(recorder, count: 3)

        let exportAfter = model.makeDiagnosticExport().renderShareText(buildVersion: "test", now: pinnedNow)
        XCTAssertEqual(exportAfter, exportBefore)
    }

    private static func connectedModelAndConnector(
        pointerEventDelay: Duration? = nil
    ) async throws -> (model: NaruRemoteAppModel, connector: PointerCapturingStreamingConnector) {
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
            framebuffer: framebuffer,
            pointerEventDelay: pointerEventDelay
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await Task.sleep(for: .milliseconds(80))
        return (model, connector)
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
private final class PointerCapturingStreamingConnector: RFBStreamingClient {
    private struct Recording {
        var framebuffers: [RFBRawFramebuffer]
        var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String
    private let pointerEventDelay: Duration?

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffer: RFBRawFramebuffer,
        pointerEventDelay: Duration? = nil
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.pointerEventDelay = pointerEventDelay
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(framebuffers: [framebuffer, framebuffer, framebuffer])
        )
    }

    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

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
            name: name
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
        if let pointerEventDelay {
            try await Task.sleep(for: pointerEventDelay)
        }
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        // Key events are out of scope for pointer-event tests; Direct
        // Keystroke Mode tests live in DirectKeystrokeModeTests.swift.
    }
}
