import Foundation
import NaruRemoteCore

public enum NaruHelperTextBridgeCapabilityProbe {
    public static func response(
        platformSupported: Bool = true,
        canInsertWithAccessibility: Bool,
        canInsertWithUnicodeEvents: Bool,
        canFallbackToPasteboard: Bool
    ) -> NaruHelperCapabilityResponse {
        guard platformSupported else {
            return NaruHelperCapabilityResponse(
                availability: .versionUnsupported,
                permissionState: NaruHelperPermissionState(
                    accessibility: "unsupported",
                    accessibilityValueInsert: "unsupported",
                    unicodeKeyboardEvent: "unsupported",
                    inputMonitoring: "notRequired",
                    pasteboardFallback: "unsupported",
                    activeUserSession: "unsupported"
                ),
                supportedStrategies: []
            )
        }

        let canInsertNatively = canInsertWithAccessibility || canInsertWithUnicodeEvents
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
                accessibility: canInsertWithAccessibility ? "granted" : "missing",
                accessibilityValueInsert: canInsertWithAccessibility ? "granted" : "missing",
                unicodeKeyboardEvent: canInsertWithUnicodeEvents ? "granted" : "missing",
                inputMonitoring: "notRequired",
                pasteboardFallback: canFallbackToPasteboard ? "available" : "missing",
                activeUserSession: "available"
            ),
            supportedStrategies: supportedStrategies
        )
    }
}
