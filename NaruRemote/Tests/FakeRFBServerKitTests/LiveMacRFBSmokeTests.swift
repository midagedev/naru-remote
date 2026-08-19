import Foundation
import NaruRemoteCore
import XCTest

/// Live-server smoke that bypasses the simulator entirely and exercises
/// `RFBNetworkClient` against a real macOS Screen Sharing endpoint from
/// the host shell.  Skipped automatically unless `NARU_LIVE_MAC_HOST`
/// and `NARU_LIVE_MAC_PASSWORD` are set, so CI / `swift test` runs do
/// not depend on a host machine being reachable.
///
/// Goal: when the simulator E2E fails, this proves whether the bug is
/// in the protocol stack (this test fails) or the iOS plumbing (this
/// test passes; the simulator side is the suspect).
///
/// Run from the repo root:
///   NARU_LIVE_MAC_HOST=<private-host-or-ip> NARU_LIVE_MAC_PORT=5900 \
///     NARU_LIVE_MAC_PASSWORD=<redacted> \
///     swift test --filter FakeRFBServerKitTests.LiveMacRFBSmokeTests
final class LiveMacRFBSmokeTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    func testConnectFirstFrameSucceedsAgainstRealMacScreenSharing() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
        }

        let client = RFBNetworkClient()
        let serverInit: RFBServerInit
        do {
            serverInit = try client.connectFirstFrame(
                host: host,
                port: port,
                credential: .vncPassword(password),
                timeout: 8
            )
        } catch {
            XCTFail("RFBNetworkClient failed: \(safeFailureLabel(for: error))")
            return
        }

        XCTAssertEqual(client.state, .receivingFrames, "Client should be streaming after first frame")
        XCTAssertGreaterThan(serverInit.width, 0, "Server reported zero width")
        XCTAssertGreaterThan(serverInit.height, 0, "Server reported zero height")

        // Print a tiny summary so the test log doubles as the
        // verification artefact for the user.
        let frame = client.lastFrame
        let summary = """
        Connected to configured live target; \
        firstFrameMetadata=\(frame == nil ? "missing" : "present") \
        state=\(client.state.rawValue)
        """
        print(summary)

        client.disconnect()
        XCTAssertEqual(client.state, .disconnected)
    }

    /// Mirror exactly what `NaruRemoteAppModel.runConnectionAttempt`
    /// does when the connector also conforms to `RFBStreamingClient`:
    /// `connectSession` to negotiate + auth, then `RFBFramePump.run`
    /// with `maxFrames: 1` to pull one framebuffer update.  This is
    /// the path the iOS Connect button actually takes — if it works
    /// from the host shell, the bug is in the iOS plumbing (Local
    /// Network, NWConnection, env-var injection, etc.).
    func testStreamingSessionMirrorsConnectButtonPathAgainstRealMac() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
        }

        let connector: any RFBFirstFrameConnecting = RFBNetworkClient()
        guard let streamingClient = connector as? any RFBStreamingClient else {
            return XCTFail("RFBNetworkClient should conform to RFBStreamingClient")
        }

        // Mirror the model's default `frameStreamConfiguration` for
        // both connectSession and per-frame pump.nextFrame calls.
        let modelTimeout: TimeInterval = 8
        let connectStart = Date()
        do {
            _ = try streamingClient.connectSession(
                host: host,
                port: port,
                credential: .vncPassword(password),
                timeout: modelTimeout
            )
        } catch {
            XCTFail(
                "connectSession failed after \(milliseconds(since: connectStart)) ms: \(safeFailureLabel(for: error))"
            )
            return
        }
        let connectElapsed = Date().timeIntervalSince(connectStart)

        let pump = RFBFramePump(source: streamingClient)
        var firstFrame: RFBFramePumpFrame?
        let frameStart = Date()
        do {
            _ = try pump.run(
                configuration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: modelTimeout)
            ) { frame in
                firstFrame = frame
                return .stop
            }
        } catch {
            XCTFail(
                "RFBFramePump.run failed after \(milliseconds(since: frameStart)) ms: \(safeFailureLabel(for: error))"
            )
            return
        }
        let frameElapsed = Date().timeIntervalSince(frameStart)
        print("⏱ connectSession=\(connectElapsed)s firstFramePump=\(frameElapsed)s (model timeout=\(modelTimeout)s)")

        guard let firstFrame else {
            XCTFail("Pump returned no first frame")
            return
        }

        let summary = """
        Streaming path OK against configured live target; \
        firstFrameSequence=\(firstFrame.sequence) \
        capturedAt=\(firstFrame.capturedAt)
        """
        print(summary)
    }

    /// Repeat the model-default-timeout streaming attempt several
    /// times to capture firstFrame timing variance.  If even one
    /// attempt slips past the model timeout, the simulator/iPhone
    /// failure mode is explained — the default request budget is too
    /// tight for a large retina framebuffer over the current link.
    func testStreamingFirstFrameTimingVariance() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
        }

        let modelTimeout: TimeInterval = 8
        let attempts = 5
        var connectMs: [Double] = []
        var frameMs: [Double] = []
        var failures: [String] = []

        for attempt in 1...attempts {
            let client = RFBNetworkClient()
            let streamingClient: any RFBStreamingClient = client

            let connectStart = Date()
            do {
                _ = try streamingClient.connectSession(
                    host: host,
                    port: port,
                    credential: .vncPassword(password),
                    timeout: modelTimeout
                )
            } catch {
                failures.append("attempt \(attempt) connect: \(safeFailureLabel(for: error))")
                client.disconnect()
                continue
            }
            let connectElapsed = Date().timeIntervalSince(connectStart) * 1000
            connectMs.append(connectElapsed)

            let pump = RFBFramePump(source: streamingClient)
            let frameStart = Date()
            do {
                _ = try pump.run(
                    configuration: RFBFramePumpConfiguration(maxFrames: 1, requestTimeout: modelTimeout)
                ) { _ in .stop }
            } catch {
                failures.append(
                    "attempt \(attempt) firstFrame: \(safeFailureLabel(for: error)) "
                        + "(\(milliseconds(since: frameStart)) ms)"
                )
                client.disconnect()
                continue
            }
            let frameElapsed = Date().timeIntervalSince(frameStart) * 1000
            frameMs.append(frameElapsed)
            client.disconnect()
            print(String(
                format: "  attempt %d: connect=%.0f ms  firstFrame=%.0f ms",
                attempt,
                connectElapsed,
                frameElapsed
            ))
        }

        let connectMax = connectMs.max() ?? 0
        let frameMax = frameMs.max() ?? 0
        let frameAvg = frameMs.isEmpty ? 0 : frameMs.reduce(0, +) / Double(frameMs.count)
        print(String(format: "Σ connect max=%.0f ms  firstFrame avg=%.0f ms max=%.0f ms (timeout=%.0f ms)  failures=%d/%d",
                     connectMax, frameAvg, frameMax, modelTimeout * 1000, failures.count, attempts))
        if !failures.isEmpty {
            print("✗ failures:\n" + failures.joined(separator: "\n"))
        }
    }

    /// Compares the two currently shippable preference profiles against
    /// the real macOS server. ZRLE should win on bandwidth-constrained
    /// links; Hextile can win on very local links when compression CPU
    /// dominates first-frame latency. The output guides which profile
    /// should become the app default or adaptive starting point.
    func testEncodingPreferenceTimingAgainstRealMac() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
        }

        let zrle = try measureFirstFrameTiming(
            label: "ZRLE-first",
            preference: .increment2,
            host: host,
            password: password
        )
        let zrleLowCompression = try measureFirstFrameTiming(
            label: "ZRLE-first-compress0",
            preference: RFBEncodingPreference(zrle: true, compressionLevel: 0),
            host: host,
            password: password
        )
        let localLowLatency = try measureFirstFrameTiming(
            label: "Hextile-first-with-ZRLE",
            preference: RFBEncodingPreference(zrle: true, preferHextileOverZRLE: true),
            host: host,
            password: password
        )
        let hextile = try measureFirstFrameTiming(
            label: "Hextile-only",
            preference: .increment1,
            host: host,
            password: password
        )

        print(String(
            format: "Encoding preference comparison: ZRLE-first avg=%.0f ms; ZRLE-compress0 avg=%.0f ms; Hextile+ZRLE avg=%.0f ms; Hextile-only avg=%.0f ms",
            zrle.averageMs,
            zrleLowCompression.averageMs,
            localLowLatency.averageMs,
            hextile.averageMs
        ))
    }

    /// Benchmarks what happens after the first full frame on a quiet
    /// macOS Screen Sharing desktop. A production-grade server normally
    /// holds an incremental request until pixels change; if it instead
    /// returns empty updates immediately, the app model's idle backoff is
    /// what prevents a hot request / GPU publish loop.
    func testIdleIncrementalUpdateBehaviorAgainstRealMac() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let timeout: TimeInterval = 3
        _ = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: timeout
        )

        let firstStart = Date()
        _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)
        let firstMs = Date().timeIntervalSince(firstStart) * 1000

        let idleProbeTimeout: TimeInterval = 0.75
        let idleStart = Date()
        do {
            let update = try client.requestFramebufferUpdate(
                incremental: true,
                timeout: idleProbeTimeout
            )
            let idleMs = Date().timeIntervalSince(idleStart) * 1000
            let status = update.changedPixelCount == 0 ? "empty-update" : "content-update"
            print(String(
                format: "Idle incremental returned in %.0f ms; status=%@",
                idleMs,
                status
            ))
        } catch let error as RFBNetworkClientError where error == .timedOut || error == .readTimedOut {
            let heldMs = Date().timeIntervalSince(idleStart) * 1000
            print(String(
                format: "Idle incremental held for %.0f ms after firstFrame=%.0f ms (no empty-update churn)",
                heldMs,
                firstMs
            ))
        }
    }

    /// Spec 017 promotion evidence: with the *default* encoding preference,
    /// does the real macOS Screen Sharing server honor a region-scoped
    /// incremental `FramebufferUpdateRequest` — clip its damage to the
    /// rectangle, hold when nothing inside it changed (D94's starvation
    /// shape is a request that never comes back *and* wedges the stream),
    /// and leave the connection healthy for the next full request?
    ///
    /// The stimulus is this machine's own desktop, which is changing while
    /// the test runs (terminal output, simulators).
    func testRegionScopedIncrementalRequestsAgainstRealMac() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
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
        _ = try client.requestFramebufferUpdate(incremental: false, timeout: 8)

        // A corner quarter of the screen — small enough that damage outside
        // it is likely while the test runs, which is exactly what must NOT
        // be delivered for a region request.
        let region = RFBFramebufferUpdateRegion(
            x: 0,
            y: 0,
            width: UInt16(max(Int(serverInit.width) / 2, 1)),
            height: UInt16(max(Int(serverInit.height) / 2, 1))
        )

        var deliveredUpdates = 0
        var heldRequests = 0
        var outOfRegionRects = 0
        for _ in 1...5 {
            do {
                let update = try client.requestFramebufferUpdate(
                    incremental: true,
                    timeout: 1.5,
                    region: region
                )
                deliveredUpdates += 1
                for rect in update.dirtyRectangles {
                    if rect.x + rect.width > Int(region.width) + Int(region.x)
                        || rect.y + rect.height > Int(region.height) + Int(region.y) {
                        outOfRegionRects += 1
                    }
                }
            } catch let error as RFBNetworkClientError where error == .timedOut || error == .readTimedOut {
                // Held: no damage inside the region during the wait. This is
                // the correct server behavior, not a failure.
                heldRequests += 1
            }
        }

        // The stream must stay healthy after region requests: a full
        // incremental either delivers or is legitimately held, but the
        // protocol must not desync.
        var fullRecovered = true
        do {
            _ = try client.requestFramebufferUpdate(incremental: true, timeout: 3, region: nil)
        } catch let error as RFBNetworkClientError where error == .timedOut || error == .readTimedOut {
            // Held is fine; a decode/desync error is not (rethrown below).
        } catch {
            fullRecovered = false
            XCTFail("Full request after region requests desynced: \(safeFailureLabel(for: error))")
        }

        print(
            "Region-scoped incremental against live target: delivered=\(deliveredUpdates) "
                + "held=\(heldRequests) outOfRegionRects=\(outOfRegionRects) "
                + "fullRecovered=\(fullRecovered)"
        )
        XCTAssertEqual(
            deliveredUpdates + heldRequests,
            5,
            "Every region request must either deliver or be held — anything else desyncs the stream"
        )
        XCTAssertEqual(
            outOfRegionRects,
            0,
            "The server must clip damage to the requested region; out-of-region rects would make viewport-scoped requests unsafe"
        )
    }

    private func measureFirstFrameTiming(
        label: String,
        preference: RFBEncodingPreference,
        host: String,
        password: String,
        attempts: Int = 3
    ) throws -> (averageMs: Double, maxMs: Double) {
        let timeout: TimeInterval = 5
        var frameMs: [Double] = []
        var failures: [String] = []

        for attempt in 1...attempts {
            let client = RFBNetworkClient(encodingPreference: preference)
            do {
                _ = try client.connectSession(
                    host: host,
                    port: port,
                    credential: .vncPassword(password),
                    timeout: timeout
                )
                let start = Date()
                _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)
                let elapsed = Date().timeIntervalSince(start) * 1000
                frameMs.append(elapsed)
                print(String(format: "  %@ attempt %d firstFrame=%.0f ms", label, attempt, elapsed))
            } catch {
                failures.append("\(label) attempt \(attempt): \(safeFailureLabel(for: error))")
            }
            client.disconnect()
        }

        if !failures.isEmpty {
            print("encoding preference timing failures:\n" + failures.joined(separator: "\n"))
        }
        XCTAssertFalse(frameMs.isEmpty, "\(label) produced no successful first-frame samples")

        let average = frameMs.isEmpty ? 0 : frameMs.reduce(0, +) / Double(frameMs.count)
        return (average, frameMs.max() ?? 0)
    }

    private func milliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1_000).rounded())
    }

    private func safeFailureLabel(for error: Error) -> String {
        switch error {
        case RFBNetworkClientError.invalidPort:
            return "invalid-port"
        case RFBNetworkClientError.connectTimedOut:
            return "connect-timeout"
        case RFBNetworkClientError.timedOut:
            return "timeout"
        case RFBNetworkClientError.readTimedOut:
            return "read-timeout"
        case RFBNetworkClientError.incompleteTranscript:
            return "incomplete-transcript"
        case RFBNetworkClientError.connectionFailed:
            return "connection-failed"
        case RFBNetworkClientError.writeTimedOut:
            return "write-timeout"
        case RFBNetworkClientError.writeFailed:
            return "write-failed"
        case RFBNetworkClientError.authenticationRequired:
            return "authentication-required"
        case RFBNetworkClientError.unsupportedSecurityTypes:
            return "unsupported-security-types"
        case RFBNetworkClientError.unsupportedFramebufferEncoding:
            return "unsupported-framebuffer-encoding"
        case RFBNetworkClientError.notConnected:
            return "not-connected"
        case RFBNetworkClientError.unsupportedBestEffortPointerMask:
            return "unsupported-best-effort-pointer-mask"
        case RFBProtocolDecoderError.insufficientData:
            return "protocol-insufficient-data"
        case RFBProtocolDecoderError.invalidProtocolVersion:
            return "invalid-protocol-version"
        case RFBProtocolDecoderError.securityFailed:
            return "security-failed"
        case RFBProtocolDecoderError.unexpectedMessageType:
            return "unexpected-message-type"
        case RFBProtocolDecoderError.truncatedServerCutText:
            return "truncated-server-cuttext"
        case RFBProtocolDecoderError.invalidServerCutTextEncoding:
            return "invalid-server-cuttext-encoding"
        case RFBProtocolDecoderError.malformedExtendedServerCutText:
            return "malformed-extended-server-cuttext"
        case RFBRawFramebufferDecoderError.unsupportedPixelFormat:
            return "unsupported-pixel-format"
        case RFBRawFramebufferDecoderError.unsupportedEncoding:
            return "unsupported-encoding"
        case RFBRawFramebufferDecoderError.rectangleOutOfBounds:
            return "rectangle-out-of-bounds"
        case RFBRawFramebufferDecoderError.insufficientPixelData:
            return "insufficient-pixel-data"
        case RFBRawFramebufferDecoderError.framebufferSizeMismatch:
            return "framebuffer-size-mismatch"
        case RFBRawFramebufferDecoderError.copyRectOutOfBounds:
            return "copyrect-out-of-bounds"
        case RFBRawFramebufferDecoderError.malformedHextile:
            return "malformed-hextile"
        case RFBRawFramebufferDecoderError.invalidDimensions:
            return "invalid-dimensions"
        case RFBRawFramebufferDecoderError.malformedZRLE:
            return "malformed-zrle"
        case RFBRawFramebufferDecoderError.malformedCursor:
            return "malformed-cursor"
        case RFBRawFramebufferDecoderError.malformedTight:
            return "malformed-tight"
        case RFBByteReaderError.insufficientData:
            return "byte-reader-insufficient-data"
        case RFBByteReaderError.negativeRequest:
            return "byte-reader-negative-request"
        case RFBZlibInflateStream.InflateError.initializationFailed:
            return "zlib-initialization-failed"
        case RFBZlibInflateStream.InflateError.inflateFailed:
            return "zlib-inflate-failed"
        case RFBZlibInflateStream.InflateError.streamEndedUnexpectedly:
            return "zlib-stream-ended"
        case RFBTightZlibStreams.StoreError.invalidStreamIndex:
            return "tight-zlib-invalid-stream"
        case RFBVNCAuthenticationError.invalidChallengeLength:
            return "vnc-auth-invalid-challenge"
        case RFBVNCAuthenticationError.encryptionFailed:
            return "vnc-auth-encryption-failed"
        case RFBClientMessageEncodingError.unsupportedFenceFlags:
            return "client-message-encoding"
        case RFBClientMessageEncodingError.fencePayloadTooLarge:
            return "client-message-encoding"
        case RFBClientMessageEncodingError.extendedClipboardPayloadTooLarge:
            return "client-message-encoding"
        case RFBClientMessageEncodingError.zlibCompressionFailed:
            return "client-message-encoding"
        default:
            return "unexpected-error"
        }
    }
}
