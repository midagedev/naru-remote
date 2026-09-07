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
    /// Spec 042 FR-007 (phone side): the pointer mode the phone is in when
    /// the stream starts. The helper needs it up front — `.trackpad` means
    /// the phone draws its own cursor glyph and the helper must not bake
    /// the system cursor into captured frames. Default `.trackpad` (the
    /// app's default pointer mode).
    var pointerControlMode: PointerControlMode

    init(
        streamPowerMode: StreamPowerMode,
        isSystemLowPowerModeEnabled: Bool,
        thermalState: SessionStreamThermalState,
        isNetworkConstrained: Bool,
        deviceSupportsHEVCDecode: Bool,
        pointerControlMode: PointerControlMode = .trackpad
    ) {
        self.streamPowerMode = streamPowerMode
        self.isSystemLowPowerModeEnabled = isSystemLowPowerModeEnabled
        self.thermalState = thermalState
        self.isNetworkConstrained = isNetworkConstrained
        self.deviceSupportsHEVCDecode = deviceSupportsHEVCDecode
        self.pointerControlMode = pointerControlMode
    }

    var requestBody: HelperVideoStartStreamRequestBody {
        HelperVideoStartStreamRequestBody(
            codec: .h264,
            latencyMode: .lowLatency,
            qualityBucket: .readability,
            maxFrameRateBucket: frameRateBucket,
            acceptsHEVC: deviceSupportsHEVCDecode ? true : nil,
            // Never nil: the helper's cursor rendering depends on knowing
            // the phone's mode, and nil would silently mean the legacy
            // "always bake the cursor" behaviour (spec 042 FR-007).
            pointerMode: pointerMode
        )
    }

    private var pointerMode: HelperVideoPointerMode {
        switch pointerControlMode {
        case .trackpad: return .trackpad
        case .directTouch: return .directTouch
        }
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
