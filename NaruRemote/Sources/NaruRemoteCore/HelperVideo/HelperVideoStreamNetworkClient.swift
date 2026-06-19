import Foundation

#if canImport(Network)
import Network

public final class HelperVideoStreamNetworkClient: @unchecked Sendable {
    public let host: String
    public let port: UInt16
    public let profileFingerprint: String
    public let transportProtection: HelperVideoTransportProtection

    private static let streamEventBufferLimit = 8
    private static let streamEventBackpressureDelay: DispatchTimeInterval = .milliseconds(24)

    private let pairingSecret: String
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.naruremote.helper-video-stream-client")

    public init(
        host: String,
        port: UInt16,
        profileFingerprint: String,
        pairingSecret: String,
        transportProtection: HelperVideoTransportProtection,
        timeout: TimeInterval = 3
    ) {
        self.host = host
        self.port = port
        self.profileFingerprint = profileFingerprint
        self.pairingSecret = pairingSecret
        self.transportProtection = transportProtection
        self.timeout = timeout
    }

    public func startStream(
        _ requestBody: HelperVideoStartStreamRequestBody = HelperVideoStartStreamRequestBody(),
        maxServerFrames: Int = 16,
        allowsPartialResultOnTimeout: Bool = false
    ) async throws -> HelperVideoStreamNetworkStartResult {
        guard transportProtection.allowsEncodedFramePayloads else {
            throw HelperVideoStreamNetworkClientError.transportProtectionRequired
        }
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw HelperVideoStreamNetworkClientError.invalidPort
        }

