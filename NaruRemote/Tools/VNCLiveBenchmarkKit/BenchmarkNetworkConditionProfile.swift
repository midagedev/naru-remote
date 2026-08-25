import Foundation

/// How the link between client and server behaves during a benchmark run.
///
/// Spec 029. The mobile profiles below are **derived from a measurement**, not
/// chosen: `tailscale ping` from the development Mac to the founder's iPhone,
/// connected direct over a mobile network, 2026-08-25, eight consecutive
/// samples of round-trip time in milliseconds:
///
///     41, 56, 232, 372, 416, 65, 137, 500
///
/// Median approximately 185 ms, minimum 41, maximum 500 — a twelve-fold spread.
/// Those eight numbers are the entire empirical basis, so they are written here
/// rather than in a report: anyone tightening these profiles should be able to
/// see how thin the sample is.
public enum BenchmarkNetworkConditionProfile: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case wanLatency = "wan-latency"
    case constrainedCellular = "constrained-cellular"
    /// The founder's link at its median: half of all round trips were worse
    /// than this.
    case tailnetMobileMedian = "tailnet-mobile-median"
    /// The same link at its observed tail. Not a worst case — a case that was
    /// actually seen, twice, in eight samples.
    case tailnetMobileTail = "tailnet-mobile-tail"

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    public var settings: BenchmarkNetworkConditionSettings? {
        switch self {
        case .none:
            return nil
        case .wanLatency:
            return BenchmarkNetworkConditionSettings(
                oneWayDelayMilliseconds: 80,
                throughputKilobitsPerSecond: nil,
                maxChunkBytes: 16 * 1024
            )
        case .constrainedCellular:
            return BenchmarkNetworkConditionSettings(
                oneWayDelayMilliseconds: 120,
                throughputKilobitsPerSecond: 1_024,
                maxChunkBytes: 8 * 1024
            )
        case .tailnetMobileMedian:
            // 185 ms measured round trip, modelled as a symmetric one-way delay.
            // Jitter spans the measured minimum and median rather than the full
            // range, so this profile stays the *typical* case.
            return BenchmarkNetworkConditionSettings(
                oneWayDelayMilliseconds: 92,
                throughputKilobitsPerSecond: nil,
                maxChunkBytes: 16 * 1024,
                jitterMilliseconds: 70
            )
        case .tailnetMobileTail:
            // The 500 ms sample. Uncapped throughput on purpose: this profile
            // isolates round-trip time, so a run that collapses here collapsed
            // because of latency and not because it ran out of bandwidth.
            return BenchmarkNetworkConditionSettings(
                oneWayDelayMilliseconds: 250,
                throughputKilobitsPerSecond: nil,
                maxChunkBytes: 16 * 1024,
                jitterMilliseconds: 120
            )
        }
    }
}

public struct BenchmarkNetworkConditionSettings: Codable, Equatable, Sendable {
    public let oneWayDelayMilliseconds: Int
    public let throughputKilobitsPerSecond: Int?
    public let maxChunkBytes: Int

    /// Spec 029 FR-002. Peak symmetric variation around `oneWayDelayMilliseconds`.
    ///
    /// The link this models varies by more than an order of magnitude, and a
    /// fixed-delay model reproduces its mean and none of the behaviour that
    /// depends on variance — in particular whether the transport's idle timeout
    /// is firing on responses that are slow rather than absent. Zero keeps the
    /// original fixed-delay behaviour, so existing profiles are unchanged.
    public let jitterMilliseconds: Int

    public init(
        oneWayDelayMilliseconds: Int,
        throughputKilobitsPerSecond: Int?,
        maxChunkBytes: Int,
        jitterMilliseconds: Int = 0
    ) {
        self.oneWayDelayMilliseconds = max(oneWayDelayMilliseconds, 0)
        self.throughputKilobitsPerSecond = throughputKilobitsPerSecond.map { max($0, 1) }
        self.maxChunkBytes = max(maxChunkBytes, 1)
        self.jitterMilliseconds = max(jitterMilliseconds, 0)
    }

    /// The one-way delay for one chunk, jittered.
    ///
    /// Deterministic in `sequence` rather than random: a benchmark whose
    /// conditioning cannot be replayed produces numbers that cannot be compared
    /// between runs, which is the failure spec 025 was written about. The
    /// generator is a cheap integer hash, so the same run shape always sees the
    /// same delay sequence while consecutive chunks see uncorrelated values.
    public func jitteredOneWayDelayMilliseconds(sequence: Int) -> Int {
        guard jitterMilliseconds > 0 else {
            return oneWayDelayMilliseconds
        }
        var state = UInt64(bitPattern: Int64(sequence)) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        state ^= state >> 33
        state = state &* 0xff51_afd7_ed55_8ccd
        state ^= state >> 33
        let span = 2 * jitterMilliseconds + 1
        let offset = Int(state % UInt64(span)) - jitterMilliseconds
        return max(0, oneWayDelayMilliseconds + offset)
    }

    public func chunkByteCounts(for byteCount: Int) -> [Int] {
        guard byteCount > 0 else {
            return []
        }
        var remaining = byteCount
        var chunks: [Int] = []
        while remaining > 0 {
            let chunk = min(remaining, maxChunkBytes)
            chunks.append(chunk)
            remaining -= chunk
        }
        return chunks
    }

    public func chunks(for data: Data) -> [Data] {
        chunkByteCounts(for: data.count).reduce(into: (chunks: [Data](), offset: 0)) { state, count in
            let end = state.offset + count
            state.chunks.append(data[state.offset..<end])
            state.offset = end
        }.chunks
    }

    public func delaySeconds(
        forChunkByteCount byteCount: Int,
        startsBurst: Bool = true,
        sequence: Int = 0
    ) -> TimeInterval {
        let oneWayMilliseconds = jitteredOneWayDelayMilliseconds(sequence: sequence)
        let latencySeconds = startsBurst ? TimeInterval(oneWayMilliseconds) / 1_000 : 0
        guard let throughputKilobitsPerSecond else {
            return latencySeconds
        }
        let transferSeconds = TimeInterval(max(byteCount, 0) * 8) / TimeInterval(throughputKilobitsPerSecond * 1_000)
        return latencySeconds + transferSeconds
    }
}
