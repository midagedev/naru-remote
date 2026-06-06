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
    case firstFrameWarning = "first-frame-warning"
    case firstFrameFailed = "first-frame-failed"
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
    case requestRegionAreaWarning = "request-region-area-warning"
    case requestRegionAreaFailed = "request-region-area-failed"
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

    public static let iPhonePoorNetworkTraffic = BenchmarkStreamShapePracticalTargets(
        name: "iphone-poor-network-traffic-v1",
        passContentFramesPerSecond: 4,
        failContentFramesPerSecond: 1,
        passAverageUpdateMilliseconds: 350,
        failAverageUpdateMilliseconds: 700,
        passP95UpdateMilliseconds: 600,
        failP95UpdateMilliseconds: 1_000,
        passClientProcessingP95Milliseconds: 24,
        failClientProcessingP95Milliseconds: 50,
        passRendererFullUploadPermille: 0,
        failRendererFullUploadPermille: 50,
        passAdaptivePressurePermille: 100,
        failAdaptivePressurePermille: 500,
        minimumContentUpdateSamples: 4,
        passFirstFrameMilliseconds: 5_000,
        failFirstFrameMilliseconds: 20_000,
        passRequestRegionAreaPermille: 400,
        failRequestRegionAreaPermille: 700
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
    public let passFirstFrameMilliseconds: Int?
    public let failFirstFrameMilliseconds: Int?
    public let passRequestRegionAreaPermille: Int?
    public let failRequestRegionAreaPermille: Int?

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
        minimumContentUpdateSamples: Int,
        passFirstFrameMilliseconds: Int? = nil,
        failFirstFrameMilliseconds: Int? = nil,
        passRequestRegionAreaPermille: Int? = nil,
        failRequestRegionAreaPermille: Int? = nil
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
        let passFirstFrameMilliseconds = passFirstFrameMilliseconds.map { max($0, 0) }
        self.passFirstFrameMilliseconds = passFirstFrameMilliseconds
        self.failFirstFrameMilliseconds = failFirstFrameMilliseconds.map {
            max($0, passFirstFrameMilliseconds ?? 0)
        }
        let passRequestRegionAreaPermille = passRequestRegionAreaPermille.map(Self.clampPermille)
        self.passRequestRegionAreaPermille = passRequestRegionAreaPermille
        self.failRequestRegionAreaPermille = failRequestRegionAreaPermille.map {
            max(Self.clampPermille($0), passRequestRegionAreaPermille ?? 0)
        }
    }

    private static func clampPermille(_ value: Int) -> Int {
        min(max(value, 0), 1_000)
    }
}

public enum BenchmarkStreamShapePracticalTargetSelection: String, Codable, Equatable, Sendable, CaseIterable {
    case iPhonePracticalBaseline = "iphone-practical-baseline-v1"
    case iPhoneSustainedUsability = "iphone-sustained-usability-v2"
    case iPhonePoorNetworkTraffic = "iphone-poor-network-traffic-v1"

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
        case .iPhonePoorNetworkTraffic:
            return .iPhonePoorNetworkTraffic
        }
    }
}

public struct BenchmarkStreamShapeTriageLabelCount: Codable, Equatable, Sendable {
    public let label: String
    public let count: Int

    private enum CodingKeys: String, CodingKey {
        case label
        case count
    }

    public init(label: String, count: Int) {
        self.label = label
        self.count = max(count, 0)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decode(String.self, forKey: .label),
            count: try container.decode(Int.self, forKey: .count)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(count, forKey: .count)
    }
}

fileprivate enum BenchmarkStreamShapeTriage {
    static let primaryIssuePriority: [BenchmarkStreamShapePracticalIssueCode] = [
        .probeFailed,
        .firstFrameFailed,
        .requestRegionAreaFailed,
        .fullUploadFailed,
        .clientProcessingFailed,
        .verySlowUpdate,
        .averageUpdateFailed,
        .p95UpdateFailed,
        .contentFPSFailed,
        .noContentUpdates,
        .fullUploadWarning,
        .clientProcessingWarning,
        .averageUpdateWarning,
        .p95UpdateWarning,
        .contentFPSWarning,
        .firstFrameWarning,
        .requestRegionAreaWarning,
        .adaptivePressureFailed,
        .adaptivePressureWarning,
        .insufficientContentSamples,
        .probeDisabled
    ]

    static func safeIssueCodes(
        _ values: [BenchmarkStreamShapePracticalIssueCode]
    ) -> [BenchmarkStreamShapePracticalIssueCode] {
        var seen = Set<String>()
        return values.filter { issue in
            guard !seen.contains(issue.rawValue) else {
                return false
            }
            seen.insert(issue.rawValue)
            return true
        }
    }

    static func primaryIssue(
        for issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    ) -> BenchmarkStreamShapePracticalIssueCode? {
        primaryIssuePriority.first { issueCodes.contains($0) }
    }

    static func safePrimaryIssueCode(
        _ value: BenchmarkStreamShapePracticalIssueCode?,
        issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    ) -> BenchmarkStreamShapePracticalIssueCode? {
        guard let value, issueCodes.contains(value) else {
            return nil
        }
        return value
    }

    static func primaryConstraint(
        for issue: BenchmarkStreamShapePracticalIssueCode?
    ) -> DiagnosticSustainedSessionPrimaryConstraint {
        switch issue {
        case nil, .probeDisabled?:
            return .none
        case .insufficientContentSamples?:
            return .sampleSize
        case .noContentUpdates?, .contentFPSWarning?, .contentFPSFailed?:
            return .contentCadence
        case .probeFailed?,
            .firstFrameWarning?,
            .firstFrameFailed?,
            .averageUpdateWarning?,
            .averageUpdateFailed?,
            .p95UpdateWarning?,
            .p95UpdateFailed?,
            .verySlowUpdate?:
            return .receivePath
        case .clientProcessingWarning?, .clientProcessingFailed?:
            return .clientDecode
        case .fullUploadWarning?, .fullUploadFailed?:
            return .rendererUpload
        case .requestRegionAreaWarning?, .requestRegionAreaFailed?:
            return .viewportInteraction
        case .adaptivePressureWarning?, .adaptivePressureFailed?:
            return .adaptivePacing
        }
    }

    static func recommendedNextProbe(
        for issue: BenchmarkStreamShapePracticalIssueCode?
    ) -> DiagnosticSustainedSessionNextProbe {
        switch primaryConstraint(for: issue) {
        case .none:
            return .none
        case .sampleSize:
            return .collectLongerPhysicalRun
        case .contentCadence:
            return .runSustainedV2ProfileGate
        case .receivePath:
            return .inspectServerTransportCadence
        case .clientDecode:
            return .compareEncodingProfileGate
        case .appFrameApply, .rendererUpload:
            return .inspectLocalRenderPipeline
        case .adaptivePacing:
            return .compareAdaptivePacing
        case .thermal:
            return .runPowerSaverThermalPass
        case .viewportInteraction:
            return .runViewportInteractionTrace
        case .composeInput:
            return .inspectComposeRoute
        }
    }

    static func safePrimaryConstraint(
        _ value: String?,
        matching expected: DiagnosticSustainedSessionPrimaryConstraint
    ) -> String? {
        guard let value,
              DiagnosticSustainedSessionPrimaryConstraint(rawValue: value) == expected
        else {
            return nil
        }
        return value
    }

    static func safeRecommendedNextProbe(
        _ value: String?,
        matching expected: DiagnosticSustainedSessionNextProbe
    ) -> String? {
        guard let value,
              DiagnosticSustainedSessionNextProbe(rawValue: value) == expected
        else {
            return nil
        }
        return value
    }

    static func primaryConstraintCounts(
        for labels: [String]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        labelCounts(
            for: labels,
            orderedLabels: DiagnosticSustainedSessionPrimaryConstraint.allCases.map(\.rawValue)
        )
    }

    static func recommendedNextProbeCounts(
        for labels: [String]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        labelCounts(
            for: labels,
            orderedLabels: DiagnosticSustainedSessionNextProbe.allCases.map(\.rawValue)
        )
    }

    static func mergedPrimaryConstraintCounts(
        from counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        mergedCounts(
            counts,
            orderedLabels: DiagnosticSustainedSessionPrimaryConstraint.allCases.map(\.rawValue)
        )
    }

    static func mergedRecommendedNextProbeCounts(
        from counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        mergedCounts(
            counts,
            orderedLabels: DiagnosticSustainedSessionNextProbe.allCases.map(\.rawValue)
        )
    }

    static func failureLabelCounts(
        for labels: [String]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        labelCountsPreservingOrder(for: labels)
    }

    static func mergedFailureLabelCounts(
        from counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        mergedCountsPreservingOrder(counts)
    }

    private static func labelCounts(
        for labels: [String],
        orderedLabels: [String]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        var rawCounts: [String: Int] = [:]
        for label in labels where orderedLabels.contains(label) {
            rawCounts[label, default: 0] += 1
        }
        return orderedLabels.compactMap { label in
            guard let count = rawCounts[label], count > 0 else {
                return nil
            }
            return BenchmarkStreamShapeTriageLabelCount(label: label, count: count)
        }
    }

    private static func mergedCounts(
        _ counts: [BenchmarkStreamShapeTriageLabelCount],
        orderedLabels: [String]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        var rawCounts: [String: Int] = [:]
        for entry in counts where orderedLabels.contains(entry.label) {
            rawCounts[entry.label, default: 0] += entry.count
        }
        return orderedLabels.compactMap { label in
            guard let count = rawCounts[label], count > 0 else {
                return nil
            }
            return BenchmarkStreamShapeTriageLabelCount(label: label, count: count)
        }
    }

    private static func labelCountsPreservingOrder(
        for labels: [String]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        var orderedLabels: [String] = []
        var rawCounts: [String: Int] = [:]
        for rawLabel in labels {
            let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                continue
            }
            if rawCounts[label] == nil {
                orderedLabels.append(label)
            }
            rawCounts[label, default: 0] += 1
        }
        return orderedLabels.compactMap { label in
            guard let count = rawCounts[label], count > 0 else {
                return nil
            }
            return BenchmarkStreamShapeTriageLabelCount(label: label, count: count)
        }
    }

    private static func mergedCountsPreservingOrder(
        _ counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> [BenchmarkStreamShapeTriageLabelCount] {
        var orderedLabels: [String] = []
        var rawCounts: [String: Int] = [:]
        for entry in counts where entry.count > 0 {
            let label = entry.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                continue
            }
            if rawCounts[label] == nil {
                orderedLabels.append(label)
            }
            rawCounts[label, default: 0] += entry.count
        }
        return orderedLabels.compactMap { label in
            guard let count = rawCounts[label], count > 0 else {
                return nil
            }
            return BenchmarkStreamShapeTriageLabelCount(label: label, count: count)
        }
    }
}

