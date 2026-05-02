import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class ProfileEditorReachabilityTests: XCTestCase {
    // MARK: - Validation gates (no connector touched)

    func testReturnsFailedVerdictWhenHostIsBlank() async {
        let connector = FakeReachabilityConnector(behavior: .succeed)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "   ",
            port: 5900,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertEqual(outcome.safeMessage, "Host is required.")
        XCTAssertEqual(connector.requestCount, 0, "blank host must short-circuit before reaching connector")
    }

    func testReturnsFailedVerdictWhenPortOutOfRange() async {
        let connector = FakeReachabilityConnector(behavior: .succeed)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 0,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertEqual(outcome.safeMessage, "Port must be between 1 and 65535.")
        XCTAssertEqual(connector.requestCount, 0)
    }

    // MARK: - Success paths

    func testReturnsPassedVerdictWhenNoAuthHandshakeSucceeds() async {
        let connector = FakeReachabilityConnector(behavior: .succeed)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .passed)
        XCTAssertTrue(outcome.safeMessage.contains("studio.tailnet.ts.net:5900"))
        XCTAssertTrue(outcome.safeMessage.contains("reachable"))
        XCTAssertTrue(outcome.safeMessage.contains("no password required"))
    }

    func testReturnsPassedVerdictWithPasswordRequiredWhenNoAuthRejected() async {
        // Server advertises VNC-Authentication but the editor's no-auth
        // probe (no password supplied) maps the
        // `.authenticationRequired` throw to a positive-reachability
        // verdict — the host is up, the user just needs to add a
        // password before connecting.
        let connector = FakeReachabilityConnector(behavior: .throwAuthenticationRequired)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .passed)
        XCTAssertTrue(outcome.safeMessage.contains("studio.tailnet.ts.net:5900"))
        XCTAssertTrue(outcome.safeMessage.contains("requires VNC password"))
    }

    // MARK: - Failure paths

    func testReturnsFailedVerdictWhenTCPConnectionFails() async {
        let connector = FakeReachabilityConnector(behavior: .throwConnectionFailed)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertTrue(outcome.safeMessage.contains("studio.tailnet.ts.net:5900"))
        // Catalog message for the TCP stage (constitution §IV: never
        // the raw `RFBNetworkClientError` description).  Asserts the
        // first sentence — leaves room for future copy iteration on
        // the macOS-specific guidance.
        XCTAssertTrue(
            outcome.safeMessage.contains("VNC port did not respond"),
            "expected TCP catalog detail, got: \(outcome.safeMessage)"
        )
    }

    func testReturnsFailedVerdictWhenHandshakeIncomplete() async {
        let connector = FakeReachabilityConnector(behavior: .throwIncompleteTranscript)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertTrue(outcome.safeMessage.contains("studio.tailnet.ts.net:5900"))
        XCTAssertTrue(
            outcome.safeMessage.contains("did not offer a compatible RFB security type"),
            "expected handshake catalog detail, got: \(outcome.safeMessage)"
        )
    }

    func testReturnsFailedVerdictWhenGenericErrorThrown() async {
        let connector = FakeReachabilityConnector(behavior: .throwGeneric)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: nil
        )

        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertTrue(outcome.safeMessage.contains("studio.tailnet.ts.net:5900"))
    }

    func testReturnsFailedVerdictWithAuthStageWhenServerRejectsPassword() async {
        // Real macOS Screen Sharing surfaces a wrong-password as
        // `RFBProtocolDecoderError.securityFailed(1)` — pre-fix, that
        // collapsed into the generic catch and rendered the wrong
        // "VNC handshake failed" message.  With the dedicated
        // `RFBProtocolDecoderError` catch + `Self.stage(for:)`
        // overload the editor must now route this to the
        // authentication catalog, which carries the macOS-specific
        // separate-VNC-password / 8-char hint.
        let connector = FakeAuthenticatedReachabilityConnector(behavior: .throwSecurityFailed)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: "wrongpw"
        )

        XCTAssertEqual(outcome.verdict, .failed)
        XCTAssertTrue(outcome.safeMessage.contains("studio.tailnet.ts.net:5900"))
        // Assert on the first sentence only — keeps the test resilient
        // to minor copy iteration on the macOS-specific guidance that
        // follows.
        XCTAssertTrue(
            outcome.safeMessage.contains("VNC password was rejected"),
            "expected authentication catalog detail, got: \(outcome.safeMessage)"
        )
    }

    // MARK: - Side-effect-free guarantee

    func testReachabilityTestDoesNotMutateSessionOrDiagnosticState() async throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let connector = FakeReachabilityConnector(behavior: .succeed)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            connectorFactory: { connector }
        )

        // Capture pre-test state.
        let priorSession = model.snapshot.session
        let priorDiagnostic = model.snapshot.diagnosticRun
        let priorVerdictMap = model.snapshot.lastDiagnosticVerdict

        _ = await model.runProfileEditorReachabilityTest(
            host: "candidate.tailnet.ts.net",
            port: 5901,
            password: nil
        )

        XCTAssertEqual(model.snapshot.session, priorSession)
        XCTAssertEqual(model.snapshot.diagnosticRun, priorDiagnostic)
        XCTAssertEqual(model.snapshot.lastDiagnosticVerdict, priorVerdictMap)
        XCTAssertNil(model.snapshot.latestFramebuffer)
    }

    // MARK: - Authenticated path forwarded to connector

    func testPasswordIsForwardedToAuthenticatedConnector() async {
        let connector = FakeAuthenticatedReachabilityConnector(behavior: .succeed)
        let model = NaruRemoteAppModel(connectorFactory: { connector })

        let outcome = await model.runProfileEditorReachabilityTest(
            host: "studio.tailnet.ts.net",
            port: 5900,
            password: "swordfish"
        )

        XCTAssertEqual(outcome.verdict, .passed)
        XCTAssertTrue(outcome.safeMessage.contains("requires VNC password"))
        XCTAssertEqual(connector.recordedCredentials, [.vncPassword("swordfish")])
    }
}