        let requestID = UUID()
        let request = HelperVideoWireEnvelope(
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            authProof: HelperVideoAuthProof.make(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret
            ),
            body: requestBody
        )
        let frame = try HelperVideoWireCodec.frame(request)

        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: port,
                using: NaruLowLatencyTCPParameters.make()
            )
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let completion = HelperVideoStreamNetworkCompletion(
                requestID: requestID,
                maxServerFrames: max(maxServerFrames, 1),
                continuation: continuation,
                connection: connection,
                timer: timer,
                timeout: timeout,
                allowsPartialResultOnTimeout: allowsPartialResultOnTimeout
            )

            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                completion.completeOnTimeout()
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: frame, completion: .contentProcessed { error in
                        guard error == nil else {
                            completion.complete(
                                .failure(HelperVideoStreamNetworkClientError.unreachable)
                            )
                            return
                        }
                        Self.receiveFrame(on: connection, completion: completion)
                    })
                case .failed:
                    completion.complete(.failure(HelperVideoStreamNetworkClientError.unreachable))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func streamEvents(
        _ requestBody: HelperVideoStartStreamRequestBody = HelperVideoStartStreamRequestBody()
    ) -> HelperVideoStreamNetworkEvents {
        guard transportProtection.allowsEncodedFramePayloads else {
            return HelperVideoStreamNetworkEvents(
                failure: HelperVideoStreamNetworkClientError.transportProtectionRequired
            )
        }
        guard let port = NWEndpoint.Port(rawValue: port) else {
            return HelperVideoStreamNetworkEvents(failure: HelperVideoStreamNetworkClientError.invalidPort)
        }

        let requestID = UUID()
        let request = HelperVideoWireEnvelope(
            requestID: requestID,
            messageType: .startStream,
            profileFingerprint: profileFingerprint,
            authProof: HelperVideoAuthProof.make(
                requestID: requestID,
                messageType: .startStream,
                profileFingerprint: profileFingerprint,
                pairingSecret: pairingSecret
            ),
            body: requestBody
        )
        let frame: Data
        do {
            frame = try HelperVideoWireCodec.frame(request)
        } catch {
            return HelperVideoStreamNetworkEvents(failure: HelperVideoStreamNetworkClientError.malformedFrame)
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: port,
            using: NaruLowLatencyTCPParameters.make()
        )
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let mailbox = HelperVideoStreamNetworkEventMailbox(
            maxBufferedEvents: Self.streamEventBufferLimit
        )
        let eventStream = HelperVideoStreamNetworkEventStream(
            mailbox: mailbox,
            connection: connection,
            timer: timer,
            timeout: timeout,
            backpressureDelay: Self.streamEventBackpressureDelay,
            queue: queue
        )

        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            eventStream.finish(throwing: HelperVideoStreamNetworkClientError.timedOut)
        }
        timer.resume()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: frame, completion: .contentProcessed { error in
                    guard error == nil else {
                        eventStream.finish(
                            throwing: HelperVideoStreamNetworkClientError.unreachable
                        )
                        return
                    }
                    Self.receiveEventFrame(on: connection, eventStream: eventStream)
                })
            case .failed:
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.unreachable)
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)

        return HelperVideoStreamNetworkEvents(mailbox: mailbox) {
            eventStream.cancel()
        }
    }

    private static func receiveFrame(
        on connection: NWConnection,
        completion: HelperVideoStreamNetworkCompletion
    ) {
        connection.receive(
            minimumIncompleteLength: HelperVideoWireCodec.headerByteCount,
            maximumLength: HelperVideoWireCodec.headerByteCount
        ) { header, _, isComplete, error in
            if error != nil {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.unreachable))
                return
            }
            guard let header else {
                if isComplete {
                    completion.completeWithAccumulatedFrames()
                } else {
                    completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                }
                return
            }

            let jsonLength: Int
            do {
                jsonLength = try HelperVideoWireCodec.jsonPayloadLength(from: header)
            } catch {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                return
            }

            receiveJSONPayload(
                length: jsonLength,
                header: header,
                on: connection,
                completion: completion
            )
        }
    }

    private static func receiveJSONPayload(
        length: Int,
        header: Data,
        on connection: NWConnection,
        completion: HelperVideoStreamNetworkCompletion
    ) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) {
            payload, _, _, error in
            if error != nil {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.unreachable))
                return
            }
            guard let payload else {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                return
            }

            let messageType: HelperVideoMessageType
            do {
                messageType = try JSONDecoder()
                    .decode(HelperVideoWireMessageHeader.self, from: payload)
                    .messageType
            } catch {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                return
            }

            let frame = header + payload
            switch messageType {
            case .startStream:
                completion.recordStartResponse(frame)
                receiveNextFrameIfNeeded(on: connection, completion: completion)
            case .streamStalled:
                completion.recordStall(frame)
                receiveNextFrameIfNeeded(on: connection, completion: completion)
            case .videoAccessUnit:
                receiveBinaryPayload(
                    jsonFrame: frame,
                    on: connection,
                    completion: completion
                )
            case .capabilityRequest, .requestKeyframe, .stopStream:
                completion.complete(
                    .failure(HelperVideoStreamNetworkClientError.unexpectedMessageType(messageType))
                )
            }
        }
    }

    private static func receiveBinaryPayload(
        jsonFrame: Data,
        on connection: NWConnection,
        completion: HelperVideoStreamNetworkCompletion
    ) {
        connection.receive(
            minimumIncompleteLength: HelperVideoWireCodec.headerByteCount,
            maximumLength: HelperVideoWireCodec.headerByteCount
        ) { binaryHeader, _, _, error in
            if error != nil {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.unreachable))
                return
            }
            guard let binaryHeader else {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                return
            }

            let binaryLength: Int
            do {
                binaryLength = try HelperVideoWireCodec.binaryPayloadLength(from: binaryHeader)
            } catch {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                return
            }

            connection.receive(
                minimumIncompleteLength: binaryLength,
                maximumLength: binaryLength
            ) { binaryPayload, _, _, error in
                if error != nil {
                    completion.complete(.failure(HelperVideoStreamNetworkClientError.unreachable))
                    return
                }
                guard let binaryPayload else {
                    completion.complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
                    return
                }

                completion.recordAccessUnit(
                    jsonFrame: jsonFrame,
                    binaryHeader: binaryHeader,
                    binaryPayload: binaryPayload
                )
                receiveNextFrameIfNeeded(on: connection, completion: completion)
            }
        }
    }

    private static func receiveNextFrameIfNeeded(
        on connection: NWConnection,
        completion: HelperVideoStreamNetworkCompletion
    ) {
        guard completion.shouldReceiveMoreFrames else {
            completion.completeWithAccumulatedFrames()
            return
        }
        receiveFrame(on: connection, completion: completion)
    }

    private static func receiveEventFrame(
        on connection: NWConnection,
        eventStream: HelperVideoStreamNetworkEventStream
    ) {
        connection.receive(
            minimumIncompleteLength: HelperVideoWireCodec.headerByteCount,
            maximumLength: HelperVideoWireCodec.headerByteCount
        ) { header, _, isComplete, error in
            if error != nil {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.unreachable)
                return
            }
            guard let header else {
                if isComplete {
                    eventStream.finish()
                } else {
                    eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                }
                return
            }

            let jsonLength: Int
            do {
                jsonLength = try HelperVideoWireCodec.jsonPayloadLength(from: header)
            } catch {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                return
            }

            receiveEventJSONPayload(
                length: jsonLength,
                header: header,
                on: connection,
                eventStream: eventStream
            )
        }
    }

    private static func receiveEventJSONPayload(
        length: Int,
        header: Data,
        on connection: NWConnection,
        eventStream: HelperVideoStreamNetworkEventStream
    ) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) {
            payload, _, _, error in
            if error != nil {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.unreachable)
                return
            }
            guard let payload else {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                return
            }

            let messageType: HelperVideoMessageType
            do {
                messageType = try JSONDecoder()
                    .decode(HelperVideoWireMessageHeader.self, from: payload)
                    .messageType
            } catch {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                return
            }

            let frame = header + payload
            switch messageType {
            case .startStream:
                do {
                    let response = try HelperVideoWireCodec.decodeFrame(
                        HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
                        from: frame
                    ).envelope
                    let result = eventStream.yield(.startResponse(response))
                    receiveNextEventFrame(
                        on: connection,
                        eventStream: eventStream,
                        after: result
                    )
                } catch {
                    eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                }
            case .streamStalled:
                do {
                    let stall = try HelperVideoWireCodec.decodeFrame(
                        HelperVideoWireEnvelope<HelperVideoStreamStallBody>.self,
                        from: frame
                    ).envelope
                    let result = eventStream.yield(.stall(stall))
                    receiveNextEventFrame(
                        on: connection,
                        eventStream: eventStream,
                        after: result
                    )
                } catch {
                    eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                }
            case .videoAccessUnit:
                receiveEventBinaryPayload(
                    jsonFrame: frame,
                    on: connection,
                    eventStream: eventStream
                )
            case .capabilityRequest, .requestKeyframe, .stopStream:
                eventStream.finish(
                    throwing: HelperVideoStreamNetworkClientError.unexpectedMessageType(messageType)
                )
            }
        }
    }

    private static func receiveEventBinaryPayload(
        jsonFrame: Data,
        on connection: NWConnection,
        eventStream: HelperVideoStreamNetworkEventStream
    ) {
        connection.receive(
            minimumIncompleteLength: HelperVideoWireCodec.headerByteCount,
            maximumLength: HelperVideoWireCodec.headerByteCount
        ) { binaryHeader, _, _, error in
            if error != nil {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.unreachable)
                return
            }
            guard let binaryHeader else {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                return
            }

            let binaryLength: Int
            do {
                binaryLength = try HelperVideoWireCodec.binaryPayloadLength(from: binaryHeader)
            } catch {
                eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                return
            }

            connection.receive(
                minimumIncompleteLength: binaryLength,
                maximumLength: binaryLength
            ) { binaryPayload, _, _, error in
                if error != nil {
                    eventStream.finish(throwing: HelperVideoStreamNetworkClientError.unreachable)
                    return
                }
                guard let binaryPayload else {
                    eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                    return
                }

                do {
                    let accessUnit = try HelperVideoWireCodec.decodeFrame(
                        HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
                        fromJSONFrame: jsonFrame,
                        binaryHeader: binaryHeader,
                        binaryPayload: binaryPayload
                    )
                    let result = eventStream.yield(.accessUnit(accessUnit))
                    receiveNextEventFrame(
                        on: connection,
                        eventStream: eventStream,
                        after: result
                    )
                } catch {
                    eventStream.finish(throwing: HelperVideoStreamNetworkClientError.malformedFrame)
                }
            }
        }
    }

    private static func receiveNextEventFrame(
        on connection: NWConnection,
        eventStream: HelperVideoStreamNetworkEventStream,
        after yieldResult: HelperVideoStreamNetworkEventYieldResult
    ) {
        guard yieldResult.shouldReceiveNextFrame else {
            return
        }
        eventStream.scheduleNextReceive(applyingBackpressure: yieldResult.didApplyBackpressure) {
            receiveEventFrame(on: connection, eventStream: eventStream)
        }
    }
}