public struct BenchmarkStreamShapePracticalAssessment: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case targetName
        case verdict
        case issueCodes
        case primaryIssueCode
        case primaryConstraint
        case recommendedNextProbe
    }

    public let targetName: String
    public let verdict: BenchmarkStreamShapePracticalVerdict
    public let issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    public let primaryIssueCode: BenchmarkStreamShapePracticalIssueCode?
    public let primaryConstraint: String
    public let recommendedNextProbe: String

    public init(
        targetName: String,
        verdict: BenchmarkStreamShapePracticalVerdict,
        issueCodes: [BenchmarkStreamShapePracticalIssueCode],
        primaryIssueCode: BenchmarkStreamShapePracticalIssueCode? = nil,
        primaryConstraint: String? = nil,
        recommendedNextProbe: String? = nil
    ) {
        self.targetName = targetName
        self.verdict = verdict
        let safeIssueCodes = BenchmarkStreamShapeTriage.safeIssueCodes(issueCodes)
        let primaryIssue = BenchmarkStreamShapeTriage.safePrimaryIssueCode(
            primaryIssueCode,
            issueCodes: safeIssueCodes
        ) ?? BenchmarkStreamShapeTriage.primaryIssue(for: safeIssueCodes)
        self.issueCodes = safeIssueCodes
        self.primaryIssueCode = primaryIssue
        let derivedPrimaryConstraint = BenchmarkStreamShapeTriage.primaryConstraint(for: primaryIssue)
        let derivedRecommendedNextProbe = BenchmarkStreamShapeTriage.recommendedNextProbe(for: primaryIssue)
        self.primaryConstraint = BenchmarkStreamShapeTriage.safePrimaryConstraint(
            primaryConstraint,
            matching: derivedPrimaryConstraint
        ) ?? derivedPrimaryConstraint.rawValue
        self.recommendedNextProbe = BenchmarkStreamShapeTriage.safeRecommendedNextProbe(
            recommendedNextProbe,
            matching: derivedRecommendedNextProbe
        ) ?? derivedRecommendedNextProbe.rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPrimaryIssueCode = try container.decodeIfPresent(String.self, forKey: .primaryIssueCode)
        self.init(
            targetName: try container.decode(String.self, forKey: .targetName),
            verdict: try container.decode(BenchmarkStreamShapePracticalVerdict.self, forKey: .verdict),
            issueCodes: try container.decodeIfPresent(
                [BenchmarkStreamShapePracticalIssueCode].self,
                forKey: .issueCodes
            ) ?? [],
            primaryIssueCode: rawPrimaryIssueCode.flatMap(BenchmarkStreamShapePracticalIssueCode.init(rawValue:)),
            primaryConstraint: try container.decodeIfPresent(String.self, forKey: .primaryConstraint),
            recommendedNextProbe: try container.decodeIfPresent(String.self, forKey: .recommendedNextProbe)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetName, forKey: .targetName)
        try container.encode(verdict, forKey: .verdict)
        try container.encode(issueCodes, forKey: .issueCodes)
        try container.encodeIfPresent(primaryIssueCode?.rawValue, forKey: .primaryIssueCode)
        try container.encode(primaryConstraint, forKey: .primaryConstraint)
        try container.encode(recommendedNextProbe, forKey: .recommendedNextProbe)
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
    public let firstByteWaitMilliseconds: Int?
    public let payloadReadMilliseconds: Int?
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
        case firstByteWaitMilliseconds
        case payloadReadMilliseconds
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
        firstByteWaitMilliseconds: Int? = nil,
        payloadReadMilliseconds: Int? = nil,
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
        let safeNetworkReadMilliseconds = Self.clampOptionalMilliseconds(networkReadMilliseconds)
        self.networkReadMilliseconds = safeNetworkReadMilliseconds
        let safeFirstByteWaitMilliseconds = firstByteWaitMilliseconds.map {
            min(max($0, 0), safeNetworkReadMilliseconds ?? max($0, 0))
        }
        self.firstByteWaitMilliseconds = safeFirstByteWaitMilliseconds
        let derivedPayloadReadMilliseconds = payloadReadMilliseconds
            ?? safeNetworkReadMilliseconds.flatMap { networkRead in
                safeFirstByteWaitMilliseconds.map { firstByteWait in
                    max(networkRead - firstByteWait, 0)
                }
            }
        self.payloadReadMilliseconds = Self.clampOptionalMilliseconds(derivedPayloadReadMilliseconds)
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
            firstByteWaitMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .firstByteWaitMilliseconds
            ),
            payloadReadMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .payloadReadMilliseconds
            ),
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

public enum BenchmarkStreamShapeDominantPhase: String, Codable, Equatable, Sendable, CaseIterable {
    case unknown
    case requestLoop = "request-loop"
    case networkRead = "network-read"
    case clientProcessing = "client-processing"
}

public enum BenchmarkStreamShapeNetworkReadSubphase: String, Codable, Equatable, Sendable, CaseIterable {
    case unknown
    case firstByteWait = "first-byte-wait"
    case payloadRead = "payload-read"
}

public struct BenchmarkStreamShapePhaseBudgetSummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let slowUpdateSampleCount: Int
    public let requestLoopLatency: BenchmarkLatencySummary?
    public let firstByteWaitLatency: BenchmarkLatencySummary?
    public let payloadReadLatency: BenchmarkLatencySummary?
    public let networkReadSharePermille: Int?
    public let firstByteWaitSharePermille: Int?
    public let payloadReadSharePermille: Int?
    public let clientProcessingSharePermille: Int?
    public let requestLoopSharePermille: Int?
    public let dominantPhase: BenchmarkStreamShapeDominantPhase
    public let networkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase?
    public let slowNetworkReadSharePermille: Int?
    public let slowFirstByteWaitSharePermille: Int?
    public let slowPayloadReadSharePermille: Int?
    public let slowClientProcessingSharePermille: Int?
    public let slowRequestLoopSharePermille: Int?
    public let slowDominantPhase: BenchmarkStreamShapeDominantPhase
    public let slowNetworkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase?

    public init(
        samples: [BenchmarkStreamShapeSample],
        slowUpdateThresholdMilliseconds: Int = BenchmarkStreamShapeTailSummary.defaultSlowUpdateThresholdMilliseconds
    ) {
        let phaseSamples = samples.compactMap(PhaseSample.init(sample:))
        let slowPhaseSamples = phaseSamples.filter {
            $0.durationMilliseconds >= max(slowUpdateThresholdMilliseconds, 0)
        }
        let phaseTotals = PhaseTotals(samples: phaseSamples)
        let slowPhaseTotals = PhaseTotals(samples: slowPhaseSamples)

        self.sampleCount = phaseSamples.count
        self.slowUpdateSampleCount = slowPhaseSamples.count
        self.requestLoopLatency = BenchmarkLatencySummary(phaseSamples.map(\.requestLoopMilliseconds))
        self.firstByteWaitLatency = BenchmarkLatencySummary(phaseSamples.compactMap(\.firstByteWaitMilliseconds))
        self.payloadReadLatency = BenchmarkLatencySummary(phaseSamples.compactMap(\.payloadReadMilliseconds))
        self.networkReadSharePermille = Self.permille(
            phaseTotals.networkReadMilliseconds,
            of: phaseTotals.totalMilliseconds
        )
        self.firstByteWaitSharePermille = Self.networkReadSubphasePermille(
            phaseTotals.firstByteWaitMilliseconds,
            of: phaseTotals
        )
        self.payloadReadSharePermille = Self.networkReadSubphasePermille(
            phaseTotals.payloadReadMilliseconds,
            of: phaseTotals
        )
        self.clientProcessingSharePermille = Self.permille(
            phaseTotals.clientProcessingMilliseconds,
            of: phaseTotals.totalMilliseconds
        )
        self.requestLoopSharePermille = Self.permille(
            phaseTotals.requestLoopMilliseconds,
            of: phaseTotals.totalMilliseconds
        )
        self.dominantPhase = Self.dominantPhase(for: phaseTotals)
        self.networkReadDominantSubphase = Self.networkReadDominantSubphase(for: phaseTotals)
        self.slowNetworkReadSharePermille = Self.permille(
            slowPhaseTotals.networkReadMilliseconds,
            of: slowPhaseTotals.totalMilliseconds
        )
        self.slowFirstByteWaitSharePermille = Self.networkReadSubphasePermille(
            slowPhaseTotals.firstByteWaitMilliseconds,
            of: slowPhaseTotals
        )
        self.slowPayloadReadSharePermille = Self.networkReadSubphasePermille(
            slowPhaseTotals.payloadReadMilliseconds,
            of: slowPhaseTotals
        )
        self.slowClientProcessingSharePermille = Self.permille(
            slowPhaseTotals.clientProcessingMilliseconds,
            of: slowPhaseTotals.totalMilliseconds
        )
        self.slowRequestLoopSharePermille = Self.permille(
            slowPhaseTotals.requestLoopMilliseconds,
            of: slowPhaseTotals.totalMilliseconds
        )
        self.slowDominantPhase = Self.dominantPhase(for: slowPhaseTotals)
        self.slowNetworkReadDominantSubphase = Self.networkReadDominantSubphase(for: slowPhaseTotals)
    }

    public init(
        sampleCount: Int,
        slowUpdateSampleCount: Int,
        requestLoopLatency: BenchmarkLatencySummary? = nil,
        firstByteWaitLatency: BenchmarkLatencySummary? = nil,
        payloadReadLatency: BenchmarkLatencySummary? = nil,
        networkReadSharePermille: Int? = nil,
        firstByteWaitSharePermille: Int? = nil,
        payloadReadSharePermille: Int? = nil,
        clientProcessingSharePermille: Int? = nil,
        requestLoopSharePermille: Int? = nil,
        dominantPhase: BenchmarkStreamShapeDominantPhase = .unknown,
        networkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase? = nil,
        slowNetworkReadSharePermille: Int? = nil,
        slowFirstByteWaitSharePermille: Int? = nil,
        slowPayloadReadSharePermille: Int? = nil,
        slowClientProcessingSharePermille: Int? = nil,
        slowRequestLoopSharePermille: Int? = nil,
        slowDominantPhase: BenchmarkStreamShapeDominantPhase = .unknown,
        slowNetworkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase? = nil
    ) {
        self.sampleCount = max(sampleCount, 0)
        self.slowUpdateSampleCount = max(slowUpdateSampleCount, 0)
        self.requestLoopLatency = requestLoopLatency
        self.firstByteWaitLatency = firstByteWaitLatency
        self.payloadReadLatency = payloadReadLatency
        self.networkReadSharePermille = Self.clampOptionalPermille(networkReadSharePermille)
        self.firstByteWaitSharePermille = Self.clampOptionalPermille(firstByteWaitSharePermille)
        self.payloadReadSharePermille = Self.clampOptionalPermille(payloadReadSharePermille)
        self.clientProcessingSharePermille = Self.clampOptionalPermille(clientProcessingSharePermille)
        self.requestLoopSharePermille = Self.clampOptionalPermille(requestLoopSharePermille)
        self.dominantPhase = dominantPhase
        self.networkReadDominantSubphase = networkReadDominantSubphase
        self.slowNetworkReadSharePermille = Self.clampOptionalPermille(slowNetworkReadSharePermille)
        self.slowFirstByteWaitSharePermille = Self.clampOptionalPermille(slowFirstByteWaitSharePermille)
        self.slowPayloadReadSharePermille = Self.clampOptionalPermille(slowPayloadReadSharePermille)
        self.slowClientProcessingSharePermille = Self.clampOptionalPermille(slowClientProcessingSharePermille)
        self.slowRequestLoopSharePermille = Self.clampOptionalPermille(slowRequestLoopSharePermille)
        self.slowDominantPhase = slowDominantPhase
        self.slowNetworkReadDominantSubphase = slowNetworkReadDominantSubphase
    }

    public static var empty: BenchmarkStreamShapePhaseBudgetSummary {
        BenchmarkStreamShapePhaseBudgetSummary(sampleCount: 0, slowUpdateSampleCount: 0)
    }

    private static func dominantPhase(
        for totals: PhaseTotals
    ) -> BenchmarkStreamShapeDominantPhase {
        guard totals.totalMilliseconds > 0 else {
            return .unknown
        }
        if totals.requestLoopMilliseconds >= totals.networkReadMilliseconds,
           totals.requestLoopMilliseconds >= totals.clientProcessingMilliseconds {
            return .requestLoop
        }
        if totals.networkReadMilliseconds >= totals.clientProcessingMilliseconds {
            return .networkRead
        }
        return .clientProcessing
    }

    private static func networkReadDominantSubphase(
        for totals: PhaseTotals
    ) -> BenchmarkStreamShapeNetworkReadSubphase? {
        guard totals.networkReadSplitSampleCount > 0 else {
            return nil
        }
        guard totals.firstByteWaitMilliseconds + totals.payloadReadMilliseconds > 0 else {
            return .unknown
        }
        if totals.firstByteWaitMilliseconds >= totals.payloadReadMilliseconds {
            return .firstByteWait
        }
        return .payloadRead
    }

    private static func networkReadSubphasePermille(_ value: Int, of totals: PhaseTotals) -> Int? {
        guard totals.networkReadSplitSampleCount > 0 else {
            return nil
        }
        return permille(value, of: totals.firstByteWaitMilliseconds + totals.payloadReadMilliseconds)
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

    private struct PhaseSample {
        let durationMilliseconds: Int
        let requestLoopMilliseconds: Int
        let networkReadMilliseconds: Int
        let firstByteWaitMilliseconds: Int?
        let payloadReadMilliseconds: Int?
        let clientProcessingMilliseconds: Int

        init?(sample: BenchmarkStreamShapeSample) {
            let networkReadMilliseconds = sample.networkReadMilliseconds ?? 0
            let firstByteWaitMilliseconds = sample.firstByteWaitMilliseconds
            let payloadReadMilliseconds = sample.payloadReadMilliseconds
            let clientProcessingMilliseconds = sample.clientProcessingMilliseconds ?? 0
            let requestLoopMilliseconds = sample.receiveTotalMilliseconds
                .map { max(sample.durationMilliseconds - $0, 0) } ?? 0
            guard networkReadMilliseconds + clientProcessingMilliseconds + requestLoopMilliseconds > 0 else {
                return nil
            }
            self.durationMilliseconds = sample.durationMilliseconds
            self.requestLoopMilliseconds = requestLoopMilliseconds
            self.networkReadMilliseconds = networkReadMilliseconds
            self.firstByteWaitMilliseconds = firstByteWaitMilliseconds
            self.payloadReadMilliseconds = payloadReadMilliseconds
            self.clientProcessingMilliseconds = clientProcessingMilliseconds
        }
    }

    private struct PhaseTotals {
        let requestLoopMilliseconds: Int
        let networkReadMilliseconds: Int
        let firstByteWaitMilliseconds: Int
        let payloadReadMilliseconds: Int
        let networkReadSplitSampleCount: Int
        let clientProcessingMilliseconds: Int
        let totalMilliseconds: Int

        init(samples: [PhaseSample]) {
            self.requestLoopMilliseconds = samples.reduce(0) { $0 + $1.requestLoopMilliseconds }
            self.networkReadMilliseconds = samples.reduce(0) { $0 + $1.networkReadMilliseconds }
            self.firstByteWaitMilliseconds = samples.reduce(0) {
                $0 + ($1.firstByteWaitMilliseconds ?? 0)
            }
            self.payloadReadMilliseconds = samples.reduce(0) {
                $0 + ($1.payloadReadMilliseconds ?? 0)
            }
            self.networkReadSplitSampleCount = samples.filter {
                $0.firstByteWaitMilliseconds != nil || $0.payloadReadMilliseconds != nil
            }.count
            self.clientProcessingMilliseconds = samples.reduce(0) { $0 + $1.clientProcessingMilliseconds }
            self.totalMilliseconds = requestLoopMilliseconds
                + networkReadMilliseconds
                + clientProcessingMilliseconds
        }
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
    public let firstByteWaitLatency: BenchmarkLatencySummary?
    public let payloadReadLatency: BenchmarkLatencySummary?
    public let clientProcessingLatency: BenchmarkLatencySummary?
    public let zrleInflateLatency: BenchmarkLatencySummary?
    public let zrleTileApplyLatency: BenchmarkLatencySummary?
    public let tailLatency: BenchmarkStreamShapeTailSummary
    public let phaseBudget: BenchmarkStreamShapePhaseBudgetSummary
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
        case firstByteWaitLatency
        case payloadReadLatency
        case clientProcessingLatency
        case zrleInflateLatency
        case zrleTileApplyLatency
        case tailLatency
        case phaseBudget
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
        self.firstByteWaitLatency = BenchmarkLatencySummary(samples.compactMap(\.firstByteWaitMilliseconds))
        self.payloadReadLatency = BenchmarkLatencySummary(samples.compactMap(\.payloadReadMilliseconds))
        self.clientProcessingLatency = BenchmarkLatencySummary(samples.compactMap(\.clientProcessingMilliseconds))
        self.zrleInflateLatency = BenchmarkLatencySummary(samples.compactMap(\.zrleInflateMilliseconds))
        self.zrleTileApplyLatency = BenchmarkLatencySummary(samples.compactMap(\.zrleTileApplyMilliseconds))
        self.tailLatency = BenchmarkStreamShapeTailSummary(samples: samples)
        self.phaseBudget = BenchmarkStreamShapePhaseBudgetSummary(
            samples: samples,
            slowUpdateThresholdMilliseconds: tailLatency.slowUpdateThresholdMilliseconds
        )
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
        self.firstByteWaitLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .firstByteWaitLatency
        )
        self.payloadReadLatency = try container.decodeIfPresent(
            BenchmarkLatencySummary.self,
            forKey: .payloadReadLatency
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
        self.phaseBudget = try container.decodeIfPresent(
            BenchmarkStreamShapePhaseBudgetSummary.self,
            forKey: .phaseBudget
        ) ?? .empty
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
        try container.encodeIfPresent(firstByteWaitLatency, forKey: .firstByteWaitLatency)
        try container.encodeIfPresent(payloadReadLatency, forKey: .payloadReadLatency)
        try container.encodeIfPresent(clientProcessingLatency, forKey: .clientProcessingLatency)
        try container.encodeIfPresent(zrleInflateLatency, forKey: .zrleInflateLatency)
        try container.encodeIfPresent(zrleTileApplyLatency, forKey: .zrleTileApplyLatency)
        try container.encode(tailLatency, forKey: .tailLatency)
        try container.encode(phaseBudget, forKey: .phaseBudget)
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
    public let pacingWindow: BenchmarkStreamShapePacingWindow
    public let requestRegion: BenchmarkStreamShapeRequestRegion
    public let requestRegionAreaPermille: Int?
    public let iterationOrdinal: Int?
    public let orderOrdinal: Int?
    public let firstFrameMilliseconds: Int?
    public let summary: BenchmarkStreamShapeSummary

    private enum CodingKeys: String, CodingKey {
        case label
        case transportMode
        case pacingWindow
        case requestRegion
        case requestRegionAreaPermille
        case iterationOrdinal
        case orderOrdinal
        case firstFrameMilliseconds
        case summary
    }

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode = .requestResponse,
        pacingWindow: BenchmarkStreamShapePacingWindow = .single,
        requestRegion: BenchmarkStreamShapeRequestRegion = .full,
        requestRegionAreaPermille: Int? = nil,
        iterationOrdinal: Int? = nil,
        orderOrdinal: Int? = nil,
        firstFrameMilliseconds: Int?,
        summary: BenchmarkStreamShapeSummary
    ) {
        self.label = label
        self.transportMode = transportMode
        self.pacingWindow = pacingWindow
        self.requestRegion = requestRegion
        self.requestRegionAreaPermille = Self.clampOptionalPermille(requestRegionAreaPermille)
        self.iterationOrdinal = iterationOrdinal.map { max($0, 1) }
        self.orderOrdinal = orderOrdinal.map { max($0, 1) }
        self.firstFrameMilliseconds = firstFrameMilliseconds
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decode(String.self, forKey: .label),
            transportMode: try container.decodeIfPresent(
                BenchmarkStreamShapeTransportMode.self,
                forKey: .transportMode
            ) ?? .requestResponse,
            pacingWindow: try container.decodeIfPresent(
                BenchmarkStreamShapePacingWindow.self,
                forKey: .pacingWindow
            ) ?? .single,
            requestRegion: try container.decodeIfPresent(
                BenchmarkStreamShapeRequestRegion.self,
                forKey: .requestRegion
            ) ?? .full,
            requestRegionAreaPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .requestRegionAreaPermille
            ),
            iterationOrdinal: try container.decodeIfPresent(Int.self, forKey: .iterationOrdinal),
            orderOrdinal: try container.decodeIfPresent(Int.self, forKey: .orderOrdinal),
            firstFrameMilliseconds: try container.decodeIfPresent(Int.self, forKey: .firstFrameMilliseconds),
            summary: try container.decode(BenchmarkStreamShapeSummary.self, forKey: .summary)
        )
    }

    private static func clampOptionalPermille(_ value: Int?) -> Int? {
        value.map { min(max($0, 0), 1_000) }
    }
}

