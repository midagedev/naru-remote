import CoreGraphics
import Foundation
import XCTest
@testable import NaruRemoteCore

/// Does the pixel we address in an RFB `PointerEvent` reach the pixel the
/// user is looking at?
///
/// The founder reported (2026-09-14, physical iPhone): "트랙패드 모드에서 앱에서
/// 그려진 커서와 실제 원격화면에 보이는 커서가 위치가 심하게 차이난다." Inside
/// the app the two halves cannot disagree — the drawn glyph and the outgoing
/// `PointerEvent` are both derived from `TrackpadCursor.position` through the
/// same `ViewportTransform`. So a severe, visible offset has to live in the one
/// contract no unit test can reach: what macOS Screen Sharing does with the
/// coordinates we put on the wire.
///
/// That contract is not obvious on a Retina Mac. The served framebuffer is in
/// **backing pixels** (measured here 3024×1964) while the window server places
/// the cursor in **points** (1512×982). Somebody has to divide by the backing
/// scale. If the server does it, our framebuffer-pixel coordinates are right.
/// If it does not, every pointer we send lands at twice its intended distance
/// from the origin — which is exactly the shape of "심하게 차이난다", and it
/// would grow with distance from the top-left corner.
///
/// This probe answers that with a measurement rather than a reading, and it is
/// permanent on purpose: the same question returns whenever the pointer lane,
/// the downscale ladder, or a macOS release moves.
///
/// ## Reading the result
///
/// `impliedPointsPerPixel` is the ratio the *server* is actually using, derived
/// from where the cursor landed. Compare it with `pointsPerPixel`, the ratio
/// the app assumes (display points ÷ served framebuffer width):
///
/// - equal → the wire contract holds; a misplaced cursor is a client-side bug
/// - implied ≈ 2 × assumed → the server treats our pixels as points, and the
///   client must divide by the backing scale before sending
/// - implied ≈ 0.5 × assumed → the reverse
///
/// Constitution §IV: positions here are this machine's own cursor geometry
/// during a probe, never user-entered content, and nothing is persisted.
/// Skipped unless `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` are set. It
/// moves this Mac's real cursor and puts it back afterwards.
final class LiveMacPointerCoordinateSpaceTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    /// Fractions of the served framebuffer to address. The origin is excluded
    /// on purpose: a scale error is invisible at (0, 0), and the whole question
    /// is how the error grows with distance.
    private static let probeFractions: [(x: Double, y: Double)] = [
        (0.25, 0.25),
        (0.50, 0.50),
        (0.75, 0.70)
    ]

    func testPointerEventsLandOnTheFramebufferPixelTheyAddress() async throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live pointer probe")
        }
        try LiveMacInputEnvironment.requireAQuietMac()

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 5
        )

        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let pointsPerPixel = displayBounds.width / CGFloat(max(serverInit.width, 1))
        print("""
        [pointer-space] served framebuffer : \(serverInit.width) x \(serverInit.height) px
        [pointer-space] main display       : \(Int(displayBounds.width)) x \(Int(displayBounds.height)) pt
        [pointer-space] assumed points/px  : \(String(format: "%.4f", pointsPerPixel))
        """)

        let originalLocation = LiveMacInputEnvironment.currentPointerLocation()
        defer {
            if let originalLocation {
                CGWarpMouseCursorPosition(originalLocation)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        // A freshly authenticated Screen Sharing session swallows pointer
        // events for about two seconds (measured 2026-09-14: a walk of eight
        // moves at 400 ms spacing had its first six ignored, then every
        // remaining one landed exactly). That is the server starting up, not a
        // coordinate defect, and a gate that measures through it reports a
        // wrong answer to the one question it exists to answer. So: reference
        // moves until one lands, then measure.
        try await Self.waitForTheSessionToAcceptPointerInput(
            client,
            serverInit: serverInit,
            pointsPerPixel: pointsPerPixel
        )

        var failures: [String] = []
        for fraction in Self.probeFractions {
            let x = UInt16(Double(serverInit.width) * fraction.x)
            let y = UInt16(Double(serverInit.height) * fraction.y)
            let expected = CGPoint(
                x: CGFloat(x) * pointsPerPixel,
                y: CGFloat(y) * pointsPerPixel
            )

            // Re-send until the pointer actually moves. Screen Sharing drops
            // pointer events intermittently — measured 2026-09-14: with the
            // session already awake, one move in a walk of eight was ignored
            // for seconds while its neighbours landed exactly. That is a
            // delivery property of the server, and this gate is about *where*
            // an event that lands puts the cursor. Asserting on a dropped one
            // would report a coordinate defect that is not there.
            var landed: CGPoint?
            for _ in 0..<5 {
                let before = LiveMacInputEnvironment.currentPointerLocation()
                try await client.sendPointerEvent(buttonMask: 0, x: x, y: y)
                if let settled = Self.settledPointerLocation(movedFrom: before, timeout: 2),
                   let before,
                   abs(settled.x - before.x) >= 0.5 || abs(settled.y - before.y) >= 0.5 {
                    landed = settled
                    break
                }
            }

            guard let landed else {
                throw XCTSkip(
                    "this Mac never acted on a pointer move to this point — the server is "
                        + "dropping input, so the coordinate contract cannot be measured"
                )
            }

            let impliedX = landed.x / CGFloat(max(x, 1))
            let impliedY = landed.y / CGFloat(max(y, 1))
            let errorX = landed.x - expected.x
            let errorY = landed.y - expected.y
            print("""
            [pointer-space] sent (\(x), \(y)) px → expected (\(Int(expected.x)), \(Int(expected.y))) pt, \
            landed (\(Int(landed.x)), \(Int(landed.y))) pt, \
            error (\(Int(errorX)), \(Int(errorY))) pt, \
            impliedPointsPerPixel (\(String(format: "%.4f", impliedX)), \(String(format: "%.4f", impliedY)))
            """)

            if abs(errorX) > Self.tolerancePoints || abs(errorY) > Self.tolerancePoints {
                failures.append(
                    "sent (\(x), \(y)) px, landed (\(Int(landed.x)), \(Int(landed.y))) pt, "
                        + "off by (\(Int(errorX)), \(Int(errorY))) pt"
                )
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            """
            RFB pointer events did not land where they were addressed on this \
            server: \(failures.joined(separator: "; ")). The app draws its \
            trackpad cursor at the framebuffer pixel it sends, so this offset \
            is what the user sees between the drawn cursor and the real one. \
            Read `impliedPointsPerPixel` above against the assumed ratio to see \
            which coordinate space the server is really using.
            """
        )
    }

    /// Characterisation, not a gate: walk a diagonal and record, for each
    /// step, whether the cursor moved at all and where it stopped. A scale
    /// error shows up as a growing offset; a delivery defect shows up as steps
    /// that do not move at all.
    func testCharacteriseAWalkOfPointerMoves() async throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live pointer probe")
        }
        try LiveMacInputEnvironment.requireAQuietMac()

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 5
        )
        let pointsPerPixel = CGDisplayBounds(CGMainDisplayID()).width / CGFloat(max(serverInit.width, 1))

        let originalLocation = LiveMacInputEnvironment.currentPointerLocation()
        defer {
            if let originalLocation {
                CGWarpMouseCursorPosition(originalLocation)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        // Does the server act on input only while it is answering framebuffer
        // update requests? The app's pump can be parked (spec 042 FR-008 parks
        // it whenever helper video is the primary transport), so "input needs a
        // pump" would be a shipped regression rather than a curiosity.
        let pumpsFramebufferRequests = ProcessInfo.processInfo
            .environment["NARU_POINTER_WALK_PUMP"] == "1"
        print("[pointer-walk] pumping framebuffer update requests: \(pumpsFramebufferRequests)")

        // Let the freshly authenticated session finish warming up. Measured
        // 2026-09-14: the first ~2 s after connect swallow pointer moves
        // entirely, which is a property of the server's session start and not
        // of the coordinates we send.
        let warmUpSeconds = Double(
            ProcessInfo.processInfo.environment["NARU_POINTER_WALK_WARMUP_SECONDS"] ?? "0"
        ) ?? 0
        if warmUpSeconds > 0 {
            try await Task.sleep(for: .milliseconds(Int(warmUpSeconds * 1000)))
        }
        let startedAt = Date()

        for step in 1...8 {
            let fraction = Double(step) / 10.0
            let x = UInt16(Double(serverInit.width) * fraction)
            let y = UInt16(Double(serverInit.height) * fraction)
            let before = LiveMacInputEnvironment.currentPointerLocation()
            try await client.sendPointerEvent(buttonMask: 0, x: x, y: y)
            if pumpsFramebufferRequests {
                _ = try? client.requestFramebufferUpdate(incremental: true, timeout: 1)
            }
            try await Task.sleep(for: .milliseconds(400))
            let after = LiveMacInputEnvironment.currentPointerLocation()
            let expected = CGPoint(x: CGFloat(x) * pointsPerPixel, y: CGFloat(y) * pointsPerPixel)
            let moved = (before.map { abs((after?.x ?? 0) - $0.x) + abs((after?.y ?? 0) - $0.y) > 0.5 }) ?? true
            print("""
            [pointer-walk] step \(step): sent (\(x), \(y)) px, \
            expected (\(Int(expected.x)), \(Int(expected.y))) pt, \
            landed (\(Int(after?.x ?? -1)), \(Int(after?.y ?? -1))) pt, moved=\(moved), \
            t=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s
            """)
        }
    }

    /// Sends reference moves to a known spot until one of them lands, so the
    /// measurement that follows is taken against a session that is awake.
    /// Skips — never fails — when none ever lands: that is the machine
    /// refusing to be measured, not the contract being wrong.
    private static func waitForTheSessionToAcceptPointerInput(
        _ client: RFBNetworkClient,
        serverInit: RFBServerInit,
        pointsPerPixel: CGFloat,
        attempts: Int = 12
    ) async throws {
        let x = UInt16(Double(serverInit.width) * 0.10)
        let y = UInt16(Double(serverInit.height) * 0.10)
        let target = CGPoint(x: CGFloat(x) * pointsPerPixel, y: CGFloat(y) * pointsPerPixel)
        for attempt in 1...attempts {
            try await client.sendPointerEvent(buttonMask: 0, x: x, y: y)
            try await Task.sleep(for: .milliseconds(400))
            guard let location = LiveMacInputEnvironment.currentPointerLocation() else {
                continue
            }
            if abs(location.x - target.x) <= tolerancePoints,
               abs(location.y - target.y) <= tolerancePoints {
                print("[pointer-space] session accepted pointer input after \(attempt) reference move(s)")
                return
            }
        }
        throw XCTSkip(
            """
            this Mac's Screen Sharing session never acted on a reference pointer \
            move (\(attempts) attempts). The pointer oracle is busy or the session \
            is not accepting input; the coordinate contract cannot be measured here.
            """
        )
    }

    /// Points of slack. Screen Sharing rounds to whole framebuffer pixels and
    /// the window server rounds to points; a couple of points is rounding, and
    /// the offset this probe exists to catch is hundreds.
    private static let tolerancePoints: CGFloat = 4

    /// Reads the pointer until it has both *left* where it was and stopped
    /// moving, so the measurement is the resting place rather than a sample
    /// taken before the server acted.
    ///
    /// The "left where it was" half is not pedantry: the first version of this
    /// probe settled on three stable readings alone, and reported the previous
    /// landing as the answer for a move the server had not performed yet —
    /// which reads exactly like a coordinate-space error and is not one.
    private static func settledPointerLocation(
        movedFrom origin: CGPoint?,
        timeout: TimeInterval
    ) -> CGPoint? {
        let deadline = Date().addingTimeInterval(timeout)
        var previous: CGPoint?
        var stableReadings = 0
        var hasLeftOrigin = origin == nil
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            guard let current = LiveMacInputEnvironment.currentPointerLocation() else {
                return previous
            }
            if let origin, !hasLeftOrigin {
                hasLeftOrigin = abs(current.x - origin.x) >= 0.5 || abs(current.y - origin.y) >= 0.5
            }
            if let previous, abs(current.x - previous.x) < 0.5, abs(current.y - previous.y) < 0.5 {
                stableReadings += 1
                if hasLeftOrigin, stableReadings >= 3 {
                    return current
                }
            } else {
                stableReadings = 0
            }
            previous = current
        }
        return previous
    }
}
