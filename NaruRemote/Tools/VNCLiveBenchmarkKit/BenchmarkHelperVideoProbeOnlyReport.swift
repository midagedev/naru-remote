import Foundation

public struct BenchmarkHelperVideoProbeOnlyReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let helperVideoProbeMode: BenchmarkHelperVideoProbeMode
    public let visualTransportComparison: BenchmarkVisualTransportComparisonReport
    public let safety: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        helperVideoProbeMode: BenchmarkHelperVideoProbeMode,
        visualTransportComparison: BenchmarkVisualTransportComparisonReport,
        safety: [String] = Self.defaultSafety
    ) {
        self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
        self.helperVideoProbeMode = helperVideoProbeMode
        self.visualTransportComparison = visualTransportComparison
        self.safety = safety
    }

    public static func make(
        selection: BenchmarkVisualTransportSelection,
        probeMode: BenchmarkHelperVideoProbeMode
    ) -> BenchmarkHelperVideoProbeOnlyReport {
        BenchmarkHelperVideoProbeOnlyReport(
            helperVideoProbeMode: probeMode,
            visualTransportComparison: BenchmarkHelperVideoProbe.makeComparison(
                selection: selection,
                probeMode: probeMode
            )
        )
    }

    public static let defaultSafety = [
        "helper-video probe-only reports omit live target identity, credentials, helper executable paths, endpoints, auth tokens, frame payloads, byte counts, dimensions, coordinates, pixels, raw OS errors, and exact helper timings",
        "helper-video probe-only reports emit fixed transport labels, helper probe mode labels, aggregate health bands, verdicts, and fixed issue codes only"
    ]
}
