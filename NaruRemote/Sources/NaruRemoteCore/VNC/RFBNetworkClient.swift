import Foundation
import Network

// @unchecked Sendable justified: RFBNetworkClient conforms to the
// public `RFBFirstFrameConnecting` / `RFBStreamingClient` /
// `RemoteClipboardTextClient` boundaries, all of which expose
// synchronous `throws` methods.  Migrating to `actor` would make
// every method `async`, breaking the protocol surface and the test
// fakes that implement the same protocols (deferred to a follow-up
// PR per PR #17's out-of-scope list).  Mutable state
// (`clientState`, `clientLastFrame`, `clientServerInit`,
// `clientFramebuffer`, `activeConnection`) is guarded by `lock` —
// every read and every write goes through `lock.withRFBClientLock`.
public final class RFBNetworkClient: RFBFirstFrameConnecting, RemoteClipboardTextClient, @unchecked Sendable {
    private static let minimumNoAuthFirstFrameTranscriptByteCount = 62

    private let lock = NSLock()
    private var clientState: RFBClientState = .disconnected
    private var clientLastFrame: RFBFrameMetadata?
    private var clientServerInit: RFBServerInit?
    private var clientFramebuffer: RFBRawFramebuffer?
    private var activeConnection: RFBNetworkConnection?

    public init() {}

    deinit {
        disconnect()
    }

    public var state: RFBClientState {
        lock.withRFBClientLock {
            clientState
        }
    }

    public var lastFrame: RFBFrameMetadata? {
        lock.withRFBClientLock {
            clientLastFrame
        }
    }

