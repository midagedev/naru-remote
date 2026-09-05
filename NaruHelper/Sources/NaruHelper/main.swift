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

        if CommandLine.arguments.contains("--pair") {
            try await pair()
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
        let response = NaruHelperTextBridgeLive.insert(request: request)
        try writeJSON(response)
    }

    private static func writeCapabilityResponse() throws {
        try writeJSON(NaruHelperTextBridgeLive.capabilityResponse())
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

        // Spec 040: with no --token-env the listener runs from the pairing
        // state file `--pair` maintains, verifying per connection so a
        // later `--pair` rotates the token without a listener restart.
        // The explicit env path (benchmarks, CI) keeps its fixed secret.
        let stateStore = NaruHelperPairingStateStore()
        let resolvedToken: String
        var provider: (@Sendable () -> String?)?
        if let tokenVariable = optionValue(after: "--token-env"),
           !tokenVariable.isEmpty,
           let envToken = ProcessInfo.processInfo.environment[tokenVariable],
           !envToken.isEmpty
        {
            resolvedToken = envToken
        } else {
            guard let state = try? stateStore.load() else {
                FileHandle.standardError.write(
                    Data(
                        (
                            "NaruHelper listen needs --token-env VAR_NAME or a pairing state file — "
                                + "run `NaruHelper --pair` first.\n"
                        ).utf8
                    )
                )
                Darwin.exit(2)
            }
            resolvedToken = state.token
            // Spec 041 FR-007: no launch-time fallback — once the pairing
            // state file is gone (revoke), the next handshake is refused.
            let store = stateStore
            provider = { store.currentSecret() }
        }
        let token = resolvedToken

        let port = optionValue(after: "--port")
            .flatMap(UInt16.init)
            ?? UInt16(naruHelperTextBridgeDefaultPort)
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: token,
            pairingSecretProvider: provider,
            capabilityProvider: {
                NaruHelperTextBridgeLive.capabilityResponse()
            },
            insertHandler: { request in
                NaruHelperTextBridgeLive.insert(request: request)
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
        // Spec 040: the video listener may also run from the pairing state
        // file. `parse` keeps its strict env contract, so the state values
        // are injected as the env the parser reads — argv is untouched
        // when the caller supplied its own env names (benchmarks, CI).
        var arguments = CommandLine.arguments
        var environment = ProcessInfo.processInfo.environment
        var providers: (
            secret: (@Sendable () -> String?)?,
            fingerprint: (@Sendable () -> String?)?
        ) = (nil, nil)
        if !arguments.contains("--token-env") || !arguments.contains("--profile-fingerprint-env") {
            let store = NaruHelperPairingStateStore()
            guard let state = try? store.load() else {
                FileHandle.standardError.write(
                    Data(
                        (
                            "NaruHelper video listen needs --token-env/--profile-fingerprint-env "
                                + "or a pairing state file — run `NaruHelper --pair` first.\n"
                        ).utf8
                    )
                )
                Darwin.exit(2)
            }
            if !arguments.contains("--token-env") {
                arguments += ["--token-env", "NARU_HELPER_PAIRING_STATE_TOKEN"]
                environment["NARU_HELPER_PAIRING_STATE_TOKEN"] = state.token
            }
            if !arguments.contains("--profile-fingerprint-env") {
                arguments += ["--profile-fingerprint-env", "NARU_HELPER_PAIRING_STATE_FINGERPRINT"]
                environment["NARU_HELPER_PAIRING_STATE_FINGERPRINT"] = state.fingerprint
            }
            // Spec 041 FR-007: no launch-time fallback — once the pairing
            // state file is gone (revoke), the next handshake is refused.
            providers = (
                { store.currentSecret() },
                { store.currentFingerprint() }
            )
        }
        var configuration = try NaruHelperVideoListenConfiguration.parse(
            arguments: arguments,
            environment: environment
        )
        configuration.pairingSecretProvider = providers.secret
        configuration.profileFingerprintProvider = providers.fingerprint
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

    /// Spec 040: mint a fresh pairing token, print a QR the iPhone app
    /// scans, and show the fixed-catalog permission state up front — the
    /// 2026-09-04 pairing session failed on silently-lapsed permissions,
    /// so the preflight is printed, not assumed. The offer is minted
    /// through `NaruHelperPairingSession`, the same encoder path the menu
    /// bar app's pairing window uses (spec 041 FR-003).
    private static func pair() async throws {
        let text = NaruHelperTextBridgeLive.capabilityResponse()
        let video = await NaruHelperVideoCaptureCapabilityProbe.live().capability()

        print("Naru Helper — pair with Naru Remote")
        print()
        print("Permissions on this Mac:")
        print("  Accessibility   : \(text.permissionState.accessibility)")
        print("  Screen Recording: \(video.screenRecordingPermission)")
        if text.permissionState.accessibility != "granted" {
            print("    → Accessibility is missing: run with --request-text-permission and approve it.")
        }
        if video.screenRecordingPermission != .granted {
            print("    → Screen Recording is missing: run with --video-request-screen-recording-permission and approve it.")
        }
        print()

        guard let hostInfo = NaruHelperPairingHostInfo.current() else {
            FileHandle.standardError.write(
                Data(
                    (
                        "NaruHelper --pair found no Tailscale address (100.64/10) on this Mac. "
                            + "Connect the Mac to your tailnet first — Naru does not pair over public internet.\n"
                    ).utf8
                )
            )
            Darwin.exit(2)
        }

        let vncPort = optionValue(after: "--vnc-port").flatMap(UInt16.init) ?? 5900
        let vncPassword = optionValue(after: "--vnc-password-env")
            .flatMap { ProcessInfo.processInfo.environment[$0] }
        let session = try NaruHelperPairingSession.begin(
            store: NaruHelperPairingStateStore(),
            hostInfo: hostInfo,
            vncPort: vncPort,
            vncPassword: vncPassword
        )
        let url = session.offerURL

        print("A NEW pairing token was just minted — previous QRs no longer pair.")
        print()
        if let qr = NaruHelperTerminalQr.renderLines(message: url) {
            for line in qr {
                print(line)
            }
        } else {
            print("(this terminal could not render a QR — use the code below)")
        }
        print()
        print("Or paste this code in the app (QR 찍어 추가하기 → paste):")
        print(url)
        print()
        print("Start the listeners (they read the pairing state automatically):")
        print("  \(CommandLine.arguments[0]) --listen")
        print("  \(CommandLine.arguments[0]) --video-listen")
        print()
        print("Press Return to clear the code from this terminal…")
        _ = readLine()
        print(String(repeating: "\n", count: 40))
        session.end()
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
