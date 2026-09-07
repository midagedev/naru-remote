import CoreGraphics
import Foundation
import Network
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 042 Round D, FR-008 (amended 2026-09-07): "While `.helperVideo` is
/// active the RFB client stops issuing `FramebufferUpdateRequest`s after the
/// session's first full frame has been delivered … and resumes with a full
/// (non-incremental) request on fallback. The RFB connection stays open for
/// pointer, key, and clipboard."
///
/// ## Contract ↔ assertion table (FR-008 → tests)
///
/// | FR-008 clause | Test |
/// | --- | --- |
/// | The session's first full frame is always requested and delivered, even
///   when helper video is already the healthy primary transport before the
///   RFB handshake completes (helper video is selected first; without this
///   clause a helper-video session would never hold a framebuffer). |
///   `testHelperVideoPrimarySuspendsFramebufferRequestsWithoutClosingConnection`
///   holds the RFB handshake until helper video is healthy-primary, then
///   asserts exactly one request (incremental flag 0) arrives and the frame
///   lands (`latestFramebuffer != nil`). |
/// | While helper video is the healthy primary visual transport, no further
///   `FramebufferUpdateRequest` is issued — the pump suspends, it does not
///   poll. | Same test: after the first frame the request count must not
///   grow over a ≥ 2 s window (the old behaviour sampled at
///   `helperVideoPrimaryVNCFallbackSamplingIntervalSeconds` = 1 s, so an
///   unmodified pump fails this with ≥ 2 requests). |
/// | On fallback the next request is full (non-incremental) and out within
///   250 ms. | Same test: forced mid-session fallback
///   (`updateHelperVideoStreamHealth` with `.stalled` + bucket `.one`, the
///   drive `HelperVideoFallbackNoticeTests` uses) must produce a
///   flag-0 request within 250 ms of the health update. |
/// | Pointer/key/clipboard keep working on the same RFB connection — no
///   reconnect. | Same test: a `sendPointerDownAt` during the suspended
///   window must reach the server as a PointerEvent (type 5), and the single
///   TCP connection the server accepted stays open for the whole test. |
///
/// ## Why this is an App-test, not a FakeRFBServerKitTests file
///
/// The spec names
/// `NaruRemote/Tests/FakeRFBServerKitTests/HelperVideoPrimaryFramebufferRequestGatingTests.swift`
/// but allows "an App-test if the model cannot be driven against a socket
/// server from that target — say which and why". Every assertion above is a
/// `NaruRemoteAppModel` behaviour, and `NaruRemoteAppModel` lives in the
/// `NaruRemoteApp` module. `Package.swift` (read-only this round) gives
/// `FakeRFBServerKitTests` dependencies `[FakeRFBServerKit, NaruRemoteCore]`
/// only — it cannot import `NaruRemoteApp` — and `NaruRemoteAppTests` cannot
/// import `FakeRFBServerKit`. So this file carries a file-private minimal
/// no-auth RFB socket server plus a message recorder, mirroring
/// `FakeRFBServer`'s `noAuthFramebufferRequestResponses` mechanics
/// (handshake bytes, sequential client-message parsing, one scripted update
/// per request). Test infrastructure only.
@MainActor
final class HelperVideoPrimaryFramebufferRequestGatingTests: XCTestCase {
    private nonisolated static let helperVideoSecretRef = "helper-video-token:gating"
    private nonisolated static let pairingFingerprint = "sha256:gating"