    @discardableResult
    public func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval = 2
    ) throws -> RFBServerInit {
        try connectFirstFrame(
            host: host,
            port: port,
            credential: .none,
            timeout: timeout
        )
    }

    @discardableResult
    public func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval = 2
    ) throws -> RFBServerInit {
        do {
            startConnecting()
            let connection = try RFBNetworkConnection.open(
                host: host,
                port: port,
                timeout: timeout
            )

            let serverInit = try performHandshake(
                connection: connection,
                credential: credential,
                timeout: timeout
            )

            try connection.write(
                Self.framebufferUpdateRequest(width: serverInit.width, height: serverInit.height),
                timeout: timeout
            )
            let updatePrefix = try connection.readExactly(byteCount: 4, timeout: timeout)
            let rectangleCount = Int(Self.uint16(Array(updatePrefix), at: 2))
            let updateData = try updatePrefix + connection.readExactly(
                byteCount: rectangleCount * 12,
                timeout: timeout
            )
            _ = try RFBProtocolDecoder.parseFramebufferUpdateHeader(updateData)

            lock.withRFBClientLock {
                activeConnection = connection
                clientServerInit = serverInit
                clientFramebuffer = nil
                clientLastFrame = serverInit.frameMetadata()
                clientState = .receivingFrames
            }

            return serverInit
        } catch {
            failConnection()
            throw error
        }
    }

    public func disconnect() {
        let connection = lock.withRFBClientLock {
            let connection = activeConnection
            activeConnection = nil
            clientServerInit = nil
            clientFramebuffer = nil
            clientLastFrame = nil
            clientState = .disconnected
            return connection
        }
        connection?.cancel()
    }

    @discardableResult
    public func connectNoAuthSession(
        host: String,
        port: UInt16,
        timeout: TimeInterval = 2
    ) throws -> RFBServerInit {
        try connectSession(
            host: host,
            port: port,
            credential: .none,
            timeout: timeout
        )
    }

    @discardableResult
    public func connectSession(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval = 2
    ) throws -> RFBServerInit {
        do {
            startConnecting()
            let connection = try RFBNetworkConnection.open(
                host: host,
                port: port,
                timeout: timeout
            )

            let serverInit = try performHandshake(
                connection: connection,
                credential: credential,
                timeout: timeout
            )

            lock.withRFBClientLock {
                activeConnection = connection
                clientServerInit = serverInit
                clientFramebuffer = nil
                clientLastFrame = nil
                clientState = .authenticated
            }

            return serverInit
        } catch {
            failConnection()
            throw error
        }
    }

    public func requestRawFramebufferUpdate(
        incremental: Bool = false,
        timeout: TimeInterval = 2
    ) throws -> RFBRawFramebuffer {
        try requestFramebufferUpdate(
            incremental: incremental,
            timeout: timeout
        ).framebuffer
    }

    public func requestFramebufferUpdate(
        incremental: Bool = false,
        timeout: TimeInterval = 2
    ) throws -> RFBFramebufferUpdateResult {
        let context = lock.withRFBClientLock {
            (activeConnection, clientServerInit, clientFramebuffer)
        }

        guard let connection = context.0, let serverInit = context.1 else {
            throw RFBNetworkClientError.notConnected
        }

        setState(.receivingFrames)
        try connection.write(
            Self.framebufferUpdateRequest(
                width: serverInit.width,
                height: serverInit.height,
                incremental: incremental
            ),
            timeout: timeout
        )

        let updateData = try Self.readFramebufferUpdateData(
            connection: connection,
            serverInit: serverInit,
            timeout: timeout
        )
        let updateResult = try RFBRawFramebufferDecoder.apply(
            updateData: updateData,
            serverInit: serverInit,
            previousFramebuffer: context.2
        )

        lock.withRFBClientLock {
            clientFramebuffer = updateResult.framebuffer
            clientLastFrame = serverInit.frameMetadata(receivedAt: updateResult.capturedAt)
        }

        return updateResult
    }

    public func setClipboardText(_ text: String) throws {
        guard let connection = currentActiveConnection() else {
            throw TextInjectionError.clipboardUnavailable(
                "No active RFB connection is available for text clipboard transfer."
            )
        }
        try connection.write(RFBClientMessageEncoder.clientCutText(text), timeout: 2)
    }

    public func sendPasteCommand(_ command: PasteCommand) throws {
        guard let connection = currentActiveConnection() else {
            throw TextInjectionError.pasteCommandFailed(
                "No active RFB connection is available for paste command delivery."
            )
        }
        try connection.write(RFBClientMessageEncoder.pasteCommand(command), timeout: 2)
    }

    /// Sends a single `PointerEvent` (RFC 6143 §7.5.5) on the active
    /// connection. The (x, y) coordinates come from the caller already in
    /// remote framebuffer pixel space — view→framebuffer mapping is the
    /// caller's responsibility.
    ///
    /// Per constitution §IV the coordinates are not logged at this
    /// boundary; if the connection has been torn down the call surfaces
    /// `RFBNetworkClientError.notConnected` with no extra detail.
    public func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        guard let connection = currentActiveConnection() else {
            throw RFBNetworkClientError.notConnected
        }
        try connection.write(
            RFBClientMessageEncoder.encodePointerEvent(buttonMask: buttonMask, x: x, y: y),
            timeout: 2
        )
    }

    /// Reads a single server-to-client `ServerCutText` message off the active
    /// connection and returns its UTF-8 payload. The fixed 8-byte header
    /// (1 byte message type + 3 bytes padding + 4 bytes big-endian length) is
    /// pulled first, then the declared payload length is read in full. Truncated
    /// or malformed payloads surface as typed
    /// ``RFBProtocolDecoderError`` values — never as a trap.
    ///
    /// Note: callers must know the next message on the wire is a
    /// `ServerCutText`. A non-3 message-type byte is rejected with
    /// ``RFBProtocolDecoderError/unexpectedMessageType(_:)``.
    public func receiveServerCutText(timeout: TimeInterval = 2) throws -> String {
        guard let connection = currentActiveConnection() else {
            throw TextInjectionError.clipboardUnavailable(
                "No active RFB connection is available for clipboard receive."
            )
        }

        let header = try connection.readExactly(byteCount: 8, timeout: timeout)
        let headerBytes = Array(header)
        guard headerBytes[0] == 3 else {
            throw RFBProtocolDecoderError.unexpectedMessageType(headerBytes[0])
        }

        let payloadLength = Int(Self.uint32(headerBytes, at: 4))
        let payload: Data
        if payloadLength > 0 {
            payload = try connection.readExactly(byteCount: payloadLength, timeout: timeout)
        } else {
            payload = Data()
        }

        return try RFBProtocolDecoder.parseServerCutText(header + payload)
    }

    @discardableResult
    public func connectNoAuthTranscript(
        host: String,
        port: UInt16,
        expectedByteCount: Int = 62,
        timeout: TimeInterval = 2
    ) throws -> RFBServerInit {
        do {
            startConnecting()
            let transcript = try RFBNetworkTranscriptReader.read(
                host: host,
                port: port,
                expectedByteCount: expectedByteCount,
                timeout: timeout
            )
            try validateNoAuthFirstFrameTranscript(transcript)

            setState(.handshaking)
            _ = try RFBProtocolDecoder.parseVersion(transcript[safe: 0..<12])
            let securityTypes = try RFBProtocolDecoder.parseSecurityTypes(transcript[safe: 12..<14])
            guard securityTypes.supportsNone else {
                throw RFBNetworkClientError.unsupportedSecurityTypes(securityTypes.types)
            }

            try RFBProtocolDecoder.parseSecurityResult(transcript[safe: 14..<18])
            setState(.authenticated)

            let serverInit = try RFBProtocolDecoder.parseServerInit(transcript[safe: 18..<46])
            _ = try RFBProtocolDecoder.parseFramebufferUpdateHeader(transcript[safe: 46..<62])

            lock.withRFBClientLock {
                clientServerInit = serverInit
                clientFramebuffer = nil
                clientLastFrame = serverInit.frameMetadata()
                clientState = .receivingFrames
            }

            return serverInit
        } catch {
            failConnection()
            throw error
        }
    }

    private func startConnecting() {
        let connection = lock.withRFBClientLock {
            let connection = activeConnection
            activeConnection = nil
            clientServerInit = nil
            clientFramebuffer = nil
            clientLastFrame = nil
            clientState = .connecting
            return connection
        }
        connection?.cancel()
    }

    private func setState(_ state: RFBClientState) {
        lock.withRFBClientLock {
            clientState = state
        }
    }

    private func failConnection() {
        let connection = lock.withRFBClientLock {
            let connection = activeConnection
            activeConnection = nil
            clientServerInit = nil
            clientFramebuffer = nil
            clientLastFrame = nil
            clientState = .failed
            return connection
        }
        connection?.cancel()
    }

    private func currentActiveConnection() -> RFBNetworkConnection? {
        lock.withRFBClientLock {
            activeConnection
        }
    }

    private func validateNoAuthFirstFrameTranscript(_ transcript: Data) throws {
        guard transcript.count >= Self.minimumNoAuthFirstFrameTranscriptByteCount else {
            throw RFBNetworkClientError.incompleteTranscript(
                expected: Self.minimumNoAuthFirstFrameTranscriptByteCount,
                actual: transcript.count
            )
        }
    }

    private func performHandshake(
        connection: RFBNetworkConnection,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        setState(.handshaking)
        _ = try RFBProtocolDecoder.parseVersion(connection.readExactly(byteCount: 12, timeout: timeout))
        try connection.write(Data("RFB 003.008\n".utf8), timeout: timeout)

        let securityTypeCount = try connection.readExactly(byteCount: 1, timeout: timeout)
        let securityTypesData = try securityTypeCount + connection.readExactly(
            byteCount: Int(securityTypeCount[0]),
            timeout: timeout
        )
        let securityTypes = try RFBProtocolDecoder.parseSecurityTypes(securityTypesData)
        let selectedSecurityType = try Self.selectSecurityType(
            from: securityTypes,
            credential: credential
        )

        try connection.write(Data([selectedSecurityType.rawValue]), timeout: timeout)
        switch selectedSecurityType {
        case .none:
            break
        case .vncAuthentication:
            guard case .vncPassword(let password) = credential else {
                throw RFBNetworkClientError.authenticationRequired(securityTypes.types)
            }

            let challenge = try connection.readExactly(byteCount: 16, timeout: timeout)
            let response = try RFBVNCAuthentication.response(password: password, challenge: challenge)
            try connection.write(response, timeout: timeout)
        }

        try RFBProtocolDecoder.parseSecurityResult(connection.readExactly(byteCount: 4, timeout: timeout))
        setState(.authenticated)

        try connection.write(Data([1]), timeout: timeout)

        let serverInitPrefix = try connection.readExactly(byteCount: 24, timeout: timeout)
        let nameLength = Int(Self.uint32(Array(serverInitPrefix), at: 20))
        let serverInitData = try serverInitPrefix + connection.readExactly(
            byteCount: nameLength,
            timeout: timeout
        )
        return try RFBProtocolDecoder.parseServerInit(serverInitData)
    }

    private static func selectSecurityType(
        from securityTypes: RFBSecurityTypes,
        credential: RFBConnectionCredential
    ) throws -> RFBSecurityType {
        if case .vncPassword = credential, securityTypes.supportsVNCAuthentication {
            return .vncAuthentication
        }

        if securityTypes.supportsNone {
            return .none
        }

        if securityTypes.supportsVNCAuthentication {
            throw RFBNetworkClientError.authenticationRequired(securityTypes.types)
        }

        throw RFBNetworkClientError.unsupportedSecurityTypes(securityTypes.types)
    }

    private static func readFramebufferUpdateData(
        connection: RFBNetworkConnection,
        serverInit: RFBServerInit,
        timeout: TimeInterval
    ) throws -> Data {
        let updatePrefix = try connection.readExactly(byteCount: 4, timeout: timeout)
        let rectangleCount = Int(Self.uint16(Array(updatePrefix), at: 2))
        let rectangleHeaderData = try connection.readExactly(
            byteCount: rectangleCount * 12,
            timeout: timeout
        )
        let updateHeader = try RFBProtocolDecoder.parseFramebufferUpdateHeader(updatePrefix + rectangleHeaderData)
        let bytesPerPixel = Int(serverInit.pixelFormat.bitsPerPixel) / 8

        var payload = Data()
        for rectangle in updateHeader.rectangles {
            guard rectangle.encodingType == 0 else {
                throw RFBNetworkClientError.unsupportedFramebufferEncoding(rectangle.encodingType)
            }

            let pixelByteCount = rectangle.width * rectangle.height * bytesPerPixel
            payload += try connection.readExactly(byteCount: pixelByteCount, timeout: timeout)
        }

        return updatePrefix + rectangleHeaderData + payload
    }

    private static func framebufferUpdateRequest(
        width: Int,
        height: Int,
        incremental: Bool = false
    ) -> Data {
        var bytes: [UInt8] = [3, incremental ? 1 : 0]
        bytes.append(contentsOf: uint16Bytes(0))
        bytes.append(contentsOf: uint16Bytes(0))
        bytes.append(contentsOf: uint16Bytes(UInt16(max(0, min(width, Int(UInt16.max))))))
        bytes.append(contentsOf: uint16Bytes(UInt16(max(0, min(height, Int(UInt16.max))))))
        return Data(bytes)
    }

    private static func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0x00ff)]
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 |
            UInt32(bytes[offset + 1]) << 16 |
            UInt32(bytes[offset + 2]) << 8 |
            UInt32(bytes[offset + 3])
    }
}

