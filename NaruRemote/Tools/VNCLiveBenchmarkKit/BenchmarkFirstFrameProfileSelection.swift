public enum BenchmarkFirstFrameProfileSelection: String, CaseIterable, Codable, Equatable, Sendable {
    case all
    case localLowLatency = "local-low-latency"
    case streamShapeProfiles = "stream-shape-profiles"
    case none

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public func selectedLabels(
        allProfileLabels: [String],
        streamShapeProfileLabels: [String],
        localLowLatencyLabel: String = "local-low-latency"
    ) -> [String] {
        switch self {
        case .all:
            return uniqueLabels(allProfileLabels)
        case .localLowLatency:
            return allProfileLabels.contains(localLowLatencyLabel) ? [localLowLatencyLabel] : []
        case .streamShapeProfiles:
            return uniqueLabels(streamShapeProfileLabels).filter { allProfileLabels.contains($0) }
        case .none:
            return []
        }
    }

    private func uniqueLabels(_ labels: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for label in labels where seen.insert(label).inserted {
            result.append(label)
        }
        return result
    }
}
