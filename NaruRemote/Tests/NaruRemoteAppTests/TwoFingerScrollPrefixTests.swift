import CoreGraphics
import Foundation
import NaruRemoteApp
import NaruRemoteCore
import os
import XCTest

/// Spec 043 FR-002: motion accumulated while a two-finger gesture is
/// `.undecided` is delivered to the scroll path once the gesture resolves —
/// exactly once, not re-counted — and a gesture that resolves to `.zoom`
/// delivers nothing to scroll, including on its final callback.
///
/// Founder report 2026-09-13 (physical iPhone): "vnc모드에서 두손가락 드래그
/// 스크롤의 양이 엄청 적을때가 있어" — H2: `handlePanGesture` returned early
/// while the intent was not `.scroll`, so the travel accumulated before the
/// classifier's 12-point bar never reached `sendScrollAt`. A gesture only
/// resolves after 12 points and a wheel notch costs 24, so every two-finger
/// scroll lost half a notch at its start — and a 26-point drag (a real short
/// scroll) lost its entire only notch.
///
/// The defective code itself (`MetalFramebufferHostingView` is UIKit) is not
/// unit-reachable from macOS `swift test`; what is testable here is the
/// delivery *policy* (`TwoFingerGestureClassifier.scrollDelta`, the single
/// owner of the rule) and the chain from that policy through the real
/// `NaruRemoteAppModel.sendScrollAt` to real RFB wheel events. The pre-043
/// policy is ported below as `preSpec043Delivery` (deltas delivered only once
/// the intent is `.scroll`, prefix dropped — `MetalFramebufferView`'s early
/// return, pre-spec-043) and run through the same real model, so the
/// founder's symptom is demonstrated rather than asserted.
///
/// ## Contract ↔ assertion table (FR-002 → tests)
///
/// | FR-002 clause | Test |
/// |---|---|
/// | The undecided prefix is delivered on the resolving callback, exactly
///   once, prefix + current delta | `testTheResolvingCallbackDeliversThePrefix`,
///   `testDeliveredDeltasSumToTheFullTravelOfTheGesture` |
/// | Later callbacks deliver their own delta only (no double count) |
///   `testCallbacksAfterResolutionDeliverTheirOwnDelta` |
/// | A `.zoom` gesture delivers nothing, on every callback including the
///   last (the touch count is zero by `.ended`) |
///   `testAZoomGestureDeliversNothingIncludingOnItsFinalCallback`,
///   `testAnUnresolvedGestureDeliversNothing` |
/// | A hardware trackpad scroll (no two-finger baseline) is unambiguous and
///   delivers every callback unchanged | `testHardwareScrollDeliversEveryCallbackUnchanged` |
/// | Through the real model, a 26-point two-finger drag scrolls one notch |
///   `testAShortDragScrollsOneNotchThroughTheRealModel` |
/// | Evidence: the pre-043 policy loses that notch through the same model |
///   `testPreSpec043DeliveryLosesTheFirstNotchOfAShortDrag` |
@MainActor
final class TwoFingerScrollPrefixTests: XCTestCase {

    // MARK: - The delivery policy (FR-002's single owner)

    func testTheResolvingCallbackDeliversThePrefix() {
        // A 12-point prefix accumulated while undecided (six callbacks of 2),
        // and the resolving callback carries 2 more.
        let delivered = TwoFingerGestureClassifier.scrollDelta(
            previousIntent: .undecided,
            resolvedIntent: .scroll,
            accumulatedTranslation: CGSize(width: 0, height: -12),
            callbackDelta: CGSize(width: 0, height: -2),
            hasTwoFingerBaseline: true
        )
        XCTAssertEqual(delivered, CGSize(width: 0, height: -12))
    }

    func testCallbacksAfterResolutionDeliverTheirOwnDelta() {
        let delivered = TwoFingerGestureClassifier.scrollDelta(
            previousIntent: .scroll,
            resolvedIntent: .scroll,
            accumulatedTranslation: CGSize(width: 0, height: -30),
            callbackDelta: CGSize(width: 0, height: -2),
            hasTwoFingerBaseline: true
        )
        XCTAssertEqual(
            delivered,
            CGSize(width: 0, height: -2),
            "The prefix was delivered once on the resolving callback; the accumulated translation must not be re-counted"
        )
    }

