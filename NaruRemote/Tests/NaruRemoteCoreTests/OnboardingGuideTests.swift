import XCTest
@testable import NaruRemoteCore

final class OnboardingGuideTests: XCTestCase {
    func testOnboardingStartsWithPrivateProfileActionWhenNoProfileExists() {
        let guide = OnboardingGuide(profile: nil)

        XCTAssertEqual(guide.firstActionableStep?.id, .privateTarget)
        XCTAssertEqual(guide.firstActionableStep?.state, .next)
        XCTAssertEqual(guide.steps.map(\.id), [.privateTarget, .diagnostics, .compose, .pipWatch])
    }

    func testOnboardingDoesNotEchoComposeDraftText() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let draftText = "한글과 English 😊를 같이 입력합니다"
        let attempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            status: .unknown,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )

        let guide = OnboardingGuide(
            profile: profile,
            session: session,
            latestInjectionAttempt: attempt
        )
        let visibleText = guide.steps.map { "\($0.title) \($0.detail)" }.joined(separator: "\n")

        XCTAssertFalse(visibleText.contains(draftText))
        XCTAssertTrue(visibleText.contains("Last send kept local text until confirmation."))
    }

    func testOnboardingSurfacesFailedDiagnosticSafely() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            stages: [
                DiagnosticStageResult(
                    stage: .authentication,
                    status: .failed,
                    safeTitle: "Authentication failed",
                    safeDetail: "Rejected password hunter2"
                )
            ]
        )

        let guide = OnboardingGuide(profile: profile, diagnosticRun: run)
        let diagnostics = try XCTUnwrap(guide.steps.first { $0.id == .diagnostics })

        XCTAssertEqual(diagnostics.state, .blocked)
        XCTAssertEqual(diagnostics.detail, "Authentication failed")
        XCTAssertFalse(diagnostics.detail.contains("hunter2"))
    }

    func testOnboardingHonorsPiPProfileOptOut() throws {
        let profile = try ConnectionProfile(
            displayName: "Sensitive Desk",
            host: "sensitive.tailnet.ts.net",
            allowsPiPWatch: false
        )
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )

        let guide = OnboardingGuide(profile: profile, session: session)
        let pipWatch = try XCTUnwrap(guide.steps.first { $0.id == .pipWatch })

        XCTAssertEqual(pipWatch.state, .blocked)
        XCTAssertEqual(pipWatch.detail, "Disabled for this profile.")
    }
}
