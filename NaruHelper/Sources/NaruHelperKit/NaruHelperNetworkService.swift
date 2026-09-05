import Foundation
import NaruRemoteCore

public protocol NaruHelperPairingRevocationStore: AnyObject, Sendable {
    func isRevoked(pairingSecret: String) -> Bool
    func revoke(pairingSecret: String)
}

public final class InMemoryNaruHelperPairingRevocationStore: NaruHelperPairingRevocationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var revokedSecrets: Set<String> = []

    public init() {}

    public func isRevoked(pairingSecret: String) -> Bool {
        lock.withLock {
            revokedSecrets.contains(pairingSecret)
        }
    }

    public func revoke(pairingSecret: String) {
        _ = lock.withLock {
            revokedSecrets.insert(pairingSecret)
        }
    }
}

public struct NaruHelperNetworkRequestHandler: Sendable {
    public typealias CapabilityProvider = @Sendable () -> NaruHelperCapabilityResponse
    public typealias InsertHandler = @Sendable (NaruHelperInsertTextRequest) -> NaruHelperInsertTextResponse
    /// Spec 041 FR-007: `nil` means the pairing state is gone (revoked or
    /// never paired) — never a cue to fall back to a launch-time secret.
    public typealias PairingSecretProvider = @Sendable () -> String?

    private let expectedPairingSecret: String
    private let pairingSecretProvider: PairingSecretProvider?
    private let revocationStore: any NaruHelperPairingRevocationStore
    private let onAuthorizedRequest: (@Sendable () -> Void)?
    private let capabilityProvider: CapabilityProvider
    private let insertHandler: InsertHandler

    public init(
        expectedPairingSecret: String,
        pairingSecretProvider: PairingSecretProvider? = nil,
        revocationStore: any NaruHelperPairingRevocationStore = InMemoryNaruHelperPairingRevocationStore(),
        onAuthorizedRequest: (@Sendable () -> Void)? = nil,
        capabilityProvider: @escaping CapabilityProvider,
        insertHandler: @escaping InsertHandler
    ) {
        self.expectedPairingSecret = expectedPairingSecret
        self.pairingSecretProvider = pairingSecretProvider
        self.revocationStore = revocationStore
        self.onAuthorizedRequest = onAuthorizedRequest
        self.capabilityProvider = capabilityProvider
        self.insertHandler = insertHandler
    }

    public func handle(_ request: NaruHelperNetworkRequest) -> NaruHelperNetworkResponse {
        guard request.schemaVersion == naruHelperTextBridgeSchemaVersion else {
            return failure(requestID: request.requestID, code: .versionUnsupported)
        }

        // Rotation (spec 040 FR-002) and revoke (spec 041 FR-007): with a
        // provider attached the handshake reads the current pairing state
        // per request, so a token minted by a later `--pair` run is honored
        // immediately, a superseded token is refused, and a `nil` answer —
        // the state file is gone — is a refusal. `expectedPairingSecret`
        // is consulted only when no provider is attached (the env-pinned
        // benchmark path).
        let currentSecret: String
        if let pairingSecretProvider {
            guard let providedSecret = pairingSecretProvider() else {
                return failure(requestID: request.requestID, code: .revoked)
            }
            currentSecret = providedSecret
        } else {
            currentSecret = expectedPairingSecret
        }
        guard request.pairingSecret == currentSecret else {
            return failure(requestID: request.requestID, code: .revoked)
        }

        if revocationStore.isRevoked(pairingSecret: request.pairingSecret) {
            return failure(requestID: request.requestID, code: .revoked)
        }

        onAuthorizedRequest?()

        switch request.command {
        case .capability:
            return NaruHelperNetworkResponse(
                requestID: request.requestID,
                capabilityResponse: capabilityProvider()
            )
        case .insertText:
            guard let insertRequest = request.insertRequest else {
                return NaruHelperNetworkResponse(
                    requestID: request.requestID,
                    insertResponse: insertFailure(
                        requestID: request.requestID,
                        code: .insertRejected
                    ),
                    safeFailureCode: .insertRejected
                )
            }
            let insertResponse = insertHandler(insertRequest)
            return NaruHelperNetworkResponse(
                requestID: request.requestID,
                insertResponse: insertResponse,
                safeFailureCode: insertResponse.safeFailureCode
            )
        case .revokePairing:
            revocationStore.revoke(pairingSecret: request.pairingSecret)
            return failure(requestID: request.requestID, code: .revoked)
        }
    }

