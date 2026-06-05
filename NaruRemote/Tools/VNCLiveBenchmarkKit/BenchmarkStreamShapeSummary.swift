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
    case averageUpdateWarning = "average-update-warning"
    case averageUpdateFailed = "average-update-failed"
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
        passAverageUpdateMilliseconds: nil,
        failAverageUpdateMilliseconds: nil,
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

    public static let iPhoneSustainedUsability = BenchmarkStreamShapePracticalTargets(
        name: "iphone-sustained-usability-v2",
        passContentFramesPerSecond: 8,
        failContentFramesPerSecond: 4,
        passAverageUpdateMilliseconds: 180,
        failAverageUpdateMilliseconds: 250,
        passP95UpdateMilliseconds: 350,
        failP95UpdateMilliseconds: 500,
        passClientProcessingP95Milliseconds: 24,
        failClientProcessingP95Milliseconds: 50,
        passRendererFullUploadPermille: 0,
        failRendererFullUploadPermille: 50,
        passAdaptivePressurePermille: 100,
        failAdaptivePressurePermille: 500,
        minimumContentUpdateSamples: 8
    )

    public let name: String
    public let passContentFramesPerSecond: Double
    public let failContentFramesPerSecond: Double
    public let passAverageUpdateMilliseconds: Int?
    public let failAverageUpdateMilliseconds: Int?
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
        passAverageUpdateMilliseconds: Int?,
        failAverageUpdateMilliseconds: Int?,
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
        let passAverageUpdateMilliseconds = passAverageUpdateMilliseconds.map { max($0, 0) }
        self.passAverageUpdateMilliseconds = passAverageUpdateMilliseconds
        self.failAverageUpdateMilliseconds = failAverageUpdateMilliseconds.map {
            max($0, passAverageUpdateMilliseconds ?? 0)
        }
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

public enum BenchmarkStreamShapePracticalTargetSelection: String, Codable, Equatable, Sendable, CaseIterable {
    case iPhonePracticalBaseline = "iphone-practical-baseline-v1"
    case iPhoneSustainedUsability = "iphone-sustained-usability-v2"

    public static let defaultSelection = Self.iPhoneSustainedUsability

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public var targets: BenchmarkStreamShapePracticalTargets {
        switch self {
        case .iPhonePracticalBaseline:
            return .iPhonePracticalBaseline
        case .iPhoneSustainedUsability:
            return .iPhoneSustainedUsability
        }
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
    public let zrleInflateMilliseconds: Int?
    public let zrleTileApplyMilliseconds: Int?
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
        case zrleInflateMilliseconds
        case zrleTileApplyMilliseconds
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
        zrleInflateMilliseconds: Int? = nil,
        zrleTileApplyMilliseconds: Int? = nil,
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
        self.zrleInflateMilliseconds = Self.clampOptionalMilliseconds(zrleInflateMilliseconds)
        self.zrleTileApplyMilliseconds = Self.clampOptionalMilliseconds(zrleTileApplyMilliseconds)
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
            zrleInflateMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .zrleInflateMilliseconds
            ),
            zrleTileApplyMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .zrleTileApplyMilliseconds
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
    public let attemptedSamples: Int
    public let receivedSamples: Int
    public let emptyUpdateSamples: Int
    public let contentUpdateSamples: Int
    public let timedOutSamples: Int
    public let receivedSamplePermille: Int?
    public let unansweredSamplePermille: Int?
    public let contentSamplePermille: Int?
    public let emptyResponsePermille: Int?
    public let contentResponsePermille: Int?
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
    public let zrleInflateLatency: BenchmarkLatencySummary?
    public let zrleTileApplyLatency: BenchmarkLatencySummary?
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
    public let practicalAssessment: BenchmarkStreamShapePracticalAssessment

