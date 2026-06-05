import Foundation

public enum BenchmarkStreamShapeProfileSelection {
    public static let coreMatrixSelection = "core-matrix"
    /// Current default, pure ZRLE, non-ZRLE fallback, and future adaptive path.
    public static let defaultCoreMatrixLabels = [
        "local-low-latency",
        "zrle-compression-0",
        "tight-first",
        "adaptive-good-full"
    ]

    public static func usageDescription(allProfileLabels: [String]) -> String {
        let labels = uniqueLabels(allProfileLabels).joined(separator: ",")
        return "local-low-latency|\(coreMatrixSelection)|all|comma-separated labels (\(labels))"
    }

    public static func selectedLabels(
        from rawValue: String,
        allProfileLabels: [String],
        localLowLatencyLabel: String = "local-low-latency",
        coreMatrixLabels: [String] = defaultCoreMatrixLabels
    ) throws -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BenchmarkStreamShapeProfileSelectionError.emptySelection
        }

        let allProfileLabels = uniqueLabels(allProfileLabels)
        if trimmed == "all" {
            return allProfileLabels
        }
        if trimmed == localLowLatencyLabel {
            guard allProfileLabels.contains(localLowLatencyLabel) else {
                throw BenchmarkStreamShapeProfileSelectionError.unknownLabels([localLowLatencyLabel])
            }
            return [localLowLatencyLabel]
        }
        if trimmed == coreMatrixSelection {
            let knownLabels = Set(allProfileLabels)
            let selectedLabels = uniqueLabels(coreMatrixLabels)
            let unknownLabels = selectedLabels.filter { !knownLabels.contains($0) }
            guard unknownLabels.isEmpty else {
                throw BenchmarkStreamShapeProfileSelectionError.missingCoreMatrixLabels(unknownLabels)
            }
            return selectedLabels
        }

        let requestedLabels = trimmed
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard requestedLabels.allSatisfy({ !$0.isEmpty }) else {
            throw BenchmarkStreamShapeProfileSelectionError.emptySelection
        }

        let knownLabels = Set(allProfileLabels)
        let unknownLabels = uniqueLabels(requestedLabels.filter { !knownLabels.contains($0) })
        guard unknownLabels.isEmpty else {
            throw BenchmarkStreamShapeProfileSelectionError.unknownLabels(unknownLabels)
        }

        let duplicateLabels = duplicateValues(in: requestedLabels)
        guard duplicateLabels.isEmpty else {
            throw BenchmarkStreamShapeProfileSelectionError.duplicateLabels(duplicateLabels)
        }

        return requestedLabels
    }

    private static func uniqueLabels(_ labels: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for label in labels where seen.insert(label).inserted {
            result.append(label)
        }
        return result
    }

    private static func duplicateValues(in labels: [String]) -> [String] {
        var seen: Set<String> = []
        var duplicates: [String] = []
        for label in labels where !seen.insert(label).inserted && !duplicates.contains(label) {
            duplicates.append(label)
        }
        return duplicates
    }
}

public enum BenchmarkStreamShapeProfileSelectionError: Error, Equatable, Sendable {
    case emptySelection
    case unknownLabels([String])
    case missingCoreMatrixLabels([String])
    case duplicateLabels([String])

    public var message: String {
        switch self {
        case .emptySelection:
            return "stream-shape profile selection must not be empty."
        case let .unknownLabels(labels):
            return "unknown stream-shape profile label(s): \(labels.joined(separator: ", "))."
        case let .missingCoreMatrixLabels(labels):
            return "core-matrix stream-shape profile selection is unavailable because "
                + "required profile label(s) are missing: \(labels.joined(separator: ", "))."
        case let .duplicateLabels(labels):
            return "duplicate stream-shape profile label(s): \(labels.joined(separator: ", "))."
        }
    }
}