public struct BenchmarkStreamShapeProfileAggregateReport: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let pacingWindow: BenchmarkStreamShapePacingWindow
    public let requestRegion: BenchmarkStreamShapeRequestRegion
    public let averageRequestRegionAreaPermille: Int?
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
    public let averageNetworkReadSharePermille: Int?
    public let averageFirstByteWaitSharePermille: Int?
    public let averagePayloadReadSharePermille: Int?
    public let averageClientProcessingSharePermille: Int?
    public let averageRequestLoopSharePermille: Int?
    public let dominantPhase: BenchmarkStreamShapeDominantPhase
    public let networkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase
    public let slowDominantPhase: BenchmarkStreamShapeDominantPhase
    public let slowNetworkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase
    public let maxFirstByteWaitP95Milliseconds: Int?
    public let maxPayloadReadP95Milliseconds: Int?

    private enum CodingKeys: String, CodingKey {
        case label
        case transportMode
        case pacingWindow
        case requestRegion
        case averageRequestRegionAreaPermille
        case runCount
        case usableRunCount
        case failedRunCount
        case averageUpdateMilliseconds
        case maxP95UpdateMilliseconds
        case averageContentFramesPerSecond
        case averageRendererFullUploadPermille
        case maxClientProcessingP95Milliseconds
        case maxZrleTileApplyP95Milliseconds
        case slowUpdateSamples
        case verySlowUpdateSamples
        case receivedSamples
        case contentUpdateSamples
        case averageReceivedSamplePermille
        case averageContentSamplePermille
        case averageContentResponsePermille
        case averageUnansweredSamplePermille
        case averageNetworkReadSharePermille
        case averageFirstByteWaitSharePermille
        case averagePayloadReadSharePermille
        case averageClientProcessingSharePermille
        case averageRequestLoopSharePermille
        case dominantPhase
        case networkReadDominantSubphase
        case slowDominantPhase
        case slowNetworkReadDominantSubphase
        case maxFirstByteWaitP95Milliseconds
        case maxPayloadReadP95Milliseconds
    }

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode,
        pacingWindow: BenchmarkStreamShapePacingWindow = .single,
        requestRegion: BenchmarkStreamShapeRequestRegion = .full,
        averageRequestRegionAreaPermille: Int? = nil,
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
        averageUnansweredSamplePermille: Int? = nil,
        averageNetworkReadSharePermille: Int? = nil,
        averageFirstByteWaitSharePermille: Int? = nil,
        averagePayloadReadSharePermille: Int? = nil,
        averageClientProcessingSharePermille: Int? = nil,
        averageRequestLoopSharePermille: Int? = nil,
        dominantPhase: BenchmarkStreamShapeDominantPhase = .unknown,
        networkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase = .unknown,
        slowDominantPhase: BenchmarkStreamShapeDominantPhase = .unknown,
        slowNetworkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase = .unknown,
        maxFirstByteWaitP95Milliseconds: Int? = nil,
        maxPayloadReadP95Milliseconds: Int? = nil
    ) {
        self.label = label
        self.transportMode = transportMode
        self.pacingWindow = pacingWindow
        self.requestRegion = requestRegion
        self.averageRequestRegionAreaPermille = Self.clampOptionalPermille(averageRequestRegionAreaPermille)
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
        self.averageNetworkReadSharePermille = Self.clampOptionalPermille(averageNetworkReadSharePermille)
        self.averageFirstByteWaitSharePermille = Self.clampOptionalPermille(averageFirstByteWaitSharePermille)
        self.averagePayloadReadSharePermille = Self.clampOptionalPermille(averagePayloadReadSharePermille)
        self.averageClientProcessingSharePermille = Self.clampOptionalPermille(averageClientProcessingSharePermille)
        self.averageRequestLoopSharePermille = Self.clampOptionalPermille(averageRequestLoopSharePermille)
        self.dominantPhase = dominantPhase
        self.networkReadDominantSubphase = networkReadDominantSubphase
        self.slowDominantPhase = slowDominantPhase
        self.slowNetworkReadDominantSubphase = slowNetworkReadDominantSubphase
        self.maxFirstByteWaitP95Milliseconds = maxFirstByteWaitP95Milliseconds.map { max($0, 0) }
        self.maxPayloadReadP95Milliseconds = maxPayloadReadP95Milliseconds.map { max($0, 0) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decode(String.self, forKey: .label),
            transportMode: try container.decode(BenchmarkStreamShapeTransportMode.self, forKey: .transportMode),
            pacingWindow: try container.decodeIfPresent(
                BenchmarkStreamShapePacingWindow.self,
                forKey: .pacingWindow
            ) ?? .single,
            requestRegion: try container.decodeIfPresent(
                BenchmarkStreamShapeRequestRegion.self,
                forKey: .requestRegion
            ) ?? .full,
            averageRequestRegionAreaPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageRequestRegionAreaPermille
            ),
            runCount: try container.decode(Int.self, forKey: .runCount),
            usableRunCount: try container.decode(Int.self, forKey: .usableRunCount),
            failedRunCount: try container.decode(Int.self, forKey: .failedRunCount),
            averageUpdateMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .averageUpdateMilliseconds
            ),
            maxP95UpdateMilliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .maxP95UpdateMilliseconds
            ),
            averageContentFramesPerSecond: try container.decodeIfPresent(
                Double.self,
                forKey: .averageContentFramesPerSecond
            ),
            averageRendererFullUploadPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageRendererFullUploadPermille
            ),
            maxClientProcessingP95Milliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .maxClientProcessingP95Milliseconds
            ),
            maxZrleTileApplyP95Milliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .maxZrleTileApplyP95Milliseconds
            ),
            slowUpdateSamples: try container.decode(Int.self, forKey: .slowUpdateSamples),
            verySlowUpdateSamples: try container.decode(Int.self, forKey: .verySlowUpdateSamples),
            receivedSamples: try container.decode(Int.self, forKey: .receivedSamples),
            contentUpdateSamples: try container.decode(Int.self, forKey: .contentUpdateSamples),
            averageReceivedSamplePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageReceivedSamplePermille
            ),
            averageContentSamplePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageContentSamplePermille
            ),
            averageContentResponsePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageContentResponsePermille
            ),
            averageUnansweredSamplePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageUnansweredSamplePermille
            ),
            averageNetworkReadSharePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageNetworkReadSharePermille
            ),
            averageFirstByteWaitSharePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageFirstByteWaitSharePermille
            ),
            averagePayloadReadSharePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averagePayloadReadSharePermille
            ),
            averageClientProcessingSharePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageClientProcessingSharePermille
            ),
            averageRequestLoopSharePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageRequestLoopSharePermille
            ),
            dominantPhase: try container.decodeIfPresent(
                BenchmarkStreamShapeDominantPhase.self,
                forKey: .dominantPhase
            ) ?? .unknown,
            networkReadDominantSubphase: try container.decodeIfPresent(
                BenchmarkStreamShapeNetworkReadSubphase.self,
                forKey: .networkReadDominantSubphase
            ) ?? .unknown,
            slowDominantPhase: try container.decodeIfPresent(
                BenchmarkStreamShapeDominantPhase.self,
                forKey: .slowDominantPhase
            ) ?? .unknown,
            slowNetworkReadDominantSubphase: try container.decodeIfPresent(
                BenchmarkStreamShapeNetworkReadSubphase.self,
                forKey: .slowNetworkReadDominantSubphase
            ) ?? .unknown,
            maxFirstByteWaitP95Milliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .maxFirstByteWaitP95Milliseconds
            ),
            maxPayloadReadP95Milliseconds: try container.decodeIfPresent(
                Int.self,
                forKey: .maxPayloadReadP95Milliseconds
            )
        )
    }

    public static func aggregates(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [BenchmarkStreamShapeProfileAggregateReport] {
        let orderedKeys = orderedAggregateKeys(from: reports)
        let grouped = Dictionary(grouping: reports) {
            AggregateKey(
                label: $0.label,
                transportMode: $0.transportMode,
                pacingWindow: $0.pacingWindow,
                requestRegion: $0.requestRegion
            )
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
        let firstByteWaitP95s = usableReports.compactMap { $0.summary.firstByteWaitLatency?.p95Milliseconds }
        let payloadReadP95s = usableReports.compactMap { $0.summary.payloadReadLatency?.p95Milliseconds }
        let receivedSamplePermille = usableReports.compactMap(\.summary.receivedSamplePermille)
        let contentSamplePermille = usableReports.compactMap(\.summary.contentSamplePermille)
        let contentResponsePermille = usableReports.compactMap(\.summary.contentResponsePermille)
        let unansweredSamplePermille = usableReports.compactMap(\.summary.unansweredSamplePermille)
        let requestRegionAreaPermille = reports.compactMap(\.requestRegionAreaPermille)
        let phaseBudgets = usableReports
            .map(\.summary.phaseBudget)
            .filter { $0.sampleCount > 0 }
        let slowPhaseBudgets = phaseBudgets.filter { $0.slowUpdateSampleCount > 0 }
        // Keep profile aggregates as run-level means so rotated benchmark
        // iterations have equal weight even when duration-capped attempts vary.
        return BenchmarkStreamShapeProfileAggregateReport(
            label: key.label,
            transportMode: key.transportMode,
            pacingWindow: key.pacingWindow,
            requestRegion: key.requestRegion,
            averageRequestRegionAreaPermille: roundedAverage(requestRegionAreaPermille),
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
            averageUnansweredSamplePermille: roundedAverage(unansweredSamplePermille),
            averageNetworkReadSharePermille: roundedAverage(
                phaseBudgets.compactMap(\.networkReadSharePermille)
            ),
            averageFirstByteWaitSharePermille: roundedAverage(
                phaseBudgets.compactMap(\.firstByteWaitSharePermille)
            ),
            averagePayloadReadSharePermille: roundedAverage(
                phaseBudgets.compactMap(\.payloadReadSharePermille)
            ),
            averageClientProcessingSharePermille: roundedAverage(
                phaseBudgets.compactMap(\.clientProcessingSharePermille)
            ),
            averageRequestLoopSharePermille: roundedAverage(
                phaseBudgets.compactMap(\.requestLoopSharePermille)
            ),
            dominantPhase: dominantPhase(from: phaseBudgets.map(\.dominantPhase)),
            networkReadDominantSubphase: dominantNetworkReadSubphase(
                from: phaseBudgets.compactMap(\.networkReadDominantSubphase)
            ),
            slowDominantPhase: dominantPhase(from: slowPhaseBudgets.map(\.slowDominantPhase)),
            slowNetworkReadDominantSubphase: dominantNetworkReadSubphase(
                from: slowPhaseBudgets.compactMap(\.slowNetworkReadDominantSubphase)
            ),
            maxFirstByteWaitP95Milliseconds: firstByteWaitP95s.max(),
            maxPayloadReadP95Milliseconds: payloadReadP95s.max()
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
            let key = AggregateKey(
                label: report.label,
                transportMode: report.transportMode,
                pacingWindow: report.pacingWindow,
                requestRegion: report.requestRegion
            )
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

    private static func dominantPhase(
        from phases: [BenchmarkStreamShapeDominantPhase]
    ) -> BenchmarkStreamShapeDominantPhase {
        let phases = phases.filter { $0 != .unknown }
        guard !phases.isEmpty else {
            return .unknown
        }
        let counts = Dictionary(grouping: phases, by: { $0 }).mapValues(\.count)
        let priority: [BenchmarkStreamShapeDominantPhase] = [
            .requestLoop,
            .networkRead,
            .clientProcessing
        ]
        return priority.max { lhs, rhs in
            (counts[lhs] ?? 0) < (counts[rhs] ?? 0)
        } ?? .unknown
    }

    private static func dominantNetworkReadSubphase(
        from subphases: [BenchmarkStreamShapeNetworkReadSubphase]
    ) -> BenchmarkStreamShapeNetworkReadSubphase {
        let subphases = subphases.filter { $0 != .unknown }
        guard !subphases.isEmpty else {
            return .unknown
        }
        let counts = Dictionary(grouping: subphases, by: { $0 }).mapValues(\.count)
        let priority: [BenchmarkStreamShapeNetworkReadSubphase] = [
            .firstByteWait,
            .payloadRead
        ]
        return priority.max { lhs, rhs in
            (counts[lhs] ?? 0) < (counts[rhs] ?? 0)
        } ?? .unknown
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
        let pacingWindow: BenchmarkStreamShapePacingWindow
        let requestRegion: BenchmarkStreamShapeRequestRegion
    }
}

public struct BenchmarkStreamShapeProfileGateReport: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let pacingWindow: BenchmarkStreamShapePacingWindow
    public let requestRegion: BenchmarkStreamShapeRequestRegion
    public let averageRequestRegionAreaPermille: Int?
    public let targetName: String
    public let verdict: BenchmarkStreamShapePracticalVerdict
    public let runCount: Int
    public let passRunCount: Int
    public let warningRunCount: Int
    public let failRunCount: Int
    public let disabledRunCount: Int
    public let issueCodes: [BenchmarkStreamShapePracticalIssueCode]
    public let primaryIssueCode: BenchmarkStreamShapePracticalIssueCode?
    public let primaryConstraint: String
    public let recommendedNextProbe: String
    public let primaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let recommendedNextProbeCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let failureLabelCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let averageReceivedSamplePermille: Int?
    public let averageContentSamplePermille: Int?
    public let averageContentResponsePermille: Int?
    public let averageUnansweredSamplePermille: Int?

    private enum CodingKeys: String, CodingKey {
        case label
        case transportMode
        case pacingWindow
        case requestRegion
        case averageRequestRegionAreaPermille
        case targetName
        case verdict
        case runCount
        case passRunCount
        case warningRunCount
        case failRunCount
        case disabledRunCount
        case issueCodes
        case primaryIssueCode
        case primaryConstraint
        case recommendedNextProbe
        case primaryConstraintCounts
        case recommendedNextProbeCounts
        case failureLabelCounts
        case averageReceivedSamplePermille
        case averageContentSamplePermille
        case averageContentResponsePermille
        case averageUnansweredSamplePermille
    }

    public init(
        label: String,
        transportMode: BenchmarkStreamShapeTransportMode,
        pacingWindow: BenchmarkStreamShapePacingWindow = .single,
        requestRegion: BenchmarkStreamShapeRequestRegion = .full,
        averageRequestRegionAreaPermille: Int? = nil,
        targetName: String,
        verdict: BenchmarkStreamShapePracticalVerdict,
        runCount: Int,
        passRunCount: Int,
        warningRunCount: Int,
        failRunCount: Int,
        disabledRunCount: Int,
        issueCodes: [BenchmarkStreamShapePracticalIssueCode],
        primaryIssueCode: BenchmarkStreamShapePracticalIssueCode? = nil,
        primaryConstraint: String? = nil,
        recommendedNextProbe: String? = nil,
        primaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        recommendedNextProbeCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        failureLabelCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        averageReceivedSamplePermille: Int? = nil,
        averageContentSamplePermille: Int? = nil,
        averageContentResponsePermille: Int? = nil,
        averageUnansweredSamplePermille: Int? = nil
    ) {
        self.label = label
        self.transportMode = transportMode
        self.pacingWindow = pacingWindow
        self.requestRegion = requestRegion
        self.averageRequestRegionAreaPermille = Self.clampOptionalPermille(averageRequestRegionAreaPermille)
        self.targetName = targetName
        self.verdict = verdict
        self.runCount = max(runCount, 0)
        self.passRunCount = max(passRunCount, 0)
        self.warningRunCount = max(warningRunCount, 0)
        self.failRunCount = max(failRunCount, 0)
        self.disabledRunCount = max(disabledRunCount, 0)
        let safeIssueCodes = Self.orderedIssueCodes(issueCodes)
        let derivedPrimaryIssue = BenchmarkStreamShapeTriage.safePrimaryIssueCode(
            primaryIssueCode,
            issueCodes: safeIssueCodes
        ) ?? BenchmarkStreamShapeTriage.primaryIssue(for: safeIssueCodes)
        let derivedPrimaryConstraint = BenchmarkStreamShapeTriage.primaryConstraint(for: derivedPrimaryIssue)
        let derivedRecommendedNextProbe = BenchmarkStreamShapeTriage.recommendedNextProbe(for: derivedPrimaryIssue)
        self.issueCodes = safeIssueCodes
        self.primaryIssueCode = derivedPrimaryIssue
        self.primaryConstraint = BenchmarkStreamShapeTriage.safePrimaryConstraint(
            primaryConstraint,
            matching: derivedPrimaryConstraint
        ) ?? derivedPrimaryConstraint.rawValue
        self.recommendedNextProbe = BenchmarkStreamShapeTriage.safeRecommendedNextProbe(
            recommendedNextProbe,
            matching: derivedRecommendedNextProbe
        ) ?? derivedRecommendedNextProbe.rawValue
        self.primaryConstraintCounts = primaryConstraintCounts.isEmpty
            ? BenchmarkStreamShapeTriage.primaryConstraintCounts(for: [self.primaryConstraint])
            : BenchmarkStreamShapeTriage.mergedPrimaryConstraintCounts(from: primaryConstraintCounts)
        self.recommendedNextProbeCounts = recommendedNextProbeCounts.isEmpty
            ? BenchmarkStreamShapeTriage.recommendedNextProbeCounts(for: [self.recommendedNextProbe])
            : BenchmarkStreamShapeTriage.mergedRecommendedNextProbeCounts(from: recommendedNextProbeCounts)
        self.failureLabelCounts = BenchmarkStreamShapeTriage.mergedFailureLabelCounts(from: failureLabelCounts)
        self.averageReceivedSamplePermille = Self.clampOptionalPermille(averageReceivedSamplePermille)
        self.averageContentSamplePermille = Self.clampOptionalPermille(averageContentSamplePermille)
        self.averageContentResponsePermille = Self.clampOptionalPermille(averageContentResponsePermille)
        self.averageUnansweredSamplePermille = Self.clampOptionalPermille(averageUnansweredSamplePermille)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPrimaryIssueCode = try container.decodeIfPresent(String.self, forKey: .primaryIssueCode)
        self.init(
            label: try container.decode(String.self, forKey: .label),
            transportMode: try container.decode(BenchmarkStreamShapeTransportMode.self, forKey: .transportMode),
            pacingWindow: try container.decodeIfPresent(
                BenchmarkStreamShapePacingWindow.self,
                forKey: .pacingWindow
            ) ?? .single,
            requestRegion: try container.decodeIfPresent(
                BenchmarkStreamShapeRequestRegion.self,
                forKey: .requestRegion
            ) ?? .full,
            averageRequestRegionAreaPermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageRequestRegionAreaPermille
            ),
            targetName: try container.decode(String.self, forKey: .targetName),
            verdict: try container.decode(BenchmarkStreamShapePracticalVerdict.self, forKey: .verdict),
            runCount: try container.decode(Int.self, forKey: .runCount),
            passRunCount: try container.decode(Int.self, forKey: .passRunCount),
            warningRunCount: try container.decode(Int.self, forKey: .warningRunCount),
            failRunCount: try container.decode(Int.self, forKey: .failRunCount),
            disabledRunCount: try container.decode(Int.self, forKey: .disabledRunCount),
            issueCodes: try container.decode([BenchmarkStreamShapePracticalIssueCode].self, forKey: .issueCodes),
            primaryIssueCode: rawPrimaryIssueCode.flatMap(BenchmarkStreamShapePracticalIssueCode.init(rawValue:)),
            primaryConstraint: try container.decodeIfPresent(String.self, forKey: .primaryConstraint),
            recommendedNextProbe: try container.decodeIfPresent(String.self, forKey: .recommendedNextProbe),
            primaryConstraintCounts: try container.decodeIfPresent(
                [BenchmarkStreamShapeTriageLabelCount].self,
                forKey: .primaryConstraintCounts
            ) ?? [],
            recommendedNextProbeCounts: try container.decodeIfPresent(
                [BenchmarkStreamShapeTriageLabelCount].self,
                forKey: .recommendedNextProbeCounts
            ) ?? [],
            failureLabelCounts: try container.decodeIfPresent(
                [BenchmarkStreamShapeTriageLabelCount].self,
                forKey: .failureLabelCounts
            ) ?? [],
            averageReceivedSamplePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageReceivedSamplePermille
            ),
            averageContentSamplePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageContentSamplePermille
            ),
            averageContentResponsePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageContentResponsePermille
            ),
            averageUnansweredSamplePermille: try container.decodeIfPresent(
                Int.self,
                forKey: .averageUnansweredSamplePermille
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(transportMode, forKey: .transportMode)
        try container.encode(pacingWindow, forKey: .pacingWindow)
        try container.encode(requestRegion, forKey: .requestRegion)
        try container.encodeIfPresent(averageRequestRegionAreaPermille, forKey: .averageRequestRegionAreaPermille)
        try container.encode(targetName, forKey: .targetName)
        try container.encode(verdict, forKey: .verdict)
        try container.encode(runCount, forKey: .runCount)
        try container.encode(passRunCount, forKey: .passRunCount)
        try container.encode(warningRunCount, forKey: .warningRunCount)
        try container.encode(failRunCount, forKey: .failRunCount)
        try container.encode(disabledRunCount, forKey: .disabledRunCount)
        try container.encode(issueCodes, forKey: .issueCodes)
        try container.encodeIfPresent(primaryIssueCode?.rawValue, forKey: .primaryIssueCode)
        try container.encode(primaryConstraint, forKey: .primaryConstraint)
        try container.encode(recommendedNextProbe, forKey: .recommendedNextProbe)
        try container.encode(primaryConstraintCounts, forKey: .primaryConstraintCounts)
        try container.encode(recommendedNextProbeCounts, forKey: .recommendedNextProbeCounts)
        try container.encode(failureLabelCounts, forKey: .failureLabelCounts)
        try container.encodeIfPresent(averageReceivedSamplePermille, forKey: .averageReceivedSamplePermille)
        try container.encodeIfPresent(averageContentSamplePermille, forKey: .averageContentSamplePermille)
        try container.encodeIfPresent(averageContentResponsePermille, forKey: .averageContentResponsePermille)
        try container.encodeIfPresent(averageUnansweredSamplePermille, forKey: .averageUnansweredSamplePermille)
    }

    public static func gates(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [BenchmarkStreamShapeProfileGateReport] {
        let orderedKeys = orderedGateKeys(from: reports)
        let grouped = Dictionary(grouping: reports) {
            GateKey(
                label: $0.label,
                transportMode: $0.transportMode,
                pacingWindow: $0.pacingWindow,
                requestRegion: $0.requestRegion,
                targetName: $0.summary.practicalAssessment.targetName
            )
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
        let targets = BenchmarkStreamShapePracticalTargetSelection(rawValue: key.targetName)?.targets
        let averageRequestRegionAreaPermille = roundedAverage(reports.compactMap(\.requestRegionAreaPermille))
        let gateIssueCodes = gateIssueCodes(
            firstFrameMilliseconds: reports.compactMap(\.firstFrameMilliseconds),
            averageRequestRegionAreaPermille: averageRequestRegionAreaPermille,
            targets: targets
        )
        let passRunCount = assessments.filter { $0.verdict == .pass }.count
        let warningRunCount = assessments.filter { $0.verdict == .warning }.count
        let failRunCount = assessments.filter { $0.verdict == .fail }.count
        let disabledRunCount = assessments.filter { $0.verdict == .disabled }.count
        let issueCodes = assessments.flatMap(\.issueCodes) + gateIssueCodes
        let primaryIssueCode = BenchmarkStreamShapeTriage.primaryIssue(
            for: assessments.compactMap(\.primaryIssueCode) + gateIssueCodes
        )
        let primaryConstraint = BenchmarkStreamShapeTriage.primaryConstraint(for: primaryIssueCode)
        let recommendedNextProbe = BenchmarkStreamShapeTriage.recommendedNextProbe(for: primaryIssueCode)
        return BenchmarkStreamShapeProfileGateReport(
            label: key.label,
            transportMode: key.transportMode,
            pacingWindow: key.pacingWindow,
            requestRegion: key.requestRegion,
            averageRequestRegionAreaPermille: averageRequestRegionAreaPermille,
            targetName: key.targetName,
            verdict: verdict(
                passRunCount: passRunCount,
                warningRunCount: warningRunCount,
                failRunCount: failRunCount,
                disabledRunCount: disabledRunCount,
                gateIssueCodes: gateIssueCodes
            ),
            runCount: reports.count,
            passRunCount: passRunCount,
            warningRunCount: warningRunCount,
            failRunCount: failRunCount,
            disabledRunCount: disabledRunCount,
            issueCodes: issueCodes,
            primaryIssueCode: primaryIssueCode,
            primaryConstraint: primaryConstraint.rawValue,
            recommendedNextProbe: recommendedNextProbe.rawValue,
            primaryConstraintCounts: BenchmarkStreamShapeTriage.primaryConstraintCounts(
                for: assessments.map(\.primaryConstraint)
                    + gateIssueCodes.map { BenchmarkStreamShapeTriage.primaryConstraint(for: $0).rawValue }
            ),
            recommendedNextProbeCounts: BenchmarkStreamShapeTriage.recommendedNextProbeCounts(
                for: assessments.map(\.recommendedNextProbe)
                    + gateIssueCodes.map { BenchmarkStreamShapeTriage.recommendedNextProbe(for: $0).rawValue }
            ),
            failureLabelCounts: BenchmarkStreamShapeTriage.failureLabelCounts(
                for: reports.compactMap(\.summary.failureLabel)
            ),
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
        disabledRunCount: Int,
        gateIssueCodes: [BenchmarkStreamShapePracticalIssueCode] = []
    ) -> BenchmarkStreamShapePracticalVerdict {
        let gateVerdict = gateVerdict(for: gateIssueCodes)
        if gateVerdict == .fail {
            return .fail
        }
        if failRunCount > 0 {
            return .fail
        }
        if gateVerdict == .warning {
            return .warning
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

    private static func gateVerdict(
        for issues: [BenchmarkStreamShapePracticalIssueCode]
    ) -> BenchmarkStreamShapePracticalVerdict {
        let failures: Set<BenchmarkStreamShapePracticalIssueCode> = [
            .firstFrameFailed,
            .requestRegionAreaFailed
        ]
        if issues.contains(where: failures.contains) {
            return .fail
        }
        return issues.isEmpty ? .pass : .warning
    }

    private static func gateIssueCodes(
        firstFrameMilliseconds: [Int],
        averageRequestRegionAreaPermille: Int?,
        targets: BenchmarkStreamShapePracticalTargets?
    ) -> [BenchmarkStreamShapePracticalIssueCode] {
        guard let targets else {
            return []
        }
        var issues: [BenchmarkStreamShapePracticalIssueCode] = []
        if let maxFirstFrameMilliseconds = firstFrameMilliseconds.max() {
            if let failFirstFrameMilliseconds = targets.failFirstFrameMilliseconds,
               maxFirstFrameMilliseconds > failFirstFrameMilliseconds {
                issues.append(.firstFrameFailed)
            } else if let passFirstFrameMilliseconds = targets.passFirstFrameMilliseconds,
                      maxFirstFrameMilliseconds > passFirstFrameMilliseconds {
                issues.append(.firstFrameWarning)
            }
        }
        if let averageRequestRegionAreaPermille {
            if let failRequestRegionAreaPermille = targets.failRequestRegionAreaPermille,
               averageRequestRegionAreaPermille > failRequestRegionAreaPermille {
                issues.append(.requestRegionAreaFailed)
            } else if let passRequestRegionAreaPermille = targets.passRequestRegionAreaPermille,
                      averageRequestRegionAreaPermille > passRequestRegionAreaPermille {
                issues.append(.requestRegionAreaWarning)
            }
        }
        return BenchmarkStreamShapeTriage.safeIssueCodes(issues)
    }

    private static func orderedGateKeys(
        from reports: [BenchmarkStreamShapeProfileReport]
    ) -> [GateKey] {
        var seen: Set<GateKey> = []
        var keys: [GateKey] = []
        for report in reports {
            let key = GateKey(
                label: report.label,
                transportMode: report.transportMode,
                pacingWindow: report.pacingWindow,
                requestRegion: report.requestRegion,
                targetName: report.summary.practicalAssessment.targetName
            )
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
        let pacingWindow: BenchmarkStreamShapePacingWindow
        let requestRegion: BenchmarkStreamShapeRequestRegion
        let targetName: String
    }
}

public struct BenchmarkStreamShapeOptimizationDecision: Codable, Equatable, Sendable {
    public let targetName: String
    public let verdict: BenchmarkStreamShapePracticalVerdict
    public let gateCount: Int
    public let passGateCount: Int
    public let warningGateCount: Int
    public let failGateCount: Int
    public let disabledGateCount: Int
    public let blockedGateCount: Int
    public let primaryIssueCode: BenchmarkStreamShapePracticalIssueCode?
    public let primaryConstraint: String
    public let recommendedNextProbe: String
    public let primaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let recommendedNextProbeCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let failureLabelCounts: [BenchmarkStreamShapeTriageLabelCount]

    private enum CodingKeys: String, CodingKey {
        case targetName
        case verdict
        case gateCount
        case passGateCount
        case warningGateCount
        case failGateCount
        case disabledGateCount
        case blockedGateCount
        case primaryIssueCode
        case primaryConstraint
        case recommendedNextProbe
        case primaryConstraintCounts
        case recommendedNextProbeCounts
        case failureLabelCounts
    }

    public init(
        targetName: String,
        verdict: BenchmarkStreamShapePracticalVerdict,
        gateCount: Int,
        passGateCount: Int,
        warningGateCount: Int,
        failGateCount: Int,
        disabledGateCount: Int,
        primaryIssueCode: BenchmarkStreamShapePracticalIssueCode? = nil,
        primaryConstraint: String? = nil,
        recommendedNextProbe: String? = nil,
        primaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        recommendedNextProbeCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        failureLabelCounts: [BenchmarkStreamShapeTriageLabelCount] = []
    ) {
        self.targetName = targetName
        self.verdict = verdict
        self.gateCount = max(gateCount, 0)
        self.passGateCount = max(passGateCount, 0)
        self.warningGateCount = max(warningGateCount, 0)
        self.failGateCount = max(failGateCount, 0)
        self.disabledGateCount = max(disabledGateCount, 0)
        self.blockedGateCount = max(self.warningGateCount + self.failGateCount, 0)
        self.primaryIssueCode = primaryIssueCode
        let derivedPrimaryConstraint = BenchmarkStreamShapeTriage.primaryConstraint(for: primaryIssueCode)
        let derivedRecommendedNextProbe = BenchmarkStreamShapeTriage.recommendedNextProbe(for: primaryIssueCode)
        self.primaryConstraint = BenchmarkStreamShapeTriage.safePrimaryConstraint(
            primaryConstraint,
            matching: derivedPrimaryConstraint
        ) ?? derivedPrimaryConstraint.rawValue
        self.recommendedNextProbe = BenchmarkStreamShapeTriage.safeRecommendedNextProbe(
            recommendedNextProbe,
            matching: derivedRecommendedNextProbe
        ) ?? derivedRecommendedNextProbe.rawValue
        self.primaryConstraintCounts = primaryConstraintCounts.isEmpty
            ? BenchmarkStreamShapeTriage.primaryConstraintCounts(for: [self.primaryConstraint])
            : BenchmarkStreamShapeTriage.mergedPrimaryConstraintCounts(from: primaryConstraintCounts)
        self.recommendedNextProbeCounts = recommendedNextProbeCounts.isEmpty
            ? BenchmarkStreamShapeTriage.recommendedNextProbeCounts(for: [self.recommendedNextProbe])
            : BenchmarkStreamShapeTriage.mergedRecommendedNextProbeCounts(from: recommendedNextProbeCounts)
        self.failureLabelCounts = BenchmarkStreamShapeTriage.mergedFailureLabelCounts(from: failureLabelCounts)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPrimaryIssueCode = try container.decodeIfPresent(String.self, forKey: .primaryIssueCode)
        self.init(
            targetName: try container.decode(String.self, forKey: .targetName),
            verdict: try container.decode(BenchmarkStreamShapePracticalVerdict.self, forKey: .verdict),
            gateCount: try container.decode(Int.self, forKey: .gateCount),
            passGateCount: try container.decode(Int.self, forKey: .passGateCount),
            warningGateCount: try container.decode(Int.self, forKey: .warningGateCount),
            failGateCount: try container.decode(Int.self, forKey: .failGateCount),
            disabledGateCount: try container.decode(Int.self, forKey: .disabledGateCount),
            primaryIssueCode: rawPrimaryIssueCode.flatMap(BenchmarkStreamShapePracticalIssueCode.init(rawValue:)),
            primaryConstraint: try container.decodeIfPresent(String.self, forKey: .primaryConstraint),
            recommendedNextProbe: try container.decodeIfPresent(String.self, forKey: .recommendedNextProbe),
            primaryConstraintCounts: try container.decodeIfPresent(
                [BenchmarkStreamShapeTriageLabelCount].self,
                forKey: .primaryConstraintCounts
            ) ?? [],
            recommendedNextProbeCounts: try container.decodeIfPresent(
                [BenchmarkStreamShapeTriageLabelCount].self,
                forKey: .recommendedNextProbeCounts
            ) ?? [],
            failureLabelCounts: try container.decodeIfPresent(
                [BenchmarkStreamShapeTriageLabelCount].self,
                forKey: .failureLabelCounts
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetName, forKey: .targetName)
        try container.encode(verdict, forKey: .verdict)
        try container.encode(gateCount, forKey: .gateCount)
        try container.encode(passGateCount, forKey: .passGateCount)
        try container.encode(warningGateCount, forKey: .warningGateCount)
        try container.encode(failGateCount, forKey: .failGateCount)
        try container.encode(disabledGateCount, forKey: .disabledGateCount)
        try container.encode(blockedGateCount, forKey: .blockedGateCount)
        try container.encodeIfPresent(primaryIssueCode?.rawValue, forKey: .primaryIssueCode)
        try container.encode(primaryConstraint, forKey: .primaryConstraint)
        try container.encode(recommendedNextProbe, forKey: .recommendedNextProbe)
        try container.encode(primaryConstraintCounts, forKey: .primaryConstraintCounts)
        try container.encode(recommendedNextProbeCounts, forKey: .recommendedNextProbeCounts)
        try container.encode(failureLabelCounts, forKey: .failureLabelCounts)
    }

    public static func decision(
        from gates: [BenchmarkStreamShapeProfileGateReport]
    ) -> BenchmarkStreamShapeOptimizationDecision? {
        guard let firstGate = gates.first else {
            return nil
        }
        let passGateCount = gates.filter { $0.verdict == .pass }.count
        let warningGateCount = gates.filter { $0.verdict == .warning }.count
        let failGateCount = gates.filter { $0.verdict == .fail }.count
        let disabledGateCount = gates.filter { $0.verdict == .disabled }.count
        let primaryIssueCode = BenchmarkStreamShapeTriage.primaryIssue(
            for: gates.compactMap(\.primaryIssueCode)
        )
        let primaryConstraint = BenchmarkStreamShapeTriage.primaryConstraint(for: primaryIssueCode)
        let recommendedNextProbe = BenchmarkStreamShapeTriage.recommendedNextProbe(for: primaryIssueCode)
        return BenchmarkStreamShapeOptimizationDecision(
            targetName: targetName(from: gates, fallback: firstGate.targetName),
            verdict: verdict(
                passGateCount: passGateCount,
                warningGateCount: warningGateCount,
                failGateCount: failGateCount,
                disabledGateCount: disabledGateCount
            ),
            gateCount: gates.count,
            passGateCount: passGateCount,
            warningGateCount: warningGateCount,
            failGateCount: failGateCount,
            disabledGateCount: disabledGateCount,
            primaryIssueCode: primaryIssueCode,
            primaryConstraint: primaryConstraint.rawValue,
            recommendedNextProbe: recommendedNextProbe.rawValue,
            primaryConstraintCounts: BenchmarkStreamShapeTriage.mergedPrimaryConstraintCounts(
                from: gates.flatMap(\.primaryConstraintCounts)
            ),
            recommendedNextProbeCounts: BenchmarkStreamShapeTriage.mergedRecommendedNextProbeCounts(
                from: gates.flatMap(\.recommendedNextProbeCounts)
            ),
            failureLabelCounts: BenchmarkStreamShapeTriage.mergedFailureLabelCounts(
                from: gates.flatMap(\.failureLabelCounts)
            )
        )
    }

    private static func targetName(
        from gates: [BenchmarkStreamShapeProfileGateReport],
        fallback: String
    ) -> String {
        let targetNames = Set(gates.map(\.targetName))
        return targetNames.count <= 1 ? fallback : "mixed-targets"
    }

    private static func verdict(
        passGateCount: Int,
        warningGateCount: Int,
        failGateCount: Int,
        disabledGateCount: Int
    ) -> BenchmarkStreamShapePracticalVerdict {
        if failGateCount > 0 {
            return .fail
        }
        if warningGateCount > 0 {
            return .warning
        }
        if passGateCount > 0 {
            return .pass
        }
        if disabledGateCount > 0 {
            return .disabled
        }
        return .disabled
    }
}

public enum BenchmarkStreamShapeTransportCadenceStatus: String, Codable, Equatable, Sendable {
    case notTested = "not-tested"
    case disabled
    case pass
    case belowTarget = "below-target"
    case failedBeforeSamples = "failed-before-samples"
}

public enum BenchmarkStreamShapeTransportCadenceNextAction: String, Codable, Equatable, Sendable {
    case none
    case inspectContinuousUpdatesConnection
    case tuneTransportCadence
    case compareRequestResponseEncodingProfiles
    case runPhysicalDeviceSustainedGate
}

public enum BenchmarkStreamShapeRequestCadenceSampleStatus: String, Codable, Equatable, Sendable {
    case notTested = "not-tested"
    case noUsableSamples = "no-usable-samples"
    case highContentHit = "high-content-hit"
    case unansweredWait = "unanswered-wait"
    case emptyResponse = "empty-response"
    case mixedLowHit = "mixed-low-hit"
}

public enum BenchmarkStreamShapeRequestCadenceLatencyStatus: String, Codable, Equatable, Sendable {
    case notMeasured = "not-measured"
    case pass
    case averageWarning = "average-warning"
    case averageFailed = "average-failed"
    case p95Warning = "p95-warning"
    case p95Failed = "p95-failed"
}

public enum BenchmarkStreamShapeRequestCadenceNextProbe: String, Codable, Equatable, Sendable {
    case none
    case inspectUpdateWaitTiming
    case inspectRequestRegionAndStimulus
    case tuneRequestPacingWindow
    case compareRequestResponseEncodingProfiles
    case inspectLocalRenderPipeline
    case compareAdaptivePacing
    case runPhysicalDeviceSustainedGate
    case collectLongerRun
}

public struct BenchmarkStreamShapeRequestCadenceHealth: Codable, Equatable, Sendable {
    public let targetName: String
    public let sampleStatus: BenchmarkStreamShapeRequestCadenceSampleStatus
    public let latencyStatus: BenchmarkStreamShapeRequestCadenceLatencyStatus
    public let recommendedNextProbe: BenchmarkStreamShapeRequestCadenceNextProbe
    public let requestResponseGateCount: Int
    public let requestResponseBlockedGateCount: Int
    public let requestResponseAggregateCount: Int
    public let requestResponseUsableRunCount: Int
    public let averageReceivedSamplePermille: Int?
    public let averageUnansweredSamplePermille: Int?
    public let averageContentSamplePermille: Int?
    public let averageContentResponsePermille: Int?
    public let averageUpdateMilliseconds: Int?
    public let maxP95UpdateMilliseconds: Int?
    public let averageContentFramesPerSecond: Double?
    public let dominantPhase: BenchmarkStreamShapeDominantPhase
    public let networkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase?
    public let slowDominantPhase: BenchmarkStreamShapeDominantPhase
    public let slowNetworkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase?
    public let averageFirstByteWaitSharePermille: Int?
    public let averagePayloadReadSharePermille: Int?
    public let maxFirstByteWaitP95Milliseconds: Int?
    public let maxPayloadReadP95Milliseconds: Int?
    public let requestResponsePrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let requestResponseFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount]

    public init(
        targetName: String,
        sampleStatus: BenchmarkStreamShapeRequestCadenceSampleStatus,
        latencyStatus: BenchmarkStreamShapeRequestCadenceLatencyStatus,
        recommendedNextProbe: BenchmarkStreamShapeRequestCadenceNextProbe,
        requestResponseGateCount: Int,
        requestResponseBlockedGateCount: Int,
        requestResponseAggregateCount: Int,
        requestResponseUsableRunCount: Int,
        averageReceivedSamplePermille: Int? = nil,
        averageUnansweredSamplePermille: Int? = nil,
        averageContentSamplePermille: Int? = nil,
        averageContentResponsePermille: Int? = nil,
        averageUpdateMilliseconds: Int? = nil,
        maxP95UpdateMilliseconds: Int? = nil,
        averageContentFramesPerSecond: Double? = nil,
        dominantPhase: BenchmarkStreamShapeDominantPhase = .unknown,
        networkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase? = nil,
        slowDominantPhase: BenchmarkStreamShapeDominantPhase = .unknown,
        slowNetworkReadDominantSubphase: BenchmarkStreamShapeNetworkReadSubphase? = nil,
        averageFirstByteWaitSharePermille: Int? = nil,
        averagePayloadReadSharePermille: Int? = nil,
        maxFirstByteWaitP95Milliseconds: Int? = nil,
        maxPayloadReadP95Milliseconds: Int? = nil,
        requestResponsePrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        requestResponseFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount] = []
    ) {
        self.targetName = targetName
        self.sampleStatus = sampleStatus
        self.latencyStatus = latencyStatus
        self.recommendedNextProbe = recommendedNextProbe
        self.requestResponseGateCount = max(requestResponseGateCount, 0)
        self.requestResponseBlockedGateCount = max(requestResponseBlockedGateCount, 0)
        self.requestResponseAggregateCount = max(requestResponseAggregateCount, 0)
        self.requestResponseUsableRunCount = max(requestResponseUsableRunCount, 0)
        self.averageReceivedSamplePermille = Self.clampOptionalPermille(averageReceivedSamplePermille)
        self.averageUnansweredSamplePermille = Self.clampOptionalPermille(averageUnansweredSamplePermille)
        self.averageContentSamplePermille = Self.clampOptionalPermille(averageContentSamplePermille)
        self.averageContentResponsePermille = Self.clampOptionalPermille(averageContentResponsePermille)
        self.averageUpdateMilliseconds = averageUpdateMilliseconds.map { max($0, 0) }
        self.maxP95UpdateMilliseconds = maxP95UpdateMilliseconds.map { max($0, 0) }
        self.averageContentFramesPerSecond = averageContentFramesPerSecond.map { max($0, 0) }
        self.dominantPhase = dominantPhase
        self.networkReadDominantSubphase = networkReadDominantSubphase
        self.slowDominantPhase = slowDominantPhase
        self.slowNetworkReadDominantSubphase = slowNetworkReadDominantSubphase
        self.averageFirstByteWaitSharePermille = Self.clampOptionalPermille(averageFirstByteWaitSharePermille)
        self.averagePayloadReadSharePermille = Self.clampOptionalPermille(averagePayloadReadSharePermille)
        self.maxFirstByteWaitP95Milliseconds = maxFirstByteWaitP95Milliseconds.map { max($0, 0) }
        self.maxPayloadReadP95Milliseconds = maxPayloadReadP95Milliseconds.map { max($0, 0) }
        self.requestResponsePrimaryConstraintCounts = BenchmarkStreamShapeTriage
            .mergedPrimaryConstraintCounts(from: requestResponsePrimaryConstraintCounts)
        self.requestResponseFailureLabelCounts = BenchmarkStreamShapeTriage
            .mergedFailureLabelCounts(from: requestResponseFailureLabelCounts)
    }

    public static func health(
        from aggregates: [BenchmarkStreamShapeProfileAggregateReport],
        gates: [BenchmarkStreamShapeProfileGateReport],
        targets: BenchmarkStreamShapePracticalTargets
    ) -> BenchmarkStreamShapeRequestCadenceHealth? {
        let requestAggregates = aggregates.filter { $0.transportMode == .requestResponse }
        let requestGates = gates.filter { $0.transportMode == .requestResponse }
        guard !requestAggregates.isEmpty || !requestGates.isEmpty else {
            return nil
        }

        let usableAggregates = requestAggregates.filter { $0.usableRunCount > 0 }
        let blockedGateCount = requestGates.filter {
            $0.verdict == .warning || $0.verdict == .fail
        }.count
        let primaryConstraintCounts = BenchmarkStreamShapeTriage.mergedPrimaryConstraintCounts(
            from: requestGates.flatMap(\.primaryConstraintCounts)
        )
        let failureLabelCounts = BenchmarkStreamShapeTriage.mergedFailureLabelCounts(
            from: requestGates.flatMap(\.failureLabelCounts)
        )
        let averageReceivedSamplePermille = roundedAverage(
            usableAggregates.compactMap(\.averageReceivedSamplePermille)
        )
        let averageUnansweredSamplePermille = roundedAverage(
            usableAggregates.compactMap(\.averageUnansweredSamplePermille)
        )
        let averageContentSamplePermille = roundedAverage(
            usableAggregates.compactMap(\.averageContentSamplePermille)
        )
        let averageContentResponsePermille = roundedAverage(
            usableAggregates.compactMap(\.averageContentResponsePermille)
        )
        let averageUpdateMilliseconds = roundedAverage(
            usableAggregates.compactMap(\.averageUpdateMilliseconds)
        )
        let maxP95UpdateMilliseconds = usableAggregates
            .compactMap(\.maxP95UpdateMilliseconds)
            .max()
        let averageContentFramesPerSecond = average(
            usableAggregates.compactMap(\.averageContentFramesPerSecond)
        )
        let dominantPhase = aggregateDominantPhase(
            from: usableAggregates.map(\.dominantPhase)
        )
        let networkReadDominantSubphase = aggregateNetworkReadSubphase(
            from: usableAggregates.map(\.networkReadDominantSubphase)
        )
        let slowDominantPhase = aggregateDominantPhase(
            from: usableAggregates.map(\.slowDominantPhase)
        )
        let slowNetworkReadDominantSubphase = aggregateNetworkReadSubphase(
            from: usableAggregates.map(\.slowNetworkReadDominantSubphase)
        )
        let averageFirstByteWaitSharePermille = roundedAverage(
            usableAggregates.compactMap(\.averageFirstByteWaitSharePermille)
        )
        let averagePayloadReadSharePermille = roundedAverage(
            usableAggregates.compactMap(\.averagePayloadReadSharePermille)
        )
        let maxFirstByteWaitP95Milliseconds = usableAggregates
            .compactMap(\.maxFirstByteWaitP95Milliseconds)
            .max()
        let maxPayloadReadP95Milliseconds = usableAggregates
            .compactMap(\.maxPayloadReadP95Milliseconds)
            .max()
        let sampleStatus = sampleStatus(
            usableAggregateCount: usableAggregates.count,
            averageReceivedSamplePermille: averageReceivedSamplePermille,
            averageUnansweredSamplePermille: averageUnansweredSamplePermille,
            averageContentSamplePermille: averageContentSamplePermille,
            averageContentResponsePermille: averageContentResponsePermille
        )
        let latencyStatus = latencyStatus(
            averageUpdateMilliseconds: averageUpdateMilliseconds,
            maxP95UpdateMilliseconds: maxP95UpdateMilliseconds,
            targets: targets
        )
        let nextProbe = recommendedNextProbe(
            requestGates: requestGates,
            sampleStatus: sampleStatus,
            latencyStatus: latencyStatus,
            primaryConstraintCounts: primaryConstraintCounts,
            dominantPhase: dominantPhase,
            slowDominantPhase: slowDominantPhase,
            blockedGateCount: blockedGateCount,
            usableAggregateCount: usableAggregates.count
        )

        return BenchmarkStreamShapeRequestCadenceHealth(
            targetName: targetName(from: requestGates, fallback: targets.name),
            sampleStatus: sampleStatus,
            latencyStatus: latencyStatus,
            recommendedNextProbe: nextProbe,
            requestResponseGateCount: requestGates.count,
            requestResponseBlockedGateCount: blockedGateCount,
            requestResponseAggregateCount: requestAggregates.count,
            requestResponseUsableRunCount: usableAggregates.reduce(0) { $0 + $1.usableRunCount },
            averageReceivedSamplePermille: averageReceivedSamplePermille,
            averageUnansweredSamplePermille: averageUnansweredSamplePermille,
            averageContentSamplePermille: averageContentSamplePermille,
            averageContentResponsePermille: averageContentResponsePermille,
            averageUpdateMilliseconds: averageUpdateMilliseconds,
            maxP95UpdateMilliseconds: maxP95UpdateMilliseconds,
            averageContentFramesPerSecond: averageContentFramesPerSecond,
            dominantPhase: dominantPhase,
            networkReadDominantSubphase: networkReadDominantSubphase,
            slowDominantPhase: slowDominantPhase,
            slowNetworkReadDominantSubphase: slowNetworkReadDominantSubphase,
            averageFirstByteWaitSharePermille: averageFirstByteWaitSharePermille,
            averagePayloadReadSharePermille: averagePayloadReadSharePermille,
            maxFirstByteWaitP95Milliseconds: maxFirstByteWaitP95Milliseconds,
            maxPayloadReadP95Milliseconds: maxPayloadReadP95Milliseconds,
            requestResponsePrimaryConstraintCounts: primaryConstraintCounts,
            requestResponseFailureLabelCounts: failureLabelCounts
        )
    }

    private static func sampleStatus(
        usableAggregateCount: Int,
        averageReceivedSamplePermille: Int?,
        averageUnansweredSamplePermille: Int?,
        averageContentSamplePermille: Int?,
        averageContentResponsePermille: Int?
    ) -> BenchmarkStreamShapeRequestCadenceSampleStatus {
        guard usableAggregateCount > 0 else {
            return .noUsableSamples
        }
        if (averageReceivedSamplePermille ?? 1_000) < 800
            || (averageUnansweredSamplePermille ?? 0) > 200 {
            return .unansweredWait
        }
        if (averageContentResponsePermille ?? 1_000) < 700 {
            return .emptyResponse
        }
        if (averageContentSamplePermille ?? 1_000) < 700 {
            return .mixedLowHit
        }
        return .highContentHit
    }

    private static func latencyStatus(
        averageUpdateMilliseconds: Int?,
        maxP95UpdateMilliseconds: Int?,
        targets: BenchmarkStreamShapePracticalTargets
    ) -> BenchmarkStreamShapeRequestCadenceLatencyStatus {
        guard averageUpdateMilliseconds != nil || maxP95UpdateMilliseconds != nil else {
            return .notMeasured
        }
        if let maxP95UpdateMilliseconds,
           maxP95UpdateMilliseconds > targets.failP95UpdateMilliseconds {
            return .p95Failed
        }
        if let failAverage = targets.failAverageUpdateMilliseconds,
           let averageUpdateMilliseconds,
           averageUpdateMilliseconds > failAverage {
            return .averageFailed
        }
        if let maxP95UpdateMilliseconds,
           maxP95UpdateMilliseconds > targets.passP95UpdateMilliseconds {
            return .p95Warning
        }
        if let passAverage = targets.passAverageUpdateMilliseconds,
           let averageUpdateMilliseconds,
           averageUpdateMilliseconds > passAverage {
            return .averageWarning
        }
        return .pass
    }

    private static func recommendedNextProbe(
        requestGates: [BenchmarkStreamShapeProfileGateReport],
        sampleStatus: BenchmarkStreamShapeRequestCadenceSampleStatus,
        latencyStatus: BenchmarkStreamShapeRequestCadenceLatencyStatus,
        primaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount],
        dominantPhase: BenchmarkStreamShapeDominantPhase,
        slowDominantPhase: BenchmarkStreamShapeDominantPhase,
        blockedGateCount: Int,
        usableAggregateCount: Int
    ) -> BenchmarkStreamShapeRequestCadenceNextProbe {
        let activeRequestGates = requestGates.filter { $0.verdict != .disabled }
        if !activeRequestGates.isEmpty,
           activeRequestGates.allSatisfy({ $0.verdict == .pass }) {
            return .runPhysicalDeviceSustainedGate
        }
        if usableAggregateCount == 0 {
            return .collectLongerRun
        }
        if primaryConstraint(
            DiagnosticSustainedSessionPrimaryConstraint.clientDecode,
            dominates: DiagnosticSustainedSessionPrimaryConstraint.receivePath,
            in: primaryConstraintCounts
        ) {
            return .compareRequestResponseEncodingProfiles
        }
        if primaryConstraintCount(
            DiagnosticSustainedSessionPrimaryConstraint.rendererUpload,
            in: primaryConstraintCounts
        ) > 0 {
            return .inspectLocalRenderPipeline
        }
        if primaryConstraintCount(
            DiagnosticSustainedSessionPrimaryConstraint.adaptivePacing,
            in: primaryConstraintCounts
        ) > 0 {
            return .compareAdaptivePacing
        }
        switch sampleStatus {
        case .unansweredWait:
            return .inspectUpdateWaitTiming
        case .emptyResponse, .mixedLowHit:
            return .inspectRequestRegionAndStimulus
        case .notTested:
            return .none
        case .noUsableSamples:
            return .collectLongerRun
        case .highContentHit:
            break
        }
        switch latencyStatus {
        case .averageWarning, .averageFailed, .p95Warning, .p95Failed:
            switch slowDominantPhase == .unknown ? dominantPhase : slowDominantPhase {
            case .requestLoop, .networkRead:
                return .inspectUpdateWaitTiming
            case .clientProcessing:
                return .compareRequestResponseEncodingProfiles
            case .unknown:
                return .tuneRequestPacingWindow
            }
        case .notMeasured:
            return .collectLongerRun
        case .pass:
            return blockedGateCount > 0 ? .tuneRequestPacingWindow : .none
        }
    }

    private static func aggregateDominantPhase(
        from phases: [BenchmarkStreamShapeDominantPhase]
    ) -> BenchmarkStreamShapeDominantPhase {
        let phases = phases.filter { $0 != .unknown }
        guard !phases.isEmpty else {
            return .unknown
        }
        let counts = Dictionary(grouping: phases, by: { $0 }).mapValues(\.count)
        let priority: [BenchmarkStreamShapeDominantPhase] = [
            .requestLoop,
            .networkRead,
            .clientProcessing
        ]
        return priority.max { lhs, rhs in
            (counts[lhs] ?? 0) < (counts[rhs] ?? 0)
        } ?? .unknown
    }

    private static func aggregateNetworkReadSubphase(
        from subphases: [BenchmarkStreamShapeNetworkReadSubphase]
    ) -> BenchmarkStreamShapeNetworkReadSubphase {
        let subphases = subphases.filter { $0 != .unknown }
        guard !subphases.isEmpty else {
            return .unknown
        }
        let counts = Dictionary(grouping: subphases, by: { $0 }).mapValues(\.count)
        let priority: [BenchmarkStreamShapeNetworkReadSubphase] = [
            .firstByteWait,
            .payloadRead
        ]
        return priority.max { lhs, rhs in
            (counts[lhs] ?? 0) < (counts[rhs] ?? 0)
        } ?? .unknown
    }

    private static func primaryConstraint(
        _ candidate: DiagnosticSustainedSessionPrimaryConstraint,
        dominates baseline: DiagnosticSustainedSessionPrimaryConstraint,
        in counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> Bool {
        let candidateCount = primaryConstraintCount(candidate, in: counts)
        guard candidateCount > 0 else {
            return false
        }
        return candidateCount > primaryConstraintCount(baseline, in: counts)
    }

    private static func primaryConstraintCount(
        _ constraint: DiagnosticSustainedSessionPrimaryConstraint,
        in counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> Int {
        counts.first { $0.label == constraint.rawValue }?.count ?? 0
    }

    private static func targetName(
        from gates: [BenchmarkStreamShapeProfileGateReport],
        fallback: String
    ) -> String {
        let targetNames = Set(gates.map(\.targetName))
        return targetNames.count <= 1 ? (targetNames.first ?? fallback) : "mixed-targets"
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
}

public struct BenchmarkStreamShapeTransportCadenceDiagnosis: Codable, Equatable, Sendable {
    public let targetName: String
    public let recommendedTransportMode: BenchmarkStreamShapeTransportMode?
    public let recommendedNextAction: BenchmarkStreamShapeTransportCadenceNextAction
    public let requestResponseStatus: BenchmarkStreamShapeTransportCadenceStatus
    public let continuousUpdatesStatus: BenchmarkStreamShapeTransportCadenceStatus
    public let requestResponseGateCount: Int
    public let requestResponseBlockedGateCount: Int
    public let continuousUpdatesGateCount: Int
    public let continuousUpdatesBlockedGateCount: Int
    public let requestResponsePrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let continuousUpdatesPrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let requestResponseFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount]
    public let continuousUpdatesFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount]

    public init(
        targetName: String,
        recommendedTransportMode: BenchmarkStreamShapeTransportMode? = nil,
        recommendedNextAction: BenchmarkStreamShapeTransportCadenceNextAction,
        requestResponseStatus: BenchmarkStreamShapeTransportCadenceStatus,
        continuousUpdatesStatus: BenchmarkStreamShapeTransportCadenceStatus,
        requestResponseGateCount: Int,
        requestResponseBlockedGateCount: Int,
        continuousUpdatesGateCount: Int,
        continuousUpdatesBlockedGateCount: Int,
        requestResponsePrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        continuousUpdatesPrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        requestResponseFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount] = [],
        continuousUpdatesFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount] = []
    ) {
        self.targetName = targetName
        self.recommendedTransportMode = recommendedTransportMode
        self.recommendedNextAction = recommendedNextAction
        self.requestResponseStatus = requestResponseStatus
        self.continuousUpdatesStatus = continuousUpdatesStatus
        self.requestResponseGateCount = max(requestResponseGateCount, 0)
        self.requestResponseBlockedGateCount = max(requestResponseBlockedGateCount, 0)
        self.continuousUpdatesGateCount = max(continuousUpdatesGateCount, 0)
        self.continuousUpdatesBlockedGateCount = max(continuousUpdatesBlockedGateCount, 0)
        self.requestResponsePrimaryConstraintCounts = BenchmarkStreamShapeTriage
            .mergedPrimaryConstraintCounts(from: requestResponsePrimaryConstraintCounts)
        self.continuousUpdatesPrimaryConstraintCounts = BenchmarkStreamShapeTriage
            .mergedPrimaryConstraintCounts(from: continuousUpdatesPrimaryConstraintCounts)
        self.requestResponseFailureLabelCounts = BenchmarkStreamShapeTriage
            .mergedFailureLabelCounts(from: requestResponseFailureLabelCounts)
        self.continuousUpdatesFailureLabelCounts = BenchmarkStreamShapeTriage
            .mergedFailureLabelCounts(from: continuousUpdatesFailureLabelCounts)
    }

    public static func diagnosis(
        from gates: [BenchmarkStreamShapeProfileGateReport]
    ) -> BenchmarkStreamShapeTransportCadenceDiagnosis? {
        guard let firstGate = gates.first else {
            return nil
        }
        let requestResponseGates = gates.filter { $0.transportMode == .requestResponse }
        let continuousUpdatesGates = gates.filter { $0.transportMode == .continuousUpdates }
        let requestResponseStatus = status(for: requestResponseGates)
        let continuousUpdatesStatus = status(for: continuousUpdatesGates)
        let requestResponseConstraints = BenchmarkStreamShapeTriage.mergedPrimaryConstraintCounts(
            from: requestResponseGates.flatMap(\.primaryConstraintCounts)
        )
        let continuousUpdatesConstraints = BenchmarkStreamShapeTriage.mergedPrimaryConstraintCounts(
            from: continuousUpdatesGates.flatMap(\.primaryConstraintCounts)
        )
        let requestResponseFailures = BenchmarkStreamShapeTriage.mergedFailureLabelCounts(
            from: requestResponseGates.flatMap(\.failureLabelCounts)
        )
        let continuousUpdatesFailures = BenchmarkStreamShapeTriage.mergedFailureLabelCounts(
            from: continuousUpdatesGates.flatMap(\.failureLabelCounts)
        )
        return BenchmarkStreamShapeTransportCadenceDiagnosis(
            targetName: targetName(from: gates, fallback: firstGate.targetName),
            recommendedTransportMode: recommendedTransportMode(
                requestResponseStatus: requestResponseStatus,
                continuousUpdatesStatus: continuousUpdatesStatus
            ),
            recommendedNextAction: recommendedNextAction(
                requestResponseStatus: requestResponseStatus,
                continuousUpdatesStatus: continuousUpdatesStatus,
                requestResponsePrimaryConstraintCounts: requestResponseConstraints,
                continuousUpdatesFailureLabelCounts: continuousUpdatesFailures
            ),
            requestResponseStatus: requestResponseStatus,
            continuousUpdatesStatus: continuousUpdatesStatus,
            requestResponseGateCount: requestResponseGates.count,
            requestResponseBlockedGateCount: blockedGateCount(for: requestResponseGates),
            continuousUpdatesGateCount: continuousUpdatesGates.count,
            continuousUpdatesBlockedGateCount: blockedGateCount(for: continuousUpdatesGates),
            requestResponsePrimaryConstraintCounts: requestResponseConstraints,
            continuousUpdatesPrimaryConstraintCounts: continuousUpdatesConstraints,
            requestResponseFailureLabelCounts: requestResponseFailures,
            continuousUpdatesFailureLabelCounts: continuousUpdatesFailures
        )
    }

    private static func status(
        for gates: [BenchmarkStreamShapeProfileGateReport]
    ) -> BenchmarkStreamShapeTransportCadenceStatus {
        guard !gates.isEmpty else {
            return .notTested
        }
        let activeGates = gates.filter { $0.verdict != .disabled }
        if activeGates.isEmpty {
            return .disabled
        }
        // Only classify explicit pre-sample transport failures here. Other labeled
        // regressions stay below target so future decode/stimulus/sample-bearing
        // failures are not hidden behind the transport/cadence bucket.
        if !activeGates.isEmpty,
           activeGates.allSatisfy(hasOnlyPreSampleTransportFailureLabels) {
            return .failedBeforeSamples
        }
        if activeGates.allSatisfy({ $0.verdict == .pass }) {
            return .pass
        }
        if activeGates.contains(where: { $0.verdict == .warning || $0.verdict == .fail }) {
            return .belowTarget
        }
        return .disabled
    }

    private static func recommendedTransportMode(
        requestResponseStatus: BenchmarkStreamShapeTransportCadenceStatus,
        continuousUpdatesStatus: BenchmarkStreamShapeTransportCadenceStatus
    ) -> BenchmarkStreamShapeTransportMode? {
        if requestResponseStatus == .pass {
            return .requestResponse
        }
        if continuousUpdatesStatus == .pass {
            return .continuousUpdates
        }
        if requestResponseStatus == .belowTarget {
            return .requestResponse
        }
        if continuousUpdatesStatus == .belowTarget {
            return .continuousUpdates
        }
        return nil
    }

    private static func recommendedNextAction(
        requestResponseStatus: BenchmarkStreamShapeTransportCadenceStatus,
        continuousUpdatesStatus: BenchmarkStreamShapeTransportCadenceStatus,
        requestResponsePrimaryConstraintCounts: [BenchmarkStreamShapeTriageLabelCount],
        continuousUpdatesFailureLabelCounts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> BenchmarkStreamShapeTransportCadenceNextAction {
        if requestResponseStatus == .pass || continuousUpdatesStatus == .pass {
            return .runPhysicalDeviceSustainedGate
        }
        if continuousUpdatesStatus == .failedBeforeSamples,
           !continuousUpdatesFailureLabelCounts.isEmpty {
            return .inspectContinuousUpdatesConnection
        }
        if requestResponseStatus == .belowTarget,
           primaryConstraint(
               DiagnosticSustainedSessionPrimaryConstraint.clientDecode,
               dominates: DiagnosticSustainedSessionPrimaryConstraint.receivePath,
               in: requestResponsePrimaryConstraintCounts
           ) {
            return .compareRequestResponseEncodingProfiles
        }
        if requestResponseStatus == .belowTarget || continuousUpdatesStatus == .belowTarget {
            return .tuneTransportCadence
        }
        return .none
    }

    private static func primaryConstraint(
        _ candidate: DiagnosticSustainedSessionPrimaryConstraint,
        dominates baseline: DiagnosticSustainedSessionPrimaryConstraint,
        in counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> Bool {
        let candidateCount = count(for: candidate.rawValue, in: counts)
        guard candidateCount > 0 else {
            return false
        }
        return candidateCount > count(for: baseline.rawValue, in: counts)
    }

    private static func count(
        for label: String,
        in counts: [BenchmarkStreamShapeTriageLabelCount]
    ) -> Int {
        counts.first { $0.label == label }?.count ?? 0
    }

    private static func blockedGateCount(
        for gates: [BenchmarkStreamShapeProfileGateReport]
    ) -> Int {
        gates.filter { $0.verdict == .warning || $0.verdict == .fail }.count
    }

    private static func hasOnlyPreSampleTransportFailureLabels(
        for gate: BenchmarkStreamShapeProfileGateReport
    ) -> Bool {
        !gate.failureLabelCounts.isEmpty
            && gate.failureLabelCounts.allSatisfy { isPreSampleTransportFailureLabel($0.label) }
    }

    private static func isPreSampleTransportFailureLabel(_ label: String) -> Bool {
        label.hasPrefix("stream-connect-")
            || label.hasPrefix("stream-first-frame-")
            || label.hasPrefix("continuous-probe-connect-")
            || label.hasPrefix("continuous-probe-first-frame-")
            || label.hasPrefix("continuous-probe-enable-")
            || label == "stream-continuous-updates-connect-timeout"
            || label == "stream-continuous-updates-connection-failed"
            || label == "stream-continuous-updates-continuous-updates-not-confirmed"
            || label == "stream-continuous-updates-not-connected"
            || label == "stream-incremental-connect-timeout"
            || label == "stream-incremental-connection-failed"
            || label == "stream-incremental-not-connected"
    }

    private static func targetName(
        from gates: [BenchmarkStreamShapeProfileGateReport],
        fallback: String
    ) -> String {
        let targetNames = Set(gates.map(\.targetName))
        return targetNames.count <= 1 ? fallback : "mixed-targets"
    }
}

public struct BenchmarkStreamShapeRecommendation: Codable, Equatable, Sendable {
    public let label: String
    public let transportMode: BenchmarkStreamShapeTransportMode
    public let pacingWindow: BenchmarkStreamShapePacingWindow
    public let requestRegion: BenchmarkStreamShapeRequestRegion
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
        pacingWindow: BenchmarkStreamShapePacingWindow = .single,
        requestRegion: BenchmarkStreamShapeRequestRegion = .full,
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
        self.pacingWindow = pacingWindow
        self.requestRegion = requestRegion
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
            pacingWindow: report.pacingWindow,
            requestRegion: report.requestRegion,
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
            pacingWindow: aggregate.pacingWindow,
            requestRegion: aggregate.requestRegion,
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
