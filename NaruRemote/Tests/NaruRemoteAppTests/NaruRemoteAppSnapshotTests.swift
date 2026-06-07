import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class NaruRemoteAppSnapshotTests: XCTestCase {
    func testSessionStreamStatsBuildSafeDiagnosticPerformanceReport() throws {
        let framebuffer = RFBRawFramebuffer(width: 4, height: 4)
        let firstFrame = RFBFramePumpFrame(
            sequence: 1,
            framebuffer: framebuffer,
            dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 4, height: 4)],
            changedPixelCount: 16,
            capturedAt: Date(timeIntervalSince1970: 100),
            isIncremental: false,
            encodingMix: RFBFramebufferEncodingMix(rawRectangles: 1)
        )
        let emptyFrame = RFBFramePumpFrame(
            sequence: 2,
            framebuffer: framebuffer,
            dirtyRectangles: [],
            changedPixelCount: 0,
            capturedAt: Date(timeIntervalSince1970: 100.5),
            isIncremental: true,
            encodingMix: RFBFramebufferEncodingMix(copyRectRectangles: 1, cursorRectangles: 1)
        )
        var stats = SessionStreamStats()

        stats.record(
            frame: firstFrame,
            thermalState: .nominal,
            appFrameApplyMilliseconds: 12
        )
        stats.record(
            frame: emptyFrame,
            thermalState: .serious,
            usesAdaptiveClientPressurePacing: true,
            appFrameApplyMilliseconds: 95
        )
        stats.recordRendererUploadTiming(milliseconds: 4)
        stats.recordRendererUploadTiming(milliseconds: 92)
        stats.recordPacingDecision(
            SessionStreamPacingDecision(
                delay: 1.0 / 24.0,
                usesThermalPacing: true,
                usesPowerSaverPacing: false,
                usesEmptyBackoffPacing: false
            )
        )
        stats.recordPacingDecision(
            SessionStreamPacingDecision(
                delay: 0.125,
                usesThermalPacing: false,
                usesPowerSaverPacing: true,
                usesEmptyBackoffPacing: true,
                usesViewportInteractionPacing: true
            )
        )
        stats.recordViewportRedrawDiagnostics(
            ViewportRedrawDiagnostics(
                interactionCount: 2,
                gestureSampleCount: 9,
                gestureLongFrameCount: 2,
                gestureMaxIntervalMilliseconds: 34,
                incomingFrameDeferredCount: 5,
                redrawRequestCount: 11,
                redrawFlushCount: 6,
                decelerationFrameCount: 3,
                observedMaximumFramesPerSecond: 120
            )
        )
        stats.recordViewportInteractionRequestPause(pollCount: 3, milliseconds: 40)
        stats.recordViewportInteractionRequestPause(pollCount: 12, milliseconds: 260)
        stats.recordOutboundInputEvent(
            queueDelayMilliseconds: 12,
            operationMilliseconds: 30
        )
        stats.recordOutboundInputEvent(
            queueDelayMilliseconds: 120,
            operationMilliseconds: 260,
            timedOut: true
        )
        stats.recordMainActorResponsivenessDelay(milliseconds: 12)
        stats.recordMainActorResponsivenessDelay(milliseconds: 260)

        let report = try XCTUnwrap(stats.diagnosticStreamPerformanceReport)
        XCTAssertEqual(report.observedDurationBucket, DiagnosticDurationBucket.underOneSecond.rawValue)
        XCTAssertEqual(report.deliveredFramesPerSecondBucket, DiagnosticFrameRateBucket.underFive.rawValue)
        XCTAssertEqual(report.contentFramesPerSecondBucket, DiagnosticFrameRateBucket.notMeasured.rawValue)
        XCTAssertEqual(report.deliveredFrameCount, 2)
        XCTAssertEqual(report.contentFrameCount, 1)
        XCTAssertEqual(report.emptyUpdateCount, 1)
        XCTAssertEqual(report.startupPreflightRequestedHiddenFrameCount, 0)
        XCTAssertEqual(report.startupPreflightConsumedHiddenFrameCount, 0)
        XCTAssertEqual(report.startupPreflightOutcome, DiagnosticStartupPreflightOutcome.notRequested.rawValue)
        XCTAssertEqual(report.contentFramePermille, 500)
        XCTAssertEqual(report.emptyUpdatePermille, 500)
        XCTAssertEqual(report.transportIdleTimeoutPermille, 0)
        XCTAssertEqual(report.adaptiveClientPressurePacingSampleCount, 1)
        XCTAssertEqual(report.adaptiveClientPressurePacingPermille, 500)
        XCTAssertEqual(report.dirtyRectangleSampleCount, 2)
        XCTAssertEqual(report.dirtyRectangleCountMax, 1)
        XCTAssertEqual(report.dirtyAreaPermilleMax, 1_000)
        XCTAssertEqual(report.changedPixelsPermilleMax, 1_000)
        XCTAssertEqual(report.rendererUploadSampleCount, 1)
        XCTAssertEqual(report.rendererPartialUploadCount, 0)
        XCTAssertEqual(report.rendererFullUploadCount, 1)
        XCTAssertEqual(report.rendererPartialUploadPermille, 0)
        XCTAssertEqual(report.rendererFullUploadPermille, 1_000)
        XCTAssertEqual(report.rendererUploadRegionCountMax, 1)
        XCTAssertEqual(report.rendererUploadTimingSampleCount, 2)
        XCTAssertEqual(report.averageRendererUploadTimingBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(report.maxRendererUploadTimingBucket, DiagnosticTimingBucket.lagging.rawValue)
        XCTAssertEqual(report.viewportInteractionCount, 2)
        XCTAssertEqual(report.viewportGestureSampleCount, 9)
        XCTAssertEqual(report.viewportGestureLongFrameCount, 2)
        XCTAssertEqual(report.viewportGestureLongFramePermille, 222)
        XCTAssertEqual(report.viewportGestureMaxIntervalBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(report.viewportIncomingFrameDeferredCount, 5)
        XCTAssertEqual(report.viewportIncomingFrameDeferredPermille, 313)
        XCTAssertEqual(report.viewportStutterHint, DiagnosticViewportStutterHint.mixedViewportPressure.rawValue)
        XCTAssertEqual(report.viewportRedrawRequestCount, 11)
        XCTAssertEqual(report.viewportRedrawFlushCount, 6)
        XCTAssertEqual(report.viewportDecelerationFrameCount, 3)
        XCTAssertEqual(report.viewportDisplayRefreshRateBucket, DiagnosticFrameRateBucket.sixtyOrMore.rawValue)
        XCTAssertEqual(report.appFrameApplyTimingSampleCount, 2)
        XCTAssertEqual(report.averageAppFrameApplyTimingBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(report.maxAppFrameApplyTimingBucket, DiagnosticTimingBucket.lagging.rawValue)
        XCTAssertEqual(report.streamPacingDelaySampleCount, 2)
        XCTAssertEqual(report.averageStreamPacingDelayBucket, DiagnosticTimingBucket.lagging.rawValue)
        XCTAssertEqual(report.maxStreamPacingDelayBucket, DiagnosticTimingBucket.lagging.rawValue)
        XCTAssertEqual(report.thermalPacingSampleCount, 1)
        XCTAssertEqual(report.powerSaverPacingSampleCount, 1)
        XCTAssertEqual(report.emptyBackoffPacingSampleCount, 1)
        XCTAssertEqual(report.viewportInteractionPacingSampleCount, 1)
        XCTAssertEqual(report.viewportInteractionRequestPauseCount, 2)
        XCTAssertEqual(report.viewportInteractionRequestPausePollCount, 15)
        XCTAssertEqual(
            report.averageViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.lagging.rawValue
        )
        XCTAssertEqual(
            report.maxViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.stalled.rawValue
        )
        XCTAssertEqual(
            report.viewportRequestPauseHint,
            DiagnosticViewportRequestPauseHint.activeMixedViewportPressure.rawValue
        )
        XCTAssertEqual(report.outboundInputEventSampleCount, 2)
        XCTAssertEqual(report.outboundInputEventTimeoutCount, 1)
        XCTAssertEqual(
            report.averageOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.interactive.rawValue
        )
        XCTAssertEqual(
            report.maxOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.lagging.rawValue
        )
        XCTAssertEqual(
            report.averageOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.lagging.rawValue
        )
        XCTAssertEqual(
            report.maxOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.stalled.rawValue
        )
        XCTAssertEqual(report.mainActorResponsivenessSampleCount, 2)
        XCTAssertEqual(
            report.averageMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.lagging.rawValue
        )
        XCTAssertEqual(
            report.maxMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.stalled.rawValue
        )
        XCTAssertEqual(
            report.actualEncodingMix,
            RFBFramebufferEncodingMix(rawRectangles: 1, copyRectRectangles: 1, cursorRectangles: 1)
        )
        XCTAssertEqual(report.thermalState, SessionStreamThermalState.serious.rawValue)
    }

    func testSessionStreamStatsTrackTimeoutsWithoutDirtySamples() {
        let framebuffer = RFBRawFramebuffer(width: 4, height: 4)
        let timeoutFrame = RFBFramePumpFrame(
            sequence: 2,
            framebuffer: framebuffer,
            dirtyRectangles: [],
            changedPixelCount: 0,
            isIncremental: true,
            transportIdleTimedOut: true
        )
        var stats = SessionStreamStats()

        stats.record(frame: timeoutFrame, thermalState: .serious)

        XCTAssertEqual(stats.deliveredFrameCount, 1)
        XCTAssertEqual(stats.contentFrameCount, 0)
        XCTAssertEqual(stats.emptyUpdateCount, 0)
        XCTAssertEqual(stats.transportIdleTimeoutCount, 1)
        XCTAssertEqual(stats.adaptiveClientPressurePacingSampleCount, 0)
        XCTAssertEqual(stats.dirtyRectangleSampleCount, 0)
        XCTAssertEqual(stats.mainActorResponsivenessSampleCount, 0)
        XCTAssertNil(stats.averageDirtyRectangleCount)
        XCTAssertNil(stats.averageDirtyAreaPermille)
        XCTAssertNil(stats.averageChangedPixelsPermille)
        XCTAssertEqual(stats.appFrameApplyTimingSampleCount, 0)
        XCTAssertEqual(stats.thermalState, .serious)
    }

    func testSnapshotUsesSelectedProfileForTitleAndSubtitle() throws {
        let first = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net", port: 5901)

        let snapshot = NaruRemoteAppSnapshot(
            profiles: [first, second],
            selectedProfileID: second.id
        )

        XCTAssertEqual(snapshot.title, "Desk")
        XCTAssertEqual(snapshot.subtitle, "desk.tailnet.ts.net:5901")
        XCTAssertEqual(snapshot.selectedProfile, second)
    }

    func testSnapshotFallsBackToFirstProfileWhenSelectionIsStale() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")

        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: UUID()
        )

        XCTAssertEqual(snapshot.selectedProfile, profile)
        XCTAssertEqual(snapshot.title, "Studio")
    }

    func testInputStatusKeepsUnknownPasteHonest() {
        let sessionID = UUID()
        let draftID = UUID()
        let attempt = TextInjectionAttempt(
            draftID: draftID,
            sessionID: sessionID,
            path: .vncClipboardPaste,
            status: .unknown,
            remoteClipboardRestore: .unsupported,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )

        let snapshot = NaruRemoteAppSnapshot(latestInjectionAttempt: attempt)

        XCTAssertEqual(snapshot.inputStatusText, "Paste command sent; remote app confirmation unavailable.")
    }

    func testInputStatusCompactsBlockedMultilingualComposeFailure() {
        let attempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: UUID(),
            path: .vncClipboardPaste,
            payloadEncoding: .utf8ExtensionRequired,
            status: .failed,
            safeMessage: "Text clipboard unavailable: This VNC server has not confirmed UTF-8 clipboard support."
        )

        let snapshot = NaruRemoteAppSnapshot(latestInjectionAttempt: attempt)

        XCTAssertEqual(
            snapshot.inputStatusText,
            "Multilingual Compose needs Mac helper"
        )
    }

    func testInputHelperStatusSurfacesUTF8ComposeRequirement() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "한글과 English")
        )

        XCTAssertEqual(
            snapshot.inputHelperStatusText,
            "Korean/CJK/emoji needs Mac helper setup"
        )
    }

    func testInputHelperStatusExplainsLegacyUTF8PasteAfterDispatch() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let attempt = TextInjectionAttempt(
            draftID: UUID(),
            sessionID: session.id,
            path: .vncClipboardPaste,
            pasteCommand: .commandV,
            payloadEncoding: .utf8ExtensionRequired,
            clipboardTransferMode: .legacyClientCutText,
            utf8ClipboardSupport: .unknown,
            status: .unknown,
            clipboardSetStatus: .succeeded,
            pasteCommandStatus: .succeeded,
            safeMessage: "Paste command sent through legacy VNC clipboard."
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "한글과 English"),
            latestInjectionAttempt: attempt
        )

        XCTAssertEqual(
            snapshot.inputHelperStatusText,
            "Legacy paste sent; helper is more reliable for Korean/CJK"
        )
    }

    func testInputHelperStatusHidesForAsciiDraftWithoutHelperState() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: session,
            composeDraft: ComposeDraft(sessionID: session.id, text: "hello")
        )

        XCTAssertNil(snapshot.inputHelperStatusText)
    }

    func testInputHelperStatusShowsReachableHelperState() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: session,
            helperTextBridgeState: [
                profile.id: HelperTextBridgeProfileState(
                    isEnabled: true,
                    pairingFingerprint: "sha256:helper-pairing",
                    availability: .reachable,
                    lastCheckedBucket: .recent
                )
            ]
        )

        XCTAssertEqual(snapshot.inputHelperStatusText, "Helper ready for multilingual Compose")
    }

    func testDiagnosticRowsExposeSafeStageText() {
        let profileID = UUID()
        let run = ConnectionDiagnosticRun(
            profileID: profileID,
            stages: [
                DiagnosticMessageCatalog.failure(for: .dns)
            ]
        )

        let snapshot = NaruRemoteAppSnapshot(diagnosticRun: run)

        XCTAssertEqual(snapshot.diagnosticRows.count, 1)
        XCTAssertEqual(snapshot.diagnosticRows.first?.stage, "dns")
        XCTAssertEqual(snapshot.diagnosticRows.first?.status, "failed")
        XCTAssertEqual(snapshot.diagnosticRows.first?.title, "MagicDNS did not resolve")
    }

    func testDiagnosticRowsUseStableUniqueIDsForRepeatedStages() {
        let profileID = UUID()
        let first = DiagnosticMessageCatalog.failure(for: .tcp)
        let second = DiagnosticMessageCatalog.failure(for: .tcp)
        let run = ConnectionDiagnosticRun(profileID: profileID, stages: [first, second])

        let snapshot = NaruRemoteAppSnapshot(diagnosticRun: run)

        XCTAssertEqual(snapshot.diagnosticRows.count, 2)
        XCTAssertNotEqual(snapshot.diagnosticRows[0].id, snapshot.diagnosticRows[1].id)
    }

    func testPiPWatchStatusWaitsForFirstFrameBeforeSessionIsActive() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .connecting)
        let snapshot = NaruRemoteAppSnapshot(profiles: [profile], session: session)

        XCTAssertFalse(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "PiP after first frame")
    }

    func testPiPWatchStatusWaitsForFirstFrameEvenWhenSessionIsActive() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(profileID: profile.id, state: .active)
        let snapshot = NaruRemoteAppSnapshot(profiles: [profile], session: session)

        XCTAssertFalse(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "PiP after first frame")
    }

    func testPiPWatchStatusHonorsProfileOptOut() throws {
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
        let snapshot = NaruRemoteAppSnapshot(profiles: [profile], session: session)

        XCTAssertFalse(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "PiP disabled for profile")
    }

    func testPiPWatchStatusShowsWatchingState() throws {
        let profile = try ConnectionProfile(displayName: "Studio", host: "studio.tailnet.ts.net")
        let session = RemoteSession(
            profileID: profile.id,
            state: .active,
            lastFrameAt: Date(timeIntervalSince1970: 100)
        )
        let pipWatchSession = PiPWatchSession(sessionID: session.id, state: .watching)
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            session: session,
            pipWatchSession: pipWatchSession
        )

        XCTAssertTrue(snapshot.isPiPWatchAvailable)
        XCTAssertEqual(snapshot.pipWatchStatusText, "Watching in PiP")
    }

    func testConnectionGridCardsExposeProfileAndVerdictState() throws {
        let studio = try ConnectionProfile(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            hostKind: .magicDNS
        )
        let publicHost = try ConnectionProfile(
            displayName: "Public Test",
            host: "203.0.113.5",
            hostKind: .advancedManualPublicEndpoint
        )
        let preview = ProfilePreviewThumbnail(
            width: 1,
            height: 1,
            sourceWidth: 2,
            sourceHeight: 2,
            capturedAt: Date(timeIntervalSince1970: 100),
            pixels: [RFBColor(red: 1, green: 2, blue: 3)]
        )
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [studio, publicHost],
            selectedProfileID: publicHost.id,
            profilePreviews: [studio.id: preview],
            profileReachability: [
                studio.id: .reachable,
                publicHost.id: .unreachable(failedStage: .tcp)
            ],
            lastDiagnosticVerdict: [studio.id: .passed]
        )

        XCTAssertEqual(snapshot.connectionGridCards.count, 2)
        XCTAssertEqual(snapshot.connectionGridCards[0].displayName, "Studio")
        XCTAssertEqual(snapshot.connectionGridCards[0].endpoint, "studio.tailnet.ts.net:5900")
        XCTAssertEqual(snapshot.connectionGridCards[0].preview, preview)
        XCTAssertEqual(snapshot.connectionGridCards[0].reachability, .reachable)
        XCTAssertEqual(snapshot.connectionGridCards[0].verdict, .passed)
        XCTAssertFalse(snapshot.connectionGridCards[0].isSelected)
        XCTAssertEqual(snapshot.connectionGridCards[1].hostKind, .advancedManualPublicEndpoint)
        XCTAssertNil(snapshot.connectionGridCards[1].preview)
        XCTAssertEqual(snapshot.connectionGridCards[1].reachability, .unreachable(failedStage: .tcp))
        XCTAssertEqual(snapshot.connectionGridCards[1].verdict, .unknown)
        XCTAssertTrue(snapshot.connectionGridCards[1].isSelected)
    }
}
