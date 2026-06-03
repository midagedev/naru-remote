import Foundation

/// Integer millisecond latency distribution for the live VNC benchmark.
///
/// The summary intentionally keeps the source samples out of the JSON
/// report while preserving enough shape to compare profiles across
/// short benchmark runs. Percentiles use the nearest-rank method so
/// every reported value is an observed sample.
public struct BenchmarkLatencySummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let averageMilliseconds: Int
    public let minMilliseconds: Int
    public let p50Milliseconds: Int
    public let p95Milliseconds: Int
    public let maxMilliseconds: Int

    public var averageValue: Int { averageMilliseconds }
    public var minValue: Int { minMilliseconds }
    public var p50Value: Int { p50Milliseconds }
    public var p95Value: Int { p95Milliseconds }
    public var maxValue: Int { maxMilliseconds }

    public init?(_ samples: [Int]) {
        guard !samples.isEmpty else {
            return nil
        }

        let sorted = samples.sorted()
        self.sampleCount = sorted.count
        self.averageMilliseconds = sorted.reduce(0, +) / sorted.count
        self.minMilliseconds = sorted[0]
        self.p50Milliseconds = Self.nearestRank(sorted, percentile: 0.50)
        self.p95Milliseconds = Self.nearestRank(sorted, percentile: 0.95)
        self.maxMilliseconds = sorted[sorted.count - 1]
    }

    private static func nearestRank(_ sortedSamples: [Int], percentile: Double) -> Int {
        precondition(!sortedSamples.isEmpty, "nearestRank requires at least one sample")
        let clamped = min(max(percentile, 0), 1)
        let rank = Int((clamped * Double(sortedSamples.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sortedSamples.count - 1)
        return sortedSamples[index]
    }
}
