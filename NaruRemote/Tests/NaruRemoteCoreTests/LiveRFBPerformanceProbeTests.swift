import XCTest
@testable import NaruRemoteCore

/// Env-gated live probe against a real VNC server (the dev Mac's Screen
/// Sharing on 127.0.0.1:5900). NOT part of CI — it only runs when
/// `NARU_LIVE_VNC_PASSWORD` is set, and it prints a per-stage timing
/// report so we can locate the binding performance ceiling against a real
/// server instead of guessing.
///
/// Run:
///   NARU_LIVE_VNC_PASSWORD=... swift test \
///     --filter NaruRemoteCoreTests.LiveRFBPerformanceProbeTests
final class LiveRFBPerformanceProbeTests: XCTestCase {
    private var host: String {
        ProcessInfo.processInfo.environment["NARU_LIVE_VNC_HOST"] ?? "127.0.0.1"
    }
    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_VNC_PORT"] ?? "5900") ?? 5900
    }
    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_VNC_PASSWORD"]
    }

    func testLivePerStageProfile() throws {
        guard let password else {
            throw XCTSkip("Set NARU_LIVE_VNC_PASSWORD to run the live probe.")
        }

        // Measure the production encoding + pump profile, then two contrast
        // profiles, so we can attribute the ceiling.
        try runProfile(
            label: "PROD localLowLatency / continuous+pipeline3",
            preference: .localLowLatency,
            updateMode: .continuousUpdates,
            pipelineDepth: 3,
            password: password
        )
        try runProfile(
            label: "request/response depth1 (RTT-bound baseline)",
            preference: .localLowLatency,
            updateMode: .requestResponse,
            pipelineDepth: 1,
            password: password
        )
        try runProfile(
            label: "request/response depth3 (pipeline only)",
            preference: .localLowLatency,
            updateMode: .requestResponse,
            pipelineDepth: 3,
            password: password
        )
    }

    private func runProfile(
        label: String,
        preference: RFBEncodingPreference,
        updateMode: RFBFramePumpUpdateMode,
        pipelineDepth: Int,
        password: String
    ) throws {
        let client = RFBNetworkClient(encodingPreference: preference)
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: 8
        )
        defer { client.disconnect() }

        // Keep the screen changing so we measure update-under-change, not an
        // idle screen. Small cursor jitter near the top-left dirties a region
        // every ~16ms via the best-effort (non-blocking) input path — the
        // same path production pointer-moves use.
        let stopJitter = ManagedAtomicFlag()
        let jitter = Thread {
            var i = 0
            while !stopJitter.value {
                let x = UInt16(40 + (i % 20))
                let y = UInt16(40 + ((i / 20) % 20))
                try? client.sendBestEffortPointerEvent(buttonMask: 0, x: x, y: y)
                i += 1
                Thread.sleep(forTimeInterval: 1.0 / 60.0)
            }
        }
        jitter.start()
        defer { stopJitter.value = true }

        let pump = RFBFramePump(source: client)
        let config = RFBFramePumpConfiguration(
            maxFrames: nil,
            requestTimeout: 8,
            frameInterval: 0,
            idleFrameInterval: 0.05,
            updateMode: updateMode,
            requestPipelineDepth: pipelineDepth
        )

        var samples: [Sample] = []
        let startedAt = Date()
        let runSeconds: TimeInterval = 6
        _ = try pump.run(configuration: config) { frame in
            samples.append(
                Sample(
                    isIncremental: frame.isIncremental,
                    changedPixelCount: frame.changedPixelCount,
                    dirtyRectCount: frame.dirtyRectangles.count,
                    totalMs: frame.timing?.totalMilliseconds,
                    networkReadMs: frame.timing?.networkReadMilliseconds,
                    payloadReadMs: frame.timing?.payloadReadMilliseconds,
                    clientProcessingMs: frame.timing?.clientProcessingMilliseconds,
                    zrleInflateMs: frame.decodeMetrics.zrleInflateMilliseconds,
                    zrleApplyMs: frame.decodeMetrics.zrleTileApplyMilliseconds,
                    raw: frame.encodingMix.rawRectangles,
                    zrle: frame.encodingMix.zrleRectangles,
                    hextile: frame.encodingMix.hextileRectangles,
                    copyRect: frame.encodingMix.copyRectRectangles,
                    tight: frame.encodingMix.tightRectangles,
                    idle: frame.transportIdleTimedOut
                )
            )
            return Date().timeIntervalSince(startedAt) >= runSeconds ? .stop : .continue
        }

        report(
            label: label,
            serverName: serverInit.name,
            width: serverInit.width,
            height: serverInit.height,
            elapsed: Date().timeIntervalSince(startedAt),
            samples: samples
        )
    }

    private struct Sample {
        let isIncremental: Bool
        let changedPixelCount: Int
        let dirtyRectCount: Int
        let totalMs: Int?
        let networkReadMs: Int?
        let payloadReadMs: Int?
        let clientProcessingMs: Int?
        let zrleInflateMs: Int
        let zrleApplyMs: Int
        let raw: Int
        let zrle: Int
        let hextile: Int
        let copyRect: Int
        let tight: Int
        let idle: Bool
    }

    private func report(
        label: String,
        serverName: String,
        width: Int,
        height: Int,
        elapsed: TimeInterval,
        samples: [Sample]
    ) {
        let content = samples.filter { !$0.idle && $0.changedPixelCount > 0 }
        let contentFPS = elapsed > 0 ? Double(content.count) / elapsed : 0
        let deliveredFPS = elapsed > 0 ? Double(samples.count) / elapsed : 0

        func stats(_ values: [Int]) -> String {
            guard !values.isEmpty else { return "n/a" }
            let sorted = values.sorted()
            let avg = values.reduce(0, +) / values.count
            let p50 = sorted[sorted.count / 2]
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            return "avg \(avg) / p50 \(p50) / p95 \(p95) / max \(sorted.last!)"
        }

        let totalMix = samples.reduce(into: (raw: 0, zrle: 0, hex: 0, copy: 0, tight: 0)) {
            $0.raw += $1.raw; $0.zrle += $1.zrle; $0.hex += $1.hextile
            $0.copy += $1.copyRect; $0.tight += $1.tight
        }

        print("""

        ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ┃ \(label)
        ┃ server="\(serverName)" \(width)x\(height)  elapsed=\(String(format: "%.1f", elapsed))s
        ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        ┃ frames: \(samples.count) delivered (\(String(format: "%.1f", deliveredFPS)) fps)  |  \
        \(content.count) content (\(String(format: "%.1f", contentFPS)) fps)  |  \
        \(samples.filter { $0.idle }.count) idle
        ┃ total ms      : \(stats(samples.compactMap { $0.totalMs }))
        ┃ networkRead ms: \(stats(samples.compactMap { $0.networkReadMs }))
        ┃ payloadRead ms: \(stats(samples.compactMap { $0.payloadReadMs }))
        ┃ clientProc ms : \(stats(samples.compactMap { $0.clientProcessingMs }))
        ┃ zrleInflate ms: \(stats(samples.map { $0.zrleInflateMs }))
        ┃ zrleApply ms  : \(stats(samples.map { $0.zrleApplyMs }))
        ┃ dirtyRects    : \(stats(samples.map { $0.dirtyRectCount }))
        ┃ changedPixels : \(stats(samples.map { $0.changedPixelCount }))
        ┃ encodings     : raw=\(totalMix.raw) zrle=\(totalMix.zrle) hex=\(totalMix.hex) copy=\(totalMix.copy) tight=\(totalMix.tight)
        ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        """)
    }
}

/// Minimal cross-thread flag for the jitter loop (avoids importing Atomics).
private final class ManagedAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
