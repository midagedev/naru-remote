import Foundation

public enum BenchmarkStreamShapeProfileSelection {
    public static let coreMatrixSelection = "core-matrix"
    public static let zrleIsolationSelection = "zrle-isolation"
    public static let pixelFormatIsolationSelection = "pixel-format-isolation"
    public static let appLowTrafficSelection = "app-low-traffic"
    /// Current default, pure ZRLE, non-ZRLE fallback, and future adaptive path.
    public static let defaultCoreMatrixLabels = [
        "local-low-latency",
        "zrle-compression-0",
        "tight-first",
        "adaptive-good-full"
    ]
    /// Current default, pure ZRLE, and cursor/clipboard ZRLE extension variants.
    public static let defaultZrleIsolationLabels = [
        "local-low-latency",
        "zrle-compression-0",
        "zrle-compression-0-cursor",
        "zrle-compression-0-clipboard",
        "zrle-compression-0-cursor-clipboard"
    ]
    /// Full-color vs benchmark-only RGB565-in-32 variants for server
    /// SetPixelFormat compatibility and sustained-stream pressure checks.
    public static let defaultPixelFormatIsolationLabels = [
        "local-low-latency",
        "local-low-latency-rgb565",
        "tight-first",
        "tight-first-rgb565",
        "zrle-compression-0",
        "zrle-compression-0-rgb565"
    ]
    /// Exact app-side opt-in low-traffic stream profile labels.
    public static let defaultAppLowTrafficLabels = [
        "local-low-latency-rgb565",
        "zrle-compression-0-rgb565"
    ]

    public static func usageDescription(allProfileLabels: [String]) -> String {
        let labels = uniqueLabels(allProfileLabels).joined(separator: ",")
        return "local-low-latency|\(coreMatrixSelection)|\(zrleIsolationSelection)|"
            + "\(pixelFormatIsolationSelection)|\(appLowTrafficSelection)|"
            + "all|comma-separated labels (\(labels))"
    }

    public static func selectedLabels(
        from rawValue: String,
        allProfileLabels: [String],
        localLowLatencyLabel: String = "local-low-latency",
        coreMatrixLabels: [String] = defaultCoreMatrixLabels,
        zrleIsolationLabels: [String] = defaultZrleIsolationLabels,
        pixelFormatIsolationLabels: [String] = defaultPixelFormatIsolationLabels,
        appLowTrafficLabels: [String] = defaultAppLowTrafficLabels
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
            return try namedSelectionLabels(
                coreMatrixLabels,
                allProfileLabels: allProfileLabels,
                missingError: BenchmarkStreamShapeProfileSelectionError.missingCoreMatrixLabels
            )
        }
        if trimmed == zrleIsolationSelection {
            return try namedSelectionLabels(
                zrleIsolationLabels,
                allProfileLabels: allProfileLabels,
                missingError: BenchmarkStreamShapeProfileSelectionError.missingZrleIsolationLabels
            )
        }
        if trimmed == pixelFormatIsolationSelection {
            return try namedSelectionLabels(
                pixelFormatIsolationLabels,
                allProfileLabels: allProfileLabels,
                missingError: BenchmarkStreamShapeProfileSelectionError.missingPixelFormatIsolationLabels
            )
        }
        if trimmed == appLowTrafficSelection {
            return try namedSelectionLabels(
                appLowTrafficLabels,
                allProfileLabels: allProfileLabels,
                missingError: BenchmarkStreamShapeProfileSelectionError.missingAppLowTrafficLabels
            )
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

    private static func namedSelectionLabels(
        _ labels: [String],
        allProfileLabels: [String],
        missingError: ([String]) -> BenchmarkStreamShapeProfileSelectionError
    ) throws -> [String] {
        let knownLabels = Set(allProfileLabels)
        let selectedLabels = uniqueLabels(labels)
        let unknownLabels = selectedLabels.filter { !knownLabels.contains($0) }
        guard unknownLabels.isEmpty else {
            throw missingError(unknownLabels)
        }
        return selectedLabels
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
    case missingZrleIsolationLabels([String])
    case missingPixelFormatIsolationLabels([String])
    case missingAppLowTrafficLabels([String])
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
        case let .missingZrleIsolationLabels(labels):
            return "zrle-isolation stream-shape profile selection is unavailable because "
                + "required profile label(s) are missing: \(labels.joined(separator: ", "))."
        case let .missingPixelFormatIsolationLabels(labels):
            return "pixel-format-isolation stream-shape profile selection is unavailable because "
                + "required profile label(s) are missing: \(labels.joined(separator: ", "))."
        case let .missingAppLowTrafficLabels(labels):
            return "app-low-traffic stream-shape profile selection is unavailable because "
                + "required profile label(s) are missing: \(labels.joined(separator: ", "))."
        case let .duplicateLabels(labels):
            return "duplicate stream-shape profile label(s): \(labels.joined(separator: ", "))."
        }
    }
}