    private enum CodingKeys: String, CodingKey {
        case status
        case requestedSamples
        case attemptedSamples
        case receivedSamples
        case emptyUpdateSamples
        case contentUpdateSamples
        case timedOutSamples
        case receivedSamplePermille
        case unansweredSamplePermille
        case contentSamplePermille
        case emptyResponsePermille
        case contentResponsePermille
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
        case zrleInflateLatency
        case zrleTileApplyLatency
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
        attemptedSamples: Int? = nil,
        samples: [BenchmarkStreamShapeSample],
        elapsedMilliseconds: Int?,
        firstTimeoutMilliseconds: Int?,
        failureLabel: String?,
        adaptiveClientPressurePacingSamples: Int = 0,
        viewportInteractionPacingSamples: Int = 0,
        viewportInteractionPausedRequestCount: Int = 0,
        viewportInteractionPausePollCount: Int = 0,
        viewportInteractionPausedMilliseconds: Int = 0,
        practicalTargets: BenchmarkStreamShapePracticalTargets = .iPhonePracticalBaseline
    ) {
        let requestedSamples = max(requestedSamples, 0)
        let receivedSamples = samples.count
        let attemptedSamples = max(attemptedSamples ?? requestedSamples, receivedSamples)
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
        self.attemptedSamples = attemptedSamples
        self.receivedSamples = receivedSamples
        self.emptyUpdateSamples = emptyUpdateSamples
        self.contentUpdateSamples = contentUpdateSamples
        self.timedOutSamples = firstTimeoutMilliseconds == nil ? 0 : 1
        self.receivedSamplePermille = Self.permille(receivedSamples, of: attemptedSamples)
        self.unansweredSamplePermille = Self.permille(
            max(attemptedSamples - receivedSamples, 0),
            of: attemptedSamples
        )
        self.contentSamplePermille = Self.permille(contentUpdateSamples, of: attemptedSamples)
        self.emptyResponsePermille = Self.permille(emptyUpdateSamples, of: receivedSamples)
        self.contentResponsePermille = Self.permille(contentUpdateSamples, of: receivedSamples)
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
        self.zrleInflateLatency = BenchmarkLatencySummary(samples.compactMap(\.zrleInflateMilliseconds))
        self.zrleTileApplyLatency = BenchmarkLatencySummary(samples.compactMap(\.zrleTileApplyMilliseconds))
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
        self.practicalAssessment = Self.practicalAssessment(
            status: status,
            failureLabel: failureLabel,
            contentUpdateSamples: contentUpdateSamples,
            contentFramesPerSecond: contentFramesPerSecond,
            updateLatency: updateLatency,
            clientProcessingLatency: clientProcessingLatency,
            tailLatency: tailLatency,
            rendererFullUploadPermille: rendererFullUploadPermille,
            adaptiveClientPressurePacingPermille: adaptiveClientPressurePacingPermille,
            targets: practicalTargets
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(BenchmarkStreamShapeStatus.self, forKey: .status)
        let requestedSamples = max(try container.decode(Int.self, forKey: .requestedSamples), 0)
        let receivedSamples = max(try container.decode(Int.self, forKey: .receivedSamples), 0)
        let attemptedSamples = max(
            try container.decodeIfPresent(Int.self, forKey: .attemptedSamples) ?? requestedSamples,
            receivedSamples
        )
        let emptyUpdateSamples = max(try container.decode(Int.self, forKey: .emptyUpdateSamples), 0)
        let contentUpdateSamples = max(try container.decode(Int.self, forKey: .contentUpdateSamples), 0)
        let timedOutSamples = max(try container.decode(Int.self, forKey: .timedOutSamples), 0)
        self.status = status
        self.requestedSamples = requestedSamples
        self.attemptedSamples = attemptedSamples
        self.receivedSamples = receivedSamples
        self.emptyUpdateSamples = emptyUpdateSamples
        self.contentUpdateSamples = contentUpdateSamples
        self.timedOutSamples = timedOutSamples
        self.receivedSamplePermille = Self.clampOptionalPermille(try container.decodeIfPresent(
            Int.self,
            forKey: .receivedSamplePermille
        )) ?? Self.permille(receivedSamples, of: attemptedSamples)
        self.unansweredSamplePermille = Self.clampOptionalPermille(try container.decodeIfPresent(
            Int.self,
            forKey: .unansweredSamplePermille
        )) ?? Self.permille(max(attemptedSamples - receivedSamples, 0), of: attemptedSamples)
        self.contentSamplePermille = Self.clampOptionalPermille(try container.decodeIfPresent(
            Int.self,
            forKey: .contentSamplePermille
        )) ?? Self.permille(contentUpdateSamples, of: attemptedSamples)
        self.emptyResponsePermille = Self.clampOptionalPermille(try container.decodeIfPresent(
            Int.self,
            forKey: .emptyResponsePermille
        )) ?? Self.permille(emptyUpdateSamples, of: receivedSamples)
        self.contentResponsePermille = Self.clampOptionalPermille(try container.decodeIfPresent(
            Int.self,
            forKey: .contentResponsePermille
        )) ?? Self.permille(contentUpdateSamples, of: receivedSamples)
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
        self.zrleInflateLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .zrleInflateLatency
        )
        self.zrleTileApplyLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .zrleTileApplyLatency
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
        self.practicalAssessment = try container.decodeIfPresent(
            BenchmarkStreamShapePracticalAssessment.self,
            forKey: .practicalAssessment
        ) ?? Self.practicalAssessment(
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
        return value > 0 ? min(max(rounded, 1), 1_000) : 0
    }

    private static func clampOptionalPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
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
            if let failAverage = targets.failAverageUpdateMilliseconds,
               updateLatency.averageMilliseconds > failAverage {
                issues.append(.averageUpdateFailed)
            } else if let passAverage = targets.passAverageUpdateMilliseconds,
                      updateLatency.averageMilliseconds > passAverage {
                issues.append(.averageUpdateWarning)
            }

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
            .averageUpdateFailed,
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
        try container.encode(attemptedSamples, forKey: .attemptedSamples)
        try container.encode(receivedSamples, forKey: .receivedSamples)
        try container.encode(emptyUpdateSamples, forKey: .emptyUpdateSamples)
        try container.encode(contentUpdateSamples, forKey: .contentUpdateSamples)
        try container.encode(timedOutSamples, forKey: .timedOutSamples)
        try container.encodeIfPresent(receivedSamplePermille, forKey: .receivedSamplePermille)
        try container.encodeIfPresent(unansweredSamplePermille, forKey: .unansweredSamplePermille)
        try container.encodeIfPresent(contentSamplePermille, forKey: .contentSamplePermille)
        try container.encodeIfPresent(emptyResponsePermille, forKey: .emptyResponsePermille)
        try container.encodeIfPresent(contentResponsePermille, forKey: .contentResponsePermille)
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
        try container.encodeIfPresent(zrleInflateLatency, forKey: .zrleInflateLatency)
        try container.encodeIfPresent(zrleTileApplyLatency, forKey: .zrleTileApplyLatency)
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
    public let firstSlowUpdateOrdinal: Int?
    public let firstSlowContentUpdateOrdinal: Int?
    public let firstVerySlowUpdateOrdinal: Int?
    public let firstVerySlowContentUpdateOrdinal: Int?

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
        self.firstSlowUpdateOrdinal = Self.firstUpdateOrdinal(
            in: samples,
            atOrAbove: slowThreshold
        )
        self.firstSlowContentUpdateOrdinal = Self.firstContentUpdateOrdinal(
            in: samples,
            atOrAbove: slowThreshold
        )
        self.firstVerySlowUpdateOrdinal = Self.firstUpdateOrdinal(
            in: samples,
            atOrAbove: verySlowThreshold
        )
        self.firstVerySlowContentUpdateOrdinal = Self.firstContentUpdateOrdinal(
            in: samples,
            atOrAbove: verySlowThreshold
        )
    }

