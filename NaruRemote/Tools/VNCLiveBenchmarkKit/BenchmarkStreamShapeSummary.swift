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

public enum BenchmarkStreamShapePracticalVerdict: String, Codable, Equatable, Sendable {
    case disabled
    case pass
    case warning
    case fail
}

public enum BenchmarkStreamShapePracticalIssueCode: String, Codable, Equatable, Sendable, CaseIterable {
    case probeDisabled = "probe-disabled"
    case probeFailed = "probe-failed"
    case noContentUpdates = "no-content-updates"
    case insufficientContentSamples = "insufficient-content-samples"
    case contentFPSWarning = "content-fps-warning"
    case contentFPSFailed = "content-fps-failed"
    case p95UpdateWarning = "p95-update-warning"
    case p95UpdateFailed = "p95-update-failed"
    case clientProcessingWarning = "client-processing-warning"
    case clientProcessingFailed = "client-processing-failed"
    case verySlowUpdate = "very-slow-update"
    case fullUploadWarning = "full-upload-warning"
    case fullUploadFailed = "full-upload-failed"
    case adaptivePressureWarning = "adaptive-pressure-warning"
    case adaptivePressureFailed = "adaptive-pressure-failed"
}

public struct BenchmarkStreamShapePracticalTargets: Codable, Equatable, Sendable {
    public static let iPhonePracticalBaseline = BenchmarkStreamShapePracticalTargets(
        name: "iphone-practical-baseline-v1",
        passContentFramesPerSecond: 8,
        failContentFramesPerSecond: 4,
        passP95UpdateMilliseconds: 500,
        failP95UpdateMilliseconds: 1_000,
        passClientProcessingP95Milliseconds: 24,
        failClientProcessingP95Milliseconds: 50,
        passRendererFullUploadPermille: 50,
        failRendererFullUploadPermille: 150,
        passAdaptivePressurePermille: 100,
        failAdaptivePressurePermille: 500,
        minimumContentUpdateSamples: 3
    )

    public let name: String
    public let passContentFramesPerSecond: Double
    public let failContentFramesPerSecond: Double
    public let passP95UpdateMilliseconds: Int
    public let failP95UpdateMilliseconds: Int
    public let passClientProcessingP95Milliseconds: Int
    public let failClientProcessingP95Milliseconds: Int
    public let passRendererFullUploadPermille: Int
    public let failRendererFullUploadPermille: Int
    public let passAdaptivePressurePermille: Int
    public let failAdaptivePressurePermille: Int
    public let minimumContentUpdateSamples: Int

    public init(
        name: String,
        passContentFramesPerSecond: Double,
        failContentFramesPerSecond: Double,
        passP95UpdateMilliseconds: Int,
        failP95UpdateMilliseconds: Int,
        passClientProcessingP95Milliseconds: Int,
        failClientProcessingP95Milliseconds: Int,
        passRendererFullUploadPermille: Int,
        failRendererFullUploadPermille: Int,
        passAdaptivePressurePermille: Int,
        failAdaptivePressurePermille: Int,
        minimumContentUpdateSamples: Int
    ) {
        self.name = name
        self.passContentFramesPerSecond = max(passContentFramesPerSecond, 0)
        self.failContentFramesPerSecond = max(failContentFramesPerSecond, 0)
        self.passP95UpdateMilliseconds = max(passP95UpdateMilliseconds, 0)
        self.failP95UpdateMilliseconds = max(failP95UpdateMilliseconds, self.passP95UpdateMilliseconds)
        self.passClientProcessingP95Milliseconds = max(passClientProcessingP95Milliseconds, 0)
        self.failClientProcessingP95Milliseconds = max(
            failClientProcessingP95Milliseconds,
            self.passClientProcessingP95Milliseconds
        )
        self.passRendererFullUploadPermille = Self.clampPermille(passRendererFullUploadPermille)
        self.failRendererFullUploadPermille = max(
            Self.clampPermille(failRendererFullUploadPermille),
            self.passRendererFullUploadPermille
        )
        self.passAdaptivePressurePermille = Self.clampPermille(passAdaptivePressurePermille)
        self.failAdaptivePressurePermille = max(
            Self.clampPermille(failAdaptivePressurePermille),
            self.passAdaptivePressurePermille
        )
        self.minimumContentUpdateSamples = max(minimumContentUpdateSamples, 0)
    }

    private static func clampPermille(_ value: Int) -> Int {
        min(max(value, 0), 1_000)
    }
}

public struct BenchmarkStreamShapePracticalAssessment: Codable, Equatable, Sendable {
    public let targetName: String
    public let verdict: BenchmarkStreamShapePracticalVerdict
    public let issueCodes: [BenchmarkStreamShapePracticalIssueCode]

