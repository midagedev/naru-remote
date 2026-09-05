import Foundation
import NaruRemoteCore

#if canImport(Network)

/// Owns both helper listeners in one process (spec 041 FR-002): the text
/// bridge server and the video server are built here from one pairing
/// store, so the menu bar app never wires two processes or two stores.
///
/// Both handlers read the pairing state **per request** through the store
/// (`{ store.currentSecret() }` / `{ store.currentFingerprint() }`), which
/// is what makes rotation and revoke take effect on the next handshake
/// without a restart (spec 040 FR-002 / spec 041 FR-007). There is
/// deliberately no launch-time secret to fall back to — `store` is the
/// single owner of the truth. A shared `onAuthorizedRequest` fires from
/// both handlers, which is the app's "a phone just paired" signal.
public final class NaruHelperListenerRuntime: @unchecked Sendable {
    private let textServer: NaruHelperNetworkServer
    private let videoServer: NaruHelperVideoStreamNetworkServer

    /// Per-listener state, relayed from both servers. Settable before or
    /// after ``start()``. Delivered on the listeners' dispatch queues.
    public var onStateChange: (@Sendable (NaruHelperListenerKind, NaruHelperListenerState) -> Void)? {
        didSet { relayStateHandlers() }
    }

    public init(
        store: NaruHelperPairingStateStore,
        textPort: UInt16 = UInt16(naruHelperTextBridgeDefaultPort),
        videoPort: UInt16 = UInt16(naruHelperVideoStreamDefaultPort),
        onAuthorizedRequest: (@Sendable () -> Void)? = nil,
        capabilityProvider: @escaping NaruHelperNetworkRequestHandler.CapabilityProvider,
        insertHandler: @escaping NaruHelperNetworkRequestHandler.InsertHandler,
        videoSourceMode: NaruHelperVideoListenSourceMode = .screenCaptureKit,
        videoFrameCount: Int = 0,
        videoAccessUnitSource: (any NaruHelperVideoAccessUnitSource)? = nil
    ) throws {
        let textHandler = NaruHelperNetworkRequestHandler(
            // Providers are attached below, so the fixed secret is never
            // consulted — the empty string states "no launch-time secret"
            // rather than smuggling one in.
            expectedPairingSecret: "",
            pairingSecretProvider: { store.currentSecret() },
            onAuthorizedRequest: onAuthorizedRequest,
            capabilityProvider: capabilityProvider,
            insertHandler: insertHandler
        )
        self.textServer = try NaruHelperNetworkServer(port: textPort, handler: textHandler)

        var videoConfiguration = NaruHelperVideoListenConfiguration(
            pairingSecret: "",
            profileFingerprint: "",
            port: videoPort,
            sourceMode: videoSourceMode,
            frameCount: videoFrameCount
        )
        videoConfiguration.pairingSecretProvider = { store.currentSecret() }
        videoConfiguration.profileFingerprintProvider = { store.currentFingerprint() }
        self.videoServer = try NaruHelperVideoListenRuntime(
            configuration: videoConfiguration
        ).makeServer(
            accessUnitSource: videoAccessUnitSource,
            onAuthorizedRequest: onAuthorizedRequest
        )
    }

    public func start() {
        relayStateHandlers()
        textServer.start()
        videoServer.start()
    }

    public func stop() {
        textServer.cancel()
        videoServer.cancel()
    }

    private func relayStateHandlers() {
        var textRelay: (@Sendable (NaruHelperListenerState) -> Void)?
        var videoRelay: (@Sendable (NaruHelperListenerState) -> Void)?
        if let relay = onStateChange {
            textRelay = { state in relay(.text, state) }
            videoRelay = { state in relay(.video, state) }
        }
        textServer.onStateChange = textRelay
        videoServer.onStateChange = videoRelay
    }
}
#endif
