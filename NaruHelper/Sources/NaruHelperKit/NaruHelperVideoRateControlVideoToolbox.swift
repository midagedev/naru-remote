import Foundation

#if canImport(VideoToolbox)
import VideoToolbox

extension NaruHelperVideoRateControlPolicy {
    func videoToolboxCompressionProperties() -> [(CFString, CFTypeRef)] {
        [
            (
                kVTCompressionPropertyKey_AverageBitRate,
                NSNumber(value: averageBitRate) as CFNumber
            ),
            (
                kVTCompressionPropertyKey_DataRateLimits,
                dataRateLimits.map { NSNumber(value: $0) } as CFArray
            )
        ]
    }
}
#endif
