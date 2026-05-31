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
///   NARU_LIVE_MAC_HOST=192.168.45.148 NARU_LIVE_MAC_PORT=5900 \
    ///   NARU_LIVE_MAC_PASSWORD=<ask-the-user> \
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
        } catch let error as RFBNetworkClientError {
            XCTFail("RFBNetworkClient failed at network/auth layer: \(error)")
            return
        } catch let error as RFBProtocolDecoderError {
            XCTFail("RFBNetworkClient failed at protocol-decoder layer: \(error)")
            return
        } catch {
            XCTFail("RFBNetworkClient failed with unexpected error: \(error)")
            return
        }

        XCTAssertEqual(client.state, .receivingFrames, "Client should be streaming after first frame")
        XCTAssertGreaterThan(serverInit.width, 0, "Server reported zero width")
        XCTAssertGreaterThan(serverInit.height, 0, "Server reported zero height")

        // Print a tiny summary so the test log doubles as the
        // verification artefact for the user.
        let frame = client.lastFrame
        let summary = """
        ✓ Connected to \(host):\(port) — server name="\(serverInit.name)" \
        size=\(serverInit.width)x\(serverInit.height) \
        firstFrame=\(frame.map { "\($0.width)x\($0.height)" } ?? "nil") \
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

        // Mirror the model's default `frameStreamConfiguration` —
        // `requestTimeout: 3` for both connectSession and per-frame
        // pump.nextFrame calls.  This is the tight budget the iOS
        // Connect button actually runs under.
        let modelTimeout: TimeInterval = 3
        let serverInit: RFBServerInit
        let connectStart = Date()
        do {
            serverInit = try streamingClient.connectSession(
                host: host,
                port: port,
                credential: .vncPassword(password),
                timeout: modelTimeout
            )
        } catch let error as RFBNetworkClientError {
            XCTFail("connectSession failed at network/auth layer after \(Date().timeIntervalSince(connectStart))s: \(error)")
            return
        } catch let error as RFBProtocolDecoderError {
            XCTFail("connectSession failed at protocol-decoder layer after \(Date().timeIntervalSince(connectStart))s: \(error)")
            return
        } catch {
            XCTFail("connectSession failed after \(Date().timeIntervalSince(connectStart))s: \(error)")
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
            XCTFail("RFBFramePump.run failed after \(Date().timeIntervalSince(frameStart))s: \(error)")
            return
        }
        let frameElapsed = Date().timeIntervalSince(frameStart)
        print("⏱ connectSession=\(connectElapsed)s firstFramePump=\(frameElapsed)s (model timeout=\(modelTimeout)s)")

        guard let firstFrame else {
            XCTFail("Pump returned no first frame")
            return
        }

        let summary = """
        ✓ Streaming path OK — \(host):\(port) "\(serverInit.name)" \
        size=\(serverInit.width)x\(serverInit.height) \
        firstFrame=\(firstFrame.framebuffer.width)x\(firstFrame.framebuffer.height) \
        capturedAt=\(firstFrame.capturedAt)
        """
        print(summary)
    }

    /// Repeat the model-default-timeout streaming attempt several
    /// times to capture firstFrame timing variance.  If even one
    /// attempt slips past 3s, the simulator/iPhone failure mode is
    /// explained — the model's default `requestTimeout: 3` is too
    /// tight for a 3024x1964 retina framebuffer over typical Wi-Fi.
    func testStreamingFirstFrameTimingVariance() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run live smoke")
        }

        let modelTimeout: TimeInterval = 3
        let attempts = 5
        var connectMs: [Double] = []
        var frameMs: [Double] = []
        var failures: [String] = []

        for attempt in 1...attempts {
            let client = RFBNetworkClient()
            let streamingClient: any RFBStreamingClient = client

            let connectStart = Date()
            let serverInit: RFBServerInit
            do {
                serverInit = try streamingClient.connectSession(
                    host: host,
                    port: port,
                    credential: .vncPassword(password),
                    timeout: modelTimeout
                )
            } catch {
                failures.append("attempt \(attempt) connect: \(error)")
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
                failures.append("attempt \(attempt) firstFrame: \(error) (\(Date().timeIntervalSince(frameStart) * 1000) ms)")
                client.disconnect()
                continue
            }
            let frameElapsed = Date().timeIntervalSince(frameStart) * 1000
            frameMs.append(frameElapsed)
            client.disconnect()
            print(String(format: "  attempt %d: connect=%.0f ms  firstFrame=%.0f ms  size=%dx%d",
                         attempt, connectElapsed, frameElapsed,
                         serverInit.width, serverInit.height))
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
        let serverInit = try client.connectSession(
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
            print(String(
                format: "Idle incremental returned in %.0f ms on %dx%d; changedPixels=%d dirtyRects=%d",
                idleMs,
                serverInit.width,
                serverInit.height,
                update.changedPixelCount,
                update.dirtyRectangles.count
            ))
        } catch RFBNetworkClientError.timedOut {
            let heldMs = Date().timeIntervalSince(idleStart) * 1000
            print(String(
                format: "Idle incremental held for %.0f ms after firstFrame=%.0f ms on %dx%d (no empty-update churn)",
                heldMs,
                firstMs,
                serverInit.width,
                serverInit.height
            ))
        }
    }
}
