import CryptoKit
import Foundation

/// Pure, SwiftUI-free logic for the guided Naru Helper onboarding flow
/// (spec 010). Everything here is `swift test`-able without the app
/// layer: the step machine, the CSPRNG pairing-secret generator, the
/// `sha256:` fingerprint, and the copy-able Mac setup-snippet builder.
///
/// Constitution §IV: the *raw secret* deliberately never enters any
/// value type in this file except as the transient argument to
/// `fingerprint(for:)` and the snippet-independent generator return.
/// `HelperOnboardingState` — the thing a view or a log might serialize
/// — holds only the non-secret fingerprint, never the secret itself.

// MARK: - Steps

/// Ordered position in the onboarding sheet.  `done` is the terminal
/// step after which the sheet dismisses and the editor stages the
/// generated secret for its existing Keychain save path.
public enum HelperOnboardingStep: Int, CaseIterable, Codable, Equatable, Sendable {
    case intro
    case configure
    case permissions
    case verify
    case done

    /// Short title for the sheet's navigation bar / progress label.
    public var title: String {
        switch self {
        case .intro: return "Naru Helper"
        case .configure: return "Pair Your Mac"
        case .permissions: return "Grant Permissions"
        case .verify: return "Verify"
        case .done: return "All Set"
        }
    }

    /// 1-based index for a "Step N of M" progress affordance.
    public var displayIndex: Int { rawValue + 1 }

    public static var stepCount: Int { allCases.count }

    /// The next step, or `nil` when already terminal.
    public var next: HelperOnboardingStep? {
        HelperOnboardingStep(rawValue: rawValue + 1)
    }

    /// The previous step, or `nil` when at the intro.
    public var previous: HelperOnboardingStep? {
        guard rawValue > 0 else { return nil }
        return HelperOnboardingStep(rawValue: rawValue - 1)
    }
}

// MARK: - Capabilities

/// Which helper capabilities the user is setting up.  Text and video
/// are independent (constitution §V least-privilege): a user may pair
/// only the text bridge (Accessibility) or only video (Screen
/// Recording).  Defaults to both.
public struct HelperOnboardingCapabilities: Equatable, Codable, Sendable {
    public var text: Bool
    public var video: Bool

    public init(text: Bool = true, video: Bool = true) {
        self.text = text
        self.video = video
    }

    public static let both = HelperOnboardingCapabilities(text: true, video: true)
    public static let textOnly = HelperOnboardingCapabilities(text: true, video: false)
    public static let videoOnly = HelperOnboardingCapabilities(text: false, video: true)

    /// True when at least one capability is selected; the flow should
    /// keep the text bridge as the floor if a user deselects both.
    public var hasAny: Bool { text || video }
}

// MARK: - Pairing secret + fingerprint

/// CSPRNG pairing-secret generation and the non-secret fingerprint,
/// kept in one place so the value the onboarding shows always matches
/// the value the profile editor persists on Save (spec 010 FR-005 /
/// SC-002 — no algorithm drift).
public enum HelperPairingSecret {
    /// Generate a fresh pairing secret using a cryptographically
    /// secure random source (CryptoKit `SymmetricKey(size:)` draws from
    /// the platform CSPRNG).  Encoded as unpadded base64url so the
    /// result is copy-safe in shells and URLs and carries no
    /// `+`/`/`/`=` that would need quoting.  256 bits of entropy.
    public static func generate() -> String {
        let key = SymmetricKey(size: .bits256)
        let bytes = key.withUnsafeBytes { Data($0) }
        return base64URLEncoded(bytes)
    }

