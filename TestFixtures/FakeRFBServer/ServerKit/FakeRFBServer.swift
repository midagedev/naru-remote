import Foundation
import Network

public final class FakeRFBServer: @unchecked Sendable {
    public enum Mode: Sendable {
        case transcript
        case noAuthHandshake
        case noAuthFramebufferUpdates([Data])
        /// Sends each opaque server message immediately after the no-auth
        /// handshake completes, without expecting `FramebufferUpdateRequest`
        /// messages in between. Useful for `ServerCutText` and other
        /// server-initiated messages.
        case noAuthServerMessages([Data])
        case vncAuthentication(
            challenge: Data,
            expectedResponse: Data,
            securityResult: UInt32,
            frameUpdates: [Data]?
        )
    }

    private let listener: NWListener
    private let transcript: FakeRFBTranscript
    private let queue: DispatchQueue
    private let mode: Mode
    private let clientMessageRecorder: FakeRFBClientMessageRecorder?

    public init(
        transcript: FakeRFBTranscript,
        port: UInt16 = 0,
        mode: Mode = .transcript,
        clientMessageRecorder: FakeRFBClientMessageRecorder? = nil,
        queue: DispatchQueue = DispatchQueue(label: "naru.fake-rfb-server")
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw FakeRFBServerError.invalidPort(port)
        }

        self.listener = try NWListener(using: .tcp, on: endpointPort)
        self.transcript = transcript
        self.queue = queue
        self.mode = mode
        self.clientMessageRecorder = clientMessageRecorder
    }

    public func start(timeout: TimeInterval = 2) throws -> UInt16 {
        let startState = ListenerStartState()

        listener.newConnectionHandler = { [queue, transcript, mode, clientMessageRecorder] connection in
            connection.start(queue: queue)
            switch mode {
            case .transcript:
                connection.send(content: transcript.bytes, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            case .noAuthHandshake:
                FakeRFBNoAuthHandshakeConnection(
                    connection: connection,
                    transcript: transcript,
                    clientMessageRecorder: clientMessageRecorder,
                    frameUpdates: nil
                ).start()
            case .noAuthFramebufferUpdates(let frameUpdates):
                FakeRFBNoAuthHandshakeConnection(
                    connection: connection,
                    transcript: transcript,
                    clientMessageRecorder: clientMessageRecorder,
                    frameUpdates: frameUpdates
                ).start()
            case .noAuthServerMessages(let serverMessages):
                FakeRFBNoAuthServerMessagesConnection(
                    connection: connection,
                    transcript: transcript,
                    serverMessages: serverMessages
                ).start()
            case .vncAuthentication(let challenge, let expectedResponse, let securityResult, let frameUpdates):
                FakeRFBVNCAuthenticationConnection(
                    connection: connection,
                    transcript: transcript,
                    challenge: challenge,
                    expectedResponse: expectedResponse,
                    securityResult: securityResult,
                    frameUpdates: frameUpdates
                ).start()
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                startState.markReady()
            case .failed(let error):
                startState.markFailed(error)
            default:
                break
            }
        }

        listener.start(queue: queue)
        try startState.wait(timeout: timeout)

        guard let port = listener.port?.rawValue else {
            throw FakeRFBServerError.portUnavailable
        }

        return port
    }

    public func stop() {
        listener.cancel()
    }

    deinit {
        stop()
    }
}

private final class FakeRFBNoAuthHandshakeConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let transcript: FakeRFBTranscript
    private let clientMessageRecorder: FakeRFBClientMessageRecorder?
    private let frameUpdates: [Data]?

    init(
        connection: NWConnection,
        transcript: FakeRFBTranscript,
        clientMessageRecorder: FakeRFBClientMessageRecorder?,
        frameUpdates: [Data]?
    ) {
        self.connection = connection
        self.transcript = transcript
        self.clientMessageRecorder = clientMessageRecorder
        self.frameUpdates = frameUpdates
    }

    func start() {
        send(transcript.bytes[safe: 0..<12]) { [self] in
            receive(byteCount: 12) { [self] in
                send(transcript.bytes[safe: 12..<14]) { [self] in
                    receive(byteCount: 1) { [self] in
                        send(transcript.bytes[safe: 14..<18]) { [self] in
                            receive(byteCount: 1) { [self] in
                                send(transcript.bytes[safe: 18..<46]) { [self] in
                                    // The production client sends SetEncodings
                                    // immediately after ClientInit (spec 004
                                    // FR-001).  Drain it before the fixed-size
                                    // FramebufferUpdateRequest reads so the
                                    // framing stays aligned.
                                    receiveSetEncodings { [self] in
                                        receiveFramebufferRequestsAndSendUpdates()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func send(_ data: Data, completion: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            if error == nil {
                completion()
            } else {
                self.connection.cancel()
            }
        })
    }

    private func receiveFramebufferRequestsAndSendUpdates() {
        let updates = frameUpdates ?? [transcript.bytes[safe: 46..<62]]
        receiveFramebufferRequestsAndSendUpdates(ArraySlice(updates))
    }

    private func receiveFramebufferRequestsAndSendUpdates(_ updates: ArraySlice<Data>) {
        guard let update = updates.first else {
            if let clientMessageRecorder {
                receiveClientMessages(into: clientMessageRecorder)
            } else {
                connection.cancel()
            }
            return
        }

        receive(byteCount: 10) { [self] in
            send(update) { [self] in
                receiveFramebufferRequestsAndSendUpdates(updates.dropFirst())
            }
        }
    }

    private func receive(byteCount: Int, completion: @escaping @Sendable () -> Void) {
        connection.receive(
            minimumIncompleteLength: byteCount,
            maximumLength: byteCount
        ) { [connection] _, _, _, error in
            if error == nil {
                completion()
            } else {
                connection.cancel()
            }
        }
    }

    /// Drains exactly one `SetEncodings` message (RFC 6143 §7.5.2,
    /// type 2) — 4-byte header (type, pad, u16 count) then `count`×4
    /// bytes — recording it as a control message so the negotiation
    /// assertion test can inspect it without polluting the main client
    /// byte stream.
    private func receiveSetEncodings(completion: @escaping @Sendable () -> Void) {
        receiveData(byteCount: 4) { [self] header in
            let bytes = [UInt8](header)
            let count = Int(bytes[2]) << 8 | Int(bytes[3])
            let bodyLength = count * 4
            guard bodyLength > 0 else {
                clientMessageRecorder?.appendControlMessage(header)
                completion()
                return
            }
            receiveData(byteCount: bodyLength) { [self] body in
                clientMessageRecorder?.appendControlMessage(header + body)
                completion()
            }
        }
    }

    private func receiveData(byteCount: Int, completion: @escaping @Sendable (Data) -> Void) {
        connection.receive(
            minimumIncompleteLength: byteCount,
            maximumLength: byteCount
        ) { [connection] data, _, _, error in
            if let data, data.count == byteCount, error == nil {
                completion(data)
            } else {
                connection.cancel()
            }
        }
    }

    private func receiveClientMessages(into recorder: FakeRFBClientMessageRecorder) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4096
        ) { [connection] data, _, isComplete, error in
            if let data, !data.isEmpty {
                recorder.append(data)
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }

            self.receiveClientMessages(into: recorder)
        }
    }
}

private final class FakeRFBNoAuthServerMessagesConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let transcript: FakeRFBTranscript
    private let serverMessages: [Data]

    init(
        connection: NWConnection,
        transcript: FakeRFBTranscript,
        serverMessages: [Data]
    ) {
        self.connection = connection
        self.transcript = transcript
        self.serverMessages = serverMessages
    }

    func start() {
        send(transcript.bytes[safe: 0..<12]) { [self] in
            receive(byteCount: 12) { [self] in
                send(transcript.bytes[safe: 12..<14]) { [self] in
                    receive(byteCount: 1) { [self] in
                        send(transcript.bytes[safe: 14..<18]) { [self] in
                            receive(byteCount: 1) { [self] in
                                send(transcript.bytes[safe: 18..<46]) { [self] in
                                    receiveSetEncodings { [self] in
                                        sendServerMessages(ArraySlice(serverMessages))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sendServerMessages(_ remaining: ArraySlice<Data>) {
        guard let next = remaining.first else {
            connection.cancel()
            return
        }

        send(next) { [self] in
            sendServerMessages(remaining.dropFirst())
        }
    }

    private func send(_ data: Data, completion: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            if error == nil {
                completion()
            } else {
                self.connection.cancel()
            }
        })
    }

    private func receive(byteCount: Int, completion: @escaping @Sendable () -> Void) {
        connection.receive(
            minimumIncompleteLength: byteCount,
            maximumLength: byteCount
        ) { [connection] _, _, _, error in
            if error == nil {
                completion()
            } else {
                connection.cancel()
            }
        }
    }

    private func receiveSetEncodings(completion: @escaping @Sendable () -> Void) {
        receiveData(byteCount: 4) { [self] header in
            let bytes = [UInt8](header)
            let count = Int(bytes[2]) << 8 | Int(bytes[3])
            let bodyLength = count * 4
            guard bodyLength > 0 else {
                completion()
                return
            }
            receiveData(byteCount: bodyLength) { _ in
                completion()
            }
        }
    }

    private func receiveData(byteCount: Int, completion: @escaping @Sendable (Data) -> Void) {
        connection.receive(
            minimumIncompleteLength: byteCount,
            maximumLength: byteCount
        ) { [connection] data, _, _, error in
            if let data, data.count == byteCount, error == nil {
                completion(data)
            } else {
                connection.cancel()
            }
        }
    }
}

private final class FakeRFBVNCAuthenticationConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let transcript: FakeRFBTranscript
    private let challenge: Data
    private let expectedResponse: Data
    private let securityResult: UInt32
    private let frameUpdates: [Data]?

    init(
        connection: NWConnection,
        transcript: FakeRFBTranscript,
        challenge: Data,
        expectedResponse: Data,
        securityResult: UInt32,
        frameUpdates: [Data]?
    ) {
        self.connection = connection
        self.transcript = transcript
        self.challenge = challenge
        self.expectedResponse = expectedResponse
        self.securityResult = securityResult
        self.frameUpdates = frameUpdates
    }

    func start() {
        send(transcript.bytes[safe: 0..<12]) { [self] in
            receive(byteCount: 12) { [self] _ in
                send(Data([1, 2])) { [self] in
                    receive(byteCount: 1) { [self] selection in
                        guard selection == Data([2]) else {
                            connection.cancel()
                            return
                        }

                        send(challenge) { [self] in
                            receive(byteCount: 16) { [self] response in
                                let status = response == expectedResponse ? securityResult : 1
                                send(Self.uint32Bytes(status)) { [self] in
                                    guard status == 0 else {
                                        connection.cancel()
                                        return
                                    }

                                    receive(byteCount: 1) { [self] _ in
                                        send(transcript.bytes[safe: 18..<46]) { [self] in
                                            // Drain the post-ClientInit
                                            // SetEncodings (spec 004 FR-001)
                                            // before the fixed-size update
                                            // request reads.
                                            receiveSetEncodings { [self] in
                                                receiveFramebufferRequestsAndSendUpdates()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func send(_ data: Data, completion: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in
            if error == nil {
                completion()
            } else {
                self.connection.cancel()
            }
        })
    }

    private func receive(
        byteCount: Int,
        completion: @escaping @Sendable (Data) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: byteCount,
            maximumLength: byteCount
        ) { [connection] data, _, _, error in
            if let data, data.count == byteCount, error == nil {
                completion(data)
            } else {
                connection.cancel()
            }
        }
    }

    private func receiveSetEncodings(completion: @escaping @Sendable () -> Void) {
        receive(byteCount: 4) { [self] header in
            let bytes = [UInt8](header)
            let count = Int(bytes[2]) << 8 | Int(bytes[3])
            let bodyLength = count * 4
            guard bodyLength > 0 else {
                completion()
                return
            }
            receive(byteCount: bodyLength) { _ in
                completion()
            }
        }
    }

    private func receiveFramebufferRequestsAndSendUpdates() {
        let updates = frameUpdates ?? [transcript.bytes[safe: 46..<62]]
        receiveFramebufferRequestsAndSendUpdates(ArraySlice(updates))
    }

    private func receiveFramebufferRequestsAndSendUpdates(_ updates: ArraySlice<Data>) {
        guard let update = updates.first else {
            connection.cancel()
            return
        }

        receive(byteCount: 10) { [self] _ in
            send(update) { [self] in
                receiveFramebufferRequestsAndSendUpdates(updates.dropFirst())
            }
        }
    }

    private static func uint32Bytes(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ])
    }
}

public final class FakeRFBClientMessageRecorder: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var recordedBytes = Data()
    private var recordedControlMessages: [Data] = []
    private var recordedPointerEvents: [FakeRFBPointerEvent] = []
    private var recordedKeyEvents: [FakeRFBKeyEvent] = []
    private var pointerScanCursor: Int = 0

    public init() {}

    public var bytes: Data {
        lock.lock()
        defer { lock.unlock() }
        return recordedBytes
    }

    /// Control messages (e.g. `SetEncodings`) the fake server drained
    /// during the handshake, BEFORE the framebuffer-update loop, kept
    /// out of the main `bytes`/`pointerEvents`/`keyEvents` stream so
    /// existing recorder tests stay byte-for-byte unchanged. Each entry
    /// is one complete client message as it appeared on the wire.
    public var controlMessages: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return recordedControlMessages
    }

    /// Records one fully-framed control message drained during the
    /// handshake. Called by the fake server's `SetEncodings` drain.
    public func appendControlMessage(_ data: Data) {
        lock.lock()
        recordedControlMessages.append(data)
        lock.unlock()
        semaphore.signal()
    }

    /// Blocks until at least `expected` handshake control messages have
    /// been drained, or the timeout elapses (spec 004 SetEncodings
    /// negotiation assertion).
    public func waitForControlMessages(
        _ expected: Int,
        timeout: TimeInterval = 2
    ) throws -> [Data] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let snapshot = controlMessages
            if snapshot.count >= expected {
                return snapshot
            }

            _ = semaphore.wait(timeout: .now() + 0.05)
        }

        throw FakeRFBServerError.clientMessageTimedOut(
            expected: expected,
            actual: controlMessages.count
        )
    }

    /// Snapshot of `(buttonMask, x, y)` `PointerEvent` triples decoded
    /// out of the raw client byte stream so far. Only complete 6-byte
    /// frames are surfaced; a trailing partial frame is buffered until
    /// the remaining bytes arrive (see `scanForPointerEventsLocked`).
    /// Each call returns an immutable snapshot — the underlying buffer
    /// keeps growing as more bytes arrive.
    public var pointerEvents: [FakeRFBPointerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPointerEvents
    }

    /// Snapshot of `(keysym, isDown)` `KeyEvent` pairs decoded out of
    /// the raw client byte stream so far (RFC 6143 §7.5.4, message
    /// type 4). Only complete 8-byte frames are surfaced; a trailing
    /// partial frame is buffered until the remaining bytes arrive
    /// (see `scanForPointerEventsLocked`, which also handles type 4
    /// frames). Each call returns an immutable snapshot.
    public var keyEvents: [FakeRFBKeyEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedKeyEvents
    }

    public func append(_ data: Data) {
        lock.lock()
        recordedBytes.append(data)
        scanForPointerEventsLocked()
        lock.unlock()
        semaphore.signal()
    }

    public func waitForByteCount(_ expectedByteCount: Int, timeout: TimeInterval = 2) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let currentBytes = bytes
            if currentBytes.count >= expectedByteCount {
                return currentBytes
            }

            _ = semaphore.wait(timeout: .now() + 0.05)
        }

        throw FakeRFBServerError.clientMessageTimedOut(
            expected: expectedByteCount,
            actual: bytes.count
        )
    }

    /// Blocks the caller until at least `expected` `PointerEvent`
    /// triples have been decoded out of the recorded byte stream, or
    /// the timeout elapses. Used by integration tests that drive the
    /// production client across an interactive handshake — the byte
    /// stream contains framebuffer-update requests too, so a raw
    /// `waitForByteCount` would race the pointer events.
    public func waitForPointerEvents(
        _ expected: Int,
        timeout: TimeInterval = 2
    ) throws -> [FakeRFBPointerEvent] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let snapshot = pointerEvents
            if snapshot.count >= expected {
                return snapshot
            }

            _ = semaphore.wait(timeout: .now() + 0.05)
        }

        throw FakeRFBServerError.clientMessageTimedOut(
            expected: expected,
            actual: pointerEvents.count
        )
    }

    /// Blocks the caller until at least `expected` `KeyEvent` pairs
    /// have been decoded out of the recorded byte stream, or the
    /// timeout elapses. Same shape as `waitForPointerEvents` —
    /// integration tests for Direct Keystroke Mode use this to
    /// assert ordered byte-level wire output without racing the
    /// FramebufferUpdateRequest stream.
    public func waitForKeyEvents(
        _ expected: Int,
        timeout: TimeInterval = 2
    ) throws -> [FakeRFBKeyEvent] {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let snapshot = keyEvents
            if snapshot.count >= expected {
                return snapshot
            }

            _ = semaphore.wait(timeout: .now() + 0.05)
        }

        throw FakeRFBServerError.clientMessageTimedOut(
            expected: expected,
            actual: keyEvents.count
        )
    }

    /// Walks the recorded byte buffer forward from `pointerScanCursor`,
    /// dispatching each known client message type to its frame size and
    /// appending a `FakeRFBPointerEvent` for every complete message-type
    /// 5 frame. Unknown message types abort the scan — production tests
    /// never feed unknown types so reaching that branch indicates a
    /// fixture/protocol mismatch the caller should investigate. Caller
    /// must already hold `lock`.
    private func scanForPointerEventsLocked() {
        var cursor = pointerScanCursor
        while cursor < recordedBytes.count {
            let messageType = recordedBytes[cursor]
            let frameLength: Int
            switch messageType {
            case 0:
                // SetPixelFormat: 1 + 3 padding + 16 pixel format
                frameLength = 20
            case 2:
                // SetEncodings: 1 + 1 padding + 2 number-of-encodings + 4*N
                guard cursor + 4 <= recordedBytes.count else {
                    pointerScanCursor = cursor
                    return
                }
                let count = Int(recordedBytes[cursor + 2]) << 8 | Int(recordedBytes[cursor + 3])
                frameLength = 4 + count * 4
            case 3:
                // FramebufferUpdateRequest
                frameLength = 10
            case 4:
                // KeyEvent
                frameLength = 8
            case 5:
                // PointerEvent: 1 + 1 mask + 2 x + 2 y
                frameLength = 6
            case 6:
                // ClientCutText: 1 + 3 padding + 4 length + N text
                guard cursor + 8 <= recordedBytes.count else {
                    pointerScanCursor = cursor
                    return
                }
                let length =
                    UInt32(recordedBytes[cursor + 4]) << 24 |
                    UInt32(recordedBytes[cursor + 5]) << 16 |
                    UInt32(recordedBytes[cursor + 6]) << 8 |
                    UInt32(recordedBytes[cursor + 7])
                frameLength = 8 + Int(length)
            default:
                // Unknown message type — stop scanning so callers see
                // exactly the frames decoded up to this point.
                pointerScanCursor = cursor
                return
            }

            guard cursor + frameLength <= recordedBytes.count else {
                pointerScanCursor = cursor
                return
            }

            if messageType == 5 {
                let mask = recordedBytes[cursor + 1]
                let x = UInt16(recordedBytes[cursor + 2]) << 8 | UInt16(recordedBytes[cursor + 3])
                let y = UInt16(recordedBytes[cursor + 4]) << 8 | UInt16(recordedBytes[cursor + 5])
                recordedPointerEvents.append(FakeRFBPointerEvent(buttonMask: mask, x: x, y: y))
            }

            if messageType == 4 {
                let isDown = recordedBytes[cursor + 1] == 1
                let keysym =
                    UInt32(recordedBytes[cursor + 4]) << 24 |
                    UInt32(recordedBytes[cursor + 5]) << 16 |
                    UInt32(recordedBytes[cursor + 6]) << 8 |
                    UInt32(recordedBytes[cursor + 7])
                recordedKeyEvents.append(FakeRFBKeyEvent(keysym: keysym, isDown: isDown))
            }

            cursor += frameLength
        }
        pointerScanCursor = cursor
    }
}

/// Single `PointerEvent` triple decoded by the fake server's recording
/// state machine. Mirrors the wire fields verbatim — the recorder
/// performs no view→framebuffer mapping.
public struct FakeRFBPointerEvent: Equatable, Sendable {
    public let buttonMask: UInt8
    public let x: UInt16
    public let y: UInt16

    public init(buttonMask: UInt8, x: UInt16, y: UInt16) {
        self.buttonMask = buttonMask
        self.x = x
        self.y = y
    }
}

/// Single `KeyEvent` pair decoded by the fake server's recording
/// state machine (RFC 6143 §7.5.4, message type 4). Mirrors the wire
/// fields verbatim — the keysym is the X11 keysym as it appeared on
/// the wire, big-endian decoded.
public struct FakeRFBKeyEvent: Equatable, Sendable {
    public let keysym: UInt32
    public let isDown: Bool

    public init(keysym: UInt32, isDown: Bool) {
        self.keysym = keysym
        self.isDown = isDown
    }
}

private extension Data {
    subscript(safe range: Range<Int>) -> Data {
        precondition(range.lowerBound >= 0)
        precondition(range.upperBound <= count)

        return subdata(in: range)
    }
}

public enum FakeRFBServerError: Error, Equatable, LocalizedError {
    case invalidPort(UInt16)
    case startTimedOut
    case listenerFailed(String)
    case portUnavailable
    case clientMessageTimedOut(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid fake RFB server port: \(port)"
        case .startTimedOut:
            return "Timed out while starting fake RFB server."
        case .listenerFailed(let message):
            return "Fake RFB server listener failed: \(message)"
        case .portUnavailable:
            return "Fake RFB server did not publish a listening port."
        case .clientMessageTimedOut(let expected, let actual):
            return "Timed out waiting for client messages. Expected \(expected) bytes, received \(actual)."
        }
    }
}

private final class ListenerStartState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Void, FakeRFBServerError>?

    func markReady() {
        complete(.success(()))
    }

    func markFailed(_ error: NWError) {
        complete(.failure(.listenerFailed(error.localizedDescription)))
    }

    func wait(timeout: TimeInterval) throws {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw FakeRFBServerError.startTimedOut
        }

        switch currentResult {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw FakeRFBServerError.startTimedOut
        }
    }

    private var currentResult: Result<Void, FakeRFBServerError>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private func complete(_ result: Result<Void, FakeRFBServerError>) {
        lock.lock()
        let shouldSignal = self.result == nil
        if shouldSignal {
            self.result = result
        }
        lock.unlock()

        if shouldSignal {
            semaphore.signal()
        }
    }
}
