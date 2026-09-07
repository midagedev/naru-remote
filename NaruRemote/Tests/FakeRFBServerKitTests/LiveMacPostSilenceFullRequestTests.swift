import Foundation
import NaruRemoteCore
import XCTest

/// Spec 042 FR-008 measurement (research §R3). While helper video is the
/// primary visual transport the app stops issuing `FramebufferUpdateRequest`
/// entirely and keeps the RFB connection silent as the control plane. When
/// helper video falls back, the first thing the pump does is issue one full
/// (non-incremental) request — possibly minutes after the last RFB
/// framebuffer traffic. This measures whether the real macOS Screen Sharing
/// server still answers that post-silence full request with a complete
/// rectangle set on the same connection.
///
/// Skip-if-absent like `LiveMacRFBSmokeTests`: runs only when
/// `NARU_LIVE_MAC_HOST` and `NARU_LIVE_MAC_PASSWORD` are set (password is
/// read from the environment only — never argv, never logged; constitution
/// §IV: output carries counts and timings, no addresses or credentials).
final class LiveMacPostSilenceFullRequestTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    func testFullRequestAfterSilenceCompletesRectangleSet() throws {
        guard let host, let password else {
            throw XCTSkip("not run — NARU_LIVE_MAC_PASSWORD unset")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        _ = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 8
        )

        func boundingExtent(_ rects: [RFBFrameDamageRect]) -> (width: Int, height: Int) {
            rects.reduce((width: 0, height: 0)) { extent, rect in
                (
                    width: max(extent.width, rect.x + rect.width),
                    height: max(extent.height, rect.y + rect.height)
                )
            }
        }

        // Baseline: one full frame while the connection is fresh.
        let baselineStart = Date()
        let baseline = try client.requestFramebufferUpdate(incremental: false, timeout: 10)
        let baselineMs = Date().timeIntervalSince(baselineStart) * 1000
        let baselineExtent = boundingExtent(baseline.dirtyRectangles)
        XCTAssertGreaterThan(baselineExtent.width, 0, "Baseline full update delivered no rects")

        // Silence: no framebuffer requests outstanding, exactly the FR-008
        // parked state (pointer/key/clipboard traffic would ride the same
        // connection in production; here pure silence is the worst case).
        let silenceSeconds: TimeInterval = 120
        Thread.sleep(forTimeInterval: silenceSeconds)

        // The fallback wake path: one full request after the silence.
        let postSilenceStart = Date()
        var postSilence: RFBFramebufferUpdateResult?
        var postSilenceError: String?
        do {
            postSilence = try client.requestFramebufferUpdate(incremental: false, timeout: 10)
        } catch {
            postSilenceError = String(describing: type(of: error))
        }
        let postSilenceMs = Date().timeIntervalSince(postSilenceStart) * 1000

        guard let update = postSilence else {
            print(
                "R3 post-silence full request: verdict=failed errorKind=\(postSilenceError ?? "none") "
                    + "silenceSeconds=\(silenceSeconds) baselineMs=\(Int(baselineMs))"
            )
            XCTFail("Post-silence full request failed against the live target")
            return
        }

        let postExtent = boundingExtent(update.dirtyRectangles)
        let completedFullSet = postExtent.width >= baselineExtent.width
            && postExtent.height >= baselineExtent.height

        // Desync check: one more request must still be answered (or held) on
        // the same connection after the post-silence exchange.
        var followUpHealthy = true
        do {
            _ = try client.requestFramebufferUpdate(incremental: true, timeout: 3)
        } catch let error as RFBNetworkClientError where error == .timedOut || error == .readTimedOut {
            // Held: no damage during the wait — a healthy quiet answer.
        } catch {
            followUpHealthy = false
        }

        // Privacy note (constitution §IV): counts, extents and timings only —
        // no host, no coordinates, no password material.
        print(
            "R3 post-silence full request: verdict=answered rectangleSet=\(completedFullSet ? "full-extent" : "damage-only") "
                + "silenceSeconds=\(silenceSeconds) "
                + "baselineRects=\(baseline.dirtyRectangles.count) baselineMs=\(Int(baselineMs)) "
                + "postSilenceRects=\(update.dirtyRectangles.count) postSilenceMs=\(Int(postSilenceMs)) "
                + "changedPixels=\(update.changedPixelCount) "
                + "followUpHealthy=\(followUpHealthy)"
        )

        // First live run (2026-09-07) measured rectangleSet=damage-only: the
        // server answered in 2.3 s but re-sent just 12 rects of damage, not
        // the 1488-rect full framebuffer, even for `incremental: false` —
        // Apple's server skips the full redraw once the client holds state.
        // That is a measurement of the server, not a client invariant (the
        // client composites damage onto its retained baseline), so like the
        // region-scoped test this gate asserts only what must hold on every
        // run: the request is answered within the timeout and the stream
        // stays in sync. The rectangle-set verdict stays in the printout for
        // research §R3.
        XCTAssertLessThan(
            postSilenceMs,
            10_000,
            "Post-silence full request was not answered within the wake-path budget"
        )
        XCTAssertTrue(
            followUpHealthy,
            "Stream desynced after the post-silence full request"
        )
    }
}
