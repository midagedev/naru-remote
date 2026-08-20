import Foundation
import NaruRemoteCore

public struct NaruHelperVideoRateControlPolicy: Equatable, Sendable {
    public var qualityBucket: HelperVideoQualityBucket
    public var frameRateBucket: HelperVideoFrameRateBucket
    public var codec: HelperVideoCodec
    public var averageBitRate: Int
    public var dataRateLimitBytesPerSecond: Int
    public var dataRateLimitWindowSeconds: Int

    public init(
        qualityBucket: HelperVideoQualityBucket,
        frameRateBucket: HelperVideoFrameRateBucket,
        codec: HelperVideoCodec = .h264
    ) {
        self.qualityBucket = qualityBucket
        self.frameRateBucket = frameRateBucket
        self.codec = codec
        self.averageBitRate = Self.averageBitRate(
            qualityBucket: qualityBucket,
            frameRateBucket: frameRateBucket,
            codec: codec
        )
        self.dataRateLimitBytesPerSecond = Self.dataRateLimitBytesPerSecond(
            averageBitRate: averageBitRate
        )
        self.dataRateLimitWindowSeconds = 1
    }

    public var dataRateLimits: [Int] {
        [
            dataRateLimitBytesPerSecond,
            dataRateLimitWindowSeconds
        ]
    }

    private static func averageBitRate(
        qualityBucket: HelperVideoQualityBucket,
        frameRateBucket: HelperVideoFrameRateBucket,
        codec: HelperVideoCodec
    ) -> Int {
        switch codec {
        case .hevc:
            return hevcAverageBitRate(
                qualityBucket: qualityBucket,
                frameRateBucket: frameRateBucket
            )
        case .h264, .unknown:
            return h264AverageBitRate(
                qualityBucket: qualityBucket,
                frameRateBucket: frameRateBucket
            )
        }
    }

    private static func h264AverageBitRate(
        qualityBucket: HelperVideoQualityBucket,
        frameRateBucket: HelperVideoFrameRateBucket
    ) -> Int {
        switch (qualityBucket, normalizedFrameRateBucket(frameRateBucket)) {
        case (.readability, .upTo15):
            return 1_200_000
        case (.readability, .upTo30):
            return 1_800_000
        case (.balanced, .upTo15):
            return 2_400_000
        case (.balanced, .upTo30):
            return 3_600_000
        case (.fidelity, .upTo15):
            return 4_000_000
        case (.fidelity, .upTo30):
            return 6_000_000
        case (_, .unknown):
            return h264AverageBitRate(
                qualityBucket: qualityBucket,
                frameRateBucket: .upTo30
            )
        }
    }

    // [잠정 — 디바이스 패스 대기]
    private static func hevcAverageBitRate(
        qualityBucket: HelperVideoQualityBucket,
        frameRateBucket: HelperVideoFrameRateBucket
    ) -> Int {
        switch (qualityBucket, normalizedFrameRateBucket(frameRateBucket)) {
        case (.readability, .upTo15):
            return 800_000
        case (.readability, .upTo30):
            return 1_200_000
        case (.balanced, .upTo15):
            return 1_600_000
        case (.balanced, .upTo30):
            return 2_400_000
        case (.fidelity, .upTo15):
            return 2_700_000
        case (.fidelity, .upTo30):
            return 4_000_000
        case (_, .unknown):
            return hevcAverageBitRate(
                qualityBucket: qualityBucket,
                frameRateBucket: .upTo30
            )
        }
    }

    private static func dataRateLimitBytesPerSecond(averageBitRate: Int) -> Int {
        let burstBitRate = averageBitRate + averageBitRate / 2
        return max(burstBitRate / 8, 1)
    }

    private static func normalizedFrameRateBucket(
        _ frameRateBucket: HelperVideoFrameRateBucket
    ) -> HelperVideoFrameRateBucket {
        switch frameRateBucket {
        case .unknown:
            return .upTo30
        case .upTo15, .upTo30:
            return frameRateBucket
        }
    }
}