    func testHelperVideoPrimarySuspendsFramebufferRequestsWithoutClosingConnection() async throws {
        let server = GatingNoAuthRFBServer(framebufferWidth: 2, framebufferHeight: 1)
        try server.start(on: DispatchQueue(label: "naru.gating-rfb-server"))
        defer {
            server.stop()
        }

        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "127.0.0.1",
            port: Int(server.port),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: Self.helperVideoSecretRef,
                pairingFingerprint: Self.pairingFingerprint
            )
        )
        let renderer = GatingFakeHelperVideoRenderer(displayableSequences: [1])
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id
            ),
            credentialStore: InMemoryConnectionCredentialStore(
                passwords: [Self.helperVideoSecretRef: "helper-video-secret"]
            ),
            // maxFrames nil: the loop must keep running (suspending) instead
            // of exiting; frameInterval 0: no pacing sleep may mask a poll.
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: nil, frameInterval: 0),
            streamConnectorFactory: { _, _ in
                RFBNetworkClient(encodingPreference: .localLowLatency)
            },
            helperVideoStartStream: { _, _, _, _, _ in
                Self.acceptedStartResult(
                    accessUnits: [
                        Self.accessUnit(sequence: 0, kind: .parameterSet),
                        Self.accessUnit(sequence: 1, kind: .keyframe)
                    ]
                )
            },
            helperVideoRendererFactory: { renderer }
        )
        defer {
            model.disconnect()
        }

        await model.connectSelectedProfile()

        // Helper video goes healthy-primary while the RFB handshake is still
        // gated server-side — the connect order the production model really
        // uses (`startHelperVideoStreamIfConfigured` before
        // `startFrameStream`).
        try await Self.waitUntil {
            model.snapshot.helperVideoStreamHealth.state == .healthy
                && model.snapshot.visualTransportMode == .helperVideo
        }
        server.releaseHandshake()

        // FR-008 clause 1: the first full frame is still requested and
        // delivered.
        try await Self.waitUntil {
            model.snapshot.latestFramebuffer != nil
        }
        // Let a (pre-fix) free-running pump land any would-be second request
        // before the baseline snapshot, so the count assertion cannot pass by
        // racing the loop.
        try await Task.sleep(for: .milliseconds(300))

        let baseline = server.framebufferRequestsSnapshot()
        XCTAssertEqual(
            baseline.count,
            1,
            "FR-008: exactly the session's first full FramebufferUpdateRequest may be issued; got \(baseline.count)."
        )
        XCTAssertEqual(
            baseline.first.map { !$0.incremental } ?? false,
            true,
            "FR-008: the first request must be the full (non-incremental) bootstrap frame."
        )

        // FR-008 clause 4: input keeps flowing on the same connection while
        // the visual pump is held.
        await model.sendPointerDownAt(
            viewPoint: CGPoint(x: 100, y: 50),
            viewSize: CGSize(width: 400, height: 300)
        )
        let pointerEventArrived = await server.waitForPointerEvent(timeout: 2)
        XCTAssertTrue(
            pointerEventArrived,
            "FR-008: a PointerEvent sent while the framebuffer pump is suspended must reach the server on the same RFB connection."
        )

        // FR-008 clause 2: no further request for >= 2 s while helper video
        // is the healthy primary visual transport.
        try await Task.sleep(for: .seconds(2))
        let afterQuietWindow = server.framebufferRequestsSnapshot()
        XCTAssertEqual(
            afterQuietWindow.count,
            baseline.count,
            "FR-008 violated: \(afterQuietWindow.count - baseline.count) extra FramebufferUpdateRequest(s) were issued while helper video was the healthy primary visual transport (the pump must suspend, not sample)."
        )

        // FR-008 clause 3: fallback resumes with a full (non-incremental)
        // request within 250 ms — the same drive
        // `HelperVideoFallbackNoticeTests` uses for mid-session fallback.
        let fallbackAt = Date()
        model.updateHelperVideoStreamHealth(
            HelperVideoStreamHealth(
                state: .stalled,
                sustainedUpdateBand: .stalled,
                fallbackCountBucket: .one
            )
        )
        XCTAssertEqual(model.snapshot.visualTransportMode, VisualTransportMode.vncFramebuffer)
        let fallbackRequestArrived = await server.waitForFramebufferRequestCount(
            afterQuietWindow.count + 1,
            timeout: 2
        )
        XCTAssertTrue(
            fallbackRequestArrived,
            "FR-008: fallback must resume framebuffer requests."
        )
        // FR-008 clause 3 is about the FIRST post-fallback request; the pump
        // legitimately free-runs afterwards (frameInterval 0 here), so only
        // that request's flag and latency are asserted, not exclusivity.
        let postFallbackRequests = server.framebufferRequestsSnapshot()
            .filter { $0.recordedAt >= fallbackAt }
        XCTAssertGreaterThanOrEqual(postFallbackRequests.count, 1)
        XCTAssertEqual(
            postFallbackRequests.first?.incremental,
            false,
            "FR-008: the first request after fallback must be full (non-incremental) even though frames were already delivered."
        )
        XCTAssertLessThanOrEqual(
            postFallbackRequests.first?.recordedAt.timeIntervalSince(fallbackAt) ?? .infinity,
            0.250,
            "FR-008: the post-fallback full request must be out within 250 ms."
        )
    }

    // MARK: - Fixtures

    private nonisolated static func acceptedStartResult(
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    ) -> HelperVideoStreamNetworkStartResult {
        let requestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        return HelperVideoStreamNetworkStartResult(
            requestID: requestID,
            startResponse: HelperVideoWireEnvelope(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: pairingFingerprint,
                body: HelperVideoStartStreamResponseBody(
                    result: .accepted,
                    streamDescriptor: HelperVideoStreamDescriptor()
                )
            ),
            accessUnits: accessUnits
        )
    }

    private nonisolated static func accessUnit(
        sequence: Int,
        kind: HelperVideoAccessUnitKind
    ) -> HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>> {
        HelperVideoDecodedFrame(
            envelope: HelperVideoWireEnvelope(
                messageType: .videoAccessUnit,
                profileFingerprint: pairingFingerprint,
                body: HelperVideoAccessUnitBody(sequence: sequence, kind: kind)
            ),
            binaryPayload: Data([0, 0, 0, 1, 0x65, 0x88, 0x84, 0x21])
        )
    }

    private static func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition.", file: file, line: line)
    }
}

