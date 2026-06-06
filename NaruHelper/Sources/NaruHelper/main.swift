import Foundation
import Darwin
import NaruHelperKit
import NaruRemoteCore

private enum NaruHelperCLI {
    static func run() async throws {
        if CommandLine.arguments.contains("--listen") {
            try listen()
            return
        }

        if CommandLine.arguments.contains("--capability") {
            try writeCapabilityResponse()
            return
        }

        if CommandLine.arguments.contains("--video-capability") {
            try await writeVideoCapabilityResponse()
            return
        }

        if CommandLine.arguments.contains("--video-encoder-prototype") {
            try writeVideoEncoderPrototypeResponse()
            return
        }

        let data = FileHandle.standardInput.readDataToEndOfFile()
        let request = try JSONDecoder().decode(NaruHelperInsertTextRequest.self, from: data)
        let response = insert(request: request)
        try writeJSON(response)
    }

    private static func writeCapabilityResponse() throws {
        try writeJSON(capabilityResponse())
    }

    private static func writeVideoCapabilityResponse() async throws {
        let response = await NaruHelperVideoCaptureCapabilityProbe.live().capability()
        try writeJSON(response)
    }

    private static func writeVideoEncoderPrototypeResponse() throws {
        let response = NaruHelperVideoEncoderPrototypeProbe.live().capability()
        try writeJSON(response)
    }

    private static func capabilityResponse() -> NaruHelperCapabilityResponse {
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

        return NaruHelperCapabilityResponse(
            availability: availability,
            permissionState: NaruHelperPermissionState(
                accessibility: accessibility,
                inputMonitoring: "notRequired",
                pasteboardFallback: "available",
                activeUserSession: "available"
            ),
            supportedStrategies: [.pasteboardPasteWithRestore]
        )
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

    private static func listen() throws {
        guard let token = optionValue(after: "--token"), !token.isEmpty else {
            FileHandle.standardError.write(Data("NaruHelper listen requires --token.\n".utf8))
            Darwin.exit(2)
        }

        let port = optionValue(after: "--port")
            .flatMap(UInt16.init)
            ?? UInt16(naruHelperTextBridgeDefaultPort)
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: token,
            capabilityProvider: {
                capabilityResponse()
            },
            insertHandler: { request in
                insert(request: request)
            }
        )
        let server = try NaruHelperNetworkServer(port: port, handler: handler)
        server.start()
        RunLoop.main.run()
    }

    private static func optionValue(after name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name) else {
            return nil
        }
        let valueIndex = CommandLine.arguments.index(after: index)
        guard valueIndex < CommandLine.arguments.endIndex else {
            return nil
        }
        return CommandLine.arguments[valueIndex]
    }
}

do {
    try await NaruHelperCLI.run()
} catch {
    FileHandle.standardError.write(Data("NaruHelper failed with a fixed safe error.\n".utf8))
    Darwin.exit(2)
}
