import Foundation
import NaruRemoteApp
import NaruRemoteCore

/// XCUITest screenshot hook — selects a synthetic
/// `NaruRemoteAppSnapshot` (and any post-init model mutations that
/// don't fit on the snapshot value type) so the audit harness
/// (`UXAuditScreenshotsUITests`) can drive states the live persistence
/// path cannot reach without a real RFB session.
///
/// The fixture is selected by the `NARU_TEST_FIXTURE_SNAPSHOT` launch
/// environment variable.  When the variable is unset (production) the
/// hook is fully inert: `loadFixtureSnapshot()` returns `nil`, the
/// shell builds a fresh empty model the same way it always has, and
/// `applyFixturePostInitMutations()` short-circuits.
///
/// All fixtures reuse existing `NaruRemoteCore` value types — we do
/// not fabricate new model types for the audit (constraint per
/// `chore/ux-02-audit-fixture-richness`).
enum UXAuditFixtureToken: String {
    case diagnosticsPopulated = "diagnostics-populated"
    case onboardingProgress = "onboarding-progress"
    case onboardingDone = "onboarding-done"
    case diagnosticErrorDNS = "diagnostic-error-dns"
    case incomingClipboard = "incoming-clipboard"

    static func current() -> UXAuditFixtureToken? {
        guard let raw = ProcessInfo.processInfo.environment["NARU_TEST_FIXTURE_SNAPSHOT"],
              !raw.isEmpty
        else { return nil }
        return UXAuditFixtureToken(rawValue: raw)
    }
}

enum UXAuditFixtures {
    /// Builds the snapshot for the currently-selected fixture token,
    /// or `nil` when the env var is unset / unrecognised.  The shell
    /// passes the snapshot to `NaruRemoteAppModel(snapshot:)` so the
    /// model lands in the desired UI state on first paint.
    static func loadFixtureSnapshot() -> NaruRemoteAppSnapshot? {
        guard let token = UXAuditFixtureToken.current() else {
            return nil
        }
        switch token {
        case .diagnosticsPopulated:
            return diagnosticsPopulatedSnapshot()
        case .onboardingProgress:
            return onboardingProgressSnapshot()
        case .onboardingDone:
            return onboardingDoneSnapshot()
        case .diagnosticErrorDNS:
            return diagnosticErrorDNSSnapshot()
        case .incomingClipboard:
            return incomingClipboardSnapshot()
        }
    }

    /// Some screen states (notably the incoming-clipboard banner)
    /// live on the model directly rather than on
    /// `NaruRemoteAppSnapshot`.  Apply those after the model is
    /// constructed.  No-op when the env var is unset.
    @MainActor
    static func applyFixturePostInitMutations(to model: NaruRemoteAppModel) {
        guard let token = UXAuditFixtureToken.current() else {
            return
        }
        switch token {
        case .incomingClipboard:
            // Calling `recordIncomingClipboard` is the canonical path
            // a real `ServerCutText` would take through the model —
            // it sets `pendingIncomingClipboard` to a fresh review.
            model.recordIncomingClipboard(
                "Hello from the remote computer — this is a clipboard payload that arrived from the VNC server."
            )
        case .diagnosticsPopulated,
             .onboardingProgress,
             .onboardingDone,
             .diagnosticErrorDNS:
            // All snapshot-driven; no post-init mutation needed.
            break
        }
    }

    // MARK: - Fixture builders

