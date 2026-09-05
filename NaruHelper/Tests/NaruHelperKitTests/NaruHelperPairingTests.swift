import Foundation
import NaruHelperKit
import NaruRemoteCore
import XCTest

/// Spec 040 FR-002 gates: the pairing state store rotates, the rotation is
/// observed per-connection by both listeners' handlers, and the terminal
/// QR renderer produces a scannable-shaped grid.
final class NaruHelperPairingTests: XCTestCase {

    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("naru-pairing-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    private func makeStore() -> NaruHelperPairingStateStore {
        NaruHelperPairingStateStore(
            fileURL: temporaryDirectory.appendingPathComponent("helper-pairing-state.json")
        )
    }

    // MARK: - State store

    func testLoadWithoutStateFileThrowsNotPaired() {
        XCTAssertThrowsError(try makeStore().load()) { error in
            XCTAssertEqual(error as? NaruHelperPairingStateError, .notPaired)
        }
    }

    func testRotateMintsFreshTokenAndMatchingFingerprint() throws {
        let store = makeStore()
        let first = try store.rotate()
        let second = try store.rotate()

        XCTAssertNotEqual(first.token, second.token, "rotation must supersede the old token")
        XCTAssertEqual(second.fingerprint, HelperPairingSecret.fingerprint(for: second.token))
        XCTAssertEqual(try store.load(), second, "the file must hold the newest state")
    }

