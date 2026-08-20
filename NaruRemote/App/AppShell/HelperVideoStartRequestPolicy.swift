import Foundation
import NaruRemoteCore

struct HelperVideoStartRequestPolicy: Equatable, Sendable {
    var streamPowerMode: StreamPowerMode
    var isSystemLowPowerModeEnabled: Bool
    var thermalState: SessionStreamThermalState
    /// Low Data Mode (`NWPath.isConstrained`). Cellular/hotspot
    /// (`isExpensive`) is intentionally not an input — constitution §VI.
    var isNetworkConstrained: Bool
    var deviceSupportsHEVCDecode: Bool

    init(
        streamPowerMode: StreamPowerMode,
        isSystemLowPowerModeEnabled: Bool,
        thermalState: SessionStreamThermalState,
        isNetworkConstrained: Bool,
        deviceSupportsHEVCDecode: Bool
    ) {
        self.streamPowerMode = streamPowerMode
        self.isSystemLowPowerModeEnabled = isSystemLowPowerModeEnabled
        self.thermalState = thermalState
        self.isNetworkConstrained = isNetworkConstrained
        self.deviceSupportsHEVCDecode = deviceSupportsHEVCDecode
    }

    var requestBody: HelperVideoStartStreamRequestBody {
        HelperVideoStartStreamRequestBody(
            codec: .h264,
            latencyMode: .lowLatency,
            qualityBucket: .readability,
            maxFrameRateBucket: frameRateBucket,
            acceptsHEVC: deviceSupportsHEVCDecode ? true : nil
        )
    }

    private var frameRateBucket: HelperVideoFrameRateBucket {
        guard streamPowerMode != .powerSaver,
              !isSystemLowPowerModeEnabled,
              thermalState.allowsThirtyFPSHelperVideo,
              !isNetworkConstrained
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
