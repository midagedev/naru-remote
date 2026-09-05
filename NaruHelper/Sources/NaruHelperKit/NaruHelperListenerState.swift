import Foundation

#if canImport(Network)
import Network

/// Fixed-catalog listener lifecycle (spec 041 FR-002): every surface the
/// menu bar app shows — menu rows, diagnostics, the pairing window — reads
/// this enum, never a raw `NWListener.State` or error string. The port is
/// attached to the states where it is the fact the user can act on (a
/// "port in use" row must name the port).
public enum NaruHelperListenerState: Equatable, Sendable {
    case starting
    case listening(port: UInt16)
    case portInUse(port: UInt16)
    case failed
    case stopped

    /// Single owner of the `NWListener.State` mapping — both servers use
    /// this, so `.failed(.posix(.EADDRINUSE))` can never be classified one
    /// way by the text server and another by the video server.
    static func from(
        networkState: NWListener.State,
        boundPort: UInt16?,
        requestedPort: UInt16?
    ) -> NaruHelperListenerState {
        switch networkState {
        case .setup, .waiting:
            return .starting
        case .ready:
            return .listening(port: boundPort ?? requestedPort ?? 0)
        case .failed(let error):
            if case .posix(let code) = error, code == .EADDRINUSE {
                // The bind never succeeded, so `boundPort` is nil here —
                // the port the operator asked for is the actionable fact.
                return .portInUse(port: requestedPort ?? boundPort ?? 0)
            }
            return .failed
        case .cancelled:
            return .stopped
        @unknown default:
            return .failed
        }
    }

    /// Wires `onChange` to an `NWListener`'s state changes — the single
    /// owner of that wiring for both servers. Setting the handler alone
    /// does not replay the current state, so a subscriber attached after
    /// the listener already became ready (or failed) would never hear
    /// anything; the initial emit closes that gap.
    static func install(
        on listener: NWListener,
        requestedPort: UInt16?,
        onChange: (@Sendable (NaruHelperListenerState) -> Void)?
    ) {
        guard let onChange else {
            listener.stateUpdateHandler = nil
            return
        }
        listener.stateUpdateHandler = { [weak listener] state in
            guard let listener else { return }
            onChange(NaruHelperListenerState.from(
                networkState: state,
                boundPort: listener.port?.rawValue,
                requestedPort: requestedPort
            ))
        }
        onChange(NaruHelperListenerState.from(
            networkState: listener.state,
            boundPort: listener.port?.rawValue,
            requestedPort: requestedPort
        ))
    }
}

/// Which of the two listeners a state belongs to.
public enum NaruHelperListenerKind: Equatable, Sendable {
    case text
    case video
}
#endif
