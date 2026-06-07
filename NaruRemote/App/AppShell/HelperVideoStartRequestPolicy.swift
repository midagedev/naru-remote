import Foundation
import NaruRemoteCore

struct HelperVideoStartRequestPolicy: Equatable, Sendable {
    var streamPowerMode: StreamPowerMode
    var isSystemLowPowerModeEnabled: Bool
    var thermalState: SessionStreamThermalState

    init(
        streamPowerMode: StreamPowerMode,
        isSystemLowPowerModeEnabled: Bool,
        thermalState: SessionStreamThermalState
    ) {
        self.streamPowerMode = streamPowerMode
        self.isSystemLowPowerModeEnabled = isSystemLowPowerModeEnabled
        self.thermalState = thermalState
    }

    var requestBody: HelperVideoStartStreamRequestBody {
        HelperVideoStartStreamRequestBody(
            codec: .h264,
            latencyMode: .lowLatency,
            qualityBucket: .readability,
            maxFrameRateBucket: frameRateBucket
        )
    }

    private var frameRateBucket: HelperVideoFrameRateBucket {
        guard streamPowerMode != .powerSaver,
              !isSystemLowPowerModeEnabled,
              thermalState.allowsThirtyFPSHelperVideo
        else {
            return .upTo15
        }
        return .upTo30
    }
}

private extension SessionStreamThermalState {
    var allowsThirtyFPSHelperVideo: Bool {
        switch self {
        // Unknown means no elevated pressure signal has been observed yet.
        case .unknown, .nominal:
            return true
        case .fair, .serious, .critical:
            return false
        }
    }
}
