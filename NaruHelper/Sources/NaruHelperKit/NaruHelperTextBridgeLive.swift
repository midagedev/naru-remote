import Foundation
import NaruRemoteCore

/// The live macOS wiring behind `--capability` and the insert path
/// (lifted from the CLI for spec 041 so the menu bar app and the CLI run
/// literally the same text bridge, not a copy). Pure glue: every decision
/// lives in the probe/inserters this calls.
public enum NaruHelperTextBridgeLive {
    public static func capabilityResponse() -> NaruHelperCapabilityResponse {
        #if os(macOS)
        let accessibilityInserter = MacAccessibilityFocusedTextInserter()
        let unicodeEventInserter = MacUnicodeKeyboardTextInserter()
        let poster = MacPasteCommandPoster()
        return NaruHelperTextBridgeCapabilityProbe.response(
            canInsertWithAccessibility: accessibilityInserter.canInsertTextDirectly,
            canInsertWithUnicodeEvents: unicodeEventInserter.canInsertTextDirectly,
            canFallbackToPasteboard: poster.canPostPasteCommand
        )
        #else
        return NaruHelperTextBridgeCapabilityProbe.response(
            platformSupported: false,
            canInsertWithAccessibility: false,
            canInsertWithUnicodeEvents: false,
            canFallbackToPasteboard: false
        )
        #endif
    }

    public static func insert(
        request: NaruHelperInsertTextRequest
    ) -> NaruHelperInsertTextResponse {
        #if os(macOS)
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: MacGeneralPasteboard(),
            pasteCommandPoster: MacPasteCommandPoster(),
            nativeTextInserter: MacNativeTextInserter.live()
        )
        return inserter.insertText(request: request)
        #else
        return NaruHelperInsertTextResponse(
            requestID: request.requestID,
            status: .failed,
            strategyUsed: .unsupported,
            safeFailureCode: .versionUnsupported
        )
        #endif
    }
}
