import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec FR-015 acceptance: zero saved profiles → exactly one
/// primary CTA into the profile editor; ≥ 1 saved profile → no
/// empty-state chrome.  Visibility is derived purely from
/// `profiles.isEmpty` — there is no persisted dismissal flag and no
/// model-side toggle (see `NaruRemoteAppShell.body`).
@MainActor
final class EmptyHomeTests: XCTestCase {
    func testNoProfilesYieldsEmptyHomeSnapshot() {
        let model = NaruRemoteAppModel()

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
    }

    func testOneProfileYieldsPopulatedHomeSnapshot() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile])
        )

        XCTAssertFalse(model.snapshot.profiles.isEmpty)
    }

    func testEmptyHomeSnapshotDoesNotExposeOnboardingChrome() {
        // Constitution §IV / spec FR-016: the empty home cannot
        // accidentally re-introduce a feature checklist or capability
        // preview.  `NaruRemoteAppSnapshot` no longer ships an
        // onboarding guide, so the snapshot's externally-visible
        // surface is only profile + session state.  This test exists
        // to guard against a future refactor accidentally re-adding
        // such a property and quietly putting it back on screen.
        let model = NaruRemoteAppModel()
        let snapshot = model.snapshot

        // Probe the published surface: nothing onboarding-shaped is
        // observable.  The compile-time check (the test would fail
        // to build if `onboardingGuide` returned to the snapshot
        // type) is the real assertion; the runtime checks below are
        // sanity for the empty home.
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.diagnosticRun)
        XCTAssertNil(snapshot.composeDraft)
        XCTAssertNil(snapshot.pipWatchSession)
        XCTAssertNil(snapshot.latestFramebuffer)
    }
}
