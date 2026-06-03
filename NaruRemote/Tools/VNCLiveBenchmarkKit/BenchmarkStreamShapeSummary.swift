import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeStatus: String, Codable, Equatable, Sendable {
    case disabled
    case noUpdateBeforeTimeout = "no-update-before-timeout"
    case emptyUpdate = "empty-update"
    case contentUpdate = "content-update"
    case mixedUpdates = "mixed-updates"
    case failed
}

public enum BenchmarkStreamUpdateKind: String, Codable, Equatable, Sendable {
    case emptyUpdate = "empty-update"
    case contentUpdate = "content-update"
}

public enum BenchmarkStreamShapeTransportMode: String, Codable, Equatable, Sendable, CaseIterable {
    case requestResponse = "request-response"
    case continuousUpdates = "continuous-updates"
}

public struct BenchmarkStreamShapeSample: Codable, Equatable, Sendable {
    public let kind: BenchmarkStreamUpdateKind
    public let durationMilliseconds: Int
    public let dirtyRectangleCount: Int
    public let dirtyAreaPermille: Int
    public let changedPixelsPermille: Int
    public let rendererUploadStrategy: FramebufferUploadStrategy
    public let rendererUploadRegionCount: Int

    public init(
        kind: BenchmarkStreamUpdateKind,
        durationMilliseconds: Int,
        dirtyRectangleCount: Int,
        dirtyAreaPermille: Int,
        changedPixelsPermille: Int,
        rendererUploadStrategy: FramebufferUploadStrategy = .none,
        rendererUploadRegionCount: Int = 0
    ) {
        self.kind = kind
        self.durationMilliseconds = max(durationMilliseconds, 0)
        self.dirtyRectangleCount = max(dirtyRectangleCount, 0)
        self.dirtyAreaPermille = Self.clampPermille(dirtyAreaPermille)
        self.changedPixelsPermille = Self.clampPermille(changedPixelsPermille)
        self.rendererUploadStrategy = rendererUploadStrategy
        self.rendererUploadRegionCount = max(rendererUploadRegionCount, 0)
    }

    private static func clampPermille(_ value: Int) -> Int {
        min(max(value, 0), 1_000)
    }
}

public struct BenchmarkStreamShapeSummary: Codable, Equatable, Sendable {
    public let status: BenchmarkStreamShapeStatus
    public let requestedSamples: Int
    public let receivedSamples: Int
    public let emptyUpdateSamples: Int
    public let contentUpdateSamples: Int
    public let timedOutSamples: Int
    public let elapsedMilliseconds: Int?
    public let deliveredFramesPerSecond: Double?
    public let contentFramesPerSecond: Double?
    public let updateLatency: BenchmarkLatencySummary?
    public let dirtyRectangleCount: BenchmarkLatencySummary?
    public let dirtyAreaPermille: BenchmarkLatencySummary?
    public let changedPixelsPermille: BenchmarkLatencySummary?
    public let tailLatency: BenchmarkStreamShapeTailSummary
    public let rendererUploadSampleCount: Int
    public let rendererPartialUploadSamples: Int
    public let rendererFullUploadSamples: Int
    public let rendererPartialUploadPermille: Int?
    public let rendererFullUploadPermille: Int?
    public let rendererUploadRegionCount: BenchmarkLatencySummary?
    public let firstTimeoutMilliseconds: Int?
    public let failureLabel: String?

