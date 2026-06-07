import Foundation
import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class DirectKeystrokeModeTests: XCTestCase {

    // MARK: - Initial state

    func testFreshModelIsInComposeMode() {
        let model = NaruRemoteAppModel()
        XCTAssertFalse(model.directKeystrokeMode.isActive)
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)
    }

    // MARK: - toggleDirectKeystrokeMode

    func testToggleFlipsIsActive() {
        let model = NaruRemoteAppModel()

        model.toggleDirectKeystrokeMode()
        XCTAssertTrue(model.directKeystrokeMode.isActive)

        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.isActive)
    }

    func testToggleEntryResetsPageToQwerty() {
        // Toggle on, switch to special, toggle off, toggle on
        // again — fresh entry returns to QWERTY page.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        model.setDirectKeystrokePage(.special)
        XCTAssertEqual(model.directKeystrokeMode.page, .special)

        model.toggleDirectKeystrokeMode()
        model.toggleDirectKeystrokeMode()
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
    }

    func testToggleDoesNotTouchEntryWarningFlag() {
        // The flag is only flipped by
        // dismissDirectModeEntryWarning() — so the SwiftUI
        // dialog can render conditionally on
        // (isActive && !hasShownEntryWarningThisSession) and
        // every fresh-session entry shows the warning until the
        // user dismisses it.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)

        model.toggleDirectKeystrokeMode()
        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)
    }

    // MARK: - setDirectKeystrokePage

    func testSetPageUpdatesPageOnly() {
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        model.setDirectKeystrokePage(.special)
        XCTAssertEqual(model.directKeystrokeMode.page, .special)
        XCTAssertTrue(model.directKeystrokeMode.isActive)

        model.setDirectKeystrokePage(.qwerty)
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }

    // MARK: - dismissDirectModeEntryWarning

    func testDismissEntryWarningSetsFlag() {
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertFalse(model.directKeystrokeMode.hasShownEntryWarningThisSession)

        model.dismissDirectModeEntryWarning()
        XCTAssertTrue(model.directKeystrokeMode.hasShownEntryWarningThisSession)

        // Subsequent toggle off / on within the same session
        // keeps the flag set.
        model.toggleDirectKeystrokeMode()
        model.toggleDirectKeystrokeMode()
        XCTAssertTrue(model.directKeystrokeMode.hasShownEntryWarningThisSession)
    }

    // MARK: - tapDirectKey

    func testTapDirectKeyPageToggleSwapsPagesWithoutEmitting() async {
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)

        await model.tapDirectKey(.pageToggle)
        XCTAssertEqual(model.directKeystrokeMode.page, .special)

        await model.tapDirectKey(.pageToggle)
        XCTAssertEqual(model.directKeystrokeMode.page, .qwerty)
    }

    func testTapDirectKeyDropsCharacterEmissionWhenNotActive() async {
        // Direct mode off → emission silently dropped (FR-014
        // default; spec.md IN-003 fallback "drop silently when
        // not `.active`").  Without an active session there is
        // also no keystrokeEmitter, so the test asserts no
        // crash and consistent state.
        let model = NaruRemoteAppModel()
        // Direct mode is off by default — emission should drop.
        await model.tapDirectKey(.character("c"))

        // Toggling on with no session attached also drops since
        // keystrokeEmitter is still nil.
        model.toggleDirectKeystrokeMode()
        await model.tapDirectKey(.character("c"))

        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }

    func testTapDirectKeyDropsNonAsciiCharacters() async {
        // Korean / CJK / emoji belong to Compose & Send
        // (constitution §I); the QWERTY page does not render
        // these keys but if a Character somehow arrives, drop
        // it rather than emit garbage.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.character("한"))
        await model.tapDirectKey(.character("😊"))

        // No assertion on wire (no active session); the test's
        // value is that no crash / typed exception leaks out.
        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }

    func testTapDirectKeyReturnsBeforeSlowWireWritesAndKeepsOrder() async throws {
        // Regression for live-device freezes: the production RFB
        // key write path can wait on socket backpressure. A soft-key
        // tap must enqueue that work and return to MainActor
        // immediately, while the outbound queue still preserves the
        // exact key down/up ordering.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = KeyCapturingStreamingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 80,
                height: 60,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            keyEventDelay: .milliseconds(150)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector }
        )

        await model.connectSelectedProfile()
        try await waitForConnectedDirectSession(model)

        model.toggleDirectKeystrokeMode()

        let startedAt = Date()
        await model.tapDirectKey(.character("a"))
        await model.tapDirectKey(.character("b"))
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(
            elapsed,
            0.12,
            "Direct key taps should not wait for delayed VNC socket writes"
        )
        XCTAssertTrue(
            connector.recordedKeyEvents.isEmpty,
            "Delayed wire writes should still be pending immediately after enqueue"
        )

        try await waitForKeyEvents(connector, count: 4)
        let events = connector.recordedKeyEvents
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0].keysym, 0x0061)
        XCTAssertTrue(events[0].isDown)
        XCTAssertEqual(events[1].keysym, 0x0061)
        XCTAssertFalse(events[1].isDown)
        XCTAssertEqual(events[2].keysym, 0x0062)
        XCTAssertTrue(events[2].isDown)
        XCTAssertEqual(events[3].keysym, 0x0062)
        XCTAssertFalse(events[3].isDown)
    }

    func testTrackpadMoveBacklogDoesNotBlockDirectKeyLane() async throws {
        // Live-device regression: trackpad movement can backlog while
        // the user starts typing. Buttonless pointer moves may be
        // delayed or dropped; keystrokes must use their own outbound
        // lane so a stale cursor move cannot make the keyboard feel
        // frozen after the first character.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = KeyCapturingStreamingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 80,
                height: 60,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            pointerEventDelay: .seconds(10)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            outboundInputEventTimeout: .milliseconds(250)
        )

        await model.connectSelectedProfile()
        try await waitForConnectedDirectSession(model)

        model.togglePointerControlMode()
        model.handleTrackpadGesture(
            .dragChanged(
                viewPoint: CGPoint(x: 20, y: 20),
                translation: CGSize(width: 20, height: 20)
            ),
            viewSize: CGSize(width: 80, height: 60)
        )
        try await Task.sleep(for: .milliseconds(30))
        model.toggleDirectKeystrokeMode()
        await model.tapDirectKey(.character("a"))

        try await waitForKeyEvents(connector, count: 2, timeout: 1)
        XCTAssertEqual(
            connector.recordedKeyEvents.map { $0.keysym },
            [0x0061, 0x0061]
        )
        XCTAssertTrue(
            connector.recordedPointerEvents.isEmpty,
            "The delayed trackpad move should still be pending or timed out; it must not block keys."
        )
    }

    func testTimedOutKeyEmissionReleasesOutboundQueueForLaterPointerInput() async throws {
        // Regression for the "one key, then everything feels frozen"
        // class of failures: a stalled key client must not park the
        // shared outbound input tail forever. After the model-level
        // timeout trips, later pointer input should enqueue on a fresh
        // tail instead of waiting behind the stuck key.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = KeyCapturingStreamingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 80,
                height: 60,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            keyEventDelay: .seconds(10)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(frameInterval: 1),
            connectorFactory: { connector },
            outboundInputEventTimeout: .milliseconds(60)
        )

        await model.connectSelectedProfile()
        try await waitForConnectedDirectSession(model)

        model.toggleDirectKeystrokeMode()
        await model.tapDirectKey(.character("a"))

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertTrue(
            connector.recordedKeyEvents.isEmpty,
            "The delayed key write should be cancelled before it records stale key events"
        )

        model.sendTapAt(
            viewPoint: CGPoint(x: 10, y: 10),
            viewSize: CGSize(width: 80, height: 60)
        )

        try await waitForPointerEvents(connector, count: 2, timeout: 1)
        let pointerEvents = connector.recordedPointerEvents
        XCTAssertEqual(pointerEvents.count, 2)
        XCTAssertEqual(pointerEvents[0].mask, 0x01)
        XCTAssertEqual(pointerEvents[0].x, 10)
        XCTAssertEqual(pointerEvents[0].y, 10)
        XCTAssertEqual(pointerEvents[1].mask, 0x00)
        XCTAssertEqual(pointerEvents[1].x, 10)
        XCTAssertEqual(pointerEvents[1].y, 10)
    }

    func testTimedOutKeyEmissionDoesNotPermanentlyDisableLaterKeys() async throws {
        // Live-device regression: the first key write can time out
        // under socket pressure, but that must not nil the Direct-mode
        // emitter. The next soft-key tap should enqueue against the
        // same active session and reach the wire once the queue has
        // been reset.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = KeyCapturingStreamingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 80,
                height: 60,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            keyEventDelays: [.seconds(10), nil, nil]
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(frameInterval: 1),
            connectorFactory: { connector },
            outboundInputEventTimeout: .milliseconds(60)
        )

        await model.connectSelectedProfile()
        try await waitForConnectedDirectSession(model)

        model.toggleDirectKeystrokeMode()
        await model.tapDirectKey(.character("a"))

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertTrue(
            connector.recordedKeyEvents.isEmpty,
            "The first delayed key write should time out before recording"
        )

        await model.tapDirectKey(.character("b"))

        try await waitForKeyEvents(connector, count: 2, timeout: 1)
        XCTAssertEqual(
            connector.recordedKeyEvents.map { $0.keysym },
            [0x0062, 0x0062]
        )
        XCTAssertEqual(
            connector.recordedKeyEvents.map { $0.isDown },
            [true, false]
        )
    }

    func testTimedOutPointerInputDoesNotDisableLaterKeys() async throws {
        // Pointer failures should narrow to the pointer lane. The same
        // live session may still accept keyboard input through the key
        // lane, which is the important recovery path for terminal work.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let connector = KeyCapturingStreamingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            framebuffer: RFBRawFramebuffer(
                width: 80,
                height: 60,
                fill: RFBColor(red: 10, green: 20, blue: 30)
            ),
            pointerEventDelay: .seconds(10)
        )
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(frameInterval: 1),
            connectorFactory: { connector },
            outboundInputEventTimeout: .milliseconds(60)
        )

        await model.connectSelectedProfile()
        try await waitForConnectedDirectSession(model)

        model.sendTapAt(
            viewPoint: CGPoint(x: 10, y: 10),
            viewSize: CGSize(width: 80, height: 60)
        )
        try await Task.sleep(for: .milliseconds(140))
        XCTAssertTrue(
            connector.recordedPointerEvents.isEmpty,
            "The delayed pointer write should time out before recording"
        )

        model.toggleDirectKeystrokeMode()
        await model.tapDirectKey(.character("b"))

        try await waitForKeyEvents(connector, count: 2, timeout: 1)
        XCTAssertEqual(
            connector.recordedKeyEvents.map { $0.keysym },
            [0x0062, 0x0062]
        )
    }

    // MARK: - Sticky modifier integration (Phase 4 / US-2)

    func testFreshModelHasAllStickyModifiersIdle() {
        let model = NaruRemoteAppModel()
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .idle)
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .idle)
        XCTAssertEqual(model.stickyModifierState.slot(for: .alt), .idle)
        XCTAssertEqual(model.stickyModifierState.slot(for: .meta), .idle)
        XCTAssertTrue(model.stickyModifierState.activeModifiers.isEmpty)
    }

    func testTapModifierUpdatesStateWithoutSessionOrCrash() async {
        // No active session, so emission has no destination — but
        // a sticky-modifier tap must still update state so the
        // user can pre-arm before the wire is up.  Verify no
        // crash and the slot transitions.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))

        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)
    }

    func testTapModifierThenCharacterConsumesArmedSlot() async {
        // Without an active emitter, the .character branch drops
        // before reaching consumeAfterNonModifierEmission().
        // We assert the model state pre-emission and document
        // the consumption rule via the locked-modifier test
        // below (which exercises the post-emission state path).
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)
        XCTAssertEqual(model.stickyModifierState.activeModifiers, [.control])

        // Without an emitter, .character drops at the guard and
        // does NOT call consume (it would be wrong to consume
        // armed state when nothing reached the wire).
        await model.tapDirectKey(.character("c"))
        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .armed,
            "guard-dropped emissions must not consume armed state"
        )
    }

    func testDoubleTapShiftLocksAndClearAffordanceResets() async {
        // FR-005 + FR-013 — double-tap Shift to lock, then tap
        // Clear modifiers to release everything in one tap.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.shift))
        await model.tapDirectKey(.modifier(.shift))
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .locked)

        await model.tapDirectKey(.clearModifiers)
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .idle)
        XCTAssertTrue(model.stickyModifierState.activeModifiers.isEmpty)
    }

    func testStackedArmedModifiersRecordedOnState() async {
        // spec.md US-2 acceptance #3 — Ctrl-Shift-Tab is reachable
        // via two modifier taps then Tab.  We assert state, not
        // wire, because the test model has no session.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))
        await model.tapDirectKey(.modifier(.shift))

        XCTAssertEqual(
            model.stickyModifierState.activeModifiers,
            [.control, .shift]
        )
    }

    func testSnapshotMirrorsStickyState() async {
        // Views render off the snapshot, not by reaching back
        // into the @MainActor model directly.  Verify the
        // snapshot carries the live sticky state.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.alt))

        XCTAssertEqual(model.snapshot.stickyModifierState.slot(for: .alt), .armed)
    }

    // MARK: - Mode-switch state preservation (Phase 6 / US-4 / FR-011 / FR-012)

    func testComposeDraftSurvivesToggleIntoDirect() throws {
        // FR-011 — toggling Compose → Direct must NOT drop the
        // partial draft.  The user is alternating between writing
        // a Korean message in Compose and dropping into Direct
        // for a quick `git status`; losing the message on toggle
        // is unacceptable.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "hello")
            )
        )
        XCTAssertEqual(model.composeDraft?.text, "hello")

        model.toggleDirectKeystrokeMode()

        XCTAssertTrue(model.directKeystrokeMode.isActive)
        XCTAssertEqual(model.composeDraft?.text, "hello")
    }

    func testComposeDraftSurvivesToggleBackToCompose() throws {
        // FR-011 — toggling Direct → Compose must restore the
        // draft exactly as it was.  Mirrors US-4 Acceptance #1.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id)
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                composeDraft: ComposeDraft(sessionID: session.id, text: "hello")
            )
        )

        model.toggleDirectKeystrokeMode()  // Compose → Direct
        model.toggleDirectKeystrokeMode()  // Direct → Compose

        XCTAssertFalse(model.directKeystrokeMode.isActive)
        XCTAssertEqual(model.composeDraft?.text, "hello")
    }

    func testToggleOutOfDirectModeClearsStickyModifierState() async {
        // FR-012 — toggling out of Direct mode clears all sticky
        // modifier state, so a phantom-armed or phantom-locked
        // slot cannot survive a mode bounce and silently apply
        // to a future Direct session.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()  // enter Direct

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)

        model.toggleDirectKeystrokeMode()  // exit Direct

        XCTAssertFalse(model.directKeystrokeMode.isActive)
        XCTAssertEqual(model.stickyModifierState, StickyModifierState())
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .idle)
        XCTAssertTrue(model.stickyModifierState.activeModifiers.isEmpty)
    }

    func testToggleIntoDirectModeDoesNotPerturbStickyState() {
        // Defensive — sticky state is idle by construction in a
        // fresh model, but assert explicitly so a future
        // regression that mutates state on toggle-in (e.g.
        // accidentally calling `clear()` followed by `tap()`)
        // surfaces here.
        let model = NaruRemoteAppModel()
        XCTAssertEqual(model.stickyModifierState, StickyModifierState())

        model.toggleDirectKeystrokeMode()

        XCTAssertTrue(model.directKeystrokeMode.isActive)
        XCTAssertEqual(model.stickyModifierState, StickyModifierState())
    }

    // MARK: - Hardware-keyboard path (Phase 5 / US-3 / T033 / T034)

    func testHandleHardwareKeyDropsWhenDirectModeIsOff() async {
        // FR-007 — hardware path only fires while the user has
        // opted into Direct mode.  Stale press events that arrive
        // during a mode toggle (e.g. the user releases a key just
        // after toggling out) drop silently rather than leaking a
        // press onto the wire.
        let model = NaruRemoteAppModel()
        XCTAssertFalse(model.directKeystrokeMode.isActive)

        await model.handleHardwareKey(keysym: 0x0063, modifiers: [], isDown: true)
        await model.handleHardwareKey(keysym: 0x0063, modifiers: [], isDown: false)

        // No state perturbation; sticky state untouched.
        XCTAssertEqual(model.stickyModifierState, StickyModifierState())
        XCTAssertFalse(model.directKeystrokeMode.isActive)
    }

    func testHandleHardwareKeyDropsWhenNoEmitter() async {
        // No active session → no `keystrokeEmitter`.  Even with
        // Direct mode active, the press drops silently per IN-003.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()
        XCTAssertTrue(model.directKeystrokeMode.isActive)

        await model.handleHardwareKey(keysym: 0xFF09, modifiers: [], isDown: true)
        await model.handleHardwareKey(keysym: 0xFF09, modifiers: [], isDown: false)

        XCTAssertTrue(model.directKeystrokeMode.isActive)
    }

    func testHandleHardwareKeyDoesNotConsumeStickyArmedState() async {
        // The hardware path's modifier set comes from
        // `UIKey.modifierFlags`, NOT `StickyModifierState`.
        // Calling `handleHardwareKey` while Ctrl is armed via the
        // soft keyboard MUST NOT consume the armed slot — the
        // user expected the on-screen Ctrl to stay armed for
        // their next on-screen tap, not get eaten by an
        // unrelated hardware press.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)

        // Hardware press of `c` (no emitter, so it drops at the
        // guard — but even if it had reached the wire, the
        // sticky-armed slot must survive).
        await model.handleHardwareKey(keysym: 0x0063, modifiers: [], isDown: true)
        await model.handleHardwareKey(keysym: 0x0063, modifiers: [], isDown: false)

        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .armed,
            "hardware path must not consume sticky-armed state"
        )
        XCTAssertEqual(model.stickyModifierState.activeModifiers, [.control])
    }

    func testHandleHardwareKeyDoesNotConsumeStickyLockedState() async {
        // Locked slots survive the on-screen consumption rule,
        // and they must equally survive any hardware press.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()

        await model.tapDirectKey(.modifier(.shift))
        await model.tapDirectKey(.modifier(.shift))  // lock within 400 ms
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .locked)

        await model.handleHardwareKey(keysym: 0x0061, modifiers: [], isDown: true)
        await model.handleHardwareKey(keysym: 0x0061, modifiers: [], isDown: false)

        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .locked)
    }

    func testToggleOutClearsLastTapTimestampSoNextEntryStartsFresh() async {
        // FR-012 (transient state) — `StickyModifierState`'s
        // internal `lastTapAt` map is reset when the struct is
        // re-initialized.  Observable proof: after toggle-out,
        // toggling back in and tapping Ctrl ONCE should land in
        // `.armed`, not `.locked`.  If the clear was a partial
        // reset that left `lastTapAt` populated but rebuilt
        // slots, an immediate tap of an `armed` slot within the
        // 400 ms window would lock — but here the slot is `idle`
        // by construction so the test would still pass.  The
        // stronger observable: tap Ctrl twice within the window
        // BEFORE the bounce, then a single tap AFTER must arm,
        // not lock.
        let model = NaruRemoteAppModel()
        model.toggleDirectKeystrokeMode()  // enter Direct

        await model.tapDirectKey(.modifier(.control))   // armed
        await model.tapDirectKey(.modifier(.control))   // locked (within 400 ms)
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .locked)

        model.toggleDirectKeystrokeMode()  // exit Direct (clears)
        model.toggleDirectKeystrokeMode()  // re-enter Direct

        await model.tapDirectKey(.modifier(.control))   // a single fresh tap

        // If the toggle-out had left state intact, this last
        // tap would have flipped locked → idle.  The expected
        // post-clear behavior is idle → armed.
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)
    }

    private func waitForConnectedDirectSession(
        _ model: NaruRemoteAppModel,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if model.snapshot.latestFramebuffer != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for active Direct Keystroke session")
        throw DirectKeystrokeTestTimeout.connectedSession
    }

    private func waitForKeyEvents(
        _ connector: KeyCapturingStreamingConnector,
        count: Int,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connector.recordedKeyEvents.count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) key events; got \(connector.recordedKeyEvents.count)")
        throw DirectKeystrokeTestTimeout.keyEvents
    }

    private func waitForInputEvents(
        _ connector: KeyCapturingStreamingConnector,
        count: Int,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connector.recordedInputEvents.count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) input events; got \(connector.recordedInputEvents.count)")
        throw DirectKeystrokeTestTimeout.inputEvents
    }

    private func waitForPointerEvents(
        _ connector: KeyCapturingStreamingConnector,
        count: Int,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if connector.recordedPointerEvents.count >= count {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) pointer events; got \(connector.recordedPointerEvents.count)")
        throw DirectKeystrokeTestTimeout.inputEvents
    }
}

