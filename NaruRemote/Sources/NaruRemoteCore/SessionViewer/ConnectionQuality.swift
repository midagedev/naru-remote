import Foundation

/// Coarse connection-quality bucket shown in the session control bar.
/// Derived from frame round-trip latency only; the underlying latency
/// value is never persisted, logged, or exported (constitution §IV).
public enum ConnectionQuality: String, Sendable, Equatable, CaseIterable {
    case unknown
    case good
    case fair
    case poor

    /// Bucket a single round-trip latency sample (request → frame
    /// arrival). Thresholds chosen for an interactive remote-desktop
    /// feel: < 80 ms reads as instant, < 250 ms as usable, beyond that
    /// as laggy.
    public static func bucket(forLatencyMilliseconds milliseconds: Double) -> ConnectionQuality {
        guard milliseconds.isFinite, milliseconds >= 0 else { return .unknown }
        if milliseconds < 80 { return .good }
        if milliseconds < 250 { return .fair }
        return .poor
    }
}

/// Rolling estimator that smooths per-frame round-trip latency into a
/// stable `ConnectionQuality` so the indicator does not flicker on a
/// single slow frame. Pure value type — no I/O, no logging.
public struct ConnectionQualityEstimator: Equatable, Sendable {
    /// Exponential-moving-average smoothing factor in `[0, 1]`; higher
    /// reacts faster to change.
    private let alpha: Double
    public private(set) var smoothedLatencyMilliseconds: Double?

    public init(alpha: Double = 0.3) {
        self.alpha = Swift.min(Swift.max(alpha, 0), 1)
        self.smoothedLatencyMilliseconds = nil
    }

    /// Fold a new latency sample into the moving average. Invalid
    /// (NaN / negative) samples are ignored.
    public mutating func record(latencyMilliseconds sample: Double) {
        guard sample.isFinite, sample >= 0 else { return }
        if let previous = smoothedLatencyMilliseconds {
            smoothedLatencyMilliseconds = previous + alpha * (sample - previous)
        } else {
            smoothedLatencyMilliseconds = sample
        }
    }

    /// Current bucket, `.unknown` until the first valid sample.
    public var quality: ConnectionQuality {
        guard let smoothed = smoothedLatencyMilliseconds else { return .unknown }
        return ConnectionQuality.bucket(forLatencyMilliseconds: smoothed)
    }

    /// Drop all history (called on disconnect / profile change).
    public mutating func reset() {
        smoothedLatencyMilliseconds = nil
    }
}
