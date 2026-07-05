import CryptoKit
import XCTest
@testable import NaruRemoteCore

final class HelperOnboardingTests: XCTestCase {

    // MARK: - Secret generation (FR-004)

    func testGeneratedSecretIsBase64URLAndHighEntropy() {
        let secret = HelperPairingSecret.generate()
        // 32 bytes → 43 unpadded base64url chars.
        XCTAssertEqual(secret.count, 43)
        // base64url alphabet only: A-Z a-z 0-9 - _  (no +, /, =).
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertNil(
            secret.rangeOfCharacter(from: allowed.inverted),
            "secret must be copy-safe base64url"
        )
        XCTAssertFalse(secret.contains("+"))
        XCTAssertFalse(secret.contains("/"))
        XCTAssertFalse(secret.contains("="))
    }

    func testGeneratedSecretsAreDistinct() {
        var seen = Set<String>()
        for _ in 0..<256 {
            let secret = HelperPairingSecret.generate()
            XCTAssertFalse(seen.contains(secret), "CSPRNG produced a duplicate")
            seen.insert(secret)
        }
        XCTAssertEqual(seen.count, 256)
    }

    // MARK: - Fingerprint (FR-005 / SC-002 parity)

    func testFingerprintFormatAndDeterminism() {
        let secret = "example-pairing-secret"
        let first = HelperPairingSecret.fingerprint(for: secret)
        let second = HelperPairingSecret.fingerprint(for: secret)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("sha256:"))
        // sha256: prefix + 64 hex chars.
        XCTAssertEqual(first.count, "sha256:".count + 64)
        let hex = String(first.dropFirst("sha256:".count))
        XCTAssertNil(
            hex.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted),
            "fingerprint hex must be lowercase hex"
        )
    }

    func testFingerprintMatchesProfileEditorAlgorithm() {
        // ProfileEditorView computes: "sha256:" + SHA256(secret utf8) hex.
        // This asserts the Core helper reproduces that byte-for-byte so
        // the onboarding-displayed fingerprint equals the persisted one.
        let secret = HelperPairingSecret.generate()
        let digest = SHA256.hash(data: Data(secret.utf8))
        let expected = "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(HelperPairingSecret.fingerprint(for: secret), expected)
    }

    // MARK: - Snippet builder (FR-006 / FR-007)

    func testSnippetContainsSetupCommandsAndPorts() {
        let fingerprint = HelperPairingSecret.fingerprint(for: "s")
        let snippet = HelperOnboardingSnippet.build(
            fingerprint: fingerprint,
            host: "studio.tailnet.ts.net",
            capabilities: .both
        )
        XCTAssertTrue(snippet.contains("install-naru-helper-dev-app.sh"))
        XCTAssertTrue(snippet.contains("--request-text-permission"))
        XCTAssertTrue(snippet.contains("--request-permission"))
        XCTAssertTrue(snippet.contains("--listen"))
        XCTAssertTrue(snippet.contains("--video-listen"))
        XCTAssertTrue(snippet.contains("--port \(naruHelperTextBridgeDefaultPort)"))
        XCTAssertTrue(snippet.contains("--port \(naruHelperVideoStreamDefaultPort)"))
        XCTAssertTrue(snippet.contains("studio.tailnet.ts.net"))
    }

    func testSnippetUsesEnvIndirectionAndNeverEmbedsSecret() {
        // A real, high-entropy secret must never appear in the snippet.
        let secret = HelperPairingSecret.generate()
        let fingerprint = HelperPairingSecret.fingerprint(for: secret)
        let snippet = HelperOnboardingSnippet.build(
            fingerprint: fingerprint,
            host: "mac.local",
            capabilities: .both
        )
        XCTAssertFalse(snippet.contains(secret), "snippet must not embed the secret")
        // Env indirection: both launch lines read the secret via --token-env,
        // so the value never rides argv (`ps`-visible) on the Mac.
        XCTAssertTrue(snippet.contains("--listen --token-env \(HelperOnboardingSnippetEnv.secretVariable)"))
        XCTAssertTrue(snippet.contains("--video-listen"))
        XCTAssertFalse(snippet.contains("--token \""), "secret must never ride argv")
        // The fingerprint (non-secret) is allowed to appear for video.
        XCTAssertTrue(snippet.contains(fingerprint))
        XCTAssertTrue(snippet.contains("--profile-fingerprint-env"))
    }

    func testSnippetTextOnlyOmitsVideoLine() {
        let snippet = HelperOnboardingSnippet.build(
            fingerprint: HelperPairingSecret.fingerprint(for: "s"),
            host: "mac.local",
            capabilities: .textOnly
        )
        XCTAssertTrue(snippet.contains("--listen"))
        XCTAssertFalse(snippet.contains("--video-listen"))
        XCTAssertTrue(snippet.contains("--request-text-permission"))
        XCTAssertFalse(snippet.contains("--request-permission "))
    }

    func testSnippetVideoOnlyOmitsTextLine() {
        let snippet = HelperOnboardingSnippet.build(
            fingerprint: HelperPairingSecret.fingerprint(for: "s"),
            host: "mac.local",
            capabilities: .videoOnly
        )
        XCTAssertTrue(snippet.contains("--video-listen"))
        XCTAssertFalse(snippet.contains("\"$HELPER\" --listen"))
    }

    // MARK: - Step machine (FR-002)

    func testStepOrderingForwardAndBack() {
        XCTAssertEqual(HelperOnboardingStep.allCases,
                       [.intro, .configure, .permissions, .verify, .done])
        XCTAssertEqual(HelperOnboardingStep.intro.next, .configure)
        XCTAssertEqual(HelperOnboardingStep.verify.next, .done)
        XCTAssertNil(HelperOnboardingStep.done.next)
        XCTAssertNil(HelperOnboardingStep.intro.previous)
        XCTAssertEqual(HelperOnboardingStep.done.previous, .verify)
        XCTAssertEqual(HelperOnboardingStep.intro.displayIndex, 1)
        XCTAssertEqual(HelperOnboardingStep.stepCount, 5)
    }

    func testStateAdvanceAndBackAndRecord() {
        var state = HelperOnboardingState()
        XCTAssertEqual(state.step, .intro)
        state.advance()
        XCTAssertEqual(state.step, .configure)
        state.recordGeneratedSecret(fingerprint: "sha256:abc")
        XCTAssertTrue(state.secretGenerated)
        XCTAssertEqual(state.fingerprint, "sha256:abc")
        state.goBack()
        XCTAssertEqual(state.step, .intro)
        // goBack at the floor is a no-op.
        state.goBack()
        XCTAssertEqual(state.step, .intro)
    }

    func testCapabilitiesHelpers() {
        XCTAssertTrue(HelperOnboardingCapabilities.both.hasAny)
        XCTAssertTrue(HelperOnboardingCapabilities.textOnly.text)
        XCTAssertFalse(HelperOnboardingCapabilities.textOnly.video)
        XCTAssertFalse(HelperOnboardingCapabilities(text: false, video: false).hasAny)
    }

    // MARK: - Privacy (SP-002 / SC-004)

    func testOnboardingStateEncodingCarriesNoSecret() throws {
        let secret = HelperPairingSecret.generate()
        var state = HelperOnboardingState()
        state.advance()
        state.recordGeneratedSecret(fingerprint: HelperPairingSecret.fingerprint(for: secret))
        let data = try JSONEncoder().encode(state)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(secret), "serialized state must never contain the raw secret")
        XCTAssertTrue(json.contains("sha256:"), "state keeps only the non-secret fingerprint")
    }

    // MARK: - Verification mapping (FR-010 / FR-013)

    func testVerificationMappingFromHelperAvailability() {
        XCTAssertEqual(HelperOnboardingVerification.from(helperAvailability: .reachable), .helperReachable)
        XCTAssertEqual(HelperOnboardingVerification.from(helperAvailability: .unreachable), .helperUnreachable)
        XCTAssertEqual(HelperOnboardingVerification.from(helperAvailability: .permissionMissing), .permissionMissing)
        XCTAssertEqual(HelperOnboardingVerification.from(helperAvailability: .revoked), .revoked)
        XCTAssertEqual(HelperOnboardingVerification.from(helperAvailability: .checking), .checking)
        XCTAssertEqual(HelperOnboardingVerification.from(helperAvailability: .notConfigured), .notRun)
        XCTAssertTrue(HelperOnboardingVerification.helperReachable.isPositive)
        XCTAssertTrue(HelperOnboardingVerification.hostReachable.isPositive)
        XCTAssertFalse(HelperOnboardingVerification.helperUnreachable.isPositive)
    }
}
