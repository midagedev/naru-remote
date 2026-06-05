import Foundation

public enum ComposeSendPreparationMode: String, Codable, Equatable, CaseIterable, Sendable {
    case fastSnapshot
    case markedTextStabilization
}

public struct ComposeSendPreparationReport: Codable, Equatable, Sendable {
    public let mode: ComposeSendPreparationMode
    public let snapshotCount: Int
    public let durationBucket: DiagnosticTimingBucket

    public init(
        mode: ComposeSendPreparationMode,
        snapshotCount: Int,
        durationBucket: DiagnosticTimingBucket = .notMeasured
    ) {
        self.mode = mode
        self.snapshotCount = max(snapshotCount, 0)
        self.durationBucket = durationBucket
    }
}