    public init(
        requestedSamples: Int,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?
    ) {
        let requestedSamples = max(requestedSamples, 0)
        let emptyUpdateSamples = samples.filter { $0.kind == .emptyUpdate }.count
        let contentUpdateSamples = samples.filter { $0.kind == .contentUpdate }.count
        let rendererUploadSamples = samples.filter { $0.rendererUploadStrategy != .none }
        let rendererPartialUploadSamples = rendererUploadSamples.filter {
            $0.rendererUploadStrategy == .partial
        }.count
        let rendererFullUploadSamples = rendererUploadSamples.filter {
            $0.rendererUploadStrategy == .full
        }.count

        self.status = Self.status(
            requestedSamples: requestedSamples,
            emptyUpdateSamples: emptyUpdateSamples,
            contentUpdateSamples: contentUpdateSamples,
            firstTimeoutMilliseconds: firstTimeoutMilliseconds,
            failureLabel: failureLabel
        )
        self.requestedSamples = requestedSamples
        self.receivedSamples = samples.count
        self.emptyUpdateSamples = emptyUpdateSamples
        self.contentUpdateSamples = contentUpdateSamples
        self.timedOutSamples = firstTimeoutMilliseconds == nil ? 0 : 1
        self.elapsedMilliseconds = elapsedMilliseconds
        self.deliveredFramesPerSecond = Self.framesPerSecond(
            sampleCount: samples.count,
            elapsedMilliseconds: elapsedMilliseconds
        )
        self.contentFramesPerSecond = Self.framesPerSecond(
            sampleCount: contentUpdateSamples,
            elapsedMilliseconds: elapsedMilliseconds
        )
        self.updateLatency = BenchmarkLatencySummary(samples.map(\.durationMilliseconds))
        self.dirtyRectangleCount = BenchmarkLatencySummary(samples.map(\.dirtyRectangleCount))
        self.dirtyAreaPermille = BenchmarkLatencySummary(samples.map(\.dirtyAreaPermille))
        self.changedPixelsPermille = BenchmarkLatencySummary(samples.map(\.changedPixelsPermille))
        self.tailLatency = BenchmarkStreamShapeTailSummary(samples: samples)
        self.rendererUploadSampleCount = rendererUploadSamples.count
        self.rendererPartialUploadSamples = rendererPartialUploadSamples
        self.rendererFullUploadSamples = rendererFullUploadSamples
        self.rendererPartialUploadPermille = Self.permille(
            rendererPartialUploadSamples,
            of: rendererUploadSamples.count
        )
        self.rendererFullUploadPermille = Self.permille(
            rendererFullUploadSamples,
            of: rendererUploadSamples.count
        )
        self.rendererUploadRegionCount = BenchmarkLatencySummary(
            rendererUploadSamples.map(\.rendererUploadRegionCount)
        )
        self.firstTimeoutMilliseconds = firstTimeoutMilliseconds
        self.failureLabel = failureLabel
    }

    private static func status(
        requestedSamples: Int,
        emptyUpdateSamples: Int,
        contentUpdateSamples: Int,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?
    ) -> BenchmarkStreamShapeStatus {
        if failureLabel != nil {
            return .failed
        }
        if requestedSamples == 0 {
            return .disabled
        }
        if emptyUpdateSamples > 0, contentUpdateSamples > 0 {
            return .mixedUpdates
        }
        if contentUpdateSamples > 0 {
            return .contentUpdate
        }
        if emptyUpdateSamples > 0 {
            return .emptyUpdate
        }
        if firstTimeoutMilliseconds != nil {
            return .noUpdateBeforeTimeout
        }
        return .noUpdateBeforeTimeout
    }

    private static func framesPerSecond(sampleCount: Int, elapsedMilliseconds: Int?) -> Double? {
        guard let elapsedMilliseconds, elapsedMilliseconds > 0 else {
            return nil
        }
        return Double(sampleCount) / (Double(elapsedMilliseconds) / 1_000)
    }

    private static func permille(_ value: Int, of total: Int) -> Int? {
        guard total > 0 else {
            return nil
        }
        let rounded = Int((Double(max(value, 0)) / Double(total) * 1_000).rounded())
        return value > 0 ? max(rounded, 1) : 0
    }
}

public struct BenchmarkStreamShapeTailSummary: Codable, Equatable, Sendable {
    public static let defaultSlowUpdateThresholdMilliseconds = 250
    public static let defaultVerySlowUpdateThresholdMilliseconds = 1_000

    public let slowUpdateThresholdMilliseconds: Int
    public let verySlowUpdateThresholdMilliseconds: Int
    public let slowUpdateSamples: Int
    public let slowContentUpdateSamples: Int
    public let slowFullDirtyAreaSamples: Int
    public let slowRendererFullUploadSamples: Int
    public let verySlowUpdateSamples: Int

    public init(
        samples: [BenchmarkStreamShapeSample],
        slowUpdateThresholdMilliseconds: Int = Self.defaultSlowUpdateThresholdMilliseconds,
        verySlowUpdateThresholdMilliseconds: Int = Self.defaultVerySlowUpdateThresholdMilliseconds
    ) {
        let slowThreshold = max(slowUpdateThresholdMilliseconds, 0)
        let verySlowThreshold = max(verySlowUpdateThresholdMilliseconds, slowThreshold)
        let slowSamples = samples.filter { $0.durationMilliseconds >= slowThreshold }

        self.slowUpdateThresholdMilliseconds = slowThreshold
        self.verySlowUpdateThresholdMilliseconds = verySlowThreshold
        self.slowUpdateSamples = slowSamples.count
        self.slowContentUpdateSamples = slowSamples.filter { $0.kind == .contentUpdate }.count
        self.slowFullDirtyAreaSamples = slowSamples.filter { $0.dirtyAreaPermille >= 1_000 }.count
        self.slowRendererFullUploadSamples = slowSamples.filter {
            $0.rendererUploadStrategy == .full
        }.count
        self.verySlowUpdateSamples = samples.filter {
            $0.durationMilliseconds >= verySlowThreshold
        }.count
    }
}