    private static func firstUpdateOrdinal(
        in samples: [BenchmarkStreamShapeSample],
        atOrAbove thresholdMilliseconds: Int
    ) -> Int? {
        for (index, sample) in samples.enumerated() where sample.durationMilliseconds >= thresholdMilliseconds {
            return index + 1
        }
        return nil
    }

    private static func firstContentUpdateOrdinal(
        in samples: [BenchmarkStreamShapeSample],
        atOrAbove thresholdMilliseconds: Int
    ) -> Int? {
        var contentOrdinal = 0
        for sample in samples {
            guard sample.kind == .contentUpdate else {
                continue
            }
            contentOrdinal += 1
            if sample.durationMilliseconds >= thresholdMilliseconds {
                return contentOrdinal
            }
        }
        return nil
    }
}

public struct BenchmarkStreamShapeProfileReport: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let iterationOrdinal: Int?
    public let orderOrdinal: Int?
    public let firstFrameMilliseconds: Int?
    public let summary: BenchmarkStreamShapeSummary

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode = .requestResponse,
        iterationOrdinal: Int? = nil,
        orderOrdinal: Int? = nil,
        firstFrameMilliseconds: Int?,
        summary: BenchmarkStreamShapeSummary
    ) {
        self.label = label
        self.transportMode = transportMode
        self.iterationOrdinal = iterationOrdinal.map { max($0, 1) }
        self.orderOrdinal = orderOrdinal.map { max($0, 1) }
        self.firstFrameMilliseconds = firstFrameMilliseconds
        self.summary = summary
    }
}

