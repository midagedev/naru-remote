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

    func testFocusedInputDockRenderStateIgnoresModelMirroredComposeChanges() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let firstSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: ""),
            latestFramebuffer: RFBRawFramebuffer(width: 1600, height: 900),
            sessionStreamStats: SessionStreamStats(deliveredFrameCount: 1)
        )
        let churnedSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력"),
            latestFramebuffer: RFBRawFramebuffer(
                width: 1600,
                height: 900,
                fill: RFBColor(red: 20, green: 40, blue: 60)
            ),
            latestFrameDirtyRectangles: [
                RFBFrameDamageRect(x: 8, y: 8, width: 32, height: 24)
            ],
            latestFrameChangedPixelCount: 768,
            sessionStreamStats: SessionStreamStats(
                deliveredFrameCount: 240,
                contentFrameCount: 180,
                rendererUploadSampleCount: 180,
                mainActorResponsivenessSampleCount: 60,
                mainActorResponsivenessDelayMillisecondsTotal: 900
            )
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: firstSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            RemoteInputDockRenderState(
                snapshot: churnedSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "While UIKit owns Compose focus, first-syllable model mirroring plus status/frame churn must not invalidate the UITextView bridge."
        )
        XCTAssertNotEqual(
            RemoteInputDockRenderState(
                snapshot: firstSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            RemoteInputDockRenderState(
                snapshot: churnedSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            "After focus leaves, external model text should be adoptable again."
        )
    }

    func testFocusedInputDockRenderStateDefersSendStatusChangesUntilFocusLeaves() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let baseSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력")
        )
        let attempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            status: .unknown,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )
        let statusSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력"),
            latestInjectionAttempt: attempt
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: baseSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            RemoteInputDockRenderState(
                snapshot: statusSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "Send status is model chrome; while UIKit owns Korean/CJK Compose focus, it must not repaint the editor host."
        )
        XCTAssertNotEqual(
            RemoteInputDockRenderState(
                snapshot: baseSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            RemoteInputDockRenderState(
                snapshot: statusSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            "Once Compose focus leaves, send status should repaint normally."
        )
    }

    func testFocusedInputDockRenderStateDefersStatusClearAfterTypingOverPreviousSendResult() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let previousAttempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            status: .unknown,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )
        let statusSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입"),
            latestInjectionAttempt: previousAttempt
        )
        let editingSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력")
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: statusSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            RemoteInputDockRenderState(
                snapshot: editingSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "Typing the first Korean syllable after a previous send clears stale model status; that clear must not repaint the focused UIKit editor or the next IME key can stall."
        )
        XCTAssertNotEqual(
            RemoteInputDockRenderState(
                snapshot: statusSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            RemoteInputDockRenderState(
                snapshot: editingSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            "Once Compose focus leaves, stale send status can be cleared from the visible dock."
        )
    }

    func testFocusedComposeStatusLineStaysMountedWhenTypingClearsPreviousSendResult() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let previousAttempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            status: .unknown,
            safeMessage: "Remote app confirmation unavailable."
        )
        let statusSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: ""),
            latestInjectionAttempt: previousAttempt
        )
        let editingSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입")
        )

        let statusLine = FocusedComposeStatusLineState(
            snapshot: statusSnapshot,
            isComposeFieldFocused: true
        )
        let editingLine = FocusedComposeStatusLineState(
            snapshot: editingSnapshot,
            isComposeFieldFocused: true
        )

        XCTAssertEqual(statusLine?.text, FocusedComposeStatusLineState.focusedStatusText)
        XCTAssertEqual(editingLine?.text, FocusedComposeStatusLineState.focusedStatusText)
        XCTAssertEqual(
            statusLine,
            editingLine,
            "Focused Compose chrome should stay visually static while model send status clears; dynamic status resumes after focus leaves."
        )
        XCTAssertNotNil(statusLine)
        XCTAssertNotNil(
            editingLine,
            "The focused status sibling must remain mounted after the first syllable clears stale send chrome; removing it can collapse the keyboard safe-area layout under UIKit IME."
        )
        XCTAssertNil(
            FocusedComposeStatusLineState(
                snapshot: editingSnapshot,
                isComposeFieldFocused: false
            )
        )
    }

    func testFocusedComposeStatusLineIgnoresPublishedModelChromeChanges() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let baseSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입")
        )
        let attempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            status: .unknown,
            safeMessage: "Remote app confirmation unavailable."
        )
        let noisySnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력"),
            latestInjectionAttempt: attempt,
            helperTextBridgeState: [
                profile.id: HelperTextBridgeProfileState(
                    isEnabled: true,
                    pairingFingerprint: "sha256:helper",
                    availability: .checking,
                    lastFailureCode: nil,
                    lastCheckedBucket: .recent
                )
            ]
        )

        XCTAssertEqual(
            FocusedComposeStatusLineState(
                snapshot: baseSnapshot,
                isComposeFieldFocused: true
            ),
            FocusedComposeStatusLineState(
                snapshot: noisySnapshot,
                isComposeFieldFocused: true
            ),
            "Focused Compose's sibling chrome must not relayout when helper/send status changes under an active IME transaction."
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

    func testFocusedInputDockRenderStateDefersLiveSessionLayoutTransition() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let draftSession = RemoteSession(profileID: profile.id, state: .connecting)
        let activeSession = RemoteSession(
            id: draftSession.id,
            profileID: profile.id,
            state: .active
        )
        let draft = ComposeDraft(sessionID: draftSession.id, text: "입")
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
            composeDraft: draft,
            latestFramebuffer: RFBRawFramebuffer(width: 1600, height: 900),
            latestFrameDirtyRectangles: [
                RFBFrameDamageRect(x: 40, y: 40, width: 96, height: 48)
            ],
            latestFrameChangedPixelCount: 4_608
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: connectingSnapshot,
                isLiveSession: false,
                isComposeFieldFocused: true
            ),
            RemoteInputDockRenderState(
                snapshot: activeSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "A first frame arriving while UIKit owns Korean/CJK composition must not swap dock layout or quick-key accessories under the active UITextView."
        )
        XCTAssertNotEqual(
            RemoteInputDockRenderState(
                snapshot: connectingSnapshot,
                isLiveSession: false,
                isComposeFieldFocused: false
            ),
            RemoteInputDockRenderState(
                snapshot: activeSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            "Once focus leaves, the live session dock layout and quick-key strip should be allowed to appear."
        )
    }
}