extension RFBNetworkClient: RFBStreamingClient, RFBDamageTrackingFramebufferUpdating {}

public enum RFBNetworkClientError: Error, Equatable, LocalizedError {
    case invalidPort(UInt16)
    case timedOut
    case incompleteTranscript(expected: Int, actual: Int)
    case connectionFailed
    case writeFailed
    case authenticationRequired([UInt8])
    case unsupportedSecurityTypes([UInt8])
    case unsupportedFramebufferEncoding(Int32)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid RFB port: \(port)"
        case .timedOut:
            return "Timed out while reading RFB transcript."
        case .incompleteTranscript(let expected, let actual):
            return "RFB transcript incomplete. Expected \(expected) bytes, received \(actual)."
        case .connectionFailed:
            return "RFB TCP connection failed."
        case .writeFailed:
            return "RFB write failed."
        case .authenticationRequired(let types):
            return "RFB server requires authentication. Supported security types: \(types)"
        case .unsupportedSecurityTypes(let types):
            return "Unsupported RFB security types: \(types)"
        case .unsupportedFramebufferEncoding(let encoding):
            return "Unsupported RFB framebuffer encoding: \(encoding)"
        case .notConnected:
            return "No active RFB connection is available."
        }
    }
}

/// Wraps an `NWConnection` and its serial dispatch queue in a
/// connection-scoped object.  Both stored properties are `let` and
/// `Sendable` (`NWConnection` is `Sendable` on iOS 17+, `DispatchQueue`
/// is `Sendable`), so this class is `Sendable` by structure and does
/// not need `@unchecked`.  Mutable connection state (read buffer,
/// write completion, ready/failed signal) lives in the
/// `RFBNetwork{Read,Write,Ready}State` helpers, not here.
private final class RFBNetworkConnection: Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "naru.rfb-network-connection")

    private init(connection: NWConnection) {
        self.connection = connection
    }

    static func open(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBNetworkConnection {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw RFBNetworkClientError.invalidPort(port)
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let readyState = RFBNetworkConnectionReadyState()
        let wrapper = RFBNetworkConnection(connection: connection)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                readyState.markReady()
            case .failed:
                readyState.markFailed()
            default:
                break
            }
        }

        connection.start(queue: wrapper.queue)
        try readyState.wait(timeout: timeout)
        return wrapper
    }

    func readExactly(byteCount: Int, timeout: TimeInterval) throws -> Data {
        guard byteCount > 0 else {
            return Data()
        }

        let state = RFBNetworkReadState(expectedByteCount: byteCount)
        receiveNext(into: state, remainingByteCount: byteCount)
        return try state.wait(timeout: timeout)
    }

    func write(_ data: Data, timeout: TimeInterval) throws {
        guard !data.isEmpty else {
            return
        }

        let state = RFBNetworkWriteState()
        connection.send(content: data, completion: .contentProcessed { error in
            if error == nil {
                state.succeed()
            } else {
                state.fail()
            }
        })
        try state.wait(timeout: timeout)
    }

    func cancel() {
        connection.cancel()
    }

    private func receiveNext(into state: RFBNetworkReadState, remainingByteCount: Int) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: max(1, remainingByteCount)
        ) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                state.append(data)
            }

            if error != nil {
                state.fail(.connectionFailed)
                return
            }

            let remaining = remainingByteCount - (data?.count ?? 0)
            if state.byteCount >= state.expectedByteCountForConnection || remaining <= 0 {
                state.finish()
                return
            }

            if isComplete {
                state.finish()
                return
            }

            receiveNext(into: state, remainingByteCount: remaining)
        }
    }
}

