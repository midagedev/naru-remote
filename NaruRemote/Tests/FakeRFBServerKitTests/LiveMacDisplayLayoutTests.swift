import CoreGraphics
import Foundation
import XCTest
@testable import NaruRemoteCore

/// What does a real macOS Screen Sharing server tell us about a multi-display
/// desktop?
///
/// The founder hit this on a device (2026-08-19): "멀티모니터 지원에 대해서 좀
/// 해법이 필요하겠다고 느끼네 이거 한꺼번에 모니터 세개가 나오는군." Three
/// displays arrive as one wide framebuffer, so every display is tiny and none of
/// them is usable.
///
/// Which fix is even possible depends on a fact we can only get from a real
/// server, never from a fixture: does macOS *announce* its screen layout? RFB
/// carries that in the ExtendedDesktopSize pseudo-encoding (-308), whose payload
/// is an array of per-screen rectangles. We already request that encoding and
/// already parse the rectangle — but `consumeExtendedDesktopSizePayload` skips
/// the screen array (`RFBFramebufferDecoder.swift:412`). So the layout may be
/// arriving and being discarded, or may never arrive at all, and those two lead
/// to completely different features:
///
///   - announced → the client can offer "jump to Display 2" with real bounds;
///   - not announced → bounds must come from the user (or the helper), because
///     nothing in the pixel stream reliably marks where one display ends.
///
/// This probe answers it against the machine it runs on, and records what that
/// machine's own window server reports so the two can be compared.
///
/// Skipped unless `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` are set. It is
/// read-only: no pointer, no keys, no resize request.
final class LiveMacDisplayLayoutTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    /// The served framebuffer should be the union of every attached display —
    /// this is the claim behind "three monitors come out at once", stated as a
    /// check rather than an assumption.
    func testServedFramebufferSpansEveryAttachedDisplay() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live layout probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 5
        )

        let displays = Self.localDisplays()
        let union = Self.union(of: displays.map(\.pixelBounds))
        print("""
        Live layout probe:
          served framebuffer : \(serverInit.width) x \(serverInit.height)
          local displays     : \(displays.count)
        """)
        for display in displays {
            print("    - \(display.description)")
        }
        print("  union of displays  : \(Int(union.width)) x \(Int(union.height))")

        XCTAssertEqual(
            CGFloat(serverInit.width),
            union.width,
            accuracy: 1,
            "Screen Sharing is expected to serve the bounding box of all displays"
        )
        XCTAssertEqual(CGFloat(serverInit.height), union.height, accuracy: 1)
    }

    /// Does the server announce a screen layout at all? Recorded, not required:
    /// a `false` here is the finding, not a failure — it decides whether display
    /// bounds can come from the wire or must come from the user.
    func testWhetherTheServerAnnouncesItsScreenLayout() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live layout probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        _ = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 5
        )

        // The pseudo-rectangle, when a server sends one at all, rides along with
        // the first full update; take a couple of incrementals too in case this
        // one defers it.
        var extendedDesktopSizeRectangles = 0
        var desktopSizeRectangles = 0
        let first = try client.requestFramebufferUpdate(incremental: false, timeout: 5)
        extendedDesktopSizeRectangles += first.encodingMix.extendedDesktopSizeRectangles
        desktopSizeRectangles += first.encodingMix.desktopSizeRectangles
        for _ in 0..<2 {
            guard let update = try? client.requestFramebufferUpdate(incremental: true, timeout: 2) else {
                continue
            }
            extendedDesktopSizeRectangles += update.encodingMix.extendedDesktopSizeRectangles
            desktopSizeRectangles += update.encodingMix.desktopSizeRectangles
        }

        print("""
        Live layout probe: ExtendedDesktopSize(-308) rectangles=\(extendedDesktopSizeRectangles), \
        DesktopSize(-223) rectangles=\(desktopSizeRectangles) across 3 updates. \
        \(extendedDesktopSizeRectangles > 0
            ? "The layout is on the wire — parse the screen array instead of skipping it."
            : "No layout on the wire — display bounds must come from the user or the helper.")
        """)

        XCTAssertGreaterThan(
            first.framebuffer.width,
            0,
            "The probe only means anything if the session actually produced a frame"
        )
    }

    // MARK: - Helpers

    private struct LocalDisplay {
        let id: CGDirectDisplayID
        let pointBounds: CGRect
        let pixelBounds: CGRect

        var description: String {
            String(
                format: "display %u: %.0fx%.0f px at (%.0f, %.0f) px  [%.0fx%.0f pt]",
                id,
                pixelBounds.width, pixelBounds.height,
                pixelBounds.origin.x, pixelBounds.origin.y,
                pointBounds.width, pointBounds.height
            )
        }
    }

    /// Every attached display, with its bounds expressed in backing pixels —
    /// the unit the framebuffer uses. `CGDisplayBounds` is in points, so a
    /// Retina display measures half its served width there.
    private static func localDisplays() -> [LocalDisplay] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }

        return ids.prefix(Int(count)).map { id in
            let pointBounds = CGDisplayBounds(id)
            let mode = CGDisplayCopyDisplayMode(id)
            let pixelWidth = CGFloat(mode?.pixelWidth ?? Int(pointBounds.width))
            let pixelHeight = CGFloat(mode?.pixelHeight ?? Int(pointBounds.height))
            let scale = pointBounds.width > 0 ? pixelWidth / pointBounds.width : 1
            return LocalDisplay(
                id: id,
                pointBounds: pointBounds,
                pixelBounds: CGRect(
                    x: pointBounds.origin.x * scale,
                    y: pointBounds.origin.y * scale,
                    width: pixelWidth,
                    height: pixelHeight
                )
            )
        }
    }

    private static func union(of rects: [CGRect]) -> CGRect {
        rects.reduce(CGRect.null) { $0.union($1) }
    }
}
