import Foundation

public enum HelperVideoRenderBackpressureDecision: Equatable, Sendable {
    case renderWithoutQuery
    case queryRendererBackpressure
    case dropDeltaWithoutQuery
}

/// Bounded local gate for renderer-level helper-video backpressure.
///
/// `AVSampleBufferDisplayLayer.isReadyForMoreMediaData` is the authoritative
/// signal, but checking it requires the app renderer path. Once that signal
/// says a delta frame should be dropped, the next short run of deltas can be
/// dropped without repeatedly hopping back to the renderer. Parameter sets,
/// keyframes, and end-of-stream units always reset the skip window so decoder
/// sync and visible recovery stay intact.
public struct HelperVideoRenderBackpressureGate: Equatable, Sendable {
    public let deltaSkipLimitAfterBackpressure: Int
    private var remainingDeltaSkips = 0

    public init(deltaSkipLimitAfterBackpressure: Int = 6) {
        self.deltaSkipLimitAfterBackpressure = max(deltaSkipLimitAfterBackpressure, 0)
    }

    public mutating func decision(
        for kind: HelperVideoAccessUnitKind
    ) -> HelperVideoRenderBackpressureDecision {
        switch kind {
        case .parameterSet, .keyframe, .endOfStream:
            remainingDeltaSkips = 0
            return .renderWithoutQuery
        case .delta:
            guard remainingDeltaSkips > 0 else {
                return .queryRendererBackpressure
            }
            remainingDeltaSkips -= 1
            return .dropDeltaWithoutQuery
        }
    }

    public mutating func recordRendererBackpressureResult(
        for kind: HelperVideoAccessUnitKind,
        shouldDrop: Bool
    ) {
        guard kind == .delta, shouldDrop else {
            remainingDeltaSkips = 0
            return
        }
        remainingDeltaSkips = deltaSkipLimitAfterBackpressure
    }
}