// @unchecked Sendable justified: this is a single-shot
// semaphore + result box that bridges an `NWConnection`
// stateUpdateHandler callback (fires on a Network.framework
// dispatch queue) to a synchronous `wait(timeout:)` call on the
// caller thread.  Migrating to `actor` would force `wait` to be
// `async`, which cascades through `RFBNetworkConnection.open`,
// `RFBNetworkClient.connectFirstFrame` / `connectSession`, and the
// public RFB protocol surface — all of which the test fakes for
// the connector protocols (deferred per PR #17) currently
// implement synchronously.  Mutable state (`result`) is guarded
// by `lock`; the semaphore is signalled exactly once via the
// `shouldSignal` guard inside `complete(_:)`.
private final class RFBNetworkConnectionReadyState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Void, RFBNetworkClientError>?

    func markReady() {
        complete(.success(()))
    }

    func markFailed() {
        complete(.failure(.connectionFailed))
    }

    func wait(timeout: TimeInterval) throws {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw RFBNetworkClientError.timedOut
        }

        switch currentResult {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw RFBNetworkClientError.timedOut
        }
    }

    private var currentResult: Result<Void, RFBNetworkClientError>? {
        lock.withRFBClientLock {
            result
        }
    }

    private func complete(_ result: Result<Void, RFBNetworkClientError>) {
        let shouldSignal = lock.withRFBClientLock {
            guard self.result == nil else {
                return false
            }
            self.result = result
            return true
        }

        if shouldSignal {
            semaphore.signal()
        }
    }
}

