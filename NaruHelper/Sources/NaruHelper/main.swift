import Foundation
import Darwin
import NaruHelperKit
import NaruRemoteCore

private enum NaruHelperCLI {
    static func run() async throws {
        if CommandLine.arguments.contains("--listen") {
            try await listen()
            return
        }

        if CommandLine.arguments.contains("--video-listen") {
            try await listenVideo()
            return
        }

        if CommandLine.arguments.contains("--capability") {
            try writeCapabilityResponse()
            return
        }

        if CommandLine.arguments.contains("--request-text-permission") {
            try writeTextPermissionRequestResponse()
            return
        }

        if CommandLine.arguments.contains("--video-capability") {
            try await writeVideoCapabilityResponse()
            return
        }

        if CommandLine.arguments.contains("--video-request-screen-recording-permission") {
            try writeVideoScreenRecordingPermissionRequestResponse()
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

    private static func writeTextPermissionRequestResponse() throws {
        let response = NaruHelperTextPermissionRequester.live().request()
        try writeJSON(response)
    }

    private static func writeVideoCapabilityResponse() async throws {
        let response = await NaruHelperVideoCaptureCapabilityProbe.live().capability()
        try writeJSON(response)
    }

    private static func writeVideoScreenRecordingPermissionRequestResponse() throws {
        let response = NaruHelperVideoScreenRecordingPermissionRequester.live().request()
        try writeJSON(response)
    }

    private static func writeVideoEncoderPrototypeResponse() throws {
        let response = NaruHelperVideoEncoderPrototypeProbe.live().capability()
        try writeJSON(response)
    }

    private static func capabilityResponse() -> NaruHelperCapabilityResponse {
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

    private static func insert(
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

    private static func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func listen() async throws {
        // The pairing secret must ride env indirection: a direct --token value
        // lands in argv and stays visible to every local user via `ps` for the
        // listener's whole lifetime. Mirrors --video-listen's contract.
        if CommandLine.arguments.contains("--token") {
            FileHandle.standardError.write(
                Data("NaruHelper listen does not accept --token; use --token-env VAR_NAME.\n".utf8)
            )
            Darwin.exit(2)
        }
        guard let tokenVariable = optionValue(after: "--token-env"),
              !tokenVariable.isEmpty,
              let token = ProcessInfo.processInfo.environment[tokenVariable],
              !token.isEmpty
        else {
            FileHandle.standardError.write(
                Data("NaruHelper listen requires --token-env VAR_NAME with the pairing secret exported in that variable.\n".utf8)
            )
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
        // NWListener schedules on a dispatch queue, not the run loop, so
        // `RunLoop.main.run()` returns immediately (no sources) and the
        // process exits before serving anything. Park the task the same way
        // the (proven-alive) --video-listen runtime does.
        while true {
            _ = server.port
            try await Task.sleep(for: .seconds(3_600))
        }
    }

    private static func listenVideo() async throws {
        #if canImport(Network)
        let configuration = try NaruHelperVideoListenConfiguration.parse(
            arguments: CommandLine.arguments
        )
        let server = try NaruHelperVideoListenRuntime(
            configuration: configuration
        ).makeServer()
        server.start()
        while true {
            _ = server.port
            try await Task.sleep(for: .seconds(3_600))
        }
        #else
        FileHandle.standardError.write(Data("NaruHelper video listen unsupported.\n".utf8))
        Darwin.exit(2)
        #endif
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