public enum HelperVideoStreamNetworkEvent: Equatable, Sendable {
    case startResponse(HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>)
    case accessUnit(HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>)
    case stall(HelperVideoWireEnvelope<HelperVideoStreamStallBody>)
}

public struct HelperVideoStreamNetworkEvents: AsyncSequence, Sendable {
    public typealias Element = HelperVideoStreamNetworkEvent

    private let makeIteratorClosure: @Sendable () -> AsyncIterator

    public init(
        _ build: @escaping @Sendable (
            AsyncThrowingStream<HelperVideoStreamNetworkEvent, any Error>.Continuation
        ) -> Void
    ) {
        let stream = AsyncThrowingStream<HelperVideoStreamNetworkEvent, any Error>(
            bufferingPolicy: .unbounded,
            build
        )
        self.makeIteratorClosure = {
            AsyncIterator(streamIterator: stream.makeAsyncIterator())
        }
    }

    fileprivate init(failure error: any Error) {
        self.init { continuation in
            continuation.finish(throwing: error)
        }
    }

    fileprivate init(
        mailbox: HelperVideoStreamNetworkEventMailbox,
        onCancel: @escaping @Sendable () -> Void
    ) {
        self.makeIteratorClosure = {
            AsyncIterator(mailbox: mailbox, onCancel: onCancel)
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        makeIteratorClosure()
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var streamIterator: AsyncThrowingStream<HelperVideoStreamNetworkEvent, any Error>
            .Iterator?
        private var mailbox: HelperVideoStreamNetworkEventMailbox?
        private var cancellation: HelperVideoStreamNetworkEventCancellation?

        fileprivate init(
            streamIterator: AsyncThrowingStream<HelperVideoStreamNetworkEvent, any Error>.Iterator
        ) {
            self.streamIterator = streamIterator
            self.mailbox = nil
            self.cancellation = nil
        }

        fileprivate init(
            mailbox: HelperVideoStreamNetworkEventMailbox,
            onCancel: @escaping @Sendable () -> Void
        ) {
            self.streamIterator = nil
            self.mailbox = mailbox
            self.cancellation = HelperVideoStreamNetworkEventCancellation(onCancel)
        }

        public mutating func next() async throws -> HelperVideoStreamNetworkEvent? {
            if var streamIterator {
                let event = try await streamIterator.next()
                self.streamIterator = streamIterator
                return event
            }

            guard let mailbox else {
                return nil
            }

            let cancellation = cancellation
            return try await withTaskCancellationHandler {
                try await mailbox.next()
            } onCancel: {
                cancellation?.cancel()
            }
        }
    }
}

public struct HelperVideoStreamNetworkStartResult: Equatable, Sendable {
    public var requestID: UUID
    public var startResponse: HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>
    public var accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>]
    public var stall: HelperVideoWireEnvelope<HelperVideoStreamStallBody>?

