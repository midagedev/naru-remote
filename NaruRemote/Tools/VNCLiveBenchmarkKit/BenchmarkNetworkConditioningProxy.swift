import Foundation
import Network

public enum BenchmarkNetworkConditioningProxyError: Error, Equatable, CustomStringConvertible {
    case profileHasNoCondition(BenchmarkNetworkConditionProfile)
    case invalidPort(UInt16)
    case listenerFailed(String)
    case listenerPortUnavailable

    public var description: String {
        switch self {
        case .profileHasNoCondition(let profile):
            return "Network condition profile \(profile.rawValue) does not require a proxy."
        case .invalidPort(let port):
            return "Invalid upstream port \(port)."
        case .listenerFailed(let message):
            return "Network conditioning proxy listener failed: \(message)"
        case .listenerPortUnavailable:
            return "Network conditioning proxy listener did not publish a local port."
        }
    }
}

public final class BenchmarkNetworkConditioningProxy: @unchecked Sendable {
    public let profile: BenchmarkNetworkConditionProfile
    public let localPort: UInt16

    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var activeConnections: [BenchmarkConditionedProxyConnection] = []

    public static func start(
        upstreamHost: String,
        upstreamPort: UInt16,
        profile: BenchmarkNetworkConditionProfile,
        timeout: TimeInterval = 2
    ) throws -> BenchmarkNetworkConditioningProxy {
        guard let settings = profile.settings else {
            throw BenchmarkNetworkConditioningProxyError.profileHasNoCondition(profile)
        }
        guard upstreamPort > 0,
              let upstreamEndpointPort = NWEndpoint.Port(rawValue: upstreamPort) else {
            throw BenchmarkNetworkConditioningProxyError.invalidPort(upstreamPort)
        }

        let listener = try NWListener(using: .tcp, on: 0)
        let queue = DispatchQueue(label: "naru.live-benchmark.network-condition")
        let readyState = BenchmarkProxyListenerReadyState()
        let upstreamEndpointHost = NWEndpoint.Host(upstreamHost)

        listener.newConnectionHandler = { clientConnection in
            let upstreamConnection = NWConnection(
                host: upstreamEndpointHost,
                port: upstreamEndpointPort,
                using: .tcp
            )
            readyState.attach(
                clientConnection: clientConnection,
                upstreamConnection: upstreamConnection,
                settings: settings,
                queue: queue
            )
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readyState.markReady()
            case .failed(let error):
                readyState.markFailed(error)
            default:
                break
            }
        }

        listener.start(queue: queue)
        try readyState.wait(timeout: timeout)

        guard let port = listener.port?.rawValue else {
            throw BenchmarkNetworkConditioningProxyError.listenerPortUnavailable
        }

        let proxy = BenchmarkNetworkConditioningProxy(
            profile: profile,
            localPort: port,
            listener: listener,
            queue: queue
        )
        readyState.onAttach = { [weak proxy] connection in
            proxy?.append(connection)
        }
        return proxy
    }

    private init(
        profile: BenchmarkNetworkConditionProfile,
        localPort: UInt16,
        listener: NWListener,
        queue: DispatchQueue
    ) {
        self.profile = profile
        self.localPort = localPort
        self.listener = listener
        self.queue = queue
    }

    public func stop() {
        listener.cancel()
        let connections = lock.withLock {
            let connections = activeConnections
            activeConnections.removeAll()
            return connections
        }
        connections.forEach { $0.cancel() }
    }

    deinit {
        stop()
    }

    private func append(_ connection: BenchmarkConditionedProxyConnection) {
        lock.withLock {
            activeConnections.append(connection)
        }
        connection.onCancel = { [weak self, weak connection] in
            guard let connection else {
                return
            }
            self?.remove(connection)
        }
        connection.start()
    }

    private func remove(_ connection: BenchmarkConditionedProxyConnection) {
        lock.withLock {
            activeConnections.removeAll { $0 === connection }
        }
    }
}

private final class BenchmarkProxyListenerReadyState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var ready = false
    private var failure: NWError?
    var onAttach: (@Sendable (BenchmarkConditionedProxyConnection) -> Void)?

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

    func attach(
        clientConnection: NWConnection,
        upstreamConnection: NWConnection,
        settings: BenchmarkNetworkConditionSettings,
        queue: DispatchQueue
    ) {
        let connection = BenchmarkConditionedProxyConnection(
            clientConnection: clientConnection,
            upstreamConnection: upstreamConnection,
            settings: settings,
            queue: queue
        )
        onAttach?(connection)
    }

    func wait(timeout: TimeInterval) throws {
        let result = semaphore.wait(timeout: .now() + timeout)
        guard result == .success else {
            throw BenchmarkNetworkConditioningProxyError.listenerFailed("timed-out")
        }
        let state = lock.withLock { (ready, failure) }
        if let failure = state.1 {
            throw BenchmarkNetworkConditioningProxyError.listenerFailed("\(failure)")
        }
        guard state.0 else {
            throw BenchmarkNetworkConditioningProxyError.listenerFailed("not-ready")
        }
    }
}

