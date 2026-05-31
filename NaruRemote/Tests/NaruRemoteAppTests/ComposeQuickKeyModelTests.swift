import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Model-level behavior for the Compose-mode inline quick-key strip
/// (spec 003 US5 / FR-013).  The wire envelope itself is proven in
/// `ComposeQuickKeyTests` (Core) against a recording emitter; here we
/// assert the model's session-gating and draft-preservation rules,
/// which do not require a live streaming fake.
@MainActor
final class ComposeQuickKeyModelTests: XCTestCase {
    func testSendComposeQuickKeyDropsWithNoActiveSession() async {
        // No session → no `keystrokeEmitter`.  The call must drop
        // silently (spec.md IN-003) and not crash.
        let model = NaruRemoteAppModel()
        await model.sendComposeQuickKey(.escape)
        await model.sendComposeQuickKey(.controlC)
        // No observable state to assert beyond "did not trap"; the
        // model stays in its fresh, session-less shape.
        XCTAssertNil(model.session)
    }

    func testSendComposeQuickKeyLeavesComposeDraftUntouched() async throws {
        // FR-013 — the quick-key strip is orthogonal to the compose
        // buffer: firing a control key must never modify the partial
        // multilingual draft the user is building.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "안녕하세요 git ")
            )
        )
        XCTAssertEqual(model.composeDraft?.text, "안녕하세요 git ")

        // No emitter is wired (no live stream in this snapshot), so the
        // emission drops — but the contract under test is that the
        // draft is never touched regardless of whether the wire fired.
        await model.sendComposeQuickKey(.tab)
        await model.sendComposeQuickKey(.controlC)

        XCTAssertEqual(model.composeDraft?.text, "안녕하세요 git ")
    }
}
