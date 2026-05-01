import Foundation

/// Bounded auto-reconnect policy for an active streaming session.
///
/// When the long-lived frame task throws after the session has
/// already begun streaming, `NaruRemoteAppModel` consults this
/// policy to decide whether — and how long — to wait before
/// attempting another connection on the same profile.
///
/// Pure data: no networking, no scheduling.  The model is
/// responsible for sleeping `backoffForAttempt(_:)` and re-running
/// the connect path with the same profile + credentialRef.
///
/// Constitution §I/§IV: a reconnect must NOT replay any buffered
/// Compose & Send draft and must NOT log raw error contents.  Those
/// rules live in the model; this type only describes the timing
/// envelope.
public struct ReconnectPolicy: Sendable, Equatable {
    /// Maximum number of consecutive reconnect attempts before the
    /// session transitions to a terminal failure state.  After a
    /// successful reconnect (a fresh frame arrives), the model
    /// resets its attempt counter so a future drop gets a fresh
    /// `maxAttempts` budget.
    public let maxAttempts: Int

    /// Backoff before the FIRST reconnect attempt.  Subsequent
    /// attempts double the previous backoff up to `maxBackoff`.
    public let initialBackoff: Duration

    /// Upper bound on the per-attempt backoff.  The exponential
    /// schedule clamps to this so a long-running flap does not push
    /// the wait toward minutes.
    public let maxBackoff: Duration

    public init(
        maxAttempts: Int = 3,
        initialBackoff: Duration = .milliseconds(500),
        maxBackoff: Duration = .seconds(8)
    ) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
    }

    /// Backoff to wait BEFORE the `attempt`-th reconnect attempt
    /// (1-based).  Returns `min(initialBackoff * 2^(attempt-1),
    /// maxBackoff)`.  Inputs `<= 0` are treated as `1`.
    public func backoffForAttempt(_ attempt: Int) -> Duration {
        let normalized = max(1, attempt)
        // Exponent is `(attempt - 1)`.  We multiply via repeated
        // doubling on a Duration so we never lose precision through
        // a floating-point round-trip.
        var current = initialBackoff
        var step = 1
        while step < normalized {
            current = current + current
            // Once `current` exceeds `maxBackoff`, additional
            // doublings are pointless — clamp and stop.
            if current >= maxBackoff {
                return maxBackoff
            }
            step += 1
        }
        return current >= maxBackoff ? maxBackoff : current
    }
}