/// Minimal `HelperVideoAccessUnitRendering` fake (same shape as the gate
/// file's `GestureFakeHelperVideoRenderer`; that one is `private` to its
/// file).
private final class GatingFakeHelperVideoRenderer: HelperVideoAccessUnitRendering {
    private let displayableSequences: Set<Int>

    init(displayableSequences: Set<Int>) {
        self.displayableSequences = displayableSequences
    }

    func enqueueDisplayableAccessUnit(
        _ decoded: HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>
    ) async throws -> Bool {
        displayableSequences.contains(decoded.envelope.body.sequence)
    }

    func flush() async {}
}

/// File-private minimal no-auth RFB socket server for the gating test.
///
/// Mirrors `FakeRFBServer`'s `Mode.noAuthFramebufferRequestResponses`
/// mechanics: a fixed no-auth handshake, sequential client-message parsing
/// (SetPixelFormat / SetEncodings / FramebufferUpdateRequest / KeyEvent /
/// PointerEvent / ClientCutText), one scripted 2-rect-wide raw update sent
/// per received `FramebufferUpdateRequest`, and a handshake gate so a test
/// can hold `ServerInit` back while helper video goes healthy-primary.
///
/// Constitution §IV: the recorder keeps counts, flags, and timestamps only —
/// no coordinates are surfaced beyond the x/y the protocol asserts on, and
/// nothing is logged.
private final class GatingNoAuthRFBServer: @unchecked Sendable {
    struct FramebufferRequestRecord {
        let incremental: Bool
        let recordedAt: Date
    }

    struct PointerEventRecord {
        let buttonMask: UInt8
        let x: UInt16
        let y: UInt16
    }

    private let framebufferWidth: Int
    private let framebufferHeight: Int
    private var queue = DispatchQueue(label: "naru.gating-rfb-server")
    private let lock = NSLock()
    private let condition = NSCondition()
    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var framebufferRequests: [FramebufferRequestRecord] = []
    private var pointerEvents: [PointerEventRecord] = []
    private var serverError: String?
    private var handshakeGateRemaining = true
    private var stopped = false
    private(set) var port: UInt16 = 0

    init(framebufferWidth: Int, framebufferHeight: Int) {
        self.framebufferWidth = framebufferWidth
        self.framebufferHeight = framebufferHeight
    }

    // MARK: Lifecycle