    func testStateFileIsReadableOnlyByOwner() throws {
        let store = makeStore()
        try store.rotate()
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.int16Value ?? 0,
            0o600,
            "the pairing state carries the live secret — it must be 0600"
        )
    }

    func testCurrentSecretObservesExternalRotationWithoutRestart() throws {
        // A listener holds one store; `--pair` in another process writes
        // the file through its own store instance. The listener's
        // per-connection read must see the new token.
        let listenerStore = makeStore()
        let pairStore = makeStore()
        let first = try pairStore.rotate()

        XCTAssertEqual(listenerStore.currentSecret(), first.token)
        let second = try pairStore.rotate()
        XCTAssertEqual(listenerStore.currentSecret(), second.token)
        XCTAssertNotEqual(listenerStore.currentSecret(), first.token)
    }

    // Spec 041 FR-007 (FAIL-first): deleting the state file must revoke —
    // `currentSecret()` may not keep serving the cached token once the file
    // is gone.
    func testCurrentSecretIsNilWhenStateFileIsAbsent() throws {
        let store = makeStore()
        let state = try store.rotate()
        XCTAssertEqual(store.currentSecret(), state.token)

        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertNil(
            store.currentSecret(),
            "an absent state file means not paired — the cached token must be dropped"
        )
        XCTAssertNil(
            store.currentFingerprint(),
            "revoke must clear the fingerprint cache too"
        )
    }

    // Spec 041 FR-007: a *transient* failure (present but unreadable or
    // undecodable) keeps the last known state — a mid-read hiccup must not
    // lock every paired phone out. Absence is refusal; corruption is not.
    func testCurrentSecretKeepsCachedValueWhenStateFileIsTransientlyUnreadable() throws {
        let store = makeStore()
        let state = try store.rotate()

        try Data("not json at all".utf8).write(to: store.fileURL)
        XCTAssertEqual(
            store.currentSecret(),
            state.token,
            "an undecodable file is transient — the cache keeps serving"
        )
        XCTAssertEqual(store.currentFingerprint(), state.fingerprint)

        // 3-class defense: a decodable file whose fingerprint was not
        // derived from its token (hand-edited / malicious) is corruption,
        // not a new truth to adopt. Written with FileManager, not
        // `persist` — `persist` would legitimately refresh this store's
        // own cache with what it wrote.
        let tampered = NaruHelperPairingState(
            token: "attacker-controlled-token",
            fingerprint: "sha256:not-the-derived-fingerprint"
        )
        try JSONEncoder().encode(tampered).write(to: store.fileURL, options: [.atomic])
        XCTAssertEqual(
            store.currentSecret(),
            state.token,
            "a fingerprint that does not derive from the token must not be adopted"
        )

        // Stale schema (missing keys) decodes as failure — transient too.
        try Data(#"{"token":"x"}"#.utf8).write(to: store.fileURL)
        XCTAssertEqual(store.currentSecret(), state.token)

        // Absence — and only absence — clears it.
        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertNil(store.currentSecret())
    }

    // Spec 041 FR-007: revoke removes the file and the store immediately
    // reports not-paired on the per-connection path.
    func testRevokeRemovesFileAndClearsCurrentState() throws {
        let store = makeStore()
        let state = try store.rotate()
        XCTAssertEqual(store.currentSecret(), state.token)

        try store.revoke()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertNil(store.currentSecret())
        XCTAssertNil(store.currentFingerprint())

        // Revoking an unpaired Mac is a no-op, not an error.
        XCTAssertNoThrow(try store.revoke())
    }

    // MARK: - Revocation through the handlers (T-A2)

    func testTextHandlerRefusesWhenProviderReturnsNil() throws {
        let handler = makeTextHandler(secret: "launch-time-secret", provider: { nil })
        let request = NaruHelperNetworkRequest(
            requestID: UUID(),
            command: .capability,
            pairingSecret: "launch-time-secret",
            capabilityRequest: NaruHelperNetworkCapabilityRequest()
        )

        XCTAssertEqual(
            handler.handle(request).safeFailureCode,
            .revoked,
            "a nil provider answer means not paired — the launch-time secret must not rescue it"
        )
    }

    func testVideoAuthorizeRefusesWhenProviderReturnsNil() throws {
        let store = makeStore()
        let state = try store.rotate()
        let handler = NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: state.token,
            expectedProfileFingerprint: state.fingerprint,
            pairingSecretProvider: { nil },
            profileFingerprintProvider: { nil },
            capabilityProvider: {
                HelperVideoCapabilityResponseBody(
                    availability: .available,
                    screenRecordingPermission: .granted,
                    codecSupport: .h264,
                    latencyModes: [.lowLatency]
                )
            }
        )
        let envelope = NaruHelperVideoTransportRequestHandler.signedEnvelope(
            messageType: .capabilityRequest,
            profileFingerprint: state.fingerprint,
            pairingSecret: state.token,
            body: HelperVideoCapabilityRequestBody()
        )

        let result = handler.authorize(envelope)
        XCTAssertEqual(result.status, .rejected)
        XCTAssertEqual(
            result.safeFailureCode,
            .revoked,
            "a nil provider answer means not paired — the fixed fingerprint must not rescue it"
        )
    }

    func testRevokeRefusesFormerlyValidProofThroughBothHandlers() throws {
        // US-3 SC-004 end-to-end at the handler layer: a proof that was
        // accepted before revoke is refused with the fixed `revoked` code
        // on its very next attempt — by the text handler and the video
        // handler alike.
        let store = makeStore()
        let state = try store.rotate()
        let textHandler = makeTextHandler(
            secret: state.token,
            provider: { store.currentSecret() }
        )
        let videoHandler = NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: state.token,
            expectedProfileFingerprint: state.fingerprint,
            pairingSecretProvider: { store.currentSecret() },
            profileFingerprintProvider: { store.currentFingerprint() },
            capabilityProvider: {
                HelperVideoCapabilityResponseBody(
                    availability: .available,
                    screenRecordingPermission: .granted,
                    codecSupport: .h264,
                    latencyModes: [.lowLatency]
                )
            }
        )

        func textRequest() -> NaruHelperNetworkRequest {
            NaruHelperNetworkRequest(
                requestID: UUID(),
                command: .capability,
                pairingSecret: state.token,
                capabilityRequest: NaruHelperNetworkCapabilityRequest()
            )
        }
        func videoEnvelope() -> HelperVideoWireEnvelope<HelperVideoCapabilityRequestBody> {
            NaruHelperVideoTransportRequestHandler.signedEnvelope(
                messageType: .capabilityRequest,
                profileFingerprint: state.fingerprint,
                pairingSecret: state.token,
                body: HelperVideoCapabilityRequestBody()
            )
        }

        XCTAssertEqual(textHandler.handle(textRequest()).safeFailureCode, .none)
        XCTAssertEqual(videoHandler.authorize(videoEnvelope()).status, .accepted)

        try store.revoke()
        XCTAssertEqual(textHandler.handle(textRequest()).safeFailureCode, .revoked)
        XCTAssertEqual(
            videoHandler.authorize(videoEnvelope()).status,
            .rejected,
            "revoke must refuse the video handshake too"
        )
        XCTAssertEqual(videoHandler.authorize(videoEnvelope()).safeFailureCode, .revoked)
    }

    // MARK: - Authorized-request hook (T-A2)

    private final class HookCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    func testTextHandlerAuthorizedHookFiresOncePerAcceptedRequestAndNeverOnRefusal() throws {
        let counter = HookCounter()
        let store = makeStore()
        let state = try store.rotate()
        let handler = NaruHelperNetworkRequestHandler(
            expectedPairingSecret: state.token,
            pairingSecretProvider: { store.currentSecret() },
            onAuthorizedRequest: { counter.increment() },
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .failed,
                    strategyUsed: .unsupported
                )
            }
        )

        func request(with secret: String) -> NaruHelperNetworkRequest {
            NaruHelperNetworkRequest(
                requestID: UUID(),
                command: .capability,
                pairingSecret: secret,
                capabilityRequest: NaruHelperNetworkCapabilityRequest()
            )
        }

        XCTAssertEqual(counter.value, 0, "the hook must not fire before any request")
        XCTAssertEqual(handler.handle(request(with: state.token)).safeFailureCode, .none)
        XCTAssertEqual(handler.handle(request(with: state.token)).safeFailureCode, .none)
        XCTAssertEqual(counter.value, 2, "one fire per accepted proof")
        XCTAssertEqual(handler.handle(request(with: "wrong-secret")).safeFailureCode, .revoked)
        XCTAssertEqual(counter.value, 2, "a refused proof must not fire the hook")
    }

    func testVideoHandlerAuthorizedHookFiresOncePerAcceptedProofAndNeverOnRefusal() throws {
        let counter = HookCounter()
        let store = makeStore()
        let state = try store.rotate()
        let handler = NaruHelperVideoTransportRequestHandler(
            expectedPairingSecret: state.token,
            expectedProfileFingerprint: state.fingerprint,
            pairingSecretProvider: { store.currentSecret() },
            profileFingerprintProvider: { store.currentFingerprint() },
            onAuthorizedRequest: { counter.increment() },
            capabilityProvider: {
                HelperVideoCapabilityResponseBody(
                    availability: .available,
                    screenRecordingPermission: .granted,
                    codecSupport: .h264,
                    latencyModes: [.lowLatency]
                )
            }
        )

        func envelope(fingerprint: String) -> HelperVideoWireEnvelope<HelperVideoCapabilityRequestBody> {
            NaruHelperVideoTransportRequestHandler.signedEnvelope(
                messageType: .capabilityRequest,
                profileFingerprint: fingerprint,
                pairingSecret: state.token,
                body: HelperVideoCapabilityRequestBody()
            )
        }

        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(handler.authorize(envelope(fingerprint: state.fingerprint)).status, .accepted)
        XCTAssertEqual(counter.value, 1, "one fire per accepted proof")
        XCTAssertEqual(
            handler.authorize(envelope(fingerprint: "sha256:wrong")).status,
            .rejected
        )
        XCTAssertEqual(counter.value, 1, "a refused proof must not fire the hook")
    }

    // MARK: - Text handler rotation

    private func makeTextHandler(
        secret: String,
        provider: (@Sendable () -> String?)?
    ) -> NaruHelperNetworkRequestHandler {
        NaruHelperNetworkRequestHandler(
            expectedPairingSecret: secret,
            pairingSecretProvider: provider,
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .failed,
                    strategyUsed: .unsupported
                )
            }
        )
    }

    func testTextHandlerRefusesSupersededTokenAfterRotation() throws {
        let store = makeStore()
        let state = try store.rotate()
        let handler = makeTextHandler(
            secret: state.token,
            provider: { store.currentSecret() }
        )

        func request(with secret: String) -> NaruHelperNetworkRequest {
            NaruHelperNetworkRequest(
                requestID: UUID(),
                command: .capability,
                pairingSecret: secret,
                capabilityRequest: NaruHelperNetworkCapabilityRequest()
            )
        }

        XCTAssertEqual(handler.handle(request(with: state.token)).safeFailureCode, .none)

        let rotated = try store.rotate()
        XCTAssertEqual(
            handler.handle(request(with: state.token)).safeFailureCode,
            .revoked,
            "a photographed QR's token must be refused after the next --pair"
        )
        XCTAssertEqual(handler.handle(request(with: rotated.token)).safeFailureCode, .none)
    }

    // MARK: - Video handler rotation

    func testVideoAuthorizationFollowsRotatedState() throws {
        let store = makeStore()
        let state = try store.rotate()

        func makeHandler() -> NaruHelperVideoTransportRequestHandler {
            NaruHelperVideoTransportRequestHandler(
                expectedPairingSecret: state.token,
                expectedProfileFingerprint: state.fingerprint,
                pairingSecretProvider: { store.currentSecret() },
                profileFingerprintProvider: { store.currentFingerprint() },
                capabilityProvider: {
                    HelperVideoCapabilityResponseBody(
                        availability: .available,
                        screenRecordingPermission: .granted,
                        codecSupport: .h264,
                        latencyModes: [.lowLatency]
                    )
                }
            )
        }

        func envelope(signedWith secret: String, fingerprint: String)
            -> HelperVideoWireEnvelope<HelperVideoCapabilityRequestBody>
        {
            NaruHelperVideoTransportRequestHandler.signedEnvelope(
                messageType: .capabilityRequest,
                profileFingerprint: fingerprint,
                pairingSecret: secret,
                body: HelperVideoCapabilityRequestBody()
            )
        }

        let handler = makeHandler()
        let before = handler.authorize(envelope(signedWith: state.token, fingerprint: state.fingerprint))
        XCTAssertEqual(before.status, .accepted)

        let rotated = try store.rotate()
        let oldProof = handler.authorize(envelope(signedWith: state.token, fingerprint: state.fingerprint))
        XCTAssertEqual(
            oldProof.status,
            .rejected,
            "video must refuse the superseded fingerprint/secret pair"
        )
        let newProof = handler.authorize(
            envelope(signedWith: rotated.token, fingerprint: rotated.fingerprint)
        )
        XCTAssertEqual(newProof.status, .accepted)
    }

    // MARK: - Terminal QR

    func testQrRendersStructuredHalfBlockGrid() throws {
        let token = HelperPairingSecret.generate()
        let offer = NaruPairingOffer(
            host: .init(label: "Test Mac", addresses: ["100.64.0.1"]),
            helper: .init(token: token, fingerprint: HelperPairingSecret.fingerprint(for: token))
        )
        let message = try NaruPairingOfferWire.encode(offer)

        let lines = try XCTUnwrap(NaruHelperTerminalQr.renderLines(message: message))
        XCTAssertGreaterThanOrEqual(lines.count, 14, "v1 QR + quiet zone must be at least 14 half-block rows")
        let widths = Set(lines.map(\.count))
        XCTAssertEqual(widths.count, 1, "every line must be the same width for a monospace grid")
        let alphabet = Set("█▀▄ ")
        for line in lines {
            XCTAssertTrue(
                line.allSatisfy { alphabet.contains($0) },
                "only half-block glyphs and spaces may appear"
            )
        }
        // Quiet zone: the outermost character rows/columns are blank.
        XCTAssertTrue(lines.first!.allSatisfy { $0 == " " })
        XCTAssertTrue(lines.last!.allSatisfy { $0 == " " })
        XCTAssertTrue(lines.allSatisfy { $0.first == " " && $0.last == " " })
    }

    func testQrOutputContainsNoSecretOutsideTheCode() throws {
        // The QR *is* the credential carrier; the renderer must not leak
        // the token into any other form (no debug print path exists here —
        // the assertion pins the API to lines-of-glyphs only).
        let token = HelperPairingSecret.generate()
        let offer = NaruPairingOffer(
            host: .init(label: "Test Mac", addresses: ["100.64.0.1"]),
            helper: .init(token: token, fingerprint: HelperPairingSecret.fingerprint(for: token))
        )
        let lines = try XCTUnwrap(NaruHelperTerminalQr.renderLines(message: try NaruPairingOfferWire.encode(offer)))
        for line in lines {
            XCTAssertFalse(line.contains(token))
        }
    }
}
