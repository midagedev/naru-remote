import Foundation
import Network

public final class FakeRFBServer: @unchecked Sendable {
    public enum Mode: Sendable {
        case transcript
        case noAuthHandshake
        case noAuthFramebufferUpdates([Data])
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
                                    receiveFramebufferRequestsAndSendUpdates()
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

    public init() {}

    public var bytes: Data {
        lock.lock()
        defer { lock.unlock() }
        return recordedBytes
    }

    public func append(_ data: Data) {
        lock.lock()
        recordedBytes.append(data)
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
