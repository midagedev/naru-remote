import Foundation
import Network
import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkNetworkConditioningProxyTests: XCTestCase {
    func testProxyForwardsBytesThroughConditionedEndpoint() throws {
        let echo = try LocalEchoServer.start()
        defer { echo.stop() }
        let proxy = try BenchmarkNetworkConditioningProxy.start(
            upstreamHost: "127.0.0.1",
            upstreamPort: echo.port,
            profile: .wanLatency
        )
        defer { proxy.stop() }

        let client = LocalTCPClient(host: "127.0.0.1", port: proxy.localPort)
        let payload = Data("naru-proxy-smoke".utf8)

        XCTAssertEqual(try client.roundTrip(payload, timeout: 2), payload)
    }

    func testNoneProfileDoesNotStartProxy() {
        XCTAssertThrowsError(
            try BenchmarkNetworkConditioningProxy.start(
                upstreamHost: "127.0.0.1",
                upstreamPort: 5900,
                profile: .none
            )
        ) { error in
            XCTAssertEqual(
                error as? BenchmarkNetworkConditioningProxyError,
                .profileHasNoCondition(.none)
            )
        }
    }
}

private final class LocalEchoServer: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "naru.proxy-test.echo")

    static func start(timeout: TimeInterval = 2) throws -> LocalEchoServer {
        let listener = try NWListener(using: .tcp, on: 0)
        let ready = LocalListenerReadyState()
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue(label: "naru.proxy-test.echo.connection"))
            receiveAndEcho(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.markReady()
            case .failed(let error):
                ready.markFailed(error)
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "naru.proxy-test.echo.listener"))
        try ready.wait(timeout: timeout)
        guard let port = listener.port?.rawValue else {
            throw LocalTCPError.portUnavailable
        }
        return LocalEchoServer(port: port, listener: listener)
    }

    private init(port: UInt16, listener: NWListener) {
        self.port = port
        self.listener = listener
    }

    func stop() {
        listener.cancel()
    }

    private static func receiveAndEcho(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            guard error == nil, !isComplete else {
                connection.cancel()
                return
            }
            guard let data, !data.isEmpty else {
                receiveAndEcho(connection)
                return
            }
            connection.send(content: data, completion: .contentProcessed { error in
                guard error == nil else {
                    connection.cancel()
                    return
                }
                receiveAndEcho(connection)
            })
        }
    }
}

private final class LocalTCPClient {
    private let host: String
    private let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func roundTrip(_ payload: Data, timeout: TimeInterval) throws -> Data {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw LocalTCPError.invalidPort
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let queue = DispatchQueue(label: "naru.proxy-test.client")
        try waitForReady(connection, queue: queue, timeout: timeout)
        defer { connection.cancel() }
        try send(payload, on: connection, timeout: timeout)
        return try receive(byteCount: payload.count, on: connection, timeout: timeout)
    }

    private func waitForReady(
        _ connection: NWConnection,
        queue: DispatchQueue,
        timeout: TimeInterval
    ) throws {
        let ready = LocalConnectionReadyState()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.markReady()
            case .failed(let error):
                ready.markFailed(error)
            default:
                break
            }
        }
        connection.start(queue: queue)
        try ready.wait(timeout: timeout)
    }

    private func send(_ payload: Data, on connection: NWConnection, timeout: TimeInterval) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LocalResultBox<Void>()
        connection.send(content: payload, completion: .contentProcessed { error in
            if let error {
                box.complete(.failure(LocalTCPError.network("\(error)")))
            } else {
                box.complete(.success(()))
            }
            semaphore.signal()
        })
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw LocalTCPError.timedOut
        }
        try box.value().get()
    }

    private func receive(byteCount: Int, on connection: NWConnection, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LocalResultBox<Data>()
        connection.receive(minimumIncompleteLength: byteCount, maximumLength: byteCount) { data, _, _, error in
            if let error {
                box.complete(.failure(LocalTCPError.network("\(error)")))
            } else if let data, data.count == byteCount {
                box.complete(.success(data))
            } else {
                box.complete(.failure(LocalTCPError.incompleteRead))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw LocalTCPError.timedOut
        }
        return try box.value().get()
    }
}

private final class LocalListenerReadyState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var ready = false
    private var failure: NWError?

    func markReady() {
        lock.withLock {
            ready = true
        }
        semaphore.signal()
    }

    func markFailed(_ error: NWError) {
        lock.withLock {
            failure = error
        }
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) throws {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw LocalTCPError.timedOut
        }
        let state = lock.withLock { (ready, failure) }
        if let failure = state.1 {
            throw LocalTCPError.network("\(failure)")
        }
        guard state.0 else {
            throw LocalTCPError.notReady
        }
    }
}

private final class LocalConnectionReadyState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var ready = false
    private var failure: NWError?

    func markReady() {
        lock.withLock {
            ready = true
        }
        semaphore.signal()
    }

    func markFailed(_ error: NWError) {
        lock.withLock {
            failure = error
        }
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) throws {
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw LocalTCPError.timedOut
        }
        let state = lock.withLock { (ready, failure) }
        if let failure = state.1 {
            throw LocalTCPError.network("\(failure)")
        }
        guard state.0 else {
            throw LocalTCPError.notReady
        }
    }
}

private final class LocalResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func complete(_ result: Result<T, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func value() throws -> Result<T, Error> {
        try lock.withLock {
            guard let result else {
                throw LocalTCPError.notReady
            }
            return result
        }
    }
}

private enum LocalTCPError: Error, Equatable {
    case invalidPort
    case portUnavailable
    case timedOut
    case incompleteRead
    case notReady
    case network(String)
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

