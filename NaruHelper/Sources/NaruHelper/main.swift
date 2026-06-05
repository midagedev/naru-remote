import Foundation
import NaruHelperKit
import NaruRemoteCore

private enum NaruHelperCLI {
    static func run() throws {
        if CommandLine.arguments.contains("--capability") {
            try writeCapabilityResponse()
            return
        }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        let request = try JSONDecoder().decode(NaruHelperInsertTextRequest.self, from: data)
        let response = insert(request: request)
        try writeJSON(response)
    }

    private static func writeCapabilityResponse() throws {
        #if os(macOS)
        let poster = MacPasteCommandPoster()
        let availability: HelperTextBridgeAvailability = poster.canPostPasteCommand
            ? .reachable
            : .permissionMissing
        let accessibility = poster.canPostPasteCommand ? "granted" : "missing"
        #else
        let availability: HelperTextBridgeAvailability = .versionUnsupported
        let accessibility = "unsupported"
        #endif

        let response = NaruHelperCapabilityResponse(
            availability: availability,
            permissionState: NaruHelperPermissionState(
                accessibility: accessibility,
                inputMonitoring: "notRequired",
                pasteboardFallback: "available",
                activeUserSession: "available"
            ),
            supportedStrategies: [.pasteboardPasteWithRestore]
        )
        try writeJSON(response)
    }

    private static func insert(
        request: NaruHelperInsertTextRequest
    ) -> NaruHelperInsertTextResponse {
        #if os(macOS)
        let inserter = NaruHelperPasteboardTextInserter(
            pasteboard: MacGeneralPasteboard(),
            pasteCommandPoster: MacPasteCommandPoster()
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

    private static func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

do {
    try NaruHelperCLI.run()
} catch {
    FileHandle.standardError.write(Data("NaruHelper failed with a fixed safe error.\n".utf8))
    Foundation.exit(2)
}