public struct BenchmarkStreamShapeProfileReport: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let firstFrameMilliseconds: Int?
    public let summary: BenchmarkStreamShapeSummary

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode = .requestResponse,
        firstFrameMilliseconds: Int?,
        summary: BenchmarkStreamShapeSummary
    ) {
        self.label = label
        self.transportMode = transportMode
        self.firstFrameMilliseconds = firstFrameMilliseconds
        self.summary = summary
    }
}

public struct BenchmarkStreamShapeRecommendation: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let reason: String
    public let averageUpdateMilliseconds: Int
    public let p95UpdateMilliseconds: Int
    public let contentFramesPerSecond: Double
    public let rendererFullUploadPermille: Int
    public let slowUpdateSamples: Int
    public let receivedSamples: Int
    public let contentUpdateSamples: Int

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode,
        reason: String,
        averageUpdateMilliseconds: Int,
        p95UpdateMilliseconds: Int,
        contentFramesPerSecond: Double,
        rendererFullUploadPermille: Int,
        slowUpdateSamples: Int,
        receivedSamples: Int,
        contentUpdateSamples: Int
    ) {
        self.label = label
        self.transportMode = transportMode
        self.reason = reason
        self.averageUpdateMilliseconds = max(averageUpdateMilliseconds, 0)
        self.p95UpdateMilliseconds = max(p95UpdateMilliseconds, 0)
        self.contentFramesPerSecond = max(contentFramesPerSecond, 0)
        self.rendererFullUploadPermille = min(max(rendererFullUploadPermille, 0), 1_000)
        self.slowUpdateSamples = max(slowUpdateSamples, 0)
        self.receivedSamples = max(receivedSamples, 0)
        self.contentUpdateSamples = max(contentUpdateSamples, 0)
    }

    public static func recommendedRequestResponseProfile(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> BenchmarkStreamShapeRecommendation? {
        reports
            .compactMap(BenchmarkStreamShapeRecommendation.init(report:))
            .sorted(by: isPreferred)
            .first
    }

    private init?(report: BenchmarkStreamShapeProfileReport) {
        guard report.transportMode == .requestResponse,
              report.summary.failureLabel == nil,
              report.summary.receivedSamples > 0,
              report.summary.contentUpdateSamples > 0,
              report.summary.rendererUploadSampleCount > 0,
              let updateLatency = report.summary.updateLatency,
              let contentFramesPerSecond = report.summary.contentFramesPerSecond,
              let rendererFullUploadPermille = report.summary.rendererFullUploadPermille
        else {
            return nil
        }

        self.init(
            label: report.label,
            transportMode: report.transportMode,
            reason: "lowest-average-update-latency-among-request-response-profiles",
            averageUpdateMilliseconds: updateLatency.averageMilliseconds,
            p95UpdateMilliseconds: updateLatency.p95Milliseconds,
            contentFramesPerSecond: contentFramesPerSecond,
            rendererFullUploadPermille: rendererFullUploadPermille,
            slowUpdateSamples: report.summary.tailLatency.slowUpdateSamples,
            receivedSamples: report.summary.receivedSamples,
            contentUpdateSamples: report.summary.contentUpdateSamples
        )
    }

    private static func isPreferred(
        _ lhs: BenchmarkStreamShapeRecommendation,
        _ rhs: BenchmarkStreamShapeRecommendation
    ) -> Bool {
        if lhs.averageUpdateMilliseconds != rhs.averageUpdateMilliseconds {
            return lhs.averageUpdateMilliseconds < rhs.averageUpdateMilliseconds
        }
        if lhs.p95UpdateMilliseconds != rhs.p95UpdateMilliseconds {
            return lhs.p95UpdateMilliseconds < rhs.p95UpdateMilliseconds
        }
        if lhs.rendererFullUploadPermille != rhs.rendererFullUploadPermille {
            return lhs.rendererFullUploadPermille < rhs.rendererFullUploadPermille
        }
        if lhs.slowUpdateSamples != rhs.slowUpdateSamples {
            return lhs.slowUpdateSamples < rhs.slowUpdateSamples
        }
        if lhs.contentFramesPerSecond != rhs.contentFramesPerSecond {
            return lhs.contentFramesPerSecond > rhs.contentFramesPerSecond
        }
        return lhs.receivedSamples > rhs.receivedSamples
    }
}
