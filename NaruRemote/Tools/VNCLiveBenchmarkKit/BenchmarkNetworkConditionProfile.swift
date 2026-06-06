import Foundation

public enum BenchmarkNetworkConditionProfile: String, Codable, Equatable, Sendable, CaseIterable {
    case none
    case wanLatency = "wan-latency"
    case constrainedCellular = "constrained-cellular"

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
        }
    }
}

public struct BenchmarkNetworkConditionSettings: Codable, Equatable, Sendable {
    public let oneWayDelayMilliseconds: Int
    public let throughputKilobitsPerSecond: Int?
    public let maxChunkBytes: Int

    public init(
        oneWayDelayMilliseconds: Int,
        throughputKilobitsPerSecond: Int?,
        maxChunkBytes: Int
    ) {
        self.oneWayDelayMilliseconds = max(oneWayDelayMilliseconds, 0)
        self.throughputKilobitsPerSecond = throughputKilobitsPerSecond.map { max($0, 1) }
        self.maxChunkBytes = max(maxChunkBytes, 1)
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
        startsBurst: Bool = true
    ) -> TimeInterval {
        let latencySeconds = startsBurst ? TimeInterval(oneWayDelayMilliseconds) / 1_000 : 0
        guard let throughputKilobitsPerSecond else {
            return latencySeconds
        }
        let transferSeconds = TimeInterval(max(byteCount, 0) * 8) / TimeInterval(throughputKilobitsPerSecond * 1_000)
        return latencySeconds + transferSeconds
    }
}