    public init(
        requestID: UUID,
        startResponse: HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>,
        accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = [],
        stall: HelperVideoWireEnvelope<HelperVideoStreamStallBody>? = nil
    ) {
        self.requestID = requestID
        self.startResponse = startResponse
        self.accessUnits = accessUnits
        self.stall = stall
    }
}

public enum HelperVideoStreamNetworkClientError: Error, Equatable, Sendable {
    case invalidPort
    case transportProtectionRequired
    case unreachable
    case timedOut
    case malformedFrame
    case missingStartResponse
    case unexpectedMessageType(HelperVideoMessageType)
}

private struct HelperVideoWireMessageHeader: Decodable {
    var messageType: HelperVideoMessageType
}

private final class HelperVideoStreamNetworkEventCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private let onCancel: @Sendable () -> Void
    private var didCancel = false

    init(_ onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    deinit {
        cancel()
    }

    func cancel() {
        lock.lock()
        guard !didCancel else {
            lock.unlock()
            return
        }
        didCancel = true
        lock.unlock()

        onCancel()
    }
}

private struct HelperVideoStreamNetworkEventYieldResult: Sendable {
    var shouldReceiveNextFrame: Bool
    var didApplyBackpressure: Bool

    static let enqueued = HelperVideoStreamNetworkEventYieldResult(
        shouldReceiveNextFrame: true,
        didApplyBackpressure: false
    )
    static let backpressured = HelperVideoStreamNetworkEventYieldResult(
        shouldReceiveNextFrame: true,
        didApplyBackpressure: true
    )
    static let stopped = HelperVideoStreamNetworkEventYieldResult(
        shouldReceiveNextFrame: false,
        didApplyBackpressure: false
    )
}

