import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class RemoteInputDockRenderStateTests: XCTestCase {
    func testInputDockRenderStateIgnoresStreamingTelemetryAndFramebufferNoise() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let draft = ComposeDraft(sessionID: session.id, text: "입력느낌")
        let baseSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: draft,
            sessionStreamStats: SessionStreamStats(deliveredFrameCount: 1)
        )
        let noisyStreamingSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: draft,
            latestFramebuffer: RFBRawFramebuffer(width: 4, height: 4),
            latestFrameDirtyRectangles: [
                RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 4)
            ],
            latestFrameChangedPixelCount: 16,
            sessionStreamStats: SessionStreamStats(
                deliveredFrameCount: 240,
                contentFrameCount: 200,
                emptyUpdateCount: 40,
                rendererUploadSampleCount: 200,
                rendererFullUploadCount: 10,
                receiveTimingSampleCount: 200,
                receiveTotalMillisecondsTotal: 40_000,
                receiveTotalMillisecondsMax: 650,
                appFrameApplyTimingSampleCount: 200,
                appFrameApplyMillisecondsTotal: 2_400,
                appFrameApplyMillisecondsMax: 45,
                mainActorResponsivenessSampleCount: 60,
                mainActorResponsivenessDelayMillisecondsTotal: 900,
                mainActorResponsivenessDelayMillisecondsMax: 120
            )
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(snapshot: baseSnapshot, isLiveSession: true),
            RemoteInputDockRenderState(snapshot: noisyStreamingSnapshot, isLiveSession: true),
            "Video/telemetry churn must not invalidate the UIKit Compose bridge when the visible input state is unchanged."
        )
    }

    func testInputDockRenderStateChangesWhenComposeDraftTextChanges() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)

        let firstSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력")
        )
        let nextSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력느낌")
        )

        XCTAssertNotEqual(
            RemoteInputDockRenderState(snapshot: firstSnapshot, isLiveSession: true),
            RemoteInputDockRenderState(snapshot: nextSnapshot, isLiveSession: true)
        )
    }

    func testInputDockRenderStateChangesWhenComposeQuickKeysBecomeAvailable() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let draftSession = RemoteSession(profileID: profile.id, state: .connecting)
        let activeSession = RemoteSession(
            id: draftSession.id,
            profileID: profile.id,
            state: .active
        )
        let draft = ComposeDraft(sessionID: draftSession.id, text: "입력")
        let connectingSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: draftSession,
            composeDraft: draft
        )
        let activeSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: activeSession,
            composeDraft: draft
        )

        XCTAssertNotEqual(
            RemoteInputDockRenderState(snapshot: connectingSnapshot, isLiveSession: true),
            RemoteInputDockRenderState(snapshot: activeSnapshot, isLiveSession: true)
        )
    }
}