private final class BenchmarkConditionedProxyConnection: @unchecked Sendable {
    private let clientConnection: NWConnection
    private let upstreamConnection: NWConnection
    private let settings: BenchmarkNetworkConditionSettings
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var cancelled = false
    private var clientToUpstream: BenchmarkConditionedPipe?
    private var upstreamToClient: BenchmarkConditionedPipe?
    var onCancel: (@Sendable () -> Void)?

    init(
        clientConnection: NWConnection,
        upstreamConnection: NWConnection,
        settings: BenchmarkNetworkConditionSettings,
        queue: DispatchQueue
    ) {
        self.clientConnection = clientConnection
        self.upstreamConnection = upstreamConnection
        self.settings = settings
        self.queue = queue
    }

    func start() {
        clientConnection.start(queue: queue)
        upstreamConnection.start(queue: queue)

        clientToUpstream = BenchmarkConditionedPipe(
            source: clientConnection,
            destination: upstreamConnection,
            settings: settings,
            queue: queue,
            onStop: { [weak self] in self?.cancel() }
        )
        upstreamToClient = BenchmarkConditionedPipe(
            source: upstreamConnection,
            destination: clientConnection,
            settings: settings,
            queue: queue,
            onStop: { [weak self] in self?.cancel() }
        )
        clientToUpstream?.start()
        upstreamToClient?.start()
    }

    func cancel() {
        let shouldCancel = lock.withLock {
            if cancelled {
                return false
            }
            cancelled = true
            return true
        }
        guard shouldCancel else {
            return
        }
        clientConnection.cancel()
        upstreamConnection.cancel()
        onCancel?()
    }
}

private final class BenchmarkConditionedPipe: @unchecked Sendable {
    private let source: NWConnection
    private let destination: NWConnection
    private let settings: BenchmarkNetworkConditionSettings
    private let queue: DispatchQueue
    private let onStop: @Sendable () -> Void
    private var pendingChunks: [BenchmarkConditionedChunk] = []
    private var isSending = false
    private var isStopped = false

    init(
        source: NWConnection,
        destination: NWConnection,
        settings: BenchmarkNetworkConditionSettings,
        queue: DispatchQueue,
        onStop: @escaping @Sendable () -> Void
    ) {
        self.source = source
        self.destination = destination
        self.settings = settings
        self.queue = queue
        self.onStop = onStop
    }

    func start() {
        receiveNext()
    }

    private func receiveNext() {
        source.receive(
            minimumIncompleteLength: 1,
            maximumLength: settings.maxChunkBytes
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            if let data, !data.isEmpty {
                enqueue(data)
            }
            if error != nil || isComplete {
                stop()
                return
            }
            receiveNext()
        }
    }

    private func enqueue(_ data: Data) {
        let startsNewBurst = pendingChunks.isEmpty && !isSending
        pendingChunks.append(
            contentsOf: settings.chunks(for: data).enumerated().map { offset, chunk in
                BenchmarkConditionedChunk(
                    data: chunk,
                    startsBurst: startsNewBurst && offset == 0
                )
            }
        )
        guard !isSending else {
            return
        }
        sendNext()
    }

    /// Spec 029. Counts bursts so the jitter generator is replayable per run.
    private var burstSequence = 0

    private func sendNext() {
        guard !isStopped else {
            return
        }
        guard !pendingChunks.isEmpty else {
            isSending = false
            return
        }
        isSending = true
        let chunk = pendingChunks.removeFirst()
        // Spec 029 FR-002. Jitter is applied per burst, inside the existing
        // chained send, so chunk order is preserved by construction.
        //
        // An earlier attempt scheduled every chunk independently on an absolute
        // timeline. That is a better queueing model on paper and it was wrong
        // here for two reasons: the defect it was written to fix does not exist
        // (measured — a multi-chunk payload already paid the link latency once,
        // not once per chunk), and independent scheduling with per-chunk jitter
        // lets a later chunk overtake an earlier one, which would corrupt the
        // RFB stream rather than merely slow it down.
        let delay = settings.delaySeconds(
            forChunkByteCount: chunk.data.count,
            startsBurst: chunk.startsBurst,
            sequence: burstSequence
        )
        if chunk.startsBurst {
            burstSequence += 1
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !isStopped else {
                return
            }
            destination.send(content: chunk.data, completion: .contentProcessed { [weak self] error in
                guard let self else {
                    return
                }
                if error != nil {
                    stop()
                    return
                }
                sendNext()
            })
        }
    }

    private func stop() {
        guard !isStopped else {
            return
        }
        isStopped = true
        pendingChunks.removeAll()
        onStop()
    }
}

private struct BenchmarkConditionedChunk {
    let data: Data
    let startsBurst: Bool
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