    public init(
        targetName: String,
        verdict: BenchmarkStreamShapePracticalVerdict,
        issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    ) {
        self.targetName = targetName
        self.verdict = verdict
        self.issueCodes = issueCodes
    }
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
    public let viewportInteractionPausedRequestCount: Int
    public let viewportInteractionPausedRequestPermille: Int?
    public let viewportInteractionPausePollCount: Int
    public let viewportInteractionPausedMilliseconds: Int
    public let firstTimeoutMilliseconds: Int?
    public let failureLabel: String?
    public var practicalAssessment: BenchmarkStreamShapePracticalAssessment {
        Self.practicalAssessment(
            status: status,
            failureLabel: failureLabel,
            contentUpdateSamples: contentUpdateSamples,
            contentFramesPerSecond: contentFramesPerSecond,
            updateLatency: updateLatency,
            clientProcessingLatency: clientProcessingLatency,
            tailLatency: tailLatency,
            rendererFullUploadPermille: rendererFullUploadPermille,
            adaptiveClientPressurePacingPermille: adaptiveClientPressurePacingPermille
        )
    }

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
        case viewportInteractionPausedRequestCount
        case viewportInteractionPausedRequestPermille
        case viewportInteractionPausePollCount
        case viewportInteractionPausedMilliseconds
        case firstTimeoutMilliseconds
        case failureLabel
        case practicalAssessment
    }

    public init(
        requestedSamples: Int,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?,
        adaptiveClientPressurePacingSamples: Int = 0,
        viewportInteractionPacingSamples: Int = 0,
        viewportInteractionPausedRequestCount: Int = 0,
        viewportInteractionPausePollCount: Int = 0,
        viewportInteractionPausedMilliseconds: Int = 0
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
        let viewportInteractionPausedRequestCount = min(
            max(viewportInteractionPausedRequestCount, 0),
            requestedSamples
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
        self.viewportInteractionPausedRequestCount = viewportInteractionPausedRequestCount
        self.viewportInteractionPausedRequestPermille = Self.permille(
            viewportInteractionPausedRequestCount,
            of: requestedSamples
        )
        self.viewportInteractionPausePollCount = max(viewportInteractionPausePollCount, 0)
        self.viewportInteractionPausedMilliseconds = max(viewportInteractionPausedMilliseconds, 0)
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
        self.viewportInteractionPausedRequestCount = min(
            max(
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .viewportInteractionPausedRequestCount
                ) ?? 0,
                0
            ),
            self.requestedSamples
        )
        self.viewportInteractionPausedRequestPermille = try container.decodeIfPresent(
            Int.self,
            forKey: .viewportInteractionPausedRequestPermille
        ) ?? Self.permille(
            self.viewportInteractionPausedRequestCount,
            of: self.requestedSamples
        )
        self.viewportInteractionPausePollCount = max(
            try container.decodeIfPresent(
                Int.self,
                forKey: .viewportInteractionPausePollCount
            ) ?? 0,
            0
        )
        self.viewportInteractionPausedMilliseconds = max(
            try container.decodeIfPresent(
                Int.self,
                forKey: .viewportInteractionPausedMilliseconds
            ) ?? 0,
            0
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

    private static func practicalAssessment(
        status: BenchmarkStreamShapeStatus,
        failureLabel: String?,
        contentUpdateSamples: Int,
        contentFramesPerSecond: Double?,
        updateLatency: BenchmarkLatencySummary?,
        clientProcessingLatency: BenchmarkLatencySummary?,
        tailLatency: BenchmarkStreamShapeTailSummary,
        rendererFullUploadPermille: Int?,
        adaptiveClientPressurePacingPermille: Int?,
        targets: BenchmarkStreamShapePracticalTargets = .iPhonePracticalBaseline
    ) -> BenchmarkStreamShapePracticalAssessment {
        if status == .disabled {
            return BenchmarkStreamShapePracticalAssessment(
                targetName: targets.name,
                verdict: .disabled,
                issueCodes: [.probeDisabled]
            )
        }
        if failureLabel != nil || status == .failed {
            return BenchmarkStreamShapePracticalAssessment(
                targetName: targets.name,
                verdict: .fail,
                issueCodes: [.probeFailed]
            )
        }

        var issues: [BenchmarkStreamShapePracticalIssueCode] = []
        if contentUpdateSamples == 0 {
            issues.append(.noContentUpdates)
        } else if contentUpdateSamples < targets.minimumContentUpdateSamples {
            issues.append(.insufficientContentSamples)
        }

        if let contentFramesPerSecond {
            if contentFramesPerSecond < targets.failContentFramesPerSecond {
                issues.append(.contentFPSFailed)
            } else if contentFramesPerSecond < targets.passContentFramesPerSecond {
                issues.append(.contentFPSWarning)
            }
        } else if contentUpdateSamples > 0 {
            issues.append(.contentFPSWarning)
        }

        if let updateLatency {
            if updateLatency.p95Milliseconds > targets.failP95UpdateMilliseconds {
                issues.append(.p95UpdateFailed)
            } else if updateLatency.p95Milliseconds > targets.passP95UpdateMilliseconds {
                issues.append(.p95UpdateWarning)
            }
        }

        if let clientProcessingLatency {
            if clientProcessingLatency.p95Milliseconds > targets.failClientProcessingP95Milliseconds {
                issues.append(.clientProcessingFailed)
            } else if clientProcessingLatency.p95Milliseconds > targets.passClientProcessingP95Milliseconds {
                issues.append(.clientProcessingWarning)
            }
        }

        if tailLatency.verySlowUpdateSamples > 0 {
            issues.append(.verySlowUpdate)
        }

        if let rendererFullUploadPermille {
            if rendererFullUploadPermille > targets.failRendererFullUploadPermille {
                issues.append(.fullUploadFailed)
            } else if rendererFullUploadPermille > targets.passRendererFullUploadPermille {
                issues.append(.fullUploadWarning)
            }
        }

        if let adaptiveClientPressurePacingPermille {
            if adaptiveClientPressurePacingPermille > targets.failAdaptivePressurePermille {
                issues.append(.adaptivePressureFailed)
            } else if adaptiveClientPressurePacingPermille > targets.passAdaptivePressurePermille {
                issues.append(.adaptivePressureWarning)
            }
        }

        return BenchmarkStreamShapePracticalAssessment(
            targetName: targets.name,
            verdict: verdict(for: issues),
            issueCodes: issues
        )
    }

    private static func verdict(
        for issues: [BenchmarkStreamShapePracticalIssueCode]
    ) -> BenchmarkStreamShapePracticalVerdict {
        let failures: Set<BenchmarkStreamShapePracticalIssueCode> = [
            .probeFailed,
            .noContentUpdates,
            .contentFPSFailed,
            .p95UpdateFailed,
            .clientProcessingFailed,
            .verySlowUpdate,
            .fullUploadFailed,
            .adaptivePressureFailed
        ]
        if issues.contains(where: failures.contains) {
            return .fail
        }
        return issues.isEmpty ? .pass : .warning
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(requestedSamples, forKey: .requestedSamples)
        try container.encode(receivedSamples, forKey: .receivedSamples)
        try container.encode(emptyUpdateSamples, forKey: .emptyUpdateSamples)
        try container.encode(contentUpdateSamples, forKey: .contentUpdateSamples)
        try container.encode(timedOutSamples, forKey: .timedOutSamples)
        try container.encodeIfPresent(elapsedMilliseconds, forKey: .elapsedMilliseconds)
        try container.encodeIfPresent(deliveredFramesPerSecond, forKey: .deliveredFramesPerSecond)
        try container.encodeIfPresent(contentFramesPerSecond, forKey: .contentFramesPerSecond)
        try container.encodeIfPresent(updateLatency, forKey: .updateLatency)
        try container.encodeIfPresent(dirtyRectangleCount, forKey: .dirtyRectangleCount)
        try container.encodeIfPresent(dirtyAreaPermille, forKey: .dirtyAreaPermille)
        try container.encodeIfPresent(changedPixelsPermille, forKey: .changedPixelsPermille)
        try container.encodeIfPresent(receiveTotalLatency, forKey: .receiveTotalLatency)
        try container.encodeIfPresent(networkReadLatency, forKey: .networkReadLatency)
        try container.encodeIfPresent(clientProcessingLatency, forKey: .clientProcessingLatency)
        try container.encode(tailLatency, forKey: .tailLatency)
        try container.encode(rendererUploadSampleCount, forKey: .rendererUploadSampleCount)
        try container.encode(rendererPartialUploadSamples, forKey: .rendererPartialUploadSamples)
        try container.encode(rendererFullUploadSamples, forKey: .rendererFullUploadSamples)
        try container.encodeIfPresent(rendererPartialUploadPermille, forKey: .rendererPartialUploadPermille)
        try container.encodeIfPresent(rendererFullUploadPermille, forKey: .rendererFullUploadPermille)
        try container.encodeIfPresent(rendererUploadRegionCount, forKey: .rendererUploadRegionCount)
        try container.encode(actualEncodingMix, forKey: .actualEncodingMix)
        try container.encode(adaptiveClientPressurePacingSamples, forKey: .adaptiveClientPressurePacingSamples)
        try container.encodeIfPresent(
            adaptiveClientPressurePacingPermille,
            forKey: .adaptiveClientPressurePacingPermille
        )
        try container.encode(viewportInteractionPacingSamples, forKey: .viewportInteractionPacingSamples)
        try container.encodeIfPresent(viewportInteractionPacingPermille, forKey: .viewportInteractionPacingPermille)
        try container.encode(viewportInteractionPausedRequestCount, forKey: .viewportInteractionPausedRequestCount)
        try container.encodeIfPresent(
            viewportInteractionPausedRequestPermille,
            forKey: .viewportInteractionPausedRequestPermille
        )
        try container.encode(viewportInteractionPausePollCount, forKey: .viewportInteractionPausePollCount)
        try container.encode(viewportInteractionPausedMilliseconds, forKey: .viewportInteractionPausedMilliseconds)
        try container.encodeIfPresent(firstTimeoutMilliseconds, forKey: .firstTimeoutMilliseconds)
        try container.encodeIfPresent(failureLabel, forKey: .failureLabel)
        try container.encode(practicalAssessment, forKey: .practicalAssessment)
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
