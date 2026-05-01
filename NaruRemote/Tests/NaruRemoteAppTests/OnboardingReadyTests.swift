import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class OnboardingReadyTests: XCTestCase {
    /// Build a snapshot whose `OnboardingGuide` evaluates to fully
    /// complete: a private MagicDNS profile, a passing diagnostic
    /// run, an active remote session (so the compose step is ready),
    /// and a `.watching` PiP watch session.  Mirrors the same
    /// inputs `OnboardingGuide` already covers in
    /// `Sources/NaruRemoteCore/Onboarding/OnboardingGuide.swift`.
    private func makeCompleteSnapshot() throws -> NaruRemoteAppSnapshot {
        let profile = try ConnectionProfile(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            hostKind: .magicDNS
        )
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let diagnosticRun = ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(timeIntervalSince1970: 200),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .firstFrame,
                    status: .passed,
                    safeTitle: "First frame received",
                    safeDetail: "Remote framebuffer is available."
                )
            ]
        )
        let pipWatchSession = PiPWatchSession(
            sessionID: session.id,
            state: .watching
        )

        return NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            diagnosticRun: diagnosticRun,
            pipWatchSession: pipWatchSession
        )
    }

    func testReadyStateExposedWhenChecklistCompleteAndNotDismissed() throws {
        let snapshot = try makeCompleteSnapshot()
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(
            snapshot: snapshot,
            settingsPersistence: persistence
        )

        XCTAssertTrue(model.snapshot.onboardingGuide.isComplete)
        XCTAssertFalse(model.appSettings.dismissedOnboardingChecklist)
        XCTAssertTrue(model.showsOnboardingReady)
        XCTAssertFalse(model.showsOnboardingGuide)
    }

    func testDismissingReadyAffirmationFlipsPersistedFlag() throws {
        let snapshot = try makeCompleteSnapshot()
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(
            snapshot: snapshot,
            settingsPersistence: persistence
        )

        model.dismissOnboardingChecklist()

        XCTAssertTrue(model.appSettings.dismissedOnboardingChecklist)
        let stored = try persistence.load()
        XCTAssertTrue(stored.dismissedOnboardingChecklist)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testReadyAndGuideBothHiddenAfterDismissal() throws {
        let snapshot = try makeCompleteSnapshot()
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(
            snapshot: snapshot,
            settingsPersistence: persistence
        )

        XCTAssertTrue(model.showsOnboardingReady)

        model.dismissOnboardingChecklist()

        XCTAssertFalse(model.showsOnboardingGuide)
        XCTAssertFalse(model.showsOnboardingReady)
    }

    func testReadyHiddenWhileChecklistIncompleteRegardlessOfDismissal() throws {
        // Profile-only snapshot: diagnostics, compose, and PiP
        // steps are still pending → guide is incomplete.  The
        // ready-affirmation must stay hidden whether or not the
        // dismiss flag is set, otherwise a half-finished checklist
        // could pop a celebratory banner.
        let profile = try ConnectionProfile(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            hostKind: .magicDNS
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id
        )

        let pristine = NaruRemoteAppModel(
            snapshot: snapshot,
            settingsPersistence: InMemoryAppSettingsPersistence()
        )
        XCTAssertFalse(pristine.snapshot.onboardingGuide.isComplete)
        XCTAssertFalse(pristine.showsOnboardingReady)
        XCTAssertTrue(pristine.showsOnboardingGuide)

        let dismissed = NaruRemoteAppModel(
            snapshot: snapshot,
            settingsPersistence: InMemoryAppSettingsPersistence(
                settings: AppSettings(dismissedOnboardingChecklist: true)
            )
        )
        XCTAssertFalse(dismissed.snapshot.onboardingGuide.isComplete)
        XCTAssertFalse(dismissed.showsOnboardingReady)
        XCTAssertFalse(dismissed.showsOnboardingGuide)
    }

    func testDismissingReadyAffirmationLeavesUnrelatedModelStateIntact() throws {
        let snapshot = try makeCompleteSnapshot()
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(
            snapshot: snapshot,
            settingsPersistence: persistence
        )

        let beforeProfileID = model.snapshot.selectedProfileID
        let beforeSessionID = model.snapshot.session?.id
        let beforeDiagnostic = model.snapshot.diagnosticRun
        let beforePiPState = model.snapshot.pipWatchSession?.state
        let beforeFramebuffer = model.snapshot.latestFramebuffer
        let beforeInjectionAttempt = model.snapshot.latestInjectionAttempt

        model.dismissOnboardingChecklist()

        XCTAssertEqual(model.snapshot.selectedProfileID, beforeProfileID)
        XCTAssertEqual(model.snapshot.session?.id, beforeSessionID)
        XCTAssertEqual(model.snapshot.diagnosticRun, beforeDiagnostic)
        XCTAssertEqual(model.snapshot.pipWatchSession?.state, beforePiPState)
        XCTAssertEqual(model.snapshot.latestFramebuffer, beforeFramebuffer)
        XCTAssertEqual(model.snapshot.latestInjectionAttempt, beforeInjectionAttempt)
    }
}
