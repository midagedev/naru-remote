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

public protocol RFBStreamingClient: RFBAuthenticatedFirstFrameConnecting, RFBNoAuthSessionConnecting, RFBAuthenticatedSessionConnecting, RFBFramebufferUpdating, RemoteClipboardTextClient {}