// @unchecked Sendable justified: companion to
// `RFBNetworkConnectionReadyState` — a single-shot
// semaphore + result box bridging an `NWConnection.send`
// completion (fires on a Network.framework dispatch queue) to a
// synchronous `wait(timeout:)` on the caller thread.  Migrating to
// `actor` would make `wait` `async` and cascade through every
// `connection.write(_:timeout:)` call site, which the synchronous
// public RFB API (and the test fakes that mirror it) require to
// stay sync until the connector-protocol follow-up lands.
private final class RFBNetworkWriteState: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<Void, RFBNetworkClientError>?

    func succeed() {
        complete(.success(()))
    }

    func fail() {
        complete(.failure(.writeFailed))
    }

    func wait(timeout: TimeInterval) throws {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw RFBNetworkClientError.timedOut
        }

        switch currentResult {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw RFBNetworkClientError.timedOut
        }
    }

    private var currentResult: Result<Void, RFBNetworkClientError>? {
        lock.withRFBClientLock {
            result
        }
    }

    private func complete(_ result: Result<Void, RFBNetworkClientError>) {
        let shouldSignal = lock.withRFBClientLock {
            guard self.result == nil else {
                return false
            }
            self.result = result
            return true
        }

        if shouldSignal {
            semaphore.signal()
        }
    }
}