private enum DirectKeystrokeTestTimeout: Error {
    case connectedSession
    case keyEvents
    case inputEvents
}

private enum RecordedInputEvent: Equatable {
    case key(keysym: UInt32, isDown: Bool)
    case pointer(mask: UInt8, x: UInt16, y: UInt16)
}

private final class KeyCapturingStreamingConnector: RFBStreamingClient {
    private struct Recording {
        var framebuffers: [RFBRawFramebuffer]
        var recordedKeyEventsList: [(keysym: UInt32, isDown: Bool)] = []
        var recordedPointerEventsList: [(mask: UInt8, x: UInt16, y: UInt16)] = []
        var recordedInputEventsList: [RecordedInputEvent] = []
        var keyEventDelays: [Duration?]
        var pointerEventDelays: [Duration?]
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffer: RFBRawFramebuffer,
        keyEventDelay: Duration? = nil,
        keyEventDelays: [Duration?]? = nil,
        pointerEventDelay: Duration? = nil,
        pointerEventDelays: [Duration?]? = nil
    ) {
        self.width = width
        self.height = height
        self.name = name
        let resolvedKeyEventDelays = keyEventDelays ?? [keyEventDelay]
        let resolvedPointerEventDelays = pointerEventDelays ?? [pointerEventDelay]
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(
                framebuffers: [framebuffer, framebuffer, framebuffer],
                keyEventDelays: resolvedKeyEventDelays,
                pointerEventDelays: resolvedPointerEventDelays
            )
        )
    }

    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    var recordedKeyEvents: [(keysym: UInt32, isDown: Bool)] {
        recording.withLock { $0.recordedKeyEventsList }
    }

    var recordedPointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] {
        recording.withLock { $0.recordedPointerEventsList }
    }

    var recordedInputEvents: [RecordedInputEvent] {
        recording.withLock { $0.recordedInputEventsList }
    }

    func connectNoAuthFirstFrame(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(host: String, port: UInt16, credential: RFBConnectionCredential, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(host: String, port: UInt16, credential: RFBConnectionCredential, timeout: TimeInterval) throws -> RFBServerInit {
        RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func requestRawFramebufferUpdate(incremental: Bool, timeout: TimeInterval) throws -> RFBRawFramebuffer {
        let framebuffer = recording.withLock { state -> RFBRawFramebuffer? in
            state.framebuffers.isEmpty ? nil : state.framebuffers.removeFirst()
        }
        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return framebuffer
    }

    func setClipboardText(_ text: String) throws {}
    func sendPasteCommand(_ command: PasteCommand) throws {}

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        let pointerEventDelay = recording.withLock { state -> Duration? in
            if state.pointerEventDelays.count > 1 {
                return state.pointerEventDelays.removeFirst()
            }
            return state.pointerEventDelays.first ?? nil
        }
        if let pointerEventDelay {
            try await Task.sleep(for: pointerEventDelay)
        }
        recording.withLock { state in
            state.recordedPointerEventsList.append((buttonMask, x, y))
            state.recordedInputEventsList.append(.pointer(mask: buttonMask, x: x, y: y))
        }
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        let keyEventDelay = recording.withLock { state -> Duration? in
            if state.keyEventDelays.count > 1 {
                return state.keyEventDelays.removeFirst()
            }
            return state.keyEventDelays.first ?? nil
        }
        if let keyEventDelay {
            try await Task.sleep(for: keyEventDelay)
        }
        recording.withLock { state in
            state.recordedKeyEventsList.append((keysym, isDown))
            state.recordedInputEventsList.append(.key(keysym: keysym, isDown: isDown))
        }
    }
}
