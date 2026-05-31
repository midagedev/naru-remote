import Foundation

public struct RFBFrameMetadata: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let receivedAt: Date

    public init(width: Int, height: Int, receivedAt: Date = Date()) {
        self.width = width
        self.height = height
        self.receivedAt = receivedAt
    }
}

public enum RFBClientState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case handshaking
    case authenticated
    case receivingFrames
    case failed
}

public protocol RFBClientBoundary {
    var state: RFBClientState { get }
    var lastFrame: RFBFrameMetadata? { get }
}

public protocol RFBFirstFrameConnecting: RFBClientBoundary, Sendable {
    @discardableResult
    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit
}

public protocol RFBAuthenticatedFirstFrameConnecting: RFBFirstFrameConnecting {
    @discardableResult
    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit
}

public protocol RFBNoAuthSessionConnecting: RFBClientBoundary, Sendable {
    @discardableResult
    func connectNoAuthSession(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit
}

public protocol RFBAuthenticatedSessionConnecting: RFBClientBoundary, Sendable {
    @discardableResult
    func connectSession(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit
}

public protocol RFBFramebufferUpdating: Sendable {
    func requestRawFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBRawFramebuffer
}

public protocol RFBDamageTrackingFramebufferUpdating: RFBFramebufferUpdating {
    func requestFramebufferUpdate(
        incremental: Bool,
        timeout: TimeInterval
    ) throws -> RFBFramebufferUpdateResult
}

/// Capability boundary for server-initiated framebuffer updates, used
/// by continuous-update style transports after the client has already
/// enabled the server extension. No `FramebufferUpdateRequest` is sent
/// by this method.
public protocol RFBFramebufferUpdateReceiving: Sendable {
    func receiveFramebufferUpdate(timeout: TimeInterval) throws -> RFBFramebufferUpdateResult
}

/// Capability boundary for RFB clients that can deliver
/// `PointerEvent` messages (RFC 6143 §7.5.5, message type 5) on the
/// active connection. Pointer events are NOT a text-input path —
/// constitution §I keeps the multilingual default on the
/// clipboard/compose-and-send route. Implementations MUST NOT log
/// the `(x, y)` coordinates anywhere persistent (constitution §IV).
public protocol RFBPointerEventClient: AnyObject, Sendable {
    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws
}

/// Capability boundary for RFB clients that can deliver `KeyEvent`
/// messages (RFC 6143 §7.5.4, message type 4) on the active
/// connection. Used by Direct Keystroke Streaming Mode (the named
/// constitution §I "MAY" exception) — both the on-screen custom
/// keyboard and the Bluetooth / Magic Keyboard hardware path emit
/// through this single boundary so the wire bytes are identical
/// (`spec.md` SC-005). Implementations MUST NOT log the keysym
/// values, modifier state, or any user-facing key content
/// (constitution §IV; `spec.md` SP-005).
public protocol RFBKeyEventClient: AnyObject, Sendable {
    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws
}

/// Rectangle used by optional RFB transport-control extensions such as
/// ContinuousUpdates. It is already in remote framebuffer coordinates;
/// callers must not log these coordinates (constitution §IV).
public struct RFBFramebufferUpdateRegion: Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
    public let width: UInt16
    public let height: UInt16

    public init(x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Capability boundary for transport-control messages used by RFB
/// encoding renegotiation and pacing extensions. These messages carry
/// no user text or pixel payload, and implementations must avoid
/// logging coordinates, payload bytes, or latency samples.
public protocol RFBTransportControlClient: AnyObject, Sendable {
    func renegotiateEncodings(_ preference: RFBEncodingPreference, timeout: TimeInterval) throws
    func enableContinuousUpdates(
        _ enabled: Bool,
        region: RFBFramebufferUpdateRegion?,
        timeout: TimeInterval
    ) throws
    func sendFence(flags: RFBFenceFlags, payload: Data, timeout: TimeInterval) throws
}

public protocol RFBStreamingClient: RFBAuthenticatedFirstFrameConnecting, RFBNoAuthSessionConnecting, RFBAuthenticatedSessionConnecting, RFBFramebufferUpdating, RemoteClipboardTextClient, RFBPointerEventClient, RFBKeyEventClient {}
