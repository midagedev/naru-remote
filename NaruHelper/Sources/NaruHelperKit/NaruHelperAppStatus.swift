import Foundation

/// Fixed-catalog permission verdict (spec 041 FR-005). Derived from a
/// probe, never stored as a raw probe string.
public enum NaruHelperPermissionStatus: String, Equatable, Sendable {
    case granted
    case missing
}

/// Fixed-catalog pairing verdict (spec 041 FR-007 / US-1): `connected`
/// means an accepted helper handshake has arrived since the last
/// rotation — the runtime's authorized hook is what promotes `paired`.
public enum NaruHelperPairingStatus: Equatable, Sendable {
    case notPaired
    case paired
    case connected
}

/// The helper's whole observable state (spec 041 FR-012), assembled by
/// the app from probes + listener callbacks.
///
/// Redaction by construction: the type has **no field that could hold** a
/// token, a fingerprint, a pairing code, or an address — every component
/// is a fixed-catalog enum or a port number, so ``diagnosticsText()``
/// cannot leak credential material the way a stringly-typed status could.
/// The same rule as spec 040's `naru://pair?code=` redaction, enforced by
/// the type system instead of by filtering.
public struct NaruHelperAppStatus: Equatable, Sendable {
    public var accessibility: NaruHelperPermissionStatus
    public var screenRecording: NaruHelperPermissionStatus
    public var textListener: NaruHelperListenerState
    public var videoListener: NaruHelperListenerState
    public var pairing: NaruHelperPairingStatus
    public var loginItem: NaruHelperLoginItemState
    public var version: String

    public init(
        accessibility: NaruHelperPermissionStatus,
        screenRecording: NaruHelperPermissionStatus,
        textListener: NaruHelperListenerState,
        videoListener: NaruHelperListenerState,
        pairing: NaruHelperPairingStatus,
        loginItem: NaruHelperLoginItemState,
        version: String
    ) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.textListener = textListener
        self.videoListener = videoListener
        self.pairing = pairing
        self.loginItem = loginItem
        self.version = version
    }

    /// One `key=value` per line, fixed catalog — this is what **Copy
    /// Diagnostics** puts on the pasteboard. Port numbers are part of the
    /// catalog (a "port in use" row must name the port); addresses and
    /// credentials are not representable here.
    public func diagnosticsText() -> String {
        [
            "accessibility=\(accessibility.rawValue)",
            "screenRecording=\(screenRecording.rawValue)",
            "textListener=\(textListener.diagnosticsValue)",
            "videoListener=\(videoListener.diagnosticsValue)",
            "pairing=\(pairing.diagnosticsValue)",
            "loginItem=\(loginItem.diagnosticsValue)",
            "version=\(version)",
        ]
            .joined(separator: "\n")
    }
}

extension NaruHelperPairingStatus {
    var diagnosticsValue: String {
        switch self {
        case .notPaired: "notPaired"
        case .paired: "paired"
        case .connected: "connected"
        }
    }
}

extension NaruHelperLoginItemState {
    var diagnosticsValue: String {
        switch self {
        case .off: "off"
        case .on: "on"
        case .requiresApproval: "requiresApproval"
        case .unavailable: "unavailable"
        }
    }
}

#if canImport(Network)
extension NaruHelperListenerState {
    var diagnosticsValue: String {
        switch self {
        case .starting: "starting"
        case .listening(let port): "listening:\(port)"
        case .portInUse(let port): "portInUse:\(port)"
        case .failed: "failed"
        case .stopped: "stopped"
        }
    }
}
#endif
