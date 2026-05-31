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

    private let encodingPreference: RFBEncodingPreference
    private let lock = NSLock()
    private var clientState: RFBClientState = .disconnected
    private var clientLastFrame: RFBFrameMetadata?
    private var clientServerInit: RFBServerInit?
    private var clientFramebuffer: RFBRawFramebuffer?
    /// Per-session persistent zlib inflate for ZRLE (spec 004 FR-005).
    /// Created fresh on each connect, torn down with the connection — a
    /// new session must start a fresh zlib window.
    private var clientZlibStream: RFBZlibInflateStream?
    /// Per-session Tight zlib streams (four independent streams, reset
    /// by Tight rectangle control bits).
    private var clientTightZlibStreams: RFBTightZlibStreams?
    private var activeConnection: RFBNetworkConnection?

    public convenience init() {
        self.init(encodingPreference: .localLowLatency)
    }

    public init(encodingPreference: RFBEncodingPreference) {
        self.encodingPreference = encodingPreference
    }

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
        var pendingConnection: RFBNetworkConnection?
        do {
            startConnecting()
            let connection = try RFBNetworkConnection.open(
                host: host,
                port: port,
                timeout: timeout
            )
            pendingConnection = connection

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

            let zlibStream = try RFBZlibInflateStream()
            let tightZlibStreams = RFBTightZlibStreams()
            lock.withRFBClientLock {
                activeConnection = connection
                clientServerInit = serverInit
                clientFramebuffer = nil
                clientZlibStream = zlibStream
                clientTightZlibStreams = tightZlibStreams
                clientLastFrame = serverInit.frameMetadata()
                clientState = .receivingFrames
            }
            pendingConnection = nil

            return serverInit
        } catch {
            pendingConnection?.cancel()
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
            clientZlibStream = nil
            clientTightZlibStreams = nil
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
        var pendingConnection: RFBNetworkConnection?
        do {
            startConnecting()
            let connection = try RFBNetworkConnection.open(
                host: host,
                port: port,
                timeout: timeout
            )
            pendingConnection = connection

            let serverInit = try performHandshake(
                connection: connection,
                credential: credential,
                timeout: timeout
            )

            let zlibStream = try RFBZlibInflateStream()
            let tightZlibStreams = RFBTightZlibStreams()
            lock.withRFBClientLock {
                activeConnection = connection
                clientServerInit = serverInit
                clientFramebuffer = nil
                clientZlibStream = zlibStream
                clientTightZlibStreams = tightZlibStreams
                clientLastFrame = nil
                clientState = .authenticated
            }
            pendingConnection = nil

            return serverInit
        } catch {
            pendingConnection?.cancel()
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
            (activeConnection, clientServerInit)
        }

        guard let connection = context.0, let serverInit = context.1 else {
            throw RFBNetworkClientError.notConnected
        }

        setState(.receivingFrames)
        try writeActiveConnection(
            Self.framebufferUpdateRequest(
                width: serverInit.width,
                height: serverInit.height,
                incremental: incremental
            ),
            to: connection,
            timeout: timeout
        )

        return try receiveFramebufferUpdate(timeout: timeout)
    }

    /// Reads one server-sent `FramebufferUpdate` without first sending
    /// a `FramebufferUpdateRequest`. This is the decode seam needed by
    /// ContinuousUpdates-style transports, where the server is allowed
    /// to push updates after the client has enabled the extension. The
    /// result commits through the same framebuffer/zlib/resize path as
    /// request-response updates.
    public func receiveFramebufferUpdate(timeout: TimeInterval = 2) throws -> RFBFramebufferUpdateResult {
        let context = lock.withRFBClientLock {
            (activeConnection, clientServerInit, clientFramebuffer, clientZlibStream, clientTightZlibStreams)
        }

        guard let connection = context.0, let serverInit = context.1 else {
            throw RFBNetworkClientError.notConnected
        }

        setState(.receivingFrames)

        // Decode the next framebuffer update incrementally off the live
        // socket so variable-length encodings (Hextile / CopyRect /
        // ZRLE) work over a TCP stream that may split a rectangle across
        // reads (spec 004 FR-002). The reader also consumes TigerVNC
        // transport-control messages that may arrive before a frame.
        let reader = ConnectionByteReader(connection: connection, timeout: timeout)
        let updateResult: RFBFramebufferUpdateResult
        do {
            updateResult = try receiveNextFramebufferUpdate(
                connection: connection,
                reader: reader,
                serverInit: serverInit,
                previousFramebuffer: context.2,
                zlibStream: context.3,
                tightZlibStreams: context.4,
                timeout: timeout
            )
        } catch {
            failConnection(connection)
            throw error
        }

        // A DesktopSize / ExtendedDesktopSize pseudo-rectangle reallocated
        // the framebuffer — refresh the cached server dimensions so the
        // next FramebufferUpdateRequest and previous-frame match the new
        // size (spec 004 FR-008).
        let effectiveServerInit = updateResult.didResizeDesktop
            ? RFBServerInit(
                width: updateResult.framebuffer.width,
                height: updateResult.framebuffer.height,
                pixelFormat: serverInit.pixelFormat,
                name: serverInit.name
            )
            : serverInit

        lock.withRFBClientLock {
            clientServerInit = effectiveServerInit
            clientFramebuffer = updateResult.framebuffer
            clientLastFrame = effectiveServerInit.frameMetadata(receivedAt: updateResult.capturedAt)
        }

        return updateResult
    }

    private func receiveNextFramebufferUpdate(
        connection: RFBNetworkConnection,
        reader: RFBByteReader,
        serverInit: RFBServerInit,
        previousFramebuffer: RFBRawFramebuffer?,
        zlibStream: RFBZlibInflateStream?,
        tightZlibStreams: RFBTightZlibStreams?,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult {
        while true {
            let messageType = try reader.readUInt8()
            switch messageType {
            case 0:
                return try RFBFramebufferDecoder.decodeUpdate(
                    reader: PrefixedByteReader(prefix: [messageType], base: reader),
                    serverInit: serverInit,
                    previousFramebuffer: previousFramebuffer,
                    zlibStream: zlibStream,
                    tightZlibStreams: tightZlibStreams
                )
            case 2:
                // Bell has no payload. It can legally arrive between
                // framebuffer updates; keep waiting for the next frame.
                continue
            case 150:
                // EndOfContinuousUpdates is a one-byte TigerVNC server
                // control message. It is also the server's support
                // confirmation for the ContinuousUpdates pseudo-encoding.
                // Once a framebuffer exists, surface it as a zero-change
                // liveness frame so the frame pump can stop waiting for
                // pushed updates and fall back to request/response.
                if let previousFramebuffer {
                    return RFBFramebufferUpdateResult(
                        framebuffer: previousFramebuffer,
                        dirtyRectangles: [],
                        changedPixelCount: 0,
                        endedContinuousUpdates: true
                    )
                }
                continue
            case 248:
                try handleServerFence(
                    reader: reader,
                    connection: connection,
                    timeout: timeout
                )
                continue
            default:
                throw RFBProtocolDecoderError.unexpectedMessageType(messageType)
            }
        }
    }

    private func handleServerFence(
        reader: RFBByteReader,
        connection: RFBNetworkConnection,
        timeout: TimeInterval
    ) throws {
        try reader.skip(3)
        let rawFlags = try reader.readUInt32()
        let payloadLength = Int(try reader.readUInt8())
        let payloadBytes = try reader.readBytes(payloadLength)
        let flags = RFBFenceFlags(rawValue: rawFlags)

        guard payloadLength <= 64 else {
            throw RFBClientMessageEncodingError.fencePayloadTooLarge(
                maximum: 64,
                actual: payloadLength
            )
        }
        guard flags.contains(.request) else {
            return
        }

        let responseFlags = RFBFenceFlags(
            rawValue: rawFlags
                & RFBFenceFlags.supported.rawValue
                & ~RFBFenceFlags.request.rawValue
        )
        try connection.write(
            try RFBClientMessageEncoder.fence(
                flags: responseFlags,
                payload: Data(payloadBytes)
            ),
            timeout: timeout
        )
    }

    public func setClipboardText(_ text: String) throws {
        guard let connection = currentActiveConnection() else {
            throw TextInjectionError.clipboardUnavailable(
                "No active RFB connection is available for text clipboard transfer."
            )
        }
        try writeActiveConnection(
            RFBClientMessageEncoder.clientCutText(text),
            to: connection,
            timeout: 2
        )
    }

    public func sendPasteCommand(_ command: PasteCommand) throws {
        guard let connection = currentActiveConnection() else {
            throw TextInjectionError.pasteCommandFailed(
                "No active RFB connection is available for paste command delivery."
            )
        }
        try writeActiveConnection(
            RFBClientMessageEncoder.pasteCommand(command),
            to: connection,
            timeout: 2
        )
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
        try writeActiveConnection(
            RFBClientMessageEncoder.encodePointerEvent(buttonMask: buttonMask, x: x, y: y),
            to: connection,
            timeout: 2
        )
    }

    /// Sends a single `KeyEvent` (RFC 6143 §7.5.4, message type 4)
    /// on the active connection. The keysym comes from the caller
    /// already as an X11 keysym integer — character / hardware
    /// keycode → keysym mapping is the caller's responsibility
    /// (`KeysymMapping` in the `RemoteInputDock` module owns that
    /// table).
    ///
    /// Per constitution §IV the keysym and isDown values are not
    /// logged at this boundary; if the connection has been torn
    /// down the call surfaces `RFBNetworkClientError.notConnected`
    /// with no extra detail.
    public func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        guard let connection = currentActiveConnection() else {
            throw RFBNetworkClientError.notConnected
        }
        try writeActiveConnection(
            RFBClientMessageEncoder.keyEvent(keysym: keysym, isDown: isDown),
            to: connection,
            timeout: 2
        )
    }

    /// Re-sends `SetEncodings` on the active session so a caller can
    /// switch between low-latency and bandwidth-first profiles after
    /// observing connection quality. The preference list is a fixed
    /// catalog of encoding codes; this method logs no latency values,
    /// framebuffer geometry, or payload details.
    public func renegotiateEncodings(
        _ preference: RFBEncodingPreference,
        timeout: TimeInterval = 2
    ) throws {
        try writeControlMessage(
            RFBClientMessageEncoder.setEncodings(preference.encodingList()),
            timeout: timeout
        )
    }

    /// Sends TigerVNC's `EnableContinuousUpdates` control message for
    /// the supplied framebuffer region. When `region` is nil, the
    /// current session framebuffer size is used and clamped to the RFB
    /// u16 wire fields. This is transport pacing control only; no user
    /// input or pixel payload crosses this boundary.
    public func enableContinuousUpdates(
        _ enabled: Bool,
        region: RFBFramebufferUpdateRegion? = nil,
        timeout: TimeInterval = 2
    ) throws {
        let context = lock.withRFBClientLock {
            (activeConnection, clientServerInit)
        }
        guard let connection = context.0 else {
            throw RFBNetworkClientError.notConnected
        }

        let updateRegion = region ?? RFBFramebufferUpdateRegion(
            x: 0,
            y: 0,
            width: Self.clampedUInt16(context.1?.width ?? 0),
            height: Self.clampedUInt16(context.1?.height ?? 0)
        )

        try writeActiveConnection(
            RFBClientMessageEncoder.enableContinuousUpdates(
                enabled,
                x: updateRegion.x,
                y: updateRegion.y,
                width: updateRegion.width,
                height: updateRegion.height
            ),
            to: connection,
            timeout: timeout
        )
    }

    /// Sends TigerVNC's `ClientFence` control message on the active
    /// session. Payload validation is handled by
    /// `RFBClientMessageEncoder`; callers should keep payloads opaque
    /// and non-user-content per spec 004's logging boundary.
    public func sendFence(
        flags: RFBFenceFlags,
        payload: Data = Data(),
        timeout: TimeInterval = 2
    ) throws {
        try writeControlMessage(
            try RFBClientMessageEncoder.fence(flags: flags, payload: payload),
            timeout: timeout
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

            let zlibStream = try RFBZlibInflateStream()
            let tightZlibStreams = RFBTightZlibStreams()
            lock.withRFBClientLock {
                clientServerInit = serverInit
                clientFramebuffer = nil
                clientZlibStream = zlibStream
                clientTightZlibStreams = tightZlibStreams
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
            clientZlibStream = nil
            clientTightZlibStreams = nil
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

    private func failConnection(_ failedConnection: RFBNetworkConnection? = nil) {
        let connection: RFBNetworkConnection? = lock.withRFBClientLock {
            if let failedConnection {
                guard let activeConnection, activeConnection === failedConnection else {
                    return nil
                }
            }
            let connection = activeConnection
            activeConnection = nil
            clientServerInit = nil
            clientFramebuffer = nil
            clientZlibStream = nil
            clientTightZlibStreams = nil
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

    private func writeControlMessage(_ data: Data, timeout: TimeInterval) throws {
        guard let connection = currentActiveConnection() else {
            throw RFBNetworkClientError.notConnected
        }
        try writeActiveConnection(data, to: connection, timeout: timeout)
    }

    private func writeActiveConnection(
        _ data: Data,
        to connection: RFBNetworkConnection,
        timeout: TimeInterval
    ) throws {
        do {
            try connection.write(data, timeout: timeout)
        } catch {
            failConnection(connection)
            throw error
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
        let serverInit = try RFBProtocolDecoder.parseServerInit(serverInitData)

        // Advertise the encodings Naru can decode, in server-honored
        // preference order, so the server stops falling back to Raw
        // (spec 004 FR-001). Raw stays in the list as the universal
        // floor — negotiation is an optimization, never a correctness
        // dependency.
        try connection.write(setEncodingsMessage(), timeout: timeout)

        return serverInit
    }

    private func setEncodingsMessage() -> Data {
        RFBClientMessageEncoder.setEncodings(encodingPreference.encodingList())
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

    private static func clampedUInt16(_ value: Int) -> UInt16 {
        UInt16(max(0, min(value, Int(UInt16.max))))
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

extension RFBNetworkClient: RFBStreamingClient, RFBDamageTrackingFramebufferUpdating, RFBFramebufferUpdateReceiving, RFBTransportControlClient {}

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

/// `RFBByteReader` over a live `RFBNetworkConnection` (spec 004
/// FR-002). Each `readBytes(_:)` blocks (up to `timeout`) for exactly
/// the requested bytes via `readExactly`, so a rectangle that spans
/// multiple TCP segments simply waits for more — the decoder never
/// assumes one `recv` yields a whole rectangle. Used only within the
/// synchronous `requestFramebufferUpdate` call on the caller thread.
private final class ConnectionByteReader: RFBByteReader {
    private let connection: RFBNetworkConnection
    private let timeout: TimeInterval

    init(connection: RFBNetworkConnection, timeout: TimeInterval) {
        self.connection = connection
        self.timeout = timeout
    }

    func readBytes(_ count: Int) throws -> [UInt8] {
        guard count > 0 else {
            return []
        }
        return [UInt8](try connection.readExactly(byteCount: count, timeout: timeout))
    }
}

/// `RFBByteReader` adapter that replays a small prefix before delegating
/// to another reader. Used after peeking the server message type so the
/// pure framebuffer decoder can continue consuming a complete
/// FramebufferUpdate message without a second decode entry point.
private final class PrefixedByteReader: RFBByteReader {
    private var prefix: ArraySlice<UInt8>
    private let base: RFBByteReader

    init(prefix: [UInt8], base: RFBByteReader) {
        self.prefix = ArraySlice(prefix)
        self.base = base
    }

    func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0 else {
            throw RFBByteReaderError.negativeRequest(count)
        }
        guard count > 0 else {
            return []
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)

        while bytes.count < count, let next = prefix.first {
            bytes.append(next)
            prefix = prefix.dropFirst()
        }

        if bytes.count < count {
            bytes.append(contentsOf: try base.readBytes(count - bytes.count))
        }

        return bytes
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
        do {
            try readyState.wait(timeout: timeout)
        } catch {
            wrapper.cancel()
            throw error
        }
        return wrapper
    }

    func readExactly(byteCount: Int, timeout: TimeInterval) throws -> Data {
        guard byteCount > 0 else {
            return Data()
        }

        let state = RFBNetworkReadState(expectedByteCount: byteCount)
        receiveNext(into: state, remainingByteCount: byteCount)
        do {
            return try state.wait(timeout: timeout)
        } catch {
            cancel()
            throw error
        }
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
        do {
            try state.wait(timeout: timeout)
        } catch {
            cancel()
            throw error
        }
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
