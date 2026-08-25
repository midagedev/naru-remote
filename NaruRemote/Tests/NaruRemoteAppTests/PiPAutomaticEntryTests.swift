import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation

/// Spec 036: PiP that opens when you ask, and when you leave.
///
/// What is provable here is the *bookkeeping*. Neither the layer-mounting fix
/// (FR-001) nor `canStartPictureInPictureAutomaticallyFromInline` itself
/// (FR-004) can be executed by any runner available in this repository:
/// `AVPictureInPictureController.isPictureInPictureSupported()` is false on the
/// iPhone simulator (measured, spec 032). Those two are read from the diff and
/// confirmed on a device. What these tests hold is the part that decides
/// whether an automatically-started window is alive or frozen.
@MainActor
final class PiPAutomaticEntryTests: XCTestCase {

    private func makeModel(
        controller: AutomaticEntryFakeController
    ) throws -> NaruRemoteAppModel {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        return NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                session: session,
                latestFramebuffer: RFBRawFramebuffer(width: 4, height: 4)
            ),
            pipWatchController: controller
        )
    }

    // MARK: - FR-002: the controller is armed while the session is live

    func testRefreshPreparesTheControllerBeforeAnyTap() throws {
        let controller = AutomaticEntryFakeController()
        let model = try makeModel(controller: controller)

        model.refreshPiPAutomaticEntry()

        XCTAssertEqual(
            controller.prepareWithHostCount,
            1,
            "A controller that does not exist yet cannot be started — by a tap without a delay, or by the system"
        )
        XCTAssertEqual(
            controller.automaticEntrySettings,
            [true],
            "Automatic entry defaults on (FR-005)"
        )
        XCTAssertEqual(controller.startCount, 0, "Arming is not entering")
    }

    func testTurningAutomaticEntryOffReachesTheController() throws {
        let controller = AutomaticEntryFakeController()
        let model = try makeModel(controller: controller)
        model.refreshPiPAutomaticEntry()

        model.setPiPEntersOnLeavingApp(false)

        XCTAssertFalse(model.pipEntersOnLeavingApp)
        XCTAssertEqual(controller.automaticEntrySettings.last, false)
    }

    // MARK: - FR-004: a window the app did not start is a real session

    func testSystemStartedWindowBecomesAWatchingSession() throws {
        let controller = AutomaticEntryFakeController()
        let model = try makeModel(controller: controller)
        model.refreshPiPAutomaticEntry()
        XCTAssertNil(model.snapshot.pipWatchSession, "Nothing has entered PiP yet")

        // What AVKit does when the app leaves the foreground with automatic
        // entry armed: it starts PiP and reports `didStart`. No `startPiPWatch`
        // ran, so there is no pending session for the event to update.
        controller.emitStarted()

        XCTAssertEqual(
            model.snapshot.pipWatchSession?.state,
            .watching,
            """
            An automatically-started window has to produce a watching session: \
            every frame after this is gated on one existing, so dropping the \
            event leaves the floating window frozen on whatever it opened with.
            """
        )
    }

    /// FR-003 has no direct handle here: the streaming path that forwards
    /// frames is private and driven by a live socket. What it is gated on is
    /// `pipWatchSession` existing in a watching state, which
    /// `testSystemStartedWindowBecomesAWatchingSession` pins — and the frame
    /// that was already on screen is pushed through at adoption, which is what
    /// this checks, so the window does not open on an empty layer.
    func testSystemStartedWindowOpensWithTheCurrentFrame() throws {
        let controller = AutomaticEntryFakeController()
        let model = try makeModel(controller: controller)
        model.refreshPiPAutomaticEntry()

        controller.emitStarted()

        XCTAssertNotNil(
            model.snapshot.pipWatchSession?.lastFrame,
            "An adopted window records the frame it opened with, so staleness is measured from something"
        )
    }

    func testSystemStartedWindowClosedFromSystemChromeStops() throws {
        let controller = AutomaticEntryFakeController()
        let model = try makeModel(controller: controller)
        model.refreshPiPAutomaticEntry()
        controller.emitStarted()

        controller.emitStopped()

        XCTAssertEqual(
            model.snapshot.pipWatchSession?.state,
            .stopped,
            "Closing the floating window from the system chrome ends the session (spec 032 FR-003)"
        )
    }

    // MARK: - FR-004: the framing mode is not skipped on automatic entry

    func testAutomaticEntryAdoptsTheChosenFramingMode() throws {
        let controller = AutomaticEntryFakeController()
        let model = try makeModel(controller: controller)
        model.setPiPFramingMode(.chosenRegion)
        model.setPiPChosenRegion(
            PiPFramingTarget(centerX: 0.25, centerY: 0.75, zoomScale: 2)
        )
        model.refreshPiPAutomaticEntry()

        controller.emitStarted()

        let viewport = model.pipLayerHost.currentViewport
        XCTAssertEqual(viewport.centerX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(viewport.centerY, 0.75, accuracy: 0.0001)
        XCTAssertEqual(
            viewport.zoomScale,
            2,
            accuracy: 0.0001,
            "Automatic entry is not a second, plainer kind of PiP"
        )
    }
}

/// A controller that reports its lifecycle and accepts an automatic-entry
/// setting, so the model's side of both can be driven without AVKit.
@MainActor
private final class AutomaticEntryFakeController:
    PiPWatchControlling,
    PiPWatchLayerHostAttaching,
    PiPWatchLifecycleReporting,
    PiPWatchAutomaticEntryControlling
{
    let isSupported = true
    var lifecycle = PiPWatchControllerLifecycle()
    var onLifecycleEvent: ((PiPWatchLifecycleEvent) -> Void)?

    private(set) var prepareCount = 0
    private(set) var prepareWithHostCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var automaticEntrySettings: [Bool] = []
    private(set) var enqueuedFramebuffers: [RFBRawFramebuffer] = []

    func prepare() -> Bool {
        prepareCount += 1
        _ = lifecycle.prepare()
        return true
    }

    func prepare(layerHost: PiPLayerHost) -> Bool {
        prepareWithHostCount += 1
        _ = lifecycle.prepare()
        return true
    }

    func setStartsAutomaticallyFromInline(_ enabled: Bool) {
        automaticEntrySettings.append(enabled)
    }

    func enqueue(_ framebuffer: RFBRawFramebuffer) throws {
        enqueuedFramebuffers.append(framebuffer)
    }

    func enqueue(_ framebuffer: RFBRawFramebuffer, viewport: PiPWatchViewport) throws {
        enqueuedFramebuffers.append(framebuffer)
    }

    func start() -> Bool {
        startCount += 1
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()
        return true
    }

    func stop() {
        stop(reason: .userRequested)
    }

    func stop(reason: PiPWatchStopReason) {
        stopCount += 1
        _ = lifecycle.requestStop(reason: reason)
        lifecycle.noteStopped()
    }

    /// The system starting PiP by itself: entry was never requested by the app.
    func emitStarted() {
        _ = lifecycle.requestEntry(isPictureInPicturePossible: true)
        lifecycle.noteStarted()
        onLifecycleEvent?(.started)
    }

    func emitStopped() {
        _ = lifecycle.requestStop(reason: .systemDismissed)
        lifecycle.noteStopped()
        onLifecycleEvent?(.stopped(lifecycle.lastStopReason))
    }
}
#endif
