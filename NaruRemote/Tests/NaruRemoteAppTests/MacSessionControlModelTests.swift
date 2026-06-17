import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class MacSessionControlModelTests: XCTestCase {
    func testSendMacSessionControlDropsWithNoActiveSession() async {
        let model = NaruRemoteAppModel()

        await model.sendMacSessionControl(.missionControl)
        await model.sendMacSessionControl(.showDesktop)

        XCTAssertNil(model.session)
    }

    func testSendMacSessionControlLeavesComposeDraftUntouched() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "맥 제어 중 입력")
            )
        )

        await model.sendMacSessionControl(.missionControl)
        await model.sendMacSessionControl(.switchApplication)

        XCTAssertEqual(model.composeDraft?.text, "맥 제어 중 입력")
    }
}
