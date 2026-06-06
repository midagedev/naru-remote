import Foundation
import NaruRemoteCore

public enum BenchmarkStreamShapeFirstFrameTimingText {
    public static func receiveLine(
        _ timing: RFBFramebufferUpdateTiming?,
        indentation: String
    ) -> String? {
        guard let timing else {
            return nil
        }
        let firstByte = timing.firstByteWaitMilliseconds.map(String.init) ?? "n/a"
        let payload = timing.payloadReadMilliseconds.map(String.init) ?? "n/a"
        return "\(indentation)first-frame receive ms total/network/first-byte/payload/client: "
            + "\(timing.totalMilliseconds)/\(timing.networkReadMilliseconds)/"
            + "\(firstByte)/\(payload)/\(timing.clientProcessingMilliseconds)"
    }

    public static func aggregateLines(
        _ aggregate: BenchmarkStreamShapeProfileAggregateReport,
        indentation: String
    ) -> [String] {
        guard let total = aggregate.averageFirstFrameReceiveTotalMilliseconds,
              let network = aggregate.averageFirstFrameNetworkReadMilliseconds
        else {
            return []
        }
        let firstByte = aggregate.averageFirstFrameFirstByteWaitMilliseconds.map(String.init) ?? "n/a"
        let payload = aggregate.averageFirstFramePayloadReadMilliseconds.map(String.init) ?? "n/a"
        let client = aggregate.averageFirstFrameClientProcessingMilliseconds.map(String.init) ?? "n/a"
        let firstByteShare = aggregate.averageFirstFrameFirstByteWaitSharePermille.map(String.init) ?? "n/a"
        let payloadShare = aggregate.averageFirstFramePayloadReadSharePermille.map(String.init) ?? "n/a"
        return [
            "\(indentation)first-frame receive ms avg total/network/first-byte/payload/client: "
                + "\(total)/\(network)/\(firstByte)/\(payload)/\(client)",
            "\(indentation)first-frame network split permille avg first-byte/payload: "
                + "\(firstByteShare)/\(payloadShare)"
        ]
    }
}