    /// `sha256:` + lowercase hex of SHA-256 over the secret's UTF-8
    /// bytes.  This MUST match `ProfileEditorView`'s persisted
    /// fingerprint for the same secret; the editor delegates here.
    public static func fingerprint(for secret: String) -> String {
        let digest = SHA256.hash(data: Data(secret.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Mac setup snippet

/// Environment-variable names the Mac snippet uses for env indirection
/// (spec 010 FR-007).  The secret rides `NARU_HELPER_TOKEN`; the
/// non-secret fingerprint rides `NARU_HELPER_VIDEO_FINGERPRINT`.
/// Both helper listeners (`--listen` and `--video-listen`) reject direct
/// secret arguments and require `--token-env`, so the secret never
/// appears in argv (`ps`-visible) on the Mac.
public enum HelperOnboardingSnippetEnv {
    public static let secretVariable = "NARU_HELPER_TOKEN"
    public static let videoFingerprintVariable = "NARU_HELPER_VIDEO_FINGERPRINT"
}

/// Pure builder for the copy-able Mac setup snippet.  Assembled only
/// from non-secret inputs — the snippet text references the secret
/// through `$NARU_HELPER_TOKEN` and never embeds it (spec 010 FR-007 /
/// SP-005).  The `Copy secret` action in the view is the only place the
/// raw secret is exposed.
public enum HelperOnboardingSnippet {
    /// Path to the dev-app helper executable produced by
    /// `scripts/install-naru-helper-dev-app.sh`.  `~` expands in the
    /// user's Mac shell.
    public static let defaultHelperExecutablePath =
        "$HOME/Applications/NaruRemoteDev/NaruHelperDev.app/Contents/MacOS/NaruHelper"

    public static let installScriptPath = "./scripts/install-naru-helper-dev-app.sh"

    /// Build the snippet.  `host` is the profile host (used only in a
    /// human-readable comment so the user can confirm which Mac).
    /// `textPort` / `videoPort` default to the helper defaults.
    public static func build(
        fingerprint: String,
        host: String,
        capabilities: HelperOnboardingCapabilities = .both,
        textPort: Int = naruHelperTextBridgeDefaultPort,
        videoPort: Int = naruHelperVideoStreamDefaultPort,
        helperExecutablePath: String = defaultHelperExecutablePath,
        secretVariable: String = HelperOnboardingSnippetEnv.secretVariable,
        videoFingerprintVariable: String = HelperOnboardingSnippetEnv.videoFingerprintVariable
    ) -> String {
        var lines: [String] = []
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty {
            lines.append("# Run these in Terminal on your Mac (\(trimmedHost)).")
        } else {
            lines.append("# Run these in Terminal on your Mac.")
        }
        lines.append("# 1) Build & install the helper (one time; gives it a stable")
        lines.append("#    identity so macOS remembers its permissions).")
        lines.append("cd /path/to/naru-remote   # your Naru Remote source checkout")
        lines.append(installScriptPath)
        lines.append("")
        lines.append("# 2) Trigger the macOS permission prompts (approve them on the Mac).")
        var permissionFlags: [String] = []
        if capabilities.text {
            permissionFlags.append("--request-text-permission")   // Accessibility
        }
        if capabilities.video {
            permissionFlags.append("--request-permission")        // Screen Recording
        }
        if permissionFlags.isEmpty {
            permissionFlags.append("--request-text-permission")
        }
        lines.append("\(installScriptPath) \(permissionFlags.joined(separator: " "))")
        lines.append("")
        lines.append("# 3) Put your pairing secret in the environment.")
        lines.append("#    Paste it from the app's \"Copy secret\" action — keep it private.")
        lines.append("export \(secretVariable)='PASTE_SECRET_FROM_APP'")
        lines.append("")
        lines.append("HELPER=\"\(helperExecutablePath)\"")

        if capabilities.text {
            lines.append("")
            lines.append("# 4) Start the text bridge (needs Accessibility).")
            lines.append("\"$HELPER\" --listen --token-env \(secretVariable) --port \(textPort)")
        }

        if capabilities.video {
            lines.append("")
            lines.append("# 5) Start video in another Terminal tab (needs Screen Recording).")
            lines.append("export \(videoFingerprintVariable)='\(fingerprint)'")
            lines.append(
                "\"$HELPER\" --video-listen"
                    + " --token-env \(secretVariable)"
                    + " --profile-fingerprint-env \(videoFingerprintVariable)"
                    + " --port \(videoPort)"
            )
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Verification outcome (fixed catalog)

/// Fixed-catalog result of the verify step.  Constitution §IV: the
/// user-visible text is derived from this catalog, never from a raw
/// network/helper error.  Host-level cases come from the reachability
/// probe; helper-level cases come from `HelperTextBridgeAvailability`
/// once an in-flow handshake test is wired (spec 010 FR-013).
public enum HelperOnboardingVerification: String, Codable, Equatable, CaseIterable, Sendable {
    case notRun
    case checking
    case hostReachable
    case hostUnreachable
    case needsPassword
    case helperReachable
    case helperUnreachable
    case permissionMissing
    case revoked
    case versionUnsupported

    /// Map a helper availability into the verify catalog for the
    /// (future) in-flow handshake test.
    public static func from(helperAvailability availability: HelperTextBridgeAvailability) -> HelperOnboardingVerification {
        switch availability {
        case .notConfigured, .disabled:
            return .notRun
        case .checking:
            return .checking
        case .reachable:
            return .helperReachable
        case .unreachable:
            return .helperUnreachable
        case .permissionMissing:
            return .permissionMissing
        case .revoked:
            return .revoked
        case .versionUnsupported:
            return .versionUnsupported
        }
    }

    /// A short, safe status label.  Detailed reachability text still
    /// comes from `DiagnosticMessageCatalog` in the app layer for the
    /// host cases; this is the fixed headline.
    public var safeHeadline: String {
        switch self {
        case .notRun: return "Not tested yet"
        case .checking: return "Checking…"
        case .hostReachable: return "Mac reachable"
        case .hostUnreachable: return "Mac not reachable"
        case .needsPassword: return "Mac reachable — needs VNC password"
        case .helperReachable: return "Helper reachable"
        case .helperUnreachable: return "Helper not reachable"
        case .permissionMissing: return "Helper needs permission on the Mac"
        case .revoked: return "Helper pairing was revoked"
        case .versionUnsupported: return "Helper version is unsupported"
        }
    }

    /// True when the outcome is a positive signal the user can proceed on.
    public var isPositive: Bool {
        switch self {
        case .hostReachable, .needsPassword, .helperReachable:
            return true
        default:
            return false
        }
    }
}

// MARK: - Onboarding state (no secret)

/// Serializable, secret-free snapshot of the flow.  Safe to log or
/// persist (spec 010 SP-002 / SC-004) because it carries the non-secret
/// fingerprint and fixed-catalog values only — never the raw secret.
public struct HelperOnboardingState: Equatable, Codable, Sendable {
    public var step: HelperOnboardingStep
    public var secretGenerated: Bool
    /// Non-secret `sha256:` fingerprint of the generated secret, or nil
    /// before one is generated.
    public var fingerprint: String?
    public var capabilities: HelperOnboardingCapabilities
    public var verification: HelperOnboardingVerification

    public init(
        step: HelperOnboardingStep = .intro,
        secretGenerated: Bool = false,
        fingerprint: String? = nil,
        capabilities: HelperOnboardingCapabilities = .both,
        verification: HelperOnboardingVerification = .notRun
    ) {
        self.step = step
        self.secretGenerated = secretGenerated
        self.fingerprint = fingerprint
        self.capabilities = capabilities
        self.verification = verification
    }

    public mutating func advance() {
        if let next = step.next {
            step = next
        }
    }

    public mutating func goBack() {
        if let previous = step.previous {
            step = previous
        }
    }

    /// Record that a secret was generated, storing only its non-secret
    /// fingerprint.  The raw secret stays in the view's transient state.
    public mutating func recordGeneratedSecret(fingerprint: String) {
        secretGenerated = true
        self.fingerprint = fingerprint
    }
}