    func testAZoomGestureDeliversNothingIncludingOnItsFinalCallback() {
        // UIKit reports zero touches by `.ended`, so the instantaneous touch
        // count must not be what gates delivery — the baseline must be.
        let finalCallback = TwoFingerGestureClassifier.scrollDelta(
            previousIntent: .zoom,
            resolvedIntent: .zoom,
            accumulatedTranslation: CGSize(width: 0, height: -40),
            callbackDelta: CGSize(width: 0, height: -3),
            hasTwoFingerBaseline: true
        )
        XCTAssertNil(finalCallback)
    }

    func testAnUnresolvedGestureDeliversNothing() {
        let delivered = TwoFingerGestureClassifier.scrollDelta(
            previousIntent: .undecided,
            resolvedIntent: .undecided,
            accumulatedTranslation: CGSize(width: 0, height: -8),
            callbackDelta: CGSize(width: 0, height: -2),
            hasTwoFingerBaseline: true
        )
        XCTAssertNil(delivered)
    }

    func testHardwareScrollDeliversEveryCallbackUnchanged() {
        // A hardware trackpad scroll reports zero touches, never sets a
        // two-finger baseline, and never resolves through the classifier —
        // so the policy must not care what the classifier would have said.
        for resolvedIntent in [TwoFingerGestureIntent.undecided, .scroll, .zoom] {
            let delivered = TwoFingerGestureClassifier.scrollDelta(
                previousIntent: .undecided,
                resolvedIntent: resolvedIntent,
                accumulatedTranslation: CGSize(width: 0, height: -100),
                callbackDelta: CGSize(width: 0, height: -4),
                hasTwoFingerBaseline: false
            )
            XCTAssertEqual(
                delivered,
                CGSize(width: 0, height: -4),
                "Hardware scroll intent=\(resolvedIntent) must deliver its delta unchanged"
            )
        }
    }

    // MARK: - One gesture, folded the way the view folds it

    /// The gesture under test: 13 callbacks of 2 points straight down, spread
    /// constant — 26 points of travel, resolving to `.scroll` on callback 6
    /// (the first sample past the 12-point translation bar).
    private static let shortDragSamples: [(spreadDelta: CGFloat, translationMagnitude: CGSize)] =
        (1...13).map { _ in (CGFloat(0), CGSize(width: 0, height: -2)) }

