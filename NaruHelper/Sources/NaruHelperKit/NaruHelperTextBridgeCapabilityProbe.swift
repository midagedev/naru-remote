import Foundation
import NaruRemoteCore

public enum NaruHelperTextBridgeCapabilityProbe {
    public static func response(
        platformSupported: Bool = true,
        canInsertNatively: Bool,
        canFallbackToPasteboard: Bool
    ) -> NaruHelperCapabilityResponse {
        guard platformSupported else {
            return NaruHelperCapabilityResponse(
                availability: .versionUnsupported,
                permissionState: NaruHelperPermissionState(
                    accessibility: "unsupported",
                    inputMonitoring: "notRequired",
                    pasteboardFallback: "unsupported",
                    activeUserSession: "unsupported"
                ),
                supportedStrategies: []
            )
        }

        var supportedStrategies: [HelperTextInsertStrategy] = []
        if canInsertNatively {
            supportedStrategies.append(.nativeInsert)
        }
        if canFallbackToPasteboard {
            supportedStrategies.append(.pasteboardPasteWithRestore)
        }

        return NaruHelperCapabilityResponse(
            availability: supportedStrategies.isEmpty ? .permissionMissing : .reachable,
            permissionState: NaruHelperPermissionState(
                accessibility: canInsertNatively ? "granted" : "missing",
                inputMonitoring: "notRequired",
                pasteboardFallback: canFallbackToPasteboard ? "available" : "missing",
                activeUserSession: "available"
            ),
            supportedStrategies: supportedStrategies
        )
    }
}