    private func failure(
        requestID: UUID,
        code: HelperTextBridgeFailureCode
    ) -> NaruHelperNetworkResponse {
        NaruHelperNetworkResponse(
            requestID: requestID,
            safeFailureCode: code
        )
    }

    private func insertFailure(
        requestID: UUID,
        code: HelperTextBridgeFailureCode
    ) -> NaruHelperInsertTextResponse {
        NaruHelperInsertTextResponse(
            requestID: requestID,
            status: .failed,
            strategyUsed: .unsupported,
            safeFailureCode: code
        )
    }
}

#if canImport(Network)
import Network

public final class NaruHelperNetworkServer: @unchecked Sendable {
    private let handler: NaruHelperNetworkRequestHandler
    private let queue: DispatchQueue
    private let listener: NWListener
    private let requestedPort: UInt16?

    /// Spec 041 FR-002: listener state as fixed-catalog values, driven from
    /// `NWListener.stateUpdateHandler`. Settable before or after ``start()``.
    public var onStateChange: (@Sendable (NaruHelperListenerState) -> Void)? {
        didSet { installStateHandler() }
    }

    public init(
        port: UInt16 = UInt16(naruHelperTextBridgeDefaultPort),
        handler: NaruHelperNetworkRequestHandler,
        queue: DispatchQueue = DispatchQueue(label: "com.naruremote.helper-network-server")
    ) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw HelperTextBridgeError.unavailable(.unreachable)
        }
        self.handler = handler
        self.queue = queue
        self.requestedPort = port
        self.listener = try NWListener(using: .tcp, on: endpointPort)
    }

    public init(
        handler: NaruHelperNetworkRequestHandler,
        queue: DispatchQueue = DispatchQueue(label: "com.naruremote.helper-network-server")
    ) throws {
        self.handler = handler
        self.queue = queue
        self.requestedPort = nil
        self.listener = try NWListener(using: .tcp)
    }

    public var port: UInt16? {
        listener.port?.rawValue
    }

    public func start() {
        installStateHandler()
        listener.newConnectionHandler = { [handler, queue] connection in
            connection.start(queue: queue)
            Self.receiveRequest(on: connection, handler: handler)
        }
        listener.start(queue: queue)
    }

    public func cancel() {
        listener.cancel()
    }

    /// Idempotent: safe to call from ``onStateChange``'s didSet and again
    /// in ``start()`` regardless of wiring order.
    private func installStateHandler() {
        NaruHelperListenerState.install(
            on: listener,
            requestedPort: requestedPort,
            onChange: onStateChange
        )
    }

    private static func receiveRequest(
        on connection: NWConnection,
        handler: NaruHelperNetworkRequestHandler
    ) {
        connection.receive(
            minimumIncompleteLength: NaruHelperNetworkCodec.headerByteCount,
            maximumLength: NaruHelperNetworkCodec.headerByteCount
        ) { header, _, _, error in
            guard error == nil, let header else {
                connection.cancel()
                return
            }

            let length: Int
            do {
                length = try NaruHelperNetworkCodec.payloadLength(from: header)
            } catch {
                connection.cancel()
                return
            }

            connection.receive(
                minimumIncompleteLength: length,
                maximumLength: length
            ) { payload, _, _, error in
                guard error == nil, let payload else {
                    connection.cancel()
                    return
                }

                let response: NaruHelperNetworkResponse
                do {
                    let request = try NaruHelperNetworkCodec.decode(
                        NaruHelperNetworkRequest.self,
                        from: payload
                    )
                    response = handler.handle(request)
                } catch {
                    response = NaruHelperNetworkResponse(
                        requestID: UUID(),
                        safeFailureCode: .versionUnsupported
                    )
                }

                do {
                    let responseFrame = try NaruHelperNetworkCodec.frame(response)
                    connection.send(content: responseFrame, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                } catch {
                    connection.cancel()
                }
            }
        }
    }
}
#endif

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