    func start(on queue: DispatchQueue) throws {
        // Port 0 asks for an ephemeral port; the assigned port is then
        // published through `listener.port` once ready (same construction
        // FakeRFBServer uses). The connection handler must be installed
        // BEFORE `start` — a listener without one fails EINVAL on this OS.
        guard let endpointPort = NWEndpoint.Port(rawValue: 0) else {
            throw NSError(domain: "GatingNoAuthRFBServer", code: 4)
        }
        self.queue = queue
        let listener = try NWListener(using: .tcp, on: endpointPort)
        let ready = DispatchSemaphore(value: 0)
        listener.newConnectionHandler = { connection in
            let shouldAccept: Bool = self.lock.withLock {
                guard self.connection == nil else {
                    return false
                }
                self.connection = connection
                return true
            }
            guard shouldAccept else {
                connection.cancel()
                return
            }
            self.runConnection(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                self.lock.withLock {
                    self.serverError = "listener failed: \(error)"
                }
                ready.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener

        let waited = ready.wait(timeout: .now() + 5)
        guard waited == .success else {
            throw NSError(
                domain: "GatingNoAuthRFBServer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "listener never became ready: \(lock.withLock { serverError ?? "unknown" })"]
            )
        }
        // Read on the caller side after ready (FakeRFBServer's pattern): the
        // assigned ephemeral port is published by then.
        port = listener.port?.rawValue ?? 0
        guard port != 0 else {
            throw NSError(
                domain: "GatingNoAuthRFBServer",
                code: 5,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "listener reported no port (state: \(listener.state), error: \(lock.withLock { serverError ?? "none" }))"
                ]
            )
        }
    }

    func stop() {
        lock.withLock {
            stopped = true
        }
        condition.broadcast()
        listener?.cancel()
        connection?.cancel()
    }

    /// Completes the pending handshake (sends `ServerInit`).
    func releaseHandshake() {
        condition.lock()
        handshakeGateRemaining = false
        condition.broadcast()
        condition.unlock()
    }

    // MARK: Recorder surface

    func framebufferRequestsSnapshot() -> [FramebufferRequestRecord] {
        condition.lock()
        defer { condition.unlock() }
        return framebufferRequests
    }

    /// Async by design: a synchronous `NSCondition.wait` here would block
    /// the MainActor, and the producers being waited on (the pump loop's
    /// per-iteration MainActor hop, the pointer dispatcher's validate hop)
    /// need the MainActor to make progress. Poll with yielding sleeps.
    private static func waitUntilAsync(
        _ condition: @Sendable () -> Bool,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func waitForFramebufferRequestCount(_ count: Int, timeout: TimeInterval) async -> Bool {
        await Self.waitUntilAsync({ [self] in
            condition.lock()
            defer { condition.unlock() }
            return framebufferRequests.count >= count
        }, timeout: timeout)
    }

    func waitForPointerEvent(timeout: TimeInterval) async -> Bool {
        await Self.waitUntilAsync({ [self] in
            condition.lock()
            defer { condition.unlock() }
            return !pointerEvents.isEmpty
        }, timeout: timeout)
    }

    // MARK: Wire

    private func runConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveLoop(connection)
        DispatchQueue.global().async { [weak self] in
            self?.serve()
        }
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                self.condition.lock()
                self.receiveBuffer.append(data)
                self.condition.broadcast()
                self.condition.unlock()
            }
            if error == nil && !isComplete {
                self.receiveLoop(connection)
            } else if let error {
                self.condition.lock()
                self.serverError = "receive failed: \(error)"
                self.condition.broadcast()
                self.condition.unlock()
            }
        }
    }

    private func readExactly(_ byteCount: Int, timeout: TimeInterval = 10) throws -> Data {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while receiveBuffer.count < byteCount {
            guard !stopped, deadline.timeIntervalSinceNow > 0 else {
                throw NSError(
                    domain: "GatingNoAuthRFBServer",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "timed out reading \(byteCount) byte(s)"]
                )
            }
            // Wait in short slices so a stop() broadcast that lands before
            // this reader reaches `wait` is still noticed within a slice.
            condition.wait(until: min(deadline, Date().addingTimeInterval(0.25)))
        }
        let chunk = receiveBuffer.prefix(byteCount)
        receiveBuffer.removeFirst(byteCount)
        return Data(chunk)
    }

    private func send(_ data: Data) {
        guard let connection else {
            return
        }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func serve() {
        do {
            // Handshake (byte-for-byte the no-auth transcript shape used by
            // the FakeRFBServer fixtures).
            send(Data("RFB 003.008\n".utf8))
            _ = try readExactly(12)
            send(Data([1, 1])) // one security type: None
            _ = try readExactly(1) // chosen type
            send(Data([0, 0, 0, 0])) // security result: OK
            _ = try readExactly(1) // ClientInit

            // Gate: hold ServerInit back so helper video can go
            // healthy-primary while the RFB handshake is pending.
            condition.lock()
            while handshakeGateRemaining && !stopped {
                condition.wait()
            }
            condition.unlock()
            guard !stopped else {
                return
            }

            var serverInit = Data()
            serverInit.append(contentsOf: Self.uint16Bytes(UInt16(framebufferWidth)))
            serverInit.append(contentsOf: Self.uint16Bytes(UInt16(framebufferHeight)))
            serverInit.append(
                contentsOf: [
                    32, 24, 0, 1,
                    0, 255, 0, 255, 0, 255,
                    16, 8, 0,
                    0, 0, 0
                ]
            )
            let name = Data("Desk".utf8)
            serverInit.append(contentsOf: [0, 0, 0, UInt8(name.count)])
            serverInit.append(name)
            send(serverInit)

            // Client message loop. Every FramebufferUpdateRequest is answered
            // with one scripted raw update so the pump keeps delivering
            // frames whenever it is allowed to ask.
            while !stopped {
                let typeByte = try readExactly(1)
                guard let type = typeByte.first else {
                    continue
                }
                switch type {
                case 0: // SetPixelFormat: 1 + 3 padding + 16 format
                    _ = try readExactly(19)
                case 2: // SetEncodings — measured layout: 1 type + 1 pad +
                    // 2 count + 4*N (matches this repo's encoder,
                    // RFBClientMessageEncoder.setEncodings writes [2, 0]
                    // + count, and FakeRFBServer's parser
                    // (FakeRFBServer.swift:711) reads the same 4-byte
                    // header — NOT RFC 6143's 1+3+2).
                    let header = try readExactly(3)
                    let encodingCount = Self.uint16(header[1], header[2])
                    if encodingCount > 0 {
                        _ = try readExactly(Int(encodingCount) * 4)
                    }
                case 3: // FramebufferUpdateRequest
                    let body = try readExactly(9)
                    let incremental = body[0] == 1
                    condition.lock()
                    framebufferRequests.append(
                        FramebufferRequestRecord(
                            incremental: incremental,
                            recordedAt: Date()
                        )
                    )
                    condition.broadcast()
                    condition.unlock()
                    send(Self.rawUpdateData(width: framebufferWidth, height: framebufferHeight))
                case 4: // KeyEvent
                    _ = try readExactly(7)
                case 5: // PointerEvent
                    let body = try readExactly(5)
                    condition.lock()
                    pointerEvents.append(
                        PointerEventRecord(
                            buttonMask: body[0],
                            x: Self.uint16(body[1], body[2]),
                            y: Self.uint16(body[3], body[4])
                        )
                    )
                    condition.broadcast()
                    condition.unlock()
                case 6: // ClientCutText
                    let header = try readExactly(7)
                    let length = Int(Self.uint32(header[3], header[4], header[5], header[6]))
                    if length > 0 {
                        _ = try readExactly(min(length, 1_048_576))
                    }
                default:
                    throw NSError(
                        domain: "GatingNoAuthRFBServer",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "unknown client message type \(type)"]
                    )
                }
            }
        } catch {
            lock.withLock {
                serverError = "\(error)"
            }
        }
    }

    private static func rawUpdateData(width: Int, height: Int) -> Data {
        var bytes = Data([0, 0, 0, 1]) // type 0, pad, 1 rectangle
        bytes.append(contentsOf: uint16Bytes(0))
        bytes.append(contentsOf: uint16Bytes(0))
        bytes.append(contentsOf: uint16Bytes(UInt16(width)))
        bytes.append(contentsOf: uint16Bytes(UInt16(height)))
        bytes.append(contentsOf: [0, 0, 0, 0]) // raw encoding
        bytes.append(Data(repeating: 0x40, count: width * height * 4))
        return bytes
    }

    private static func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0x00ff)]
    }

    private static func uint16(_ high: UInt8, _ low: UInt8) -> UInt16 {
        UInt16(high) << 8 | UInt16(low)
    }

    private static func uint32(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> UInt32 {
        UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }
}