// MARK: - Fakes

private enum FakeReachabilityBehavior: Sendable {
    case succeed
    case throwConnectionFailed
    case throwIncompleteTranscript
    case throwAuthenticationRequired
    /// Mirrors what real macOS Screen Sharing sends back on a wrong
    /// VNC password: `RFBProtocolDecoderError.securityFailed(1)`
    /// thrown out of `parseSecurityResult`.  Without an explicit
    /// catch, callers mis-stage this as `.rfbHandshake`.
    case throwSecurityFailed
    case throwGeneric
}

private struct FakeUnknownError: Error {}

private final class FakeReachabilityConnector: RFBFirstFrameConnecting {
    private struct Storage {
        var requestCount: Int = 0
    }

    private let storage: OSAllocatedUnfairLock<Storage>
    private let behavior: FakeReachabilityBehavior

    init(behavior: FakeReachabilityBehavior) {
        self.behavior = behavior
        self.storage = OSAllocatedUnfairLock(initialState: Storage())
    }

    var state: RFBClientState { .disconnected }
    var lastFrame: RFBFrameMetadata? { nil }

    var requestCount: Int {
        storage.withLock { $0.requestCount }
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        storage.withLock { $0.requestCount += 1 }
        switch behavior {
        case .succeed:
            return Self.makeServerInit()
        case .throwConnectionFailed:
            throw RFBNetworkClientError.connectionFailed
        case .throwIncompleteTranscript:
            throw RFBNetworkClientError.incompleteTranscript(expected: 62, actual: 0)
        case .throwAuthenticationRequired:
            throw RFBNetworkClientError.authenticationRequired([2])
        case .throwSecurityFailed:
            throw RFBProtocolDecoderError.securityFailed(1)
        case .throwGeneric:
            throw FakeUnknownError()
        }
    }

    private static func makeServerInit() -> RFBServerInit {
        RFBServerInit(
            width: 1440,
            height: 900,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: "Test"
        )
    }
}

private final class FakeAuthenticatedReachabilityConnector: RFBAuthenticatedFirstFrameConnecting {
    private struct Storage {
        var credentials: [RFBConnectionCredential] = []
    }

    private let storage: OSAllocatedUnfairLock<Storage>
    private let behavior: FakeReachabilityBehavior

    init(behavior: FakeReachabilityBehavior) {
        self.behavior = behavior
        self.storage = OSAllocatedUnfairLock(initialState: Storage())
    }

    var state: RFBClientState { .disconnected }
    var lastFrame: RFBFrameMetadata? { nil }

    var recordedCredentials: [RFBConnectionCredential] {
        storage.withLock { $0.credentials }
    }

    func connectNoAuthFirstFrame(
        host: String,
        port: UInt16,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        // Authenticated path always routes through `connectFirstFrame`.
        // The model only falls back to this when the connector does
        // not adopt `RFBAuthenticatedFirstFrameConnecting`, so this
        // path should not be exercised in the password-supplied tests.
        throw RFBNetworkClientError.authenticationRequired([2])
    }

    func connectFirstFrame(
        host: String,
        port: UInt16,
        credential: RFBConnectionCredential,
        timeout: TimeInterval
    ) throws -> RFBServerInit {
        storage.withLock { $0.credentials.append(credential) }
        switch behavior {
        case .succeed:
            return RFBServerInit(
                width: 1440,
                height: 900,
                pixelFormat: RFBPixelFormat(
                    bitsPerPixel: 32,
                    depth: 24,
                    isBigEndian: false,
                    isTrueColor: true,
                    redMax: 255,
                    greenMax: 255,
                    blueMax: 255,
                    redShift: 16,
                    greenShift: 8,
                    blueShift: 0
                ),
                name: "Test"
            )
        case .throwConnectionFailed:
            throw RFBNetworkClientError.connectionFailed
        case .throwIncompleteTranscript:
            throw RFBNetworkClientError.incompleteTranscript(expected: 62, actual: 0)
        case .throwAuthenticationRequired:
            throw RFBNetworkClientError.authenticationRequired([2])
        case .throwSecurityFailed:
            throw RFBProtocolDecoderError.securityFailed(1)
        case .throwGeneric:
            throw FakeUnknownError()
        }
    }
}
