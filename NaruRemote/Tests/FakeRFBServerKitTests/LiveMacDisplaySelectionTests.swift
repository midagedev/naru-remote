import Foundation
import NaruRemoteCore
import XCTest

/// Multi-display selection probe (2026-09-04 research round,
/// `artifacts/research/2026-09-04-multimonitor-mac-framebuffer-research.md`).
///
/// The founder's three-display Mac serves one ~3-desktop union framebuffer,
/// which is the root of "multi-monitor sessions look terrible on a phone".
/// The web round found Apple's real machinery — the 0x451 display-layout
/// announcement and the 0x0d SetDisplay single-display selection — documented
/// (iShareScreen reverse-engineering) only inside the Apple-auth record
/// layer. But that document's layering claim already has one measured
/// counter-example in this repo: ScaleFactor 0x08 IS honored on the plain
/// VNC-password path (spec 018). So both messages earn a live probe before
/// `specs/014` commits to user-declared layouts and client-side cropping:
///
///   - if 0x0d is honored here, single-display streaming arrives without
///     Apple auth, and 014's VNC-path design changes shape;
///   - if 0x451 rectangles arrive here, display bounds come from the wire
///     and 014's manual setup becomes a fallback.
///
/// The per-display-port branch was closed by measurement the same day
/// (5901/5902/5903 → Connection refused on the target), matching the web
/// reading that the 5900+N-per-display convention belongs to third-party
/// VNC servers, not screensharingd.
///
/// The probe classifies, it does not demand: "ignored" and "rejected" are
/// valid answers about Apple; only failing to deliver a baseline frame, or
/// a stream that cannot answer a full request after the probe, is a failure
/// of ours. Note that an *honored* selection may be visible to other active
/// viewers of the same host if screensharingd applies it globally — the
/// probe restores the combined aggregate immediately, and a fresh viewer
/// connection always gets the default aggregate.
///
/// Skipped unless `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` are set.
/// No pointer events, no keys; the only writes are the two probe messages
/// and their restore.
///
/// Measured outcomes (2026-09-04, the founder's three-display imagoworks
/// host, VNC-password path): ports 5901/5902/5903 refused (per-display
/// ports closed); 0x451 advertised → never sent (3 clean updates, no
/// layout rect); 0x0d ids 0–3 → no framebuffer resize ever (10240x5114
/// throughout; extent-only changes were damage shapes, not selections).
/// Connections also drop while another viewer session is active on the
/// host — "rejected" verdicts there describe stream drops, not server
/// answers about the id. iShareScreen's record-layer claim therefore holds
/// for the display machinery; ScaleFactor 0x08 remains the lone honored
/// exception, and `specs/014`'s display bounds must come from the user or
/// the helper.
final class LiveMacDisplaySelectionTests: XCTestCase {

