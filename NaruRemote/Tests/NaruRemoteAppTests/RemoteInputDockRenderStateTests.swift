import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class RemoteInputDockRenderStateTests: XCTestCase {
    func testFloatingModeTargetsMeetMinimumTouchDimension() {
        XCTAssertGreaterThanOrEqual(
            RemoteInputDockView.minimumFloatingModeTargetDiameter,
            44
        )
    }

    func testCompactComposeEditorCollapsesOnlyWhenIdleAndEmpty() {
        XCTAssertFalse(
            RemoteInputDockView.shouldShowCompactComposeEditor(
                isFocused: false,
                text: "",
                expansionRequested: false
            )
        )
        XCTAssertTrue(
            RemoteInputDockView.shouldShowCompactComposeEditor(
                isFocused: false,
                text: "",
                expansionRequested: true
            )
        )
        XCTAssertTrue(
            RemoteInputDockView.shouldShowCompactComposeEditor(
                isFocused: true,
                text: "",
                expansionRequested: false
            )
        )
        XCTAssertTrue(
            RemoteInputDockView.shouldShowCompactComposeEditor(
                isFocused: false,
                text: "입력",
                expansionRequested: false
            )
        )
    }

    /// Spec 015 v1.1: the compact Compose field is one line, always — the
    /// founder read the old 88pt focused height as a multi-line editor. 40pt
    /// is the row's control height; growth would rebuild the tall dock.
    func testCompactComposeEditorIsOneLineTall() {
        XCTAssertEqual(RemoteInputDockView.compactComposeEditorHeight, 40)
    }

    /// Compose-reveal fix (2026-07-05): tapping the floating "Compose"
    /// reveal hoists an expansion request into the shell, which must pin
    /// the dock (leave the floating overlay) BEFORE the keyboard rises.
    /// The historical bug: the placement flipped only when focus landed,
    /// destroying the dock instance mid-focus, so the editor collapsed on
    /// every tap and Compose never opened in a live session.
    func testComposeExpansionRequestLeavesFloatingAccessory() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let activeSession = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: activeSession
        )

        // Idle live session → floating strip.
        XCTAssertTrue(
            RemoteInputDockRenderState.shouldUseFloatingLiveAccessory(
                snapshot: snapshot,
                isComposeFieldFocused: false
            )
        )
        // Expansion requested (reveal tapped, keyboard not yet up) →
        // pinned immediately.
        XCTAssertFalse(
            RemoteInputDockRenderState.shouldUseFloatingLiveAccessory(
                snapshot: snapshot,
                isComposeFieldFocused: false,
                isComposeExpansionRequested: true
            )
        )
        XCTAssertEqual(
            RemoteInputDockRenderState.resolvedLayoutStyle(
                snapshot: snapshot,
                isLiveSession: true,
                isComposeFieldFocused: false,
                isComposeExpansionRequested: true
            ),
            .compactAccessory
        )
        // And the render state carries the request so the EquatableView
        // host re-renders when it changes.
        XCTAssertNotEqual(
            RemoteInputDockRenderState(
                snapshot: snapshot,
                isLiveSession: true,
                isComposeExpansionRequested: true
            ),
            RemoteInputDockRenderState(
                snapshot: snapshot,
                isLiveSession: true,
                isComposeExpansionRequested: false
            )
        )
    }

    func testMacSessionControlsOnlyShowForActiveSessions() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connectingSession = RemoteSession(profileID: profile.id, state: .connecting)
        let activeSession = RemoteSession(profileID: profile.id, state: .active)

        XCTAssertFalse(
            RemoteInputDockRenderState(
                snapshot: NaruRemoteAppSnapshot(
                    profiles: [profile],
                    selectedProfileID: profile.id,
                    session: connectingSession
                ),
                isLiveSession: true
            ).showsMacSessionControls
        )
        XCTAssertTrue(
            RemoteInputDockRenderState(
                snapshot: NaruRemoteAppSnapshot(
                    profiles: [profile],
                    selectedProfileID: profile.id,
                    session: activeSession
                ),
                isLiveSession: true
            ).showsMacSessionControls
        )
    }

    func testLiveIdleInputDockFloatsOverViewportWithoutReservingSafeArea() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: RFBRawFramebuffer(width: 1600, height: 900)
        )
        let state = RemoteInputDockRenderState(snapshot: snapshot, isLiveSession: true)
        let chrome = RemoteInputAccessoryChromeState(
            snapshot: snapshot,
            incomingClipboardReview: nil,
            isLiveSession: true,
            isComposeFieldFocused: false
        )

        XCTAssertEqual(state.layoutStyle, .floatingAccessory)
        XCTAssertTrue(
            chrome.usesFloatingOverlay(for: state),
            "Idle remote control should keep the desktop full-height and place only a tiny floating input affordance above it."
        )
    }

    func testLiveInputDockReturnsToReservedInsetWhenInputOrChromeNeedsSpace() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let baseSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: RFBRawFramebuffer(width: 1600, height: 900)
        )
        let draftSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입력"),
            latestFramebuffer: RFBRawFramebuffer(width: 1600, height: 900)
        )
        let liveActiveSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            latestFramebuffer: RFBRawFramebuffer(width: 1600, height: 900),
            liveTypeThroughMode: LiveTypeThroughMode(isActive: true)
        )
        let review = IncomingClipboardReview(
            text: "remote copied text",
            arrivedAt: Date(timeIntervalSince1970: 1),
            id: UUID(uuidString: "F6305806-E3AF-4B37-87FE-B053D08E3D8A")!
        )
        let floatingState = RemoteInputDockRenderState(snapshot: baseSnapshot, isLiveSession: true)
        let chromeWithReview = RemoteInputAccessoryChromeState(
            snapshot: baseSnapshot,
            incomingClipboardReview: review,
            isLiveSession: true,
            isComposeFieldFocused: false
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: draftSnapshot,
                isLiveSession: true
            ).layoutStyle,
            .compactAccessory
        )
        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: baseSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ).layoutStyle,
            .compactAccessory
        )
        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: liveActiveSnapshot,
                isLiveSession: true,
                isComposeExpansionRequested: true
            ).layoutStyle,
            .compactAccessory,
            "An open Type editor (expansion requested) needs the reserved inset."
        )
        XCTAssertFalse(
            chromeWithReview.usesFloatingOverlay(for: floatingState),
            "Incoming clipboard review needs reserved bottom space instead of floating over the remote desktop."
        )
    }

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

    func testFocusedPreConnectionInputDockKeepsStandardLayout() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id
        )

        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: snapshot,
                isLiveSession: false,
                isComposeFieldFocused: false
            ).layoutStyle,
            .standard
        )
        XCTAssertEqual(
            RemoteInputDockRenderState(
                snapshot: snapshot,
                isLiveSession: false,
                isComposeFieldFocused: true
            ).layoutStyle,
            .standard,
            "Pre-connection Compose focus must not flip the dock into live compact layout; the safe-area inset is attached outside the scrollable detail content instead."
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
        XCTAssertEqual(
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
            "Live-session send status is sibling chrome; it must not repaint the UITextView host even when Compose is not focused."
        )
        XCTAssertNotEqual(
            RemoteInputDockStatusLineState(
                snapshot: baseSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            RemoteInputDockStatusLineState(
                snapshot: statusSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            ),
            "The sibling status line still reflects send status without invalidating the input host."
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

    /// Spec 015 FR-006/FR-007. The line this used to assert
    /// ("Ready to compose locally") existed to hold a `VStack` slot open —
    /// removing it mid-typing changed the stack's children and collapsed the
    /// keyboard safe-area layout under UIKit IME. The slot is now an overlay
    /// above the dock (`NaruRemoteAppShell` — the dock host's
    /// `.overlay(alignment: .top)`), so presence no longer moves the dock and
    /// the placeholder is not needed. What survives is the real requirement:
    /// a status the user can act on still shows, and a nominal one costs no
    /// screen.
    func testFocusedComposeStatusLineSpeaksOnlyWhenSomethingNeedsSaying() throws {
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

        let statusLine = RemoteInputDockStatusLineState(
            snapshot: statusSnapshot,
            isLiveSession: true,
            isComposeFieldFocused: true
        )
        let editingLine = RemoteInputDockStatusLineState(
            snapshot: editingSnapshot,
            isLiveSession: true,
            isComposeFieldFocused: true
        )

        XCTAssertEqual(
            statusLine?.text,
            "Remote app confirmation unavailable.",
            "An unconfirmed delivery keeps the user's text locally; that must be said even while the field holds focus."
        )
        XCTAssertEqual(
            editingLine?.text,
            "Korean/CJK/emoji needs Mac helper setup",
            "The stale send result clears, but an undeliverable Korean draft is still actionable."
        )

        // The nominal case: an ASCII draft on a healthy transport with nothing
        // outstanding. This is the founder's terminal posture, and it is the
        // one that must cost no screen.
        let nominalSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "ls -la")
        )
        XCTAssertNil(
            RemoteInputDockStatusLineState(
                snapshot: nominalSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "With nothing unconfirmed, failed or undeliverable, the status line costs no screen — the founder is watching the remote react, not reading 'Ready to compose locally'."
        )
        XCTAssertEqual(
            RemoteInputDockStatusLineState(
                snapshot: editingSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: false
            )?.text,
            editingSnapshot.inputHelperStatusText
        )

        let sentSnapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: ""),
            latestInjectionAttempt: TextInjectionAttempt(
                draftID: UUID(),
                sessionID: session.id,
                path: .helperTextBridge,
                status: .sent,
                safeMessage: "Inserted via Naru Helper"
            )
        )
        XCTAssertNil(
            RemoteInputDockStatusLineState(
                snapshot: sentSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "A delivery that landed is signalled by the crossing pulse, which has no height (FR-006)."
        )
    }

    /// Spec 015: status text is no longer frozen while focused — it is
    /// *suppressed unless actionable*, and it renders as an overlay above the
    /// dock instead of as a stack row. The invariant that mattered is the one
    /// asserted here: whatever the status does, the **dock's** render state is
    /// unchanged, so the equatable host does not repaint the live `UITextView`
    /// bridge and the next IME key cannot stall.
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
            RemoteInputDockRenderState(
                snapshot: baseSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            RemoteInputDockRenderState(
                snapshot: noisySnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            ),
            "Helper/send status churn must not repaint the focused dock — that is what can stall the next IME key."
        )

        // Both of these are states the user can act on, so both are allowed to
        // speak; what they must not do is move the dock.
        XCTAssertEqual(
            RemoteInputDockStatusLineState(
                snapshot: baseSnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            )?.text,
            "Korean/CJK/emoji needs Mac helper setup",
            "A Korean draft with no paired helper cannot be delivered as typed — the user has to know."
        )
        XCTAssertEqual(
            RemoteInputDockStatusLineState(
                snapshot: noisySnapshot,
                isLiveSession: true,
                isComposeFieldFocused: true
            )?.text,
            "Remote app confirmation unavailable.",
            "An unconfirmed delivery outranks the helper hint: it is about text already sent."
        )
    }

    func testFocusedInputAccessoryChromeDefersIncomingClipboardBanner() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "입")
        )
        let review = IncomingClipboardReview(
            text: "remote copied text",
            arrivedAt: Date(timeIntervalSince1970: 1),
            id: UUID(uuidString: "2D7C512B-18C2-4B2B-9F6C-DA5B15E87E3A")!
        )

        let focusedChrome = RemoteInputAccessoryChromeState(
            snapshot: snapshot,
            incomingClipboardReview: review,
            isLiveSession: true,
            isComposeFieldFocused: true
        )
        let unfocusedChrome = RemoteInputAccessoryChromeState(
            snapshot: snapshot,
            incomingClipboardReview: review,
            isLiveSession: true,
            isComposeFieldFocused: false
        )

        XCTAssertNil(
            focusedChrome.incomingClipboardReview,
            "Remote clipboard review UI must not appear above the keyboard while UIKit owns Korean/CJK Compose focus."
        )
        XCTAssertEqual(
            focusedChrome.statusLine?.text,
            "Korean/CJK/emoji needs Mac helper setup",
            "The Korean draft cannot be delivered without the helper, which is actionable and still speaks (spec 015 FR-006)."
        )
        XCTAssertEqual(
            unfocusedChrome.incomingClipboardReview,
            review,
            "The pending review is not discarded; it becomes visible again after Compose focus leaves."
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
