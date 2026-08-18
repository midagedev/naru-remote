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