public struct BenchmarkStreamShapeProfileAggregateReport: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let runCount: Int
    public let usableRunCount: Int
    public let failedRunCount: Int
    public let averageUpdateMilliseconds: Int?
    public let maxP95UpdateMilliseconds: Int?
    public let averageContentFramesPerSecond: Double?
    public let averageRendererFullUploadPermille: Int?
    public let maxClientProcessingP95Milliseconds: Int?
    public let maxZrleTileApplyP95Milliseconds: Int?
    public let slowUpdateSamples: Int
    public let verySlowUpdateSamples: Int
    public let receivedSamples: Int
    public let contentUpdateSamples: Int
    public let averageReceivedSamplePermille: Int?
    public let averageContentSamplePermille: Int?
    public let averageContentResponsePermille: Int?
    public let averageUnansweredSamplePermille: Int?

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode,
        runCount: Int,
        usableRunCount: Int,
        failedRunCount: Int,
        averageUpdateMilliseconds: Int?,
        maxP95UpdateMilliseconds: Int?,
        averageContentFramesPerSecond: Double?,
        averageRendererFullUploadPermille: Int?,
        maxClientProcessingP95Milliseconds: Int?,
        maxZrleTileApplyP95Milliseconds: Int?,
        slowUpdateSamples: Int,
        verySlowUpdateSamples: Int,
        receivedSamples: Int,
        contentUpdateSamples: Int,
        averageReceivedSamplePermille: Int? = nil,
        averageContentSamplePermille: Int? = nil,
        averageContentResponsePermille: Int? = nil,
        averageUnansweredSamplePermille: Int? = nil
    ) {
        self.label = label
        self.transportMode = transportMode
        self.runCount = max(runCount, 0)
        self.usableRunCount = max(usableRunCount, 0)
        self.failedRunCount = max(failedRunCount, 0)
        self.averageUpdateMilliseconds = averageUpdateMilliseconds.map { max($0, 0) }
        self.maxP95UpdateMilliseconds = maxP95UpdateMilliseconds.map { max($0, 0) }
        self.averageContentFramesPerSecond = averageContentFramesPerSecond.map { max($0, 0) }
        self.averageRendererFullUploadPermille = averageRendererFullUploadPermille.map {
            min(max($0, 0), 1_000)
        }
        self.maxClientProcessingP95Milliseconds = maxClientProcessingP95Milliseconds.map { max($0, 0) }
        self.maxZrleTileApplyP95Milliseconds = maxZrleTileApplyP95Milliseconds.map { max($0, 0) }
        self.slowUpdateSamples = max(slowUpdateSamples, 0)
        self.verySlowUpdateSamples = max(verySlowUpdateSamples, 0)
        self.receivedSamples = max(receivedSamples, 0)
        self.contentUpdateSamples = max(contentUpdateSamples, 0)
        self.averageReceivedSamplePermille = Self.clampOptionalPermille(averageReceivedSamplePermille)
        self.averageContentSamplePermille = Self.clampOptionalPermille(averageContentSamplePermille)
        self.averageContentResponsePermille = Self.clampOptionalPermille(averageContentResponsePermille)
        self.averageUnansweredSamplePermille = Self.clampOptionalPermille(averageUnansweredSamplePermille)
    }

    public static func aggregates(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [BenchmarkStreamShapeProfileAggregateReport] {
        let orderedKeys = orderedAggregateKeys(from: reports)
        let grouped = Dictionary(grouping: reports) {
            AggregateKey(label: $0.label, transportMode: $0.transportMode)
        }
        return orderedKeys.compactMap { key in
            grouped[key].map { aggregate(key: key, reports: $0) }
        }
    }

    private static func aggregate(
        key: AggregateKey,
        reports: [BenchmarkStreamShapeProfileReport]
    ) -> BenchmarkStreamShapeProfileAggregateReport {
        let usableReports = reports.filter(isUsable)
        let updateAverages = usableReports.compactMap { $0.summary.updateLatency?.averageMilliseconds }
        let updateP95s = usableReports.compactMap { $0.summary.updateLatency?.p95Milliseconds }
        let contentFPS = usableReports.compactMap(\.summary.contentFramesPerSecond)
        let fullUploadPermille = usableReports.compactMap(\.summary.rendererFullUploadPermille)
        let clientP95s = usableReports.compactMap { $0.summary.clientProcessingLatency?.p95Milliseconds }
        let zrleTileP95s = usableReports.compactMap { $0.summary.zrleTileApplyLatency?.p95Milliseconds }
        let receivedSamplePermille = usableReports.compactMap(\.summary.receivedSamplePermille)
        let contentSamplePermille = usableReports.compactMap(\.summary.contentSamplePermille)
        let contentResponsePermille = usableReports.compactMap(\.summary.contentResponsePermille)
        let unansweredSamplePermille = usableReports.compactMap(\.summary.unansweredSamplePermille)
        // Keep profile aggregates as run-level means so rotated benchmark
        // iterations have equal weight even when duration-capped attempts vary.
        return BenchmarkStreamShapeProfileAggregateReport(
            label: key.label,
            transportMode: key.transportMode,
            runCount: reports.count,
            usableRunCount: usableReports.count,
            failedRunCount: reports.count - usableReports.count,
            averageUpdateMilliseconds: roundedAverage(updateAverages),
            maxP95UpdateMilliseconds: updateP95s.max(),
            averageContentFramesPerSecond: average(contentFPS),
            averageRendererFullUploadPermille: roundedAverage(fullUploadPermille),
            maxClientProcessingP95Milliseconds: clientP95s.max(),
            maxZrleTileApplyP95Milliseconds: zrleTileP95s.max(),
            slowUpdateSamples: usableReports.reduce(0) { $0 + $1.summary.tailLatency.slowUpdateSamples },
            verySlowUpdateSamples: usableReports.reduce(0) { $0 + $1.summary.tailLatency.verySlowUpdateSamples },
            receivedSamples: usableReports.reduce(0) { $0 + $1.summary.receivedSamples },
            contentUpdateSamples: usableReports.reduce(0) { $0 + $1.summary.contentUpdateSamples },
            averageReceivedSamplePermille: roundedAverage(receivedSamplePermille),
            averageContentSamplePermille: roundedAverage(contentSamplePermille),
            averageContentResponsePermille: roundedAverage(contentResponsePermille),
            averageUnansweredSamplePermille: roundedAverage(unansweredSamplePermille)
        )
    }

    private static func isUsable(_ report: BenchmarkStreamShapeProfileReport) -> Bool {
        report.summary.failureLabel == nil
            && report.summary.receivedSamples > 0
            && report.summary.contentUpdateSamples > 0
            && report.summary.rendererUploadSampleCount > 0
            && report.summary.updateLatency != nil
            && report.summary.contentFramesPerSecond != nil
            && report.summary.rendererFullUploadPermille != nil
    }

    private static func orderedAggregateKeys(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [AggregateKey] {
        var seen: Set<AggregateKey> = []
        var keys: [AggregateKey] = []
        for report in reports {
            let key = AggregateKey(label: report.label, transportMode: report.transportMode)
            if seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    private static func roundedAverage(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func clampOptionalPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
    }

    private struct AggregateKey: Hashable {
        let label: String
        let transportMode: BenchmarkStreamShapeTransportMode
    }
}

public struct BenchmarkStreamShapeProfileGateReport: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let targetName: String
    public let verdict: BenchmarkStreamShapePracticalVerdict
    public let runCount: Int
    public let passRunCount: Int
    public let warningRunCount: Int
    public let failRunCount: Int
    public let disabledRunCount: Int
    public let issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    public let averageReceivedSamplePermille: Int?
    public let averageContentSamplePermille: Int?
    public let averageContentResponsePermille: Int?
    public let averageUnansweredSamplePermille: Int?

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode,
        targetName: String,
        verdict: BenchmarkStreamShapePracticalVerdict,
        runCount: Int,
        passRunCount: Int,
        warningRunCount: Int,
        failRunCount: Int,
        disabledRunCount: Int,
        issueCodes: [BenchmarkStreamShapePracticalIssueCode],
        averageReceivedSamplePermille: Int? = nil,
        averageContentSamplePermille: Int? = nil,
        averageContentResponsePermille: Int? = nil,
        averageUnansweredSamplePermille: Int? = nil
    ) {
        self.label = label
        self.transportMode = transportMode
        self.targetName = targetName
        self.verdict = verdict
        self.runCount = max(runCount, 0)
        self.passRunCount = max(passRunCount, 0)
        self.warningRunCount = max(warningRunCount, 0)
        self.failRunCount = max(failRunCount, 0)
        self.disabledRunCount = max(disabledRunCount, 0)
        self.issueCodes = Self.orderedIssueCodes(issueCodes)
        self.averageReceivedSamplePermille = Self.clampOptionalPermille(averageReceivedSamplePermille)
        self.averageContentSamplePermille = Self.clampOptionalPermille(averageContentSamplePermille)
        self.averageContentResponsePermille = Self.clampOptionalPermille(averageContentResponsePermille)
        self.averageUnansweredSamplePermille = Self.clampOptionalPermille(averageUnansweredSamplePermille)
    }

    public static func gates(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [BenchmarkStreamShapeProfileGateReport] {
        let orderedKeys = orderedGateKeys(from: reports)
        let grouped = Dictionary(grouping: reports) {
            GateKey(label: $0.label, transportMode: $0.transportMode)
        }
        return orderedKeys.compactMap { key in
            grouped[key].map { gate(key: key, reports: $0) }
        }
    }

    private static func gate(
        key: GateKey,
        reports: [BenchmarkStreamShapeProfileReport]
    ) -> BenchmarkStreamShapeProfileGateReport {
        let assessments = reports.map(\.summary.practicalAssessment)
        let passRunCount = assessments.filter { $0.verdict == .pass }.count
        let warningRunCount = assessments.filter { $0.verdict == .warning }.count
        let failRunCount = assessments.filter { $0.verdict == .fail }.count
        let disabledRunCount = assessments.filter { $0.verdict == .disabled }.count
        let issueCodes = assessments.flatMap(\.issueCodes)
        let targetName = assessments.first?.targetName ?? BenchmarkStreamShapePracticalTargets
            .iPhoneSustainedUsability
            .name
        return BenchmarkStreamShapeProfileGateReport(
            label: key.label,
            transportMode: key.transportMode,
            targetName: targetName,
            verdict: verdict(
                passRunCount: passRunCount,
                warningRunCount: warningRunCount,
                failRunCount: failRunCount,
                disabledRunCount: disabledRunCount
            ),
            runCount: reports.count,
            passRunCount: passRunCount,
            warningRunCount: warningRunCount,
            failRunCount: failRunCount,
            disabledRunCount: disabledRunCount,
            issueCodes: issueCodes,
            averageReceivedSamplePermille: roundedAverage(reports.compactMap(\.summary.receivedSamplePermille)),
            averageContentSamplePermille: roundedAverage(reports.compactMap(\.summary.contentSamplePermille)),
            averageContentResponsePermille: roundedAverage(reports.compactMap(\.summary.contentResponsePermille)),
            averageUnansweredSamplePermille: roundedAverage(reports.compactMap(\.summary.unansweredSamplePermille))
        )
    }

    private static func verdict(
        passRunCount: Int,
        warningRunCount: Int,
        failRunCount: Int,
        disabledRunCount: Int
    ) -> BenchmarkStreamShapePracticalVerdict {
        if failRunCount > 0 {
            return .fail
        }
        if warningRunCount > 0 {
            return .warning
        }
        if passRunCount > 0 {
            return .pass
        }
        if disabledRunCount > 0 {
            return .disabled
        }
        return .disabled
    }

    private static func orderedGateKeys(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [GateKey] {
        var seen: Set<GateKey> = []
        var keys: [GateKey] = []
        for report in reports {
            let key = GateKey(label: report.label, transportMode: report.transportMode)
            if seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }

    private static func orderedIssueCodes(
        _ issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    ) -> [BenchmarkStreamShapePracticalIssueCode] {
        let issueSet = Set(issueCodes)
        return BenchmarkStreamShapePracticalIssueCode.allCases.filter { issueSet.contains($0) }
    }

    private static func roundedAverage(_ values: [Int]) -> Int? {
        guard !values.isEmpty else {
            return nil
        }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private static func clampOptionalPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
    }

    private struct GateKey: Hashable {
        let label: String
        let transportMode: BenchmarkStreamShapeTransportMode
    }
}

public struct BenchmarkStreamShapeRecommendation: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let reason: String
    public let runCount: Int?
    public let usableRunCount: Int?
    public let averageUpdateMilliseconds: Int
    public let p95UpdateMilliseconds: Int
    public let contentFramesPerSecond: Double
    public let rendererFullUploadPermille: Int
    public let slowUpdateSamples: Int
    public let receivedSamples: Int
    public let contentUpdateSamples: Int
    public let contentSamplePermille: Int?
    public let contentResponsePermille: Int?

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode,
        reason: String,
        runCount: Int? = nil,
        usableRunCount: Int? = nil,
        averageUpdateMilliseconds: Int,
        p95UpdateMilliseconds: Int,
        contentFramesPerSecond: Double,
        rendererFullUploadPermille: Int,
        slowUpdateSamples: Int,
        receivedSamples: Int,
        contentUpdateSamples: Int,
        contentSamplePermille: Int? = nil,
        contentResponsePermille: Int? = nil
    ) {
        self.label = label
        self.transportMode = transportMode
        self.reason = reason
        self.runCount = runCount.map { max($0, 0) }
        self.usableRunCount = usableRunCount.map { max($0, 0) }
        self.averageUpdateMilliseconds = max(averageUpdateMilliseconds, 0)
        self.p95UpdateMilliseconds = max(p95UpdateMilliseconds, 0)
        self.contentFramesPerSecond = max(contentFramesPerSecond, 0)
        self.rendererFullUploadPermille = min(max(rendererFullUploadPermille, 0), 1_000)
        self.slowUpdateSamples = max(slowUpdateSamples, 0)
        self.receivedSamples = max(receivedSamples, 0)
        self.contentUpdateSamples = max(contentUpdateSamples, 0)
        self.contentSamplePermille = Self.clampOptionalPermille(contentSamplePermille)
        self.contentResponsePermille = Self.clampOptionalPermille(contentResponsePermille)
    }

    public static func recommendedRequestResponseProfile(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> BenchmarkStreamShapeRecommendation? {
        reports
            .compactMap(BenchmarkStreamShapeRecommendation.init(report:))
            .sorted(by: isPreferred)
            .first
    }

    public static func recommendedOrderNeutralRequestResponseProfile(
        from aggregates: [BenchmarkStreamShapeProfileAggregateReport]
    ) -> BenchmarkStreamShapeRecommendation? {
        aggregates
            .compactMap(BenchmarkStreamShapeRecommendation.init(aggregate:))
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
            runCount: report.iterationOrdinal == nil ? nil : 1,
            usableRunCount: report.iterationOrdinal == nil ? nil : 1,
            averageUpdateMilliseconds: updateLatency.averageMilliseconds,
            p95UpdateMilliseconds: updateLatency.p95Milliseconds,
            contentFramesPerSecond: contentFramesPerSecond,
            rendererFullUploadPermille: rendererFullUploadPermille,
            slowUpdateSamples: report.summary.tailLatency.slowUpdateSamples,
            receivedSamples: report.summary.receivedSamples,
            contentUpdateSamples: report.summary.contentUpdateSamples,
            contentSamplePermille: report.summary.contentSamplePermille,
            contentResponsePermille: report.summary.contentResponsePermille
        )
    }

    private init?(aggregate: BenchmarkStreamShapeProfileAggregateReport) {
        guard aggregate.transportMode == .requestResponse,
              aggregate.usableRunCount > 0,
              aggregate.contentUpdateSamples > 0,
              let averageUpdateMilliseconds = aggregate.averageUpdateMilliseconds,
              let maxP95UpdateMilliseconds = aggregate.maxP95UpdateMilliseconds,
              let averageContentFramesPerSecond = aggregate.averageContentFramesPerSecond,
              let averageRendererFullUploadPermille = aggregate.averageRendererFullUploadPermille
        else {
            return nil
        }

        self.init(
            label: aggregate.label,
            transportMode: aggregate.transportMode,
            reason: "lowest-average-update-latency-across-order-neutral-request-response-runs",
            runCount: aggregate.runCount,
            usableRunCount: aggregate.usableRunCount,
            averageUpdateMilliseconds: averageUpdateMilliseconds,
            p95UpdateMilliseconds: maxP95UpdateMilliseconds,
            contentFramesPerSecond: averageContentFramesPerSecond,
            rendererFullUploadPermille: averageRendererFullUploadPermille,
            slowUpdateSamples: aggregate.slowUpdateSamples,
            receivedSamples: aggregate.receivedSamples,
            contentUpdateSamples: aggregate.contentUpdateSamples,
            contentSamplePermille: aggregate.averageContentSamplePermille,
            contentResponsePermille: aggregate.averageContentResponsePermille
        )
    }

    private static func clampOptionalPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
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