    private static func diagnosticsPopulatedSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 4),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Host resolved",
                    safeDetail: "MagicDNS returned a private address.",
                    timestamp: fixedDate(offsetSeconds: 1)
                ),
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .passed,
                    safeTitle: "VNC port open",
                    safeDetail: "TCP connection to the VNC port succeeded.",
                    timestamp: fixedDate(offsetSeconds: 2)
                ),
                DiagnosticStageResult(
                    stage: .rfbHandshake,
                    status: .passed,
                    safeTitle: "RFB handshake complete",
                    safeDetail: "Server speaks a compatible RFB version.",
                    timestamp: fixedDate(offsetSeconds: 3)
                ),
                DiagnosticStageResult(
                    stage: .authentication,
                    status: .running,
                    safeTitle: "Authenticating",
                    safeDetail: "Negotiating credentials with the VNC server.",
                    timestamp: fixedDate(offsetSeconds: 4)
                )
            ]
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: run
        )
    }

    private static func onboardingProgressSnapshot() -> NaruRemoteAppSnapshot {
        // Step 1 (private target) complete via the seeded profile.
        // Step 2 (diagnostics) complete via a passing run.
        // Step 3 (compose) is still .waiting because there's no
        // active `RemoteSession` — that's the "Compose locally"
        // active step the punch list calls for.
        let profile = sampleProfile()
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 4),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Host resolved",
                    safeDetail: "MagicDNS returned a private address.",
                    timestamp: fixedDate(offsetSeconds: 1)
                ),
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .passed,
                    safeTitle: "VNC port open",
                    safeDetail: "TCP connection to the VNC port succeeded.",
                    timestamp: fixedDate(offsetSeconds: 2)
                ),
                DiagnosticStageResult(
                    stage: .rfbHandshake,
                    status: .passed,
                    safeTitle: "RFB handshake complete",
                    safeDetail: "Server speaks a compatible RFB version.",
                    timestamp: fixedDate(offsetSeconds: 3)
                )
            ]
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: run
        )
    }

    private static func onboardingDoneSnapshot() -> NaruRemoteAppSnapshot {
        // Mirrors `OnboardingReadyTests.makeCompleteSnapshot`: a
        // private profile, a passing diagnostic run, an .active
        // session whose lastFrameAt is set (so `allowsPiPWatch`
        // flips true), and a .watching PiP session.
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 4),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Host resolved",
                    safeDetail: "MagicDNS returned a private address.",
                    timestamp: fixedDate(offsetSeconds: 1)
                ),
                DiagnosticStageResult(
                    stage: .firstFrame,
                    status: .passed,
                    safeTitle: "First frame received",
                    safeDetail: "Remote framebuffer is available.",
                    timestamp: fixedDate(offsetSeconds: 4)
                )
            ]
        )
        let pipSession = PiPWatchSession(
            sessionID: session.id,
            state: .watching
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            diagnosticRun: run,
            pipWatchSession: pipSession
        )
    }

    private static func diagnosticErrorDNSSnapshot() -> NaruRemoteAppSnapshot {
        let profile = sampleProfile()
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            startedAt: fixedDate(offsetSeconds: 0),
            finishedAt: fixedDate(offsetSeconds: 2),
            stages: [
                DiagnosticMessageCatalog.failure(
                    for: .dns,
                    timestamp: fixedDate(offsetSeconds: 2)
                )
            ]
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: run
        )
    }

    private static func incomingClipboardSnapshot() -> NaruRemoteAppSnapshot {
        // Need an .active session so the dock + banner are mounted
        // in their post-connect form (the banner sits inside the
        // detail safeAreaInset and renders whenever
        // `pendingIncomingClipboard != nil`, but the surrounding
        // layout reads more naturally with a live session).
        let profile = sampleProfile()
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: fixedDate(offsetSeconds: 5)
        )
        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session
        )
    }

    // MARK: - Shared building blocks

    /// Stable-ID profile so multiple-fixture screenshots share the
    /// same selection target if the test suite ever cross-references
    /// them.  `try!` is fine here — the hard-coded values satisfy
    /// `ConnectionProfile`'s validation.
    private static func sampleProfile() -> ConnectionProfile {
        // swiftlint:disable:next force_try
        try! ConnectionProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            displayName: "Studio Mac",
            host: "studio.tailnet.ts.net",
            port: 5900,
            hostKind: .magicDNS
        )
    }

    /// Fixed reference date so screenshots are pixel-stable across
    /// runs (no "seconds ago" labels jitter the diff).
    private static func fixedDate(offsetSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offsetSeconds)
    }
}
