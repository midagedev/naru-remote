import Foundation

public enum BenchmarkVisualTransport: String, Codable, Equatable, CaseIterable, Sendable {
    case vnc
    case helperVideo = "helper-video"
}

public enum BenchmarkVisualTransportSelectionError: Error, Equatable, Sendable {
    case emptySelection
    case unknownLabels([String])

    public var message: String {
        switch self {
        case .emptySelection:
            return "visual-transport must include at least one label."
        case let .unknownLabels(labels):
            return "visual-transport contains unknown label(s): \(labels.joined(separator: ","))."
        }
    }
}

public struct BenchmarkVisualTransportSelection: Codable, Equatable, Sendable {
    public static let vnc = BenchmarkVisualTransportSelection(normalizedTransports: [.vnc])
    public static let helperVideo = BenchmarkVisualTransportSelection(normalizedTransports: [.helperVideo])
    public static let all = BenchmarkVisualTransportSelection(
        normalizedTransports: BenchmarkVisualTransport.allCases
    )

    public static var usageDescription: String {
        "vnc|helper-video|all|comma-separated labels (vnc,helper-video)"
    }

    public let rawValue: String
    public let transports: [BenchmarkVisualTransport]

    private init(normalizedTransports: [BenchmarkVisualTransport]) {
        precondition(!normalizedTransports.isEmpty, "visual transport selection cannot be empty")
        self.transports = normalizedTransports
        self.rawValue = self.transports.map(\.rawValue).joined(separator: ",")
    }

    public static func parse(_ rawValue: String) throws -> BenchmarkVisualTransportSelection {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BenchmarkVisualTransportSelectionError.emptySelection
        }
        if trimmed == "all" {
            return .all
        }

        let labels = trimmed
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !labels.isEmpty else {
            throw BenchmarkVisualTransportSelectionError.emptySelection
        }

        var unknownLabels: [String] = []
        var transports: [BenchmarkVisualTransport] = []
        for label in labels {
            if let transport = BenchmarkVisualTransport(rawValue: label) {
                transports.append(transport)
            } else {
                unknownLabels.append(label)
            }
        }
        guard unknownLabels.isEmpty else {
            throw BenchmarkVisualTransportSelectionError.unknownLabels(unknownLabels)
        }
        let normalizedTransports = Self.normalized(transports)
        guard !normalizedTransports.isEmpty else {
            throw BenchmarkVisualTransportSelectionError.emptySelection
        }
        return BenchmarkVisualTransportSelection(normalizedTransports: normalizedTransports)
    }

    static func normalized(
        _ transports: [BenchmarkVisualTransport]
    ) -> [BenchmarkVisualTransport] {
        let selected = Set(transports)
        return BenchmarkVisualTransport.allCases.filter(selected.contains)
    }
}

public enum BenchmarkVNCVisualTransportReportShape: String, Codable, Equatable, Sendable {
    case existingLiveBenchmarkReport = "existing-live-benchmark-report"
}

public struct BenchmarkVisualTransportComparisonReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let selectedVisualTransports: [BenchmarkVisualTransport]
    public let vncReportShape: BenchmarkVNCVisualTransportReportShape
    public let helperVideoReports: [BenchmarkHelperVideoReport]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        selectedVisualTransports: [BenchmarkVisualTransport],
        vncReportShape: BenchmarkVNCVisualTransportReportShape = .existingLiveBenchmarkReport,
        helperVideoReports: [BenchmarkHelperVideoReport] = []
    ) {
        self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
        let normalizedTransports = BenchmarkVisualTransportSelection.normalized(selectedVisualTransports)
        precondition(!normalizedTransports.isEmpty, "visual transport comparison cannot be empty")
        self.selectedVisualTransports = normalizedTransports
        self.vncReportShape = vncReportShape
        self.helperVideoReports = helperVideoReports
    }

    public static func fakeHelperComparison(
        selection: BenchmarkVisualTransportSelection
    ) -> BenchmarkVisualTransportComparisonReport {
        let helperReports = selection.transports.contains(.helperVideo)
            ? [BenchmarkHelperVideoReport()]
            : []
        return BenchmarkVisualTransportComparisonReport(
            selectedVisualTransports: selection.transports,
            helperVideoReports: helperReports
        )
    }
}
