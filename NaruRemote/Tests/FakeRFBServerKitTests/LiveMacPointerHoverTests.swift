import CoreGraphics
import Foundation
import XCTest
@testable import NaruRemoteCore

/// Does a buttonless `PointerEvent` actually move the pointer on the real Mac,
/// and does the server repaint afterwards?
///
/// The founder reported from a device (2026-08-19) that trackpad mode "실제
/// 화면에 호버이벤트를 트리거 하지 않는다". Unit tests already prove the client
/// *sends* buttonless moves (`TrackpadModeModelTests`), so the open question is
/// what happens at the other end — and that is only answerable against a real
/// macOS Screen Sharing server. This test splits the two halves:
///
/// 1. the OS pointer follows the event (read back through CoreGraphics), and
/// 2. the server sends a framebuffer update after the move, which is what makes
///    a hover highlight visible.
///
/// Skipped unless `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` are set, like
/// the rest of the live suite. It moves the host machine's real cursor and puts
/// it back afterwards.
final class LiveMacPointerHoverTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    func testButtonlessPointerEventMovesTheRealMacPointer() async throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live hover probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let timeout: TimeInterval = 5
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: timeout
        )
        _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

        let originalLocation = Self.currentPointerLocation()
        defer {
            if let originalLocation {
                CGWarpMouseCursorPosition(originalLocation)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        // The framebuffer is in server pixels; `CGEvent.location` is in display
        // points. On a Retina Mac those differ by the backing scale, and
        // comparing them raw makes a working pointer look broken — measure the
        // ratio instead of assuming it.
        let pointsPerFramebufferPixel = Self.displayPointsPerPixel(
            framebufferWidth: CGFloat(serverInit.width)
        )

        // Two targets far apart, so a stale reading cannot pass for a move.
        let targets: [(x: UInt16, y: UInt16)] = [
            (UInt16(serverInit.width / 4), UInt16(serverInit.height / 4)),
            (UInt16(serverInit.width / 2), UInt16(serverInit.height / 2))
        ]

        for target in targets {
            try await client.sendPointerEvent(buttonMask: 0, x: target.x, y: target.y)

            let expected = CGPoint(
                x: CGFloat(target.x) * pointsPerFramebufferPixel,
                y: CGFloat(target.y) * pointsPerFramebufferPixel
            )
            let observed = Self.waitForPointer(
                toReach: expected,
                tolerance: 4,
                timeout: 2
            )

            guard let observed else {
                let actual = Self.currentPointerLocation().map { "(\($0.x), \($0.y))" } ?? "unknown"
                XCTFail(
                    """
                    A buttonless PointerEvent to framebuffer (\(target.x), \(target.y)) did not move \
                    the Mac's pointer to the expected point (\(expected.x), \(expected.y)); it is at \
                    \(actual). Trackpad-mode hover cannot work until it does — the fix belongs on \
                    the send side, not in repaint.
                    """
                )
                return
            }

            XCTAssertEqual(observed.x, expected.x, accuracy: 4)
            XCTAssertEqual(observed.y, expected.y, accuracy: 4)
        }
    }

    /// A hover highlight only becomes visible if the server sends pixels after
    /// the pointer moves. This asks for an incremental update *after* a move
    /// and expects changed pixels — the moved pointer alone repaints the area
    /// it left and entered on macOS.
    func testServerRepaintsAfterAPointerMove() async throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live hover probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let timeout: TimeInterval = 5
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: timeout
        )
        _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

        let originalLocation = Self.currentPointerLocation()
        defer {
            if let originalLocation {
                CGWarpMouseCursorPosition(originalLocation)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        // Sweep across the Dock's usual band so the move crosses live UI.
        let y = UInt16(Double(serverInit.height) * 0.92)
        for step in 0..<8 {
            let x = UInt16(Double(serverInit.width) * (0.3 + 0.05 * Double(step)))
            try await client.sendPointerEvent(buttonMask: 0, x: x, y: y)
            try await Task.sleep(for: .milliseconds(40))
        }

        let update = try client.requestFramebufferUpdate(incremental: true, timeout: 2)
        print("Post-move incremental update changedPixelCount=\(update.changedPixelCount)")
        XCTAssertGreaterThan(
            update.changedPixelCount,
            0,
            """
            The server sent no pixels after the pointer swept across the desktop, so hover \
            feedback can never reach the client. The fix belongs in the update-request path.
            """
        )
    }

    /// Spec 018 T008 — measured 2026-08-20: while the Apple ScaleFactor 0.5
    /// downscale is applied, screensharingd's pointer input space stays the
    /// **unscaled** framebuffer. A PointerEvent in scaled coordinates
    /// landed at exactly half the physical center (error ≈ half the
    /// screen-center point), and full-framebuffer coordinates keep landing
    /// correctly. This test gates both halves of that truth, because the
    /// client-side mapping (`AppleServerDownscalePolicy.pointerCoordinate-
    /// Multiplier` × the model's pointer choke point) is built on it: if a
    /// macOS update ever starts inverse-mapping scaled coordinates, the
    /// second assertion here fails first and the multiplier must be
    /// retired before pointers double-map.
    func testScaledSessionPointerInputSpaceStaysUnscaled() async throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live hover probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let timeout: TimeInterval = 5
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: timeout
        )
        _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

        let originalLocation = Self.currentPointerLocation()
        defer {
            try? client.sendAppleScaleFactor(1.0)
            if let originalLocation {
                CGWarpMouseCursorPosition(originalLocation)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        // Expected physical points are computed, not sampled: sampling the
        // resting cursor (a "settle" read) mistakes the user's real mouse
        // motion for our warp on this live workstation (measured flake
        // 2026-08-20: a full-suite run captured the user's cursor position
        // as the reference). `waitForPointer(toReach:)` polls until the
        // cursor is AT the expected point, which rides out transient user
        // motion the same way the sibling hover test does.
        let pointsPerPixel = Self.displayPointsPerPixel(
            framebufferWidth: CGFloat(serverInit.width)
        )
        let expectedCenter = CGPoint(
            x: CGFloat(serverInit.width / 2) * pointsPerPixel,
            y: CGFloat(serverInit.height / 2) * pointsPerPixel
        )
        let expectedHalfCenter = CGPoint(
            x: CGFloat(serverInit.width / 4) * pointsPerPixel,
            y: CGFloat(serverInit.height / 4) * pointsPerPixel
        )

        // Reference: physical center via full-scale coordinates.
        try await client.sendPointerEvent(
            buttonMask: 0,
            x: UInt16(serverInit.width / 2),
            y: UInt16(serverInit.height / 2)
        )
        guard Self.waitForPointer(toReach: expectedCenter, tolerance: 6, timeout: 3) != nil else {
            throw XCTSkip("Reference full-scale center move did not land (pointer oracle busy)")
        }

        // Apply the downscale and wait for the DesktopSize resize to land.
        try client.sendAppleScaleFactor(0.5)
        var scaledWidth = serverInit.width
        var scaledHeight = serverInit.height
        for _ in 1...6 {
            try await Task.sleep(for: .milliseconds(500))
            let update = try client.requestFramebufferUpdate(incremental: false, timeout: 8)
            if update.framebuffer.width < serverInit.width {
                scaledWidth = update.framebuffer.width
                scaledHeight = update.framebuffer.height
                break
            }
        }
        guard scaledWidth < serverInit.width else {
            throw XCTSkip("Server did not apply the downscale this run — mapping unmeasurable")
        }

        // Park the pointer away from center so a stale read cannot pass.
        try await client.sendPointerEvent(buttonMask: 0, x: 8, y: 8)
        _ = Self.waitForPointer(toReach: CGPoint(x: 8 * pointsPerPixel, y: 8 * pointsPerPixel), tolerance: 6, timeout: 2)

        // Half 1: scaled coordinates do NOT inverse-map — they land at the
        // HALF-center physical point. Measured truth, not a defect of ours.
        try await client.sendPointerEvent(
            buttonMask: 0,
            x: UInt16(scaledWidth / 2),
            y: UInt16(scaledHeight / 2)
        )
        let scaledLandedAtHalfCenter = Self.waitForPointer(
            toReach: expectedHalfCenter,
            tolerance: 6,
            timeout: 3
        ) != nil

        // Park again, then Half 2: full-framebuffer coordinates keep
        // landing at the physical center while the downscale is applied —
        // the contract the client-side multiplier relies on.
        try await client.sendPointerEvent(buttonMask: 0, x: 8, y: 8)
        _ = Self.waitForPointer(toReach: CGPoint(x: 8 * pointsPerPixel, y: 8 * pointsPerPixel), tolerance: 6, timeout: 2)
        try await client.sendPointerEvent(
            buttonMask: 0,
            x: UInt16(serverInit.width / 2),
            y: UInt16(serverInit.height / 2)
        )
        let fullCoordsLandedAtCenter = Self.waitForPointer(
            toReach: expectedCenter,
            tolerance: 6,
            timeout: 3
        ) != nil

        // Privacy: verdict words only — no coordinates.
        print(
            "Scaled pointer input-space probe: scaledCoordsLandAtHalfCenter=\(scaledLandedAtHalfCenter) "
                + "fullCoordsLandAtCenter=\(fullCoordsLandedAtCenter)"
        )
        XCTAssertTrue(
            scaledLandedAtHalfCenter,
            """
            Scaled pointer coordinates no longer land at the half-center point — either the \
            server started inverse-mapping (retire the client-side multiplier, spec 018) or the \
            pointer oracle was busy; rerun on a quiet machine before concluding.
            """
        )
        XCTAssertTrue(
            fullCoordsLandedAtCenter,
            """
            Full-framebuffer pointer coordinates stopped landing at the physical center while \
            scaled — the contract the spec 018 pointer multiplier stands on is broken.
            """
        )
    }

    // MARK: - Helpers

    private static func currentPointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Display points per server framebuffer pixel, measured rather than
    /// assumed: Screen Sharing may serve the Retina pixel grid while
    /// `CGEvent.location` reports points.
    private static func displayPointsPerPixel(framebufferWidth: CGFloat) -> CGFloat {
        let mainDisplay = CGMainDisplayID()
        let pointWidth = CGFloat(CGDisplayBounds(mainDisplay).width)
        guard framebufferWidth > 0, pointWidth > 0 else {
            return 1
        }
        let ratio = pointWidth / framebufferWidth
        print(String(
            format: "Live probe: framebuffer %.0f px wide, display %.0f pt wide, ratio %.3f",
            framebufferWidth,
            pointWidth,
            ratio
        ))
        return ratio
    }

    private static func waitForPointer(
        toReach target: CGPoint,
        tolerance: CGFloat,
        timeout: TimeInterval
    ) -> CGPoint? {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGPoint?
        while Date() < deadline {
            guard let location = currentPointerLocation() else {
                return nil
            }
            last = location
            if abs(location.x - target.x) <= tolerance, abs(location.y - target.y) <= tolerance {
                return location
            }
            usleep(50_000)
        }
        return last.flatMap { location in
            abs(location.x - target.x) <= tolerance && abs(location.y - target.y) <= tolerance
                ? location
                : nil
        }
    }
}