private enum RFBNetworkTranscriptReader {
    static func read(
        host: String,
        port: UInt16,
        expectedByteCount: Int,
        timeout: TimeInterval
    ) throws -> Data {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw RFBNetworkClientError.invalidPort(port)
        }

        let queue = DispatchQueue(label: "naru.rfb-network-client")
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let state = RFBNetworkReadState(expectedByteCount: expectedByteCount)
        let reader = RFBNetworkConnectionReader(
            connection: connection,
            state: state,
            expectedByteCount: expectedByteCount
        )

        connection.stateUpdateHandler = { connectionState in
            switch connectionState {
            case .ready:
                reader.receiveNext()
            case .failed:
                state.fail(.connectionFailed)
            default:
                break
            }
        }

        connection.start(queue: queue)
        defer { connection.cancel() }

        return try state.wait(timeout: timeout)
    }
}

/// Pure read driver for one transcript-style read.  All stored
/// properties are `let` and the referenced `RFBNetworkReadState`
/// is itself `Sendable` (under `@unchecked` justified above), so
/// this class is `Sendable` by structure and does not need
/// `@unchecked`.
private final class RFBNetworkConnectionReader: Sendable {
    private let connection: NWConnection
    private let state: RFBNetworkReadState
    private let expectedByteCount: Int

    init(
        connection: NWConnection,
        state: RFBNetworkReadState,
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

            if error != nil {
                state.fail(.connectionFailed)
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

// @unchecked Sendable justified: accumulates byte chunks delivered
// by `NWConnection.receive` callbacks (Network.framework dispatch
// queue) into a single `Data` and surfaces them through a
// synchronous `wait(timeout:)` call.  Migrating to `actor` would
// force every accessor (`append`, `byteCount`, `finish`, `fail`,
// `wait`) to be `async`, which cascades through
// `RFBNetworkConnection.readExactly` and the public sync RFB API
// (deferred per PR #17).  Mutable state (`bytes`, `result`) is
// guarded by `lock`; the completion semaphore is signalled exactly
// once via the `shouldSignal` guard inside `complete(_:)`.
private final class RFBNetworkReadState: @unchecked Sendable {
    private let expectedByteCount: Int
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var bytes = Data()
    private var result: Result<Data, RFBNetworkClientError>?

    init(expectedByteCount: Int) {
        self.expectedByteCount = expectedByteCount
    }

    var expectedByteCountForConnection: Int {
        expectedByteCount
    }

    var byteCount: Int {
        lock.withRFBClientLock {
            bytes.count
        }
    }

    func append(_ data: Data) {
        lock.withRFBClientLock {
            bytes.append(data)
        }
    }

    func finish() {
        let data = lock.withRFBClientLock {
            bytes
        }

        guard data.count >= expectedByteCount else {
            fail(.incompleteTranscript(expected: expectedByteCount, actual: data.count))
            return
        }

        complete(.success(data))
    }

    func fail(_ error: RFBNetworkClientError) {
        complete(.failure(error))
    }

    func wait(timeout: TimeInterval) throws -> Data {
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw RFBNetworkClientError.timedOut
        }

        switch currentResult {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        case nil:
            throw RFBNetworkClientError.timedOut
        }
    }

    private var currentResult: Result<Data, RFBNetworkClientError>? {
        lock.withRFBClientLock {
            result
        }
    }

    private func complete(_ result: Result<Data, RFBNetworkClientError>) {
        let shouldSignal = lock.withRFBClientLock {
            guard self.result == nil else {
                return false
            }
            self.result = result
            return true
        }

        if shouldSignal {
            semaphore.signal()
        }
    }
}

private extension Data {
    subscript(safe range: Range<Int>) -> Data {
        precondition(range.lowerBound >= 0)
        precondition(range.upperBound <= count)

        return subdata(in: range)
    }
}

private extension NSLock {
    func withRFBClientLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