    /// Folds a sample stream exactly the way `MetalFramebufferHostingView`
    /// does: accumulate translation, resolve the intent, then ask the
    /// classifier what the scroll path receives.
    private static func deliveredDeltas(
        of samples: [(spreadDelta: CGFloat, translationMagnitude: CGSize)]
    ) -> [CGSize] {
        var intent = TwoFingerGestureIntent.undecided
        var accumulated = CGSize.zero
        var delivered: [CGSize] = []
        for sample in samples {
            let delta = sample.translationMagnitude
            accumulated = CGSize(
                width: accumulated.width + delta.width,
                height: accumulated.height + delta.height
            )
            let previous = intent
            intent = TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: sample.spreadDelta,
                translationMagnitude: TwoFingerGestureClassifier.magnitude(accumulated)
            )
            if let scrollDelta = TwoFingerGestureClassifier.scrollDelta(
                previousIntent: previous,
                resolvedIntent: intent,
                accumulatedTranslation: accumulated,
                callbackDelta: delta,
                hasTwoFingerBaseline: true
            ) {
                delivered.append(scrollDelta)
            }
        }
        return delivered
    }

    /// The pre-spec-043 delivery policy, ported from the view's early
    /// return: while the intent is not `.scroll` nothing is delivered, and
    /// when it becomes `.scroll` only that callback's delta is — the
    /// accumulated prefix never reaches the scroll path.
    private static func preSpec043DeliveredDeltas(
        of samples: [(spreadDelta: CGFloat, translationMagnitude: CGSize)]
    ) -> [CGSize] {
        var intent = TwoFingerGestureIntent.undecided
        var accumulated = CGSize.zero
        var delivered: [CGSize] = []
        for sample in samples {
            let delta = sample.translationMagnitude
            accumulated = CGSize(
                width: accumulated.width + delta.width,
                height: accumulated.height + delta.height
            )
            intent = TwoFingerGestureClassifier.resolve(
                current: intent,
                spreadDelta: sample.spreadDelta,
                translationMagnitude: TwoFingerGestureClassifier.magnitude(accumulated)
            )
            if intent == .scroll {
                delivered.append(delta)
            }
        }
        return delivered
    }

    func testDeliveredDeltasSumToTheFullTravelOfTheGesture() {
        let delivered = Self.deliveredDeltas(of: Self.shortDragSamples)

        // Resolves on callback 6: five nils, then the 12-point prefix
        // (including callback 6's own delta), then seven 2-point deltas.
        XCTAssertEqual(delivered.count, 8)
        XCTAssertEqual(delivered.first, CGSize(width: 0, height: -12))
        let total = delivered.reduce(CGFloat(0)) { $0 + abs($1.height) }
        XCTAssertEqual(
            total,
            26,
            "26 points of finger travel must reach the scroll path — prefix delivered once, nothing re-counted"
        )
    }

    // MARK: - Through the real model (fake RFB connector)

    func testAShortDragScrollsOneNotchThroughTheRealModel() async throws {
        let connection = try await Self.connectedModelAndConnector()
        defer { connection.model.disconnect() }

        for delta in Self.deliveredDeltas(of: Self.shortDragSamples) {
            connection.model.sendScrollAt(
                viewPoint: CGPoint(x: 50, y: 50),
                viewSize: CGSize(width: 100, height: 100),
                deltaX: delta.width,
                deltaY: delta.height
            )
        }
        connection.model.endScrollGesture()
        try await Self.waitForPointerEvents(connection.connector, count: 2, timeout: 2)

        XCTAssertEqual(
            connection.connector.recordedPointerEvents.map(\.mask),
            [0x10, 0x00],
            "26 points of travel are one wheel-down notch (down, up)"
        )
    }

    func testPreSpec043DeliveryLosesTheFirstNotchOfAShortDrag() async throws {
        let connection = try await Self.connectedModelAndConnector()
        defer { connection.model.disconnect() }

        // The same 26 points, delivered the way the pre-043 view delivered
        // them. Through the real, unmodified model this stream is 16 points —
        // under one notch — and the remote receives nothing. This is the
        // founder's symptom, demonstrated end to end minus the UIKit layer.
        for delta in Self.preSpec043DeliveredDeltas(of: Self.shortDragSamples) {
            connection.model.sendScrollAt(
                viewPoint: CGPoint(x: 50, y: 50),
                viewSize: CGSize(width: 100, height: 100),
                deltaX: delta.width,
                deltaY: delta.height
            )
        }
        connection.model.endScrollGesture()
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(
            connection.connector.recordedPointerEvents.count,
            0,
            "The pre-043 policy delivers 16 of the 26 points: no notch, nothing scrolled"
        )
    }

    // MARK: - Fixtures

    /// Mirrors `PointerEventTapTests.connectedModelAndConnector` (that one is
    /// `private` to its file). Same shape, same fake, so the notch arithmetic
    /// here is comparable with the scroll tests that already pin
    /// `sendScrollAt`.
    private static func connectedModelAndConnector() async throws -> (
        model: NaruRemoteAppModel, connector: PrefixCapturingStreamingConnector
    ) {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(
            width: 1024,
            height: 768,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let connector = PrefixCapturingStreamingConnector(
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
        return (model, connector)
    }

    private static func waitForPointerEvents(
        _ connector: PrefixCapturingStreamingConnector,
        count: Int,
        timeout: TimeInterval
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

/// Copy of `PointerCapturingStreamingConnector` from
/// `PointerEventTapTests.swift` (kept `private` there so the existing tests
/// stay structurally unchanged — hence this copy rather than a shared move,
/// which would touch a file outside this round's list).
private final class PrefixCapturingStreamingConnector: RFBStreamingClient {
    private struct Recording {
        var framebuffers: [RFBRawFramebuffer]
        var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffer: RFBRawFramebuffer
    ) {
        self.width = width
        self.height = height
        self.name = name
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
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {}
}