private struct HelperVideoStreamNetworkEventMailboxOfferResult: Sendable {
    var shouldDelayReceive: Bool

    static let enqueued = HelperVideoStreamNetworkEventMailboxOfferResult(
        shouldDelayReceive: false
    )
    static let backpressured = HelperVideoStreamNetworkEventMailboxOfferResult(
        shouldDelayReceive: true
    )
}

private final class HelperVideoStreamNetworkEventMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBufferedEvents: Int
    private var bufferedEvents: [HelperVideoStreamNetworkEvent] = []
    private var pendingNext: CheckedContinuation<HelperVideoStreamNetworkEvent?, any Error>?
    private var completion: Result<Void, any Error>?

    init(maxBufferedEvents: Int) {
        self.maxBufferedEvents = max(maxBufferedEvents, 1)
    }

    func offer(_ event: HelperVideoStreamNetworkEvent) -> HelperVideoStreamNetworkEventMailboxOfferResult {
        var continuation: CheckedContinuation<HelperVideoStreamNetworkEvent?, any Error>?
        var offerResult = HelperVideoStreamNetworkEventMailboxOfferResult.enqueued

        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return .backpressured
        }
        if let pendingNext {
            self.pendingNext = nil
            continuation = pendingNext
        } else {
            offerResult = appendBufferedEventLocked(event)
        }
        lock.unlock()

        continuation?.resume(returning: event)
        return offerResult
    }

    func next() async throws -> HelperVideoStreamNetworkEvent? {
        try await withCheckedThrowingContinuation { continuation in
            var event: HelperVideoStreamNetworkEvent?
            var finished: Result<Void, any Error>?

            lock.lock()
            if !bufferedEvents.isEmpty {
                event = bufferedEvents.removeFirst()
            } else if let completion {
                finished = completion
            } else {
                pendingNext = continuation
                lock.unlock()
                return
            }
            lock.unlock()

            if let event {
                continuation.resume(returning: event)
                return
            }

            switch finished {
            case .success:
                continuation.resume(returning: nil)
            case .failure(let error):
                continuation.resume(throwing: error)
            case nil:
                continuation.resume(returning: nil)
            }
        }
    }

    func finish(throwing error: (any Error)? = nil) {
        let result: Result<Void, any Error> = if let error {
            .failure(error)
        } else {
            .success(())
        }
        var continuation: CheckedContinuation<HelperVideoStreamNetworkEvent?, any Error>?

        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        completion = result
        if bufferedEvents.isEmpty {
            continuation = pendingNext
            pendingNext = nil
        }
        lock.unlock()

        guard let continuation else {
            return
        }
        switch result {
        case .success:
            continuation.resume(returning: nil)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func appendBufferedEventLocked(
        _ event: HelperVideoStreamNetworkEvent
    ) -> HelperVideoStreamNetworkEventMailboxOfferResult {
        var shouldDelayReceive = false

        // Sync/control replacement keeps only the newest useful state, but
        // delaying the next read here can let an older sync pair escape before
        // the newest parameter/keyframe pair arrives.
        switch event.bufferRole {
        case .startResponse, .stall, .endOfStream:
            _ = removeBufferedEventsLocked(matching: event.bufferRole)
        case .parameterSet:
            _ = removeBufferedEventsLocked(matching: .parameterSet)
            _ = removeBufferedEventsLocked(matching: .keyframe)
            _ = removeBufferedEventsLocked(matching: .delta)
        case .keyframe:
            _ = removeBufferedEventsLocked(matching: .keyframe)
            _ = removeBufferedEventsLocked(matching: .delta)
        case .delta:
            shouldDelayReceive = removeBufferedEventsLocked(matching: .delta)
                || shouldDelayReceive
        }

        bufferedEvents.append(event)

        while bufferedEvents.count > maxBufferedEvents {
            if let deltaIndex = bufferedEvents.firstIndex(where: { $0.bufferRole == .delta }) {
                bufferedEvents.remove(at: deltaIndex)
                shouldDelayReceive = true
                continue
            }
            guard bufferedEvents.count > 1 else {
                break
            }
            bufferedEvents.remove(at: 1)
            shouldDelayReceive = true
        }

        return shouldDelayReceive ? .backpressured : .enqueued
    }

    private func removeBufferedEventsLocked(
        matching role: HelperVideoStreamNetworkEventBufferRole
    ) -> Bool {
        let originalCount = bufferedEvents.count
        bufferedEvents.removeAll { $0.bufferRole == role }
        return bufferedEvents.count != originalCount
    }
}

private enum HelperVideoStreamNetworkEventBufferRole: Sendable {
    case startResponse
    case parameterSet
    case keyframe
    case delta
    case endOfStream
    case stall
}

private final class HelperVideoStreamNetworkEventStream: @unchecked Sendable {
    private let lock = NSLock()
    private let mailbox: HelperVideoStreamNetworkEventMailbox
    private let connection: NWConnection
    private let timer: DispatchSourceTimer
    private let timeout: TimeInterval
    private let backpressureDelay: DispatchTimeInterval
    private let queue: DispatchQueue
    private var isFinished = false

    init(
        mailbox: HelperVideoStreamNetworkEventMailbox,
        connection: NWConnection,
        timer: DispatchSourceTimer,
        timeout: TimeInterval,
        backpressureDelay: DispatchTimeInterval,
        queue: DispatchQueue
    ) {
        self.mailbox = mailbox
        self.connection = connection
        self.timer = timer
        self.timeout = timeout
        self.backpressureDelay = backpressureDelay
        self.queue = queue
    }

    func yield(_ event: HelperVideoStreamNetworkEvent) -> HelperVideoStreamNetworkEventYieldResult {
        guard !hasFinished else {
            return .stopped
        }
        refreshTimeout()
        let result = mailbox.offer(event)
        return result.shouldDelayReceive ? .backpressured : .enqueued
    }

    func scheduleNextReceive(
        applyingBackpressure: Bool,
        _ receive: @escaping @Sendable () -> Void
    ) {
        guard !hasFinished else {
            return
        }
        if applyingBackpressure {
            queue.asyncAfter(deadline: .now() + backpressureDelay, execute: receive)
        } else {
            queue.async(execute: receive)
        }
    }

    func finish() {
        finish(result: nil)
    }

    func finish(throwing error: any Error) {
        finish(result: error)
    }

    func cancel() {
        finish(result: CancellationError())
    }

    private var hasFinished: Bool {
        lock.withLock {
            isFinished
        }
    }

    private func finish(result: (any Error)?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        lock.unlock()

        timer.cancel()
        connection.cancel()
        mailbox.finish(throwing: result)
    }

    private func refreshTimeout() {
        timer.schedule(deadline: .now() + timeout)
    }
}

private extension HelperVideoStreamNetworkEvent {
    var bufferRole: HelperVideoStreamNetworkEventBufferRole {
        switch self {
        case .startResponse:
            return .startResponse
        case .stall:
            return .stall
        case .accessUnit(let accessUnit):
            switch accessUnit.envelope.body.kind {
            case .parameterSet:
                return .parameterSet
            case .keyframe:
                return .keyframe
            case .delta:
                return .delta
            case .endOfStream:
                return .endOfStream
            }
        }
    }
}

private final class HelperVideoStreamNetworkCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isCompleted = false
    private var receivedFrameCount = 0
    private var startResponse: HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>?
    private var accessUnits: [HelperVideoDecodedFrame<HelperVideoWireEnvelope<HelperVideoAccessUnitBody>>] = []
    private var stall: HelperVideoWireEnvelope<HelperVideoStreamStallBody>?

    private let requestID: UUID
    private let maxServerFrames: Int
    private let continuation: CheckedContinuation<HelperVideoStreamNetworkStartResult, Error>
    private let connection: NWConnection
    private let timer: DispatchSourceTimer
    private let timeout: TimeInterval
    private let allowsPartialResultOnTimeout: Bool

    init(
        requestID: UUID,
        maxServerFrames: Int,
        continuation: CheckedContinuation<HelperVideoStreamNetworkStartResult, Error>,
        connection: NWConnection,
        timer: DispatchSourceTimer,
        timeout: TimeInterval,
        allowsPartialResultOnTimeout: Bool
    ) {
        self.requestID = requestID
        self.maxServerFrames = maxServerFrames
        self.continuation = continuation
        self.connection = connection
        self.timer = timer
        self.timeout = timeout
        self.allowsPartialResultOnTimeout = allowsPartialResultOnTimeout
    }

    var shouldReceiveMoreFrames: Bool {
        lock.withLock {
            !isCompleted && receivedFrameCount < maxServerFrames
        }
    }

    func recordStartResponse(_ frame: Data) {
        do {
            let response = try HelperVideoWireCodec.decodeFrame(
                HelperVideoWireEnvelope<HelperVideoStartStreamResponseBody>.self,
                from: frame
            ).envelope
            lock.withLock {
                receivedFrameCount += 1
                startResponse = response
            }
            refreshTimeout()
        } catch {
            complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
        }
    }

    func recordAccessUnit(
        jsonFrame: Data,
        binaryHeader: Data,
        binaryPayload: Data
    ) {
        do {
            let accessUnit = try HelperVideoWireCodec.decodeFrame(
                HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
                fromJSONFrame: jsonFrame,
                binaryHeader: binaryHeader,
                binaryPayload: binaryPayload
            )
            lock.withLock {
                receivedFrameCount += 1
                accessUnits.append(accessUnit)
            }
            refreshTimeout()
        } catch {
            complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
        }
    }

    func recordStall(_ frame: Data) {
        do {
            let stall = try HelperVideoWireCodec.decodeFrame(
                HelperVideoWireEnvelope<HelperVideoStreamStallBody>.self,
                from: frame
            ).envelope
            lock.withLock {
                receivedFrameCount += 1
                self.stall = stall
            }
            refreshTimeout()
        } catch {
            complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
        }
    }

    func completeWithAccumulatedFrames() {
        let result: Result<HelperVideoStreamNetworkStartResult, Error> = lock.withLock {
            guard let startResponse else {
                return .failure(HelperVideoStreamNetworkClientError.missingStartResponse)
            }
            return .success(HelperVideoStreamNetworkStartResult(
                requestID: requestID,
                startResponse: startResponse,
                accessUnits: accessUnits,
                stall: stall
            ))
        }
        complete(result)
    }

    func completeOnTimeout() {
        let result: Result<HelperVideoStreamNetworkStartResult, Error> = lock.withLock {
            guard allowsPartialResultOnTimeout, let startResponse else {
                return .failure(HelperVideoStreamNetworkClientError.timedOut)
            }
            return .success(HelperVideoStreamNetworkStartResult(
                requestID: requestID,
                startResponse: startResponse,
                accessUnits: accessUnits,
                stall: stall
            ))
        }
        complete(result)
    }

    func complete(_ result: Result<HelperVideoStreamNetworkStartResult, Error>) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        lock.unlock()

        timer.cancel()
        connection.cancel()
        continuation.resume(with: result)
    }

    private func refreshTimeout() {
        timer.schedule(deadline: .now() + timeout)
    }
}
#endif
