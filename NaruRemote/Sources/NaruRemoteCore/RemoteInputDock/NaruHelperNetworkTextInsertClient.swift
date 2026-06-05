import Foundation

#if canImport(Network)
import Network

public final class NaruHelperNetworkTextInsertClient: HelperTextInsertClient, @unchecked Sendable {
    public let host: String
    public let port: UInt16
    private let pairingSecret: String
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.naruremote.helper-network-client")

    public init(
        host: String,
        port: UInt16 = UInt16(naruHelperTextBridgeDefaultPort),
        pairingSecret: String,
        timeout: TimeInterval = 3
    ) {
        self.host = host
        self.port = port
        self.pairingSecret = pairingSecret
        self.timeout = timeout
    }

    public var availability: HelperTextBridgeAvailability {
        .reachable
    }

    public func capability(
        profilePairingFingerprint: String? = nil
    ) async throws -> NaruHelperCapabilityResponse {
        let requestID = UUID()
        let response = try await send(
            NaruHelperNetworkRequest(
                requestID: requestID,
                command: .capability,
                pairingSecret: pairingSecret,
                capabilityRequest: NaruHelperNetworkCapabilityRequest(
                    profilePairingFingerprint: profilePairingFingerprint
                )
            )
        )

        guard response.requestID == requestID else {
            throw HelperTextBridgeError.unavailable(.insertRejected)
        }
        guard response.safeFailureCode == .none else {
            throw HelperTextBridgeError.unavailable(response.safeFailureCode)
        }
        guard let capabilityResponse = response.capabilityResponse else {
            throw HelperTextBridgeError.unavailable(.versionUnsupported)
        }
        return capabilityResponse
    }

    public func insertText(
        _ text: String,
        metadata: HelperTextInsertRequestMetadata
    ) async throws -> HelperTextInsertResult {
        let insertRequest = NaruHelperInsertTextRequest(
            requestID: metadata.id,
            payloadEncoding: metadata.payloadEncoding,
            payloadSizeBucket: metadata.payloadSizeBucket,
            strategyPreference: metadata.strategyPreferences,
            text: text
        )
        let response = try await send(
            NaruHelperNetworkRequest(
                requestID: metadata.id,
                command: .insertText,
                pairingSecret: pairingSecret,
                insertRequest: insertRequest
            )
        )

        guard response.requestID == metadata.id else {
            return HelperTextInsertResult(
                requestID: metadata.id,
                strategyUsed: .unsupported,
                status: .failed,
                safeFailureCode: .insertRejected
            )
        }

        guard let insertResponse = response.insertResponse else {
            return HelperTextInsertResult(
                requestID: metadata.id,
                strategyUsed: .unsupported,
                status: .failed,
                safeFailureCode: response.safeFailureCode == .none
                    ? .insertRejected
                    : response.safeFailureCode
            )
        }

        return HelperTextInsertResult(
            requestID: insertResponse.requestID,
            strategyUsed: insertResponse.strategyUsed,
            status: insertResponse.status,
            safeFailureCode: insertResponse.safeFailureCode
        )
    }

    private func send(_ request: NaruHelperNetworkRequest) async throws -> NaruHelperNetworkResponse {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw HelperTextBridgeError.unavailable(.unreachable)
        }

        let frame = try NaruHelperNetworkCodec.frame(request)
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: port,
                using: .tcp
            )
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let completion = HelperNetworkRequestCompletion(
                continuation: continuation,
                connection: connection,
                timer: timer
            )

            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                completion.complete(.failure(HelperTextBridgeError.unavailable(.insertTimedOut)))
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: frame, completion: .contentProcessed { error in
                        if error != nil {
                            completion.complete(.failure(HelperTextBridgeError.unavailable(.unreachable)))
                            return
                        }
                        Self.receiveResponse(on: connection, completion: completion)
                    })
                case .failed:
                    completion.complete(.failure(HelperTextBridgeError.unavailable(.unreachable)))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private static func receiveResponse(
        on connection: NWConnection,
        completion: HelperNetworkRequestCompletion
    ) {
        connection.receive(
            minimumIncompleteLength: NaruHelperNetworkCodec.headerByteCount,
            maximumLength: NaruHelperNetworkCodec.headerByteCount
        ) { header, _, _, error in
            if error != nil {
                completion.complete(.failure(HelperTextBridgeError.unavailable(.unreachable)))
                return
            }
            guard let header else {
                completion.complete(.failure(HelperTextBridgeError.unavailable(.unreachable)))
                return
            }

            let length: Int
            do {
                length = try NaruHelperNetworkCodec.payloadLength(from: header)
            } catch {
                completion.complete(.failure(HelperTextBridgeError.unavailable(.versionUnsupported)))
                return
            }

            connection.receive(
                minimumIncompleteLength: length,
                maximumLength: length
            ) { payload, _, _, error in
                if error != nil {
                    completion.complete(.failure(HelperTextBridgeError.unavailable(.unreachable)))
                    return
                }
                guard let payload else {
                    completion.complete(.failure(HelperTextBridgeError.unavailable(.unreachable)))
                    return
                }

                do {
                    let response = try NaruHelperNetworkCodec.decode(
                        NaruHelperNetworkResponse.self,
                        from: payload
                    )
                    completion.complete(.success(response))
                } catch {
                    completion.complete(.failure(HelperTextBridgeError.unavailable(.versionUnsupported)))
                }
            }
        }
    }
}

private final class HelperNetworkRequestCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isCompleted = false
    private let continuation: CheckedContinuation<NaruHelperNetworkResponse, Error>
    private let connection: NWConnection
    private let timer: DispatchSourceTimer

    init(
        continuation: CheckedContinuation<NaruHelperNetworkResponse, Error>,
        connection: NWConnection,
        timer: DispatchSourceTimer
    ) {
        self.continuation = continuation
        self.connection = connection
        self.timer = timer
    }

    func complete(_ result: Result<NaruHelperNetworkResponse, Error>) {
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