    private enum ProbeError: Error {
        case emptyBaselineFrame
    }

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    /// Does the VNC-password path honor `SetDisplay` (0x0d) with
    /// combine-all clear and a candidate display id? Candidates run on one
    /// session in turn; an honored selection is restored with the documented
    /// `combine = 1` aggregate body before moving on, and a candidate that
    /// errors the stream gets a fresh connection so one bad id cannot
    /// poison the rest.
    func testAppleSetDisplaySingleDisplayProbeAgainstRealMac() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live display-selection probe")
        }

        // Every fresh baseline prints its framebuffer — if a selection
        // persists across reconnects (global rather than per-connection
        // state), this is where it shows.
        func connectAndBaseline() throws -> (
            client: RFBNetworkClient,
            extent: (width: Int, height: Int),
            framebufferSize: (width: Int, height: Int)
        ) {
            let client = RFBNetworkClient()
            _ = try client.connectSession(
                host: host,
                port: port,
                credential: .vncPassword(password),
                timeout: 10
            )
            let baseline = try Self.fullUpdateWithRetry(client)
            let extent = Self.boundingExtent(baseline.dirtyRectangles)
            guard extent.width > 0 else {
                client.disconnect()
                throw ProbeError.emptyBaselineFrame
            }
            print(
                "  baseline framebuffer=\(baseline.framebuffer.width)x\(baseline.framebuffer.height)"
                    + " extent=\(extent.width)x\(extent.height)"
            )
            return (
                client,
                extent,
                (baseline.framebuffer.width, baseline.framebuffer.height)
            )
        }

        var session = try connectAndBaseline()
        defer { session.client.disconnect() }

        var verdicts: [String] = []
        // Candidate ids: 0x09's selected_screen field treats 0 as "first"
        // and 0xffffffff as "all", so index-shaped values are the first
        // thing to try; real CGDirectDisplayIDs on Apple Silicon are also
        // small integers, which the same candidates cover.
        for candidate: UInt32 in [1, 2, 0, 3] {
            do {
                try session.client.sendAppleSetDisplay(
                    combineAllDisplays: false,
                    displayId: candidate
                )
                // Give screensharingd a beat to apply (or discard) the
                // request before sampling — same settle time as the
                // ScaleFactor probe.
                Thread.sleep(forTimeInterval: 0.7)
                let update = try Self.fullUpdateWithRetry(session.client)
                let extent = Self.boundingExtent(update.dirtyRectangles)
                guard extent.width > 0 else {
                    verdicts.append("id \(candidate): indeterminate-empty-update")
                    continue
                }
                let widthRatio = Double(extent.width) / Double(max(session.extent.width, 1))
                let heightRatio = Double(extent.height) / Double(max(session.extent.height, 1))
                // Extent alone is NOT selection evidence: a full update's
                // damage can cover half the framebuffer one run and all of
                // it the next — the first version of this probe read
                // exactly that artifact as "HONORED" (2026-09-04). A real
                // selection announces itself the way ScaleFactor's resize
                // does: a DesktopSize resize.
                let resizeAnnounced = update.didResizeDesktop
                    || update.encodingMix.desktopSizeRectangles > 0
                    || update.framebuffer.width != session.framebufferSize.width
                    || update.framebuffer.height != session.framebufferSize.height
                if resizeAnnounced {
                    print(
                        "  id \(candidate) selected:"
                            + " framebuffer=\(update.framebuffer.width)x\(update.framebuffer.height)"
                            + " didResizeDesktop=\(update.didResizeDesktop)"
                            + " desktopSizeRects=\(update.encodingMix.desktopSizeRectangles)"
                    )
                    var restoreNotes: [String] = []
                    var restored = false
                    do {
                        try session.client.sendAppleSetDisplay(combineAllDisplays: true, displayId: 0)
                    } catch {
                        restoreNotes.append("send:\(Self.safeFailureLabel(for: error))")
                    }
                    for attempt in 1...4 {
                        Thread.sleep(forTimeInterval: 0.7)
                        do {
                            let restore = try Self.fullUpdateWithRetry(session.client)
                            let restoreExtent = Self.boundingExtent(restore.dirtyRectangles)
                            if restoreExtent.width >= session.extent.width {
                                restored = true
                                break
                            }
                            restoreNotes.append("attempt\(attempt):extent=\(restoreExtent.width)")
                        } catch {
                            restoreNotes.append("attempt\(attempt):\(Self.safeFailureLabel(for: error))")
                        }
                    }
                    verdicts.append(String(
                        format: "id %u: HONORED (extent ratio %.2f x %.2f) restored=%@ [%@]",
                        candidate,
                        widthRatio,
                        heightRatio,
                        restored ? "true" : "false",
                        restoreNotes.joined(separator: ",")
                    ))
                } else if widthRatio < 0.9 || heightRatio < 0.9 {
                    verdicts.append(
                        "id \(candidate): extent-only-change"
                            + " (no resize announcement — damage shape, not selection)"
                    )
                } else {
                    verdicts.append(String(
                        format: "id %u: ignored (extent ratio %.2f x %.2f)",
                        candidate,
                        widthRatio,
                        heightRatio
                    ))
                }
            } catch {
                verdicts.append("id \(candidate): rejected (\(Self.safeFailureLabel(for: error)))")
                // A rejected id may have desynced the stream — reconnect
                // and re-baseline so the next candidate starts clean.
                session.client.disconnect()
                do {
                    session = try connectAndBaseline()
                } catch {
                    XCTFail(
                        "Could not re-baseline after candidate \(candidate): "
                            + Self.safeFailureLabel(for: error)
                    )
                    return
                }
            }
        }

        // Stream-health gate: after every candidate (and restore), a full
        // request must still be answerable — held is legitimate, silent
        // death is a client-side desync and the only failure of ours.
        var healthy = false
        do {
            let final = try session.client.requestFramebufferUpdate(incremental: false, timeout: 25)
            healthy = Self.boundingExtent(final.dirtyRectangles).width > 0
            print(
                "  final health-check framebuffer=\(final.framebuffer.width)x\(final.framebuffer.height)"
            )
        } catch let error as RFBNetworkClientError where error == .timedOut || error == .readTimedOut {
            healthy = true
        } catch {
            healthy = false
        }

        // Privacy note (constitution §IV): ratios, verdict words, and probe
        // message ids only in the summary line — the per-step framebuffer
        // prints above match LiveMacDisplayLayoutTests' local-log disclosure.
        print(
            "Apple SetDisplay probe on VNC-password path: "
                + verdicts.joined(separator: " | ")
                + " streamHealthy=\(healthy)"
        )
        XCTAssertTrue(
            healthy,
            "The probe left the session unable to answer a full request — client-side desync, not an Apple answer"
        )
    }

    /// Does the server send `AppleDisplayLayout` (0x451) rectangles to a
    /// VNC-password client that advertises the encoding? The decoder cannot
    /// parse them, so a decode error naming encoding 1105 after the
    /// advertisement is the probe's signal that the layout arrived;
    /// clean updates mean it did not. Recorded, not required — a `false`
    /// here is the finding.
    func testAppleDisplayLayoutAdvertisementProbeAgainstRealMac() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live display-selection probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 10
        )

        try client.advertiseAppleDisplayLayoutEncoding()
        Thread.sleep(forTimeInterval: 0.5)

        var verdict: String
        do {
            var deliveredUpdates = 0
            _ = try client.requestFramebufferUpdate(incremental: false, timeout: 25)
            deliveredUpdates += 1
            for _ in 0..<2 {
                guard (try? client.requestFramebufferUpdate(incremental: true, timeout: 3)) != nil else {
                    continue
                }
                deliveredUpdates += 1
            }
            verdict = "no-layout-rect (\(deliveredUpdates) clean updates after advertising 0x451)"
        } catch let error as RFBRawFramebufferDecoderError {
            if case let .unsupportedEncoding(code) = error {
                verdict = code == RFBEncoding.appleDisplayLayout
                    ? "layout-rect-arrived-undecodable (encoding 1105 observed on the wire)"
                    : "unexpected-encoding-\(code)-after-advertising-0x451"
            } else {
                verdict = "decode-error (\(Self.safeFailureLabel(for: error)))"
            }
        } catch {
            verdict = "error (\(Self.safeFailureLabel(for: error)))"
        }

        // The served union is printed once to confirm the multi-display
        // baseline the probe ran against (same disclosure as
        // LiveMacDisplayLayoutTests); everything else is verdict words.
        print(
            "Apple display-layout advertisement probe on VNC-password path: "
                + "servedFramebuffer=\(serverInit.width)x\(serverInit.height) "
                + "verdict=\(verdict)"
        )
        XCTAssertGreaterThan(
            serverInit.width,
            0,
            "The probe only means anything if the session actually established"
        )
    }

    // MARK: - Helpers

    /// One full update, retried once after a longer settle when the first
    /// attempt times out — the ScaleFactor probe measured Apple applying
    /// such requests lazily (~1s), and a display re-layout may hold the
    /// first full request for similar reasons.
    private static func fullUpdateWithRetry(
        _ client: RFBNetworkClient
    ) throws -> RFBFramebufferUpdateResult {
        do {
            return try client.requestFramebufferUpdate(incremental: false, timeout: 25)
        } catch let error as RFBNetworkClientError where error == .timedOut || error == .readTimedOut {
            Thread.sleep(forTimeInterval: 2.0)
            return try client.requestFramebufferUpdate(incremental: false, timeout: 25)
        }
    }

    private static func boundingExtent(
        _ rects: [RFBFrameDamageRect]
    ) -> (width: Int, height: Int) {
        rects.reduce((width: 0, height: 0)) { extent, rect in
            (
                width: max(extent.width, rect.x + rect.width),
                height: max(extent.height, rect.y + rect.height)
            )
        }
    }

    private static func safeFailureLabel(for error: Error) -> String {
        switch error {
        case RFBNetworkClientError.timedOut:
            return "timeout"
        case RFBNetworkClientError.readTimedOut:
            return "read-timeout"
        case RFBNetworkClientError.connectTimedOut:
            return "connect-timeout"
        case RFBNetworkClientError.connectionFailed:
            return "connection-failed"
        case RFBNetworkClientError.writeTimedOut:
            return "write-timeout"
        case RFBNetworkClientError.writeFailed:
            return "write-failed"
        case RFBNetworkClientError.notConnected:
            return "not-connected"
        case ProbeError.emptyBaselineFrame:
            return "empty-baseline-frame"
        case RFBProtocolDecoderError.unexpectedMessageType:
            return "unexpected-message"
        case RFBProtocolDecoderError.insufficientData:
            return "protocol-insufficient-data"
        case RFBRawFramebufferDecoderError.unsupportedEncoding(let code):
            return "unsupported-encoding-\(code)"
        case RFBRawFramebufferDecoderError.rectangleOutOfBounds:
            return "rectangle-out-of-bounds"
        default:
            return "unexpected-error"
        }
    }
}
