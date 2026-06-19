import Foundation
import NaruRemoteCore

public enum BenchmarkTextKeystrokeProbePayload: String, Codable, Equatable, CaseIterable, Sendable {
    case ascii
    case latin1
    case unicodeHangul = "unicode-hangul"

    public static let usageDescription = allCases.map(\.rawValue).joined(separator: "|")

    public var probeText: String {
        switch self {
        case .ascii:
            return "Naru"
        case .latin1:
            return "cafe\u{00E9}"
        case .unicodeHangul:
            return "\u{D55C}\u{AE00}"
        }
    }
}

public enum BenchmarkTextKeystrokeProbeStatus: String, Codable, Equatable, Sendable {
    case observedInserted = "observed-inserted"
    case sent
    case blocked
    case failed
}

public enum BenchmarkTextKeystrokeProbeStageStatus: String, Codable, Equatable, Sendable {
    case notRun = "not-run"
    case passed
    case blocked
    case failed
}

public enum BenchmarkTextKeystrokeProbeEventCountBucket: String, Codable, Equatable, Sendable {
    case zero
    case oneToFive = "one-to-five"
    case sixToTwenty = "six-to-twenty"
    case overTwenty = "over-twenty"

    public static func bucket(for eventCount: Int) -> BenchmarkTextKeystrokeProbeEventCountBucket {
        switch eventCount {
        case ...0:
            return .zero
        case 1...5:
            return .oneToFive
        case 6...20:
            return .sixToTwenty
        default:
            return .overTwenty
        }
    }
}

public enum BenchmarkTextKeystrokeObservationStatus: String, Codable, Equatable, Sendable {
    case notRun = "not-run"
    case targetReady = "target-ready"
    case matched
    case mismatched
    case noInput = "no-input"
    case targetUnavailable = "target-unavailable"
    case timedOut = "timed-out"
    case failed
}

public struct BenchmarkTextKeystrokeObservationTargetResult: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let mode: String
    public let payload: BenchmarkTextKeystrokeProbePayload
    public let observationStatus: BenchmarkTextKeystrokeObservationStatus
    public let observedScalarCountBucket: BenchmarkTextKeystrokeProbeEventCountBucket

    public init(
        schemaVersion: Int = Self.schemaVersion,
        mode: String = "text-keystroke-observation-target",
        payload: BenchmarkTextKeystrokeProbePayload,
        observationStatus: BenchmarkTextKeystrokeObservationStatus,
        observedScalarCountBucket: BenchmarkTextKeystrokeProbeEventCountBucket
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.payload = payload
        self.observationStatus = observationStatus
        self.observedScalarCountBucket = observedScalarCountBucket
    }

    public static func make(
        payload: BenchmarkTextKeystrokeProbePayload,
        observedText: String
    ) -> BenchmarkTextKeystrokeObservationTargetResult {
        let observedScalarCount = observedText.unicodeScalars.count
        let status: BenchmarkTextKeystrokeObservationStatus
        if observedText == payload.probeText {
            status = .matched
        } else if observedText.isEmpty {
            status = .noInput
        } else {
            status = .mismatched
        }

        return BenchmarkTextKeystrokeObservationTargetResult(
            payload: payload,
            observationStatus: status,
            observedScalarCountBucket: .bucket(for: observedScalarCount)
        )
    }

    public static func ready(
        payload: BenchmarkTextKeystrokeProbePayload
    ) -> BenchmarkTextKeystrokeObservationTargetResult {
        BenchmarkTextKeystrokeObservationTargetResult(
            payload: payload,
            observationStatus: .targetReady,
            observedScalarCountBucket: .zero
        )
    }
}

public struct BenchmarkTextKeystrokeProbeReport: Codable, Equatable, Sendable {
    public static let schemaVersion = 2

    public let schemaVersion: Int
    public let mode: String
    public let status: BenchmarkTextKeystrokeProbeStatus
    public let payload: BenchmarkTextKeystrokeProbePayload
    public let networkConditionProfile: BenchmarkNetworkConditionProfile
    public let payloadEncoding: TextInjectionPayloadEncoding
    public let usesUnicodeKeysyms: Bool
    public let eventCountBucket: BenchmarkTextKeystrokeProbeEventCountBucket
    public let connectStatus: BenchmarkTextKeystrokeProbeStageStatus
    public let firstFrameStatus: BenchmarkTextKeystrokeProbeStageStatus
    public let transcodeStatus: BenchmarkTextKeystrokeProbeStageStatus
    public let sendStatus: BenchmarkTextKeystrokeProbeStageStatus
    public let observationStatus: BenchmarkTextKeystrokeObservationStatus
    public let failureLabel: String?
    public let safety: [String]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        mode: String = "text-keystroke-probe",
        status: BenchmarkTextKeystrokeProbeStatus,
        payload: BenchmarkTextKeystrokeProbePayload,
        networkConditionProfile: BenchmarkNetworkConditionProfile = .none,
        payloadEncoding: TextInjectionPayloadEncoding,
        usesUnicodeKeysyms: Bool,
        eventCountBucket: BenchmarkTextKeystrokeProbeEventCountBucket,
        connectStatus: BenchmarkTextKeystrokeProbeStageStatus,
        firstFrameStatus: BenchmarkTextKeystrokeProbeStageStatus,
        transcodeStatus: BenchmarkTextKeystrokeProbeStageStatus,
        sendStatus: BenchmarkTextKeystrokeProbeStageStatus,
        observationStatus: BenchmarkTextKeystrokeObservationStatus = .notRun,
        failureLabel: String?,
        safety: [String] = Self.defaultSafety
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.status = status
        self.payload = payload
        self.networkConditionProfile = networkConditionProfile
        self.payloadEncoding = payloadEncoding
        self.usesUnicodeKeysyms = usesUnicodeKeysyms
        self.eventCountBucket = eventCountBucket
        self.connectStatus = connectStatus
        self.firstFrameStatus = firstFrameStatus
        self.transcodeStatus = transcodeStatus
        self.sendStatus = sendStatus
        self.observationStatus = observationStatus
        self.failureLabel = failureLabel
        self.safety = safety
    }

    public static let defaultSafety = [
        "text-keystroke probe reports omit raw text, keysyms, target identity, credentials, byte counts, framebuffer dimensions, pixels, raw OS errors, and exact timings",
        "text-keystroke probe reports emit fixed payload labels, encoding labels, stage labels, event-count buckets, network-condition labels, observation labels, and safe failure labels only",
        "observed mode may enqueue a pointer focus prelude without reporting coordinates; sent means key events were enqueued on the RFB transport; observed-inserted additionally requires a controlled local target to report a fixed-label match"
    ]
}
