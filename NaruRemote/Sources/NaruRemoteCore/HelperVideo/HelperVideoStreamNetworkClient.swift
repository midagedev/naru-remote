import Foundation

#if canImport(Network)
import Network

public final class HelperVideoStreamNetworkClient: @unchecked Sendable {
    public let host: String
    public let port: UInt16
    public let profileFingerprint: String

    private let pairingSecret: String
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.naruremote.helper-video-stream-client")

    public init(
        host: String,
        port: UInt16,
        profileFingerprint: String,
        pairingSecret: String,
        timeout: TimeInterval = 3
    ) {
        self.host = host
        self.port = port
        self.profileFingerprint = profileFingerprint
        self.pairingSecret = pairingSecret
        self.timeout = timeout
    }

    public func startStream(
        _ requestBody: HelperVideoStartStreamRequestBody = HelperVideoStartStreamRequestBody(),
        maxServerFrames: Int = 16
    ) async throws -> HelperVideoStreamNetworkStartResult {
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
                using: .tcp
            )
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let completion = HelperVideoStreamNetworkCompletion(
                requestID: requestID,
                maxServerFrames: max(maxServerFrames, 1),
                continuation: continuation,
                connection: connection,
                timer: timer
            )

            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                completion.complete(.failure(HelperVideoStreamNetworkClientError.timedOut))
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

                completion.recordAccessUnit(jsonFrame + binaryHeader + binaryPayload)
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
    case unreachable
    case timedOut
    case malformedFrame
    case missingStartResponse
    case unexpectedMessageType(HelperVideoMessageType)
}

private struct HelperVideoWireMessageHeader: Decodable {
    var messageType: HelperVideoMessageType
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

    init(
        requestID: UUID,
        maxServerFrames: Int,
        continuation: CheckedContinuation<HelperVideoStreamNetworkStartResult, Error>,
        connection: NWConnection,
        timer: DispatchSourceTimer
    ) {
        self.requestID = requestID
        self.maxServerFrames = maxServerFrames
        self.continuation = continuation
        self.connection = connection
        self.timer = timer
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
        } catch {
            complete(.failure(HelperVideoStreamNetworkClientError.malformedFrame))
        }
    }

    func recordAccessUnit(_ frame: Data) {
        do {
            let accessUnit = try HelperVideoWireCodec.decodeFrame(
                HelperVideoWireEnvelope<HelperVideoAccessUnitBody>.self,
                from: frame,
                expectsBinaryPayload: true
            )
            lock.withLock {
                receivedFrameCount += 1
                accessUnits.append(accessUnit)
            }
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
}
#endif
