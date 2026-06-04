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
    public let receiveTotalMilliseconds: Int?
    public let networkReadMilliseconds: Int?
    public let clientProcessingMilliseconds: Int?
    public let actualEncodingMix: RFBFramebufferEncodingMix

    private enum CodingKeys: String, CodingKey {
        case kind
        case durationMilliseconds
        case dirtyRectangleCount
        case dirtyAreaPermille
        case changedPixelsPermille
        case rendererUploadStrategy
        case rendererUploadRegionCount
        case receiveTotalMilliseconds
        case networkReadMilliseconds
        case clientProcessingMilliseconds
        case actualEncodingMix
    }

    public init(
        kind: BenchmarkStreamUpdateKind,
        durationMilliseconds: Int,
        dirtyRectangleCount: Int,
        dirtyAreaPermille: Int,
        changedPixelsPermille: Int,
        rendererUploadStrategy: FramebufferUploadStrategy = .none,
        rendererUploadRegionCount: Int = 0,
        receiveTotalMilliseconds: Int? = nil,
        networkReadMilliseconds: Int? = nil,
        clientProcessingMilliseconds: Int? = nil,
        actualEncodingMix: RFBFramebufferEncodingMix = RFBFramebufferEncodingMix()
    ) {
        self.kind = kind
        self.durationMilliseconds = max(durationMilliseconds, 0)
        self.dirtyRectangleCount = max(dirtyRectangleCount, 0)
        self.dirtyAreaPermille = Self.clampPermille(dirtyAreaPermille)
        self.changedPixelsPermille = Self.clampPermille(changedPixelsPermille)
        self.rendererUploadStrategy = rendererUploadStrategy
        self.rendererUploadRegionCount = max(rendererUploadRegionCount, 0)
        self.receiveTotalMilliseconds = Self.clampOptionalMilliseconds(receiveTotalMilliseconds)
        self.networkReadMilliseconds = Self.clampOptionalMilliseconds(networkReadMilliseconds)
        self.clientProcessingMilliseconds = Self.clampOptionalMilliseconds(clientProcessingMilliseconds)
        self.actualEncodingMix = actualEncodingMix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(BenchmarkStreamUpdateKind.self, forKey: .kind),
            durationMilliseconds: try container.decode(Int.self, forKey: .durationMilliseconds),
            dirtyRectangleCount: try container.decode(Int.self, forKey: .dirtyRectangleCount),
            dirtyAreaPermille: try container.decode(Int.self, forKey: .dirtyAreaPermille),
            changedPixelsPermille: try container.decode(Int.self, forKey: .changedPixelsPermille),
            rendererUploadStrategy: try container.decode(
                FramebufferUploadStrategy.self,
                forKey: .rendererUploadStrategy
            ),
            rendererUploadRegionCount: try container.decode(Int.self, forKey: .rendererUploadRegionCount),
            receiveTotalMilliseconds: try container.decodeIfPresent(Int.self, forKey: .receiveTotalMilliseconds),
            networkReadMilliseconds: try container.decodeIfPresent(Int.self, forKey: .networkReadMilliseconds),
            clientProcessingMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .clientProcessingMilliseconds
            ),
            actualEncodingMix: try container.decodeIfPresent(
                RFBFramebufferEncodingMix.self,
                forKey: .actualEncodingMix
            ) ?? RFBFramebufferEncodingMix()
        )
    }

    private static func clampPermille(_ value: Int) -> Int {
        min(max(value, 0), 1_000)
    }

    private static func clampOptionalMilliseconds(_ value: Int?) -> Int? {
        value.map { max($0, 0) }
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
    public let receiveTotalLatency: BenchmarkLatencySummary?
    public let networkReadLatency: BenchmarkLatencySummary?
    public let clientProcessingLatency: BenchmarkLatencySummary?
    public let tailLatency: BenchmarkStreamShapeTailSummary
    public let rendererUploadSampleCount: Int
    public let rendererPartialUploadSamples: Int
    public let rendererFullUploadSamples: Int
    public let rendererPartialUploadPermille: Int?
    public let rendererFullUploadPermille: Int?
    public let rendererUploadRegionCount: BenchmarkLatencySummary?
    public let actualEncodingMix: RFBFramebufferEncodingMix
    public let adaptiveClientPressurePacingSamples: Int
    public let adaptiveClientPressurePacingPermille: Int?
    public let viewportInteractionPacingSamples: Int
    public let viewportInteractionPacingPermille: Int?
    public let firstTimeoutMilliseconds: Int?
    public let failureLabel: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case requestedSamples
        case receivedSamples
        case emptyUpdateSamples
        case contentUpdateSamples
        case timedOutSamples
        case elapsedMilliseconds
        case deliveredFramesPerSecond
        case contentFramesPerSecond
        case updateLatency
        case dirtyRectangleCount
        case dirtyAreaPermille
        case changedPixelsPermille
        case receiveTotalLatency
        case networkReadLatency
        case clientProcessingLatency
        case tailLatency
        case rendererUploadSampleCount
        case rendererPartialUploadSamples
        case rendererFullUploadSamples
        case rendererPartialUploadPermille
        case rendererFullUploadPermille
        case rendererUploadRegionCount
        case actualEncodingMix
        case adaptiveClientPressurePacingSamples
        case adaptiveClientPressurePacingPermille
        case viewportInteractionPacingSamples
        case viewportInteractionPacingPermille
        case firstTimeoutMilliseconds
        case failureLabel
    }

    public init(
        requestedSamples: Int,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?,
        adaptiveClientPressurePacingSamples: Int = 0,
        viewportInteractionPacingSamples: Int = 0
    ) {
        let requestedSamples = max(requestedSamples, 0)
        let receivedSamples = samples.count
        let emptyUpdateSamples = samples.filter { $0.kind == .emptyUpdate }.count
        let contentUpdateSamples = samples.filter { $0.kind == .contentUpdate }.count
        let adaptiveClientPressurePacingSamples = min(
            max(adaptiveClientPressurePacingSamples, 0),
            receivedSamples
        )
        let viewportInteractionPacingSamples = min(
            max(viewportInteractionPacingSamples, 0),
            receivedSamples
        )
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
        self.receivedSamples = receivedSamples
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
        self.receiveTotalLatency = BenchmarkLatencySummary(samples.compactMap(\.receiveTotalMilliseconds))
        self.networkReadLatency = BenchmarkLatencySummary(samples.compactMap(\.networkReadMilliseconds))
        self.clientProcessingLatency = BenchmarkLatencySummary(samples.compactMap(\.clientProcessingMilliseconds))
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
        self.actualEncodingMix = samples.reduce(RFBFramebufferEncodingMix()) { partial, sample in
            partial.adding(sample.actualEncodingMix)
        }
        self.adaptiveClientPressurePacingSamples = adaptiveClientPressurePacingSamples
        self.adaptiveClientPressurePacingPermille = Self.permille(
            adaptiveClientPressurePacingSamples,
            of: receivedSamples
        )
        self.viewportInteractionPacingSamples = viewportInteractionPacingSamples
        self.viewportInteractionPacingPermille = Self.permille(
            viewportInteractionPacingSamples,
            of: receivedSamples
        )
        self.firstTimeoutMilliseconds = firstTimeoutMilliseconds
        self.failureLabel = failureLabel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(BenchmarkStreamShapeStatus.self, forKey: .status)
        self.requestedSamples = try container.decode(Int.self, forKey: .requestedSamples)
        self.receivedSamples = try container.decode(Int.self, forKey: .receivedSamples)
        self.emptyUpdateSamples = try container.decode(Int.self, forKey: .emptyUpdateSamples)
        self.contentUpdateSamples = try container.decode(Int.self, forKey: .contentUpdateSamples)
        self.timedOutSamples = try container.decode(Int.self, forKey: .timedOutSamples)
        self.elapsedMilliseconds = try container.decodeIfPresent(Int.self, forKey: .elapsedMilliseconds)
        self.deliveredFramesPerSecond = try container.decodeIfPresent(
            Double.self,
            forKey: .deliveredFramesPerSecond
        )
        self.contentFramesPerSecond = try container.decodeIfPresent(
            Double.self,
            forKey: .contentFramesPerSecond
        )
        self.updateLatency = try container.decodeIfPresent(BenchmarkLatencySummary.self, forKey: .updateLatency)
        self.dirtyRectangleCount = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .dirtyRectangleCount
        )
        self.dirtyAreaPermille = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .dirtyAreaPermille
        )
        self.changedPixelsPermille = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .changedPixelsPermille
        )
        self.receiveTotalLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .receiveTotalLatency
        )
        self.networkReadLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .networkReadLatency
        )
        self.clientProcessingLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .clientProcessingLatency
        )
        self.tailLatency = try container.decode(BenchmarkStreamShapeTailSummary.self, forKey: .tailLatency)
        self.rendererUploadSampleCount = try container.decode(Int.self, forKey: .rendererUploadSampleCount)
        self.rendererPartialUploadSamples = try container.decode(Int.self, forKey: .rendererPartialUploadSamples)
        self.rendererFullUploadSamples = try container.decode(Int.self, forKey: .rendererFullUploadSamples)
        self.rendererPartialUploadPermille = try container.decodeIfPresent(
            Int.self,
            forKey: .rendererPartialUploadPermille
        )
        self.rendererFullUploadPermille = try container.decodeIfPresent(
            Int.self,
            forKey: .rendererFullUploadPermille
        )
        self.rendererUploadRegionCount = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .rendererUploadRegionCount
        )
        self.actualEncodingMix = try container.decodeIfPresent(
            RFBFramebufferEncodingMix.self,
            forKey: .actualEncodingMix
        ) ?? RFBFramebufferEncodingMix()
        self.adaptiveClientPressurePacingSamples = min(
            max(
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .adaptiveClientPressurePacingSamples
                ) ?? 0,
                0
            ),
            self.receivedSamples
        )
        self.adaptiveClientPressurePacingPermille = try container.decodeIfPresent(
            Int.self,
            forKey: .adaptiveClientPressurePacingPermille
        ) ?? Self.permille(
            self.adaptiveClientPressurePacingSamples,
            of: self.receivedSamples
        )
        self.viewportInteractionPacingSamples = min(
            max(
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .viewportInteractionPacingSamples
                ) ?? 0,
                0
            ),
            self.receivedSamples
        )
        self.viewportInteractionPacingPermille = try container.decodeIfPresent(
            Int.self,
            forKey: .viewportInteractionPacingPermille
        ) ?? Self.permille(
            self.viewportInteractionPacingSamples,
            of: self.receivedSamples
        )
        self.firstTimeoutMilliseconds = try container.decodeIfPresent(Int.self, forKey: .firstTimeoutMilliseconds)
        self.failureLabel = try container.decodeIfPresent(String.self, forKey: .failureLabel)
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
