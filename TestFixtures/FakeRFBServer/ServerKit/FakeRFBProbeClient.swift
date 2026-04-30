import Foundation
import Network

public enum FakeRFBProbeClient {
    public static func readTranscript(
        host: String = "127.0.0.1",
        port: UInt16,
        expectedByteCount: Int,
        timeout: TimeInterval = 2
    ) throws -> Data {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw FakeRFBProbeClientError.invalidPort(port)
        }

        let queue = DispatchQueue(label: "naru.fake-rfb-probe-client")
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let state = ProbeState(expectedByteCount: expectedByteCount)
        let reader = ProbeConnectionReader(
            connection: connection,
            state: state,
            expectedByteCount: expectedByteCount
        )

        connection.stateUpdateHandler = { connectionState in
            switch connectionState {
            case .ready:
                reader.receiveNext()
            case .failed(let error):
                state.fail(.connectionFailed(error.localizedDescription))
            default:
                break
            }
        }

        connection.start(queue: queue)
        defer { connection.cancel() }

        return try state.wait(timeout: timeout)
    }
}

private final class ProbeConnectionReader: @unchecked Sendable {
    private let connection: NWConnection
    private let state: ProbeState
    private let expectedByteCount: Int

    init(
        connection: NWConnection,
        state: ProbeState,
        expectedByteCount: Int
    ) {
        self.connection = connection
        self.state = state
        self.expectedByteCount = expectedByteCount
    }

    func receiveNext() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: max(1, expectedByteCount - state.byteCount)
        ) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                state.append(data)
            }

            if let error {
                state.fail(.connectionFailed(error.localizedDescription))
                return
            }

            if state.byteCount >= expectedByteCount || isComplete {
                state.finish()
                return
            }

            receiveNext()
        }
    }
}

public enum FakeRFBProbeClientError: Error, Equatable, LocalizedError {
    case invalidPort(UInt16)
    case timedOut
    case incompleteTranscript(expected: Int, actual: Int)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid fake RFB probe port: \(port)"
        case .timedOut:
            return "Timed out while reading fake RFB transcript."
        case .incompleteTranscript(let expected, let actual):
            return "Fake RFB transcript incomplete. Expected \(expected) bytes, received \(actual)."
        case .connectionFailed(let message):
            return "Fake RFB probe connection failed: \(message)"
        }
    }
}

private final class ProbeState: @unchecked Sendable {
    private let expectedByteCount: Int
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var bytes = Data()
    private var result: Result<Data, FakeRFBProbeClientError>?

    init(expectedByteCount: Int) {
        self.expectedByteCount = expectedByteCount
    }

    var byteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes.count
    }

    func append(_ data: Data) {
        lock.lock()
        bytes.append(data)
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let data = bytes
        lock.unlock()

        guard data.count >= expectedByteCount else {
            fail(.incompleteTranscript(expected: expectedByteCount, actual: data.count))
            return
        }

        complete(.success(data))
    }

    func fail(_ error: FakeRFBProbeClientError) {
        complete(.failure(error))
    }

    func wait(timeout: TimeInterval) throws -> Data {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw FakeRFBProbeClientError.timedOut
        }

        switch currentResult {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case nil:
            throw FakeRFBProbeClientError.timedOut
        }
    }

    private var currentResult: Result<Data, FakeRFBProbeClientError>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }

    private func complete(_ result: Result<Data, FakeRFBProbeClientError>) {
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
