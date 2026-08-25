import XCTest
@testable import NaruRemoteCore

final class DiagnosticExportTests: XCTestCase {
    func testDiagnosticFrameRateBucketFromFramesPerSecondUsesDirectBoundary() {
        XCTAssertEqual(DiagnosticFrameRateBucket.bucket(framesPerSecond: nil), .notMeasured)
        XCTAssertEqual(DiagnosticFrameRateBucket.bucket(framesPerSecond: 0), .notMeasured)
        XCTAssertEqual(DiagnosticFrameRateBucket.bucket(framesPerSecond: .nan), .notMeasured)
        XCTAssertEqual(DiagnosticFrameRateBucket.bucket(framesPerSecond: 59.9), .thirtyToSixty)
        XCTAssertEqual(DiagnosticFrameRateBucket.bucket(framesPerSecond: 60), .sixtyOrMore)
        XCTAssertEqual(DiagnosticFrameRateBucket.bucket(framesPerSecond: 120), .sixtyOrMore)
    }

    func testDiagnosticExportOmitsStageDetailsAndNextActionsByDefault() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let stage = DiagnosticStageResult(
            stage: .authentication,
            status: .failed,
            safeTitle: "Authentication failed",
            safeDetail: "Rejected password hunter2 while sending 한글과 English 😊를 같이 입력합니다",
            nextAction: "Try password hunter2 again"
        )
        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: [stage])

        let export = DiagnosticExport(run: run)

        XCTAssertTrue(export.summary.contains("Authentication failed"))
        XCTAssertFalse(export.summary.contains("hunter2"))
        XCTAssertFalse(export.summary.contains("한글과 English"))
        XCTAssertFalse(export.summary.contains("Try password"))
    }

    func testDiagnosticExportUsesCatalogDetailsInsteadOfCallerProvidedRawDetail() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let stage = DiagnosticStageResult(
            stage: .authentication,
            status: .failed,
            safeTitle: "Authentication failed",
            safeDetail: "Rejected password hunter2 while sending 한글과 English 😊를 같이 입력합니다"
        )
        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: [stage])

        let export = DiagnosticExport(
            run: run,
            detailLevel: .stageSummary
        )

        XCTAssertFalse(export.summary.contains("hunter2"))
        XCTAssertFalse(export.summary.contains("한글과 English"))
        XCTAssertTrue(export.summary.contains("Authentication stage."))
    }

    func testDiagnosticExportNeverIncludesCallerProvidedNextAction() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let stage = DiagnosticStageResult(
            stage: .tcp,
            status: .failed,
            safeTitle: "Host reached, VNC port closed",
            safeDetail: "Port closed.",
            nextAction: "Check password hunter2 on the remote host."
        )
        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: [stage])

        let export = DiagnosticExport(
            run: run,
            detailLevel: .stageSummary
        )

        XCTAssertTrue(export.summary.contains("TCP reachability stage."))
        XCTAssertFalse(export.summary.contains("Check password"))
        XCTAssertFalse(export.summary.contains("hunter2"))
    }

    /// The plain-text share rendering must be safe-catalog only —
    /// composed draft text, credential refs, raw clipboard contents,
    /// pixel bytes, and caller-provided `safeDetail` / `nextAction`
    /// strings are forbidden.  The test seeds *every* sentinel into
    /// the run that an end-to-end session could plausibly produce
    /// (failed compose-send, received clipboard event, profile
    /// creation with credential, framebuffer pump activity) and then
    /// asserts each sentinel is absent.
    func testRenderShareTextIsSafeCatalogOnlyAcrossEverySession() throws {
        let composedDraftSentinel = "한글과 English 😊 SECRETPHRASE"
        let credentialRefSentinel = "vnc-password:hunter2-credential"
        let rawClipboardSentinel = "REMOTE_COPY_TEXT_DEADBEEF"
        let pixelSentinel = "\u{ED}\u{C3}\u{AB}\u{FE}" // arbitrary high-byte pattern
        let nextActionSentinel = "Reset password 12345 on the host"

        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            credentialRef: credentialRefSentinel
        )

        // Seed every stage with a caller-provided detail/nextAction
        // that contains a different sentinel; the formatter must
        // ignore all of them and emit only safe-catalog strings.
        let stages: [DiagnosticStageResult] = [
            DiagnosticStageResult(
                stage: .dns,
                status: .passed,
                safeTitle: "Profile ready",
                safeDetail: "creds=\(credentialRefSentinel)",
                nextAction: nextActionSentinel
            ),
            DiagnosticStageResult(
                stage: .tcp,
                status: .passed,
                safeTitle: "VNC port reached",
                safeDetail: "draft=\(composedDraftSentinel)",
                nextAction: nextActionSentinel
            ),
            DiagnosticStageResult(
                stage: .rfbHandshake,
                status: .passed,
                safeTitle: "VNC handshake complete",
                safeDetail: "pixels=\(pixelSentinel)",
                nextAction: nextActionSentinel
            ),
            DiagnosticStageResult(
                stage: .authentication,
                status: .failed,
                safeTitle: "Authentication failed",
                safeDetail: "Rejected password \(credentialRefSentinel) for draft \(composedDraftSentinel)",
                nextAction: nextActionSentinel
            ),
            DiagnosticStageResult(
                stage: .firstFrame,
                status: .passed,
                safeTitle: "First frame received",
                safeDetail: "framebuffer=\(pixelSentinel)",
                nextAction: nextActionSentinel
            ),
            DiagnosticStageResult(
                stage: .clipboardText,
                status: .passed,
                safeTitle: "Text clipboard ready",
                safeDetail: "received=\(rawClipboardSentinel)",
                nextAction: nextActionSentinel
            )
        ]
        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: stages)
        let export = DiagnosticExport(run: run)

        let pinnedDate = Date(timeIntervalSince1970: 1_714_521_600)
        let rendered = export.renderShareText(
            buildVersion: "0.1.0",
            now: pinnedDate
        )

        XCTAssertTrue(rendered.contains("Naru Remote Diagnostic Summary"))
        XCTAssertTrue(rendered.contains("Build 0.1.0"))
        XCTAssertTrue(rendered.contains("[dns] passed"))
        XCTAssertTrue(rendered.contains("[tcp] passed"))
        XCTAssertTrue(rendered.contains("[rfbHandshake] passed"))
        XCTAssertTrue(rendered.contains("[authentication] failed"))
        XCTAssertTrue(rendered.contains("[firstFrame] passed"))
        XCTAssertTrue(rendered.contains("[clipboardText] passed"))
        XCTAssertTrue(rendered.contains("Authentication stage."))
        XCTAssertTrue(rendered.contains("Remote frame receive stage."))
        XCTAssertTrue(rendered.contains("Remote text clipboard stage."))

        // String-contains absence checks.
        XCTAssertFalse(rendered.contains(composedDraftSentinel))
        XCTAssertFalse(rendered.contains(credentialRefSentinel))
        XCTAssertFalse(rendered.contains(rawClipboardSentinel))
        XCTAssertFalse(rendered.contains(nextActionSentinel))
        XCTAssertFalse(rendered.contains("hunter2"))
        XCTAssertFalse(rendered.contains("12345"))
        XCTAssertFalse(rendered.contains("DEADBEEF"))
        XCTAssertFalse(rendered.contains("SECRETPHRASE"))
        XCTAssertFalse(rendered.contains("Reset password"))
        // Caller-provided stage titles never reach the share text.
        XCTAssertFalse(rendered.contains("Profile ready"))
        XCTAssertFalse(rendered.contains("Authentication failed"))
        XCTAssertFalse(rendered.contains("First frame received"))

        // Byte-pattern absence: scan the UTF-8 bytes of the rendered
        // string for the sentinels and the high-byte pixel pattern.
        let renderedBytes = Array(rendered.utf8)
        let forbiddenByteSequences: [[UInt8]] = [
            Array(composedDraftSentinel.utf8),
            Array(credentialRefSentinel.utf8),
            Array(rawClipboardSentinel.utf8),
            Array(pixelSentinel.utf8),
            Array(nextActionSentinel.utf8),
            Array("hunter2".utf8)
        ]
        for sequence in forbiddenByteSequences {
            XCTAssertFalse(
                Self.bytesContain(renderedBytes, subsequence: sequence),
                "rendered share text leaked a forbidden byte sequence"
            )
        }
    }

    func testRenderShareTextHeaderHandlesMissingBuildVersion() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let stage = DiagnosticStageResult(
            stage: .dns,
            status: .passed,
            safeTitle: "Profile ready",
            safeDetail: "anything"
        )
        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: [stage])
        let export = DiagnosticExport(run: run)

        let pinnedDate = Date(timeIntervalSince1970: 1_714_521_600)
        let rendered = export.renderShareText(buildVersion: nil, now: pinnedDate)

        XCTAssertTrue(rendered.hasPrefix("Naru Remote Diagnostic Summary"))
        XCTAssertTrue(rendered.contains("Build n/a"))
        XCTAssertTrue(rendered.contains("[dns] passed"))
    }

    func testRenderShareTextWithoutStagesStillEmitsHeader() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: [])
        let export = DiagnosticExport(run: run)

        let rendered = export.renderShareText(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )

        XCTAssertTrue(rendered.contains("Naru Remote Diagnostic Summary"))
        XCTAssertTrue(rendered.contains("Build 0.1.0"))
        XCTAssertTrue(rendered.contains("(no diagnostic stages recorded)"))
    }

    func testRenderCollectionJSONIsDeterministicCurrentSchema() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let runID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let run = ConnectionDiagnosticRun(
            id: runID,
            profileID: profileID,
            startedAt: Date(timeIntervalSince1970: 1_714_521_618),
            finishedAt: Date(timeIntervalSince1970: 1_714_521_620),
            context: DiagnosticRunContext(
                targetFingerprint: DiagnosticFingerprint.sha256Token("desk.tailnet.ts.net:5901"),
                profileHostKind: ConnectionProfile.HostKind.magicDNS.rawValue,
                configuredPort: 5901,
                hasCredentialReference: true,
                trigger: .connect,
                probeTimeoutSeconds: 3
            ),
            stages: [
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .failed,
                    safeTitle: "Host reached, VNC port closed",
                    safeDetail: "caller detail must not appear",
                    timestamp: Date(timeIntervalSince1970: 1_714_521_619),
                    metadata: DiagnosticStageMetadata(failureCode: "network.connectionFailed")
                )
            ]
        )
        let export = DiagnosticExport(run: run)
        let pinnedDate = Date(timeIntervalSince1970: 1_714_521_600)

        let rendered = export.renderCollectionJSON(buildVersion: "0.1.0", now: pinnedDate)
        let renderedAgain = export.renderCollectionJSON(buildVersion: "0.1.0", now: pinnedDate)

        XCTAssertEqual(rendered, renderedAgain)
        XCTAssertTrue(rendered.contains("\"schemaVersion\" : 34"))
        XCTAssertTrue(rendered.contains("\"generatedAt\" : \"2024-05-01T00:00:00Z\""))
        XCTAssertFalse(rendered.contains(profileID.uuidString))
        XCTAssertFalse(rendered.contains(profileID.uuidString.lowercased()))
        XCTAssertFalse(rendered.contains("desk.tailnet.ts.net"))
        XCTAssertFalse(rendered.contains("desk.tailnet.ts.net:5901"))
        XCTAssertFalse(rendered.contains("caller detail"))

        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(rendered.utf8)
        )
        XCTAssertEqual(decoded.schemaVersion, 34)
        XCTAssertEqual(decoded.generatedAt, "2024-05-01T00:00:00Z")
        XCTAssertEqual(decoded.buildVersion, "0.1.0")
        XCTAssertEqual(decoded.runID, runID.uuidString.lowercased())
        XCTAssertEqual(decoded.startedAt, "2024-05-01T00:00:18Z")
        XCTAssertEqual(decoded.finishedAt, "2024-05-01T00:00:20Z")
        XCTAssertEqual(decoded.runDurationBucket, DiagnosticDurationBucket.oneToThreeSeconds.rawValue)
        XCTAssertTrue(decoded.targetFingerprint?.hasPrefix("sha256:") ?? false)
        XCTAssertEqual(decoded.targetFingerprint?.count, "sha256:".count + 64)
        XCTAssertEqual(decoded.profileHostKind, ConnectionProfile.HostKind.magicDNS.rawValue)
        XCTAssertEqual(decoded.configuredPort, 5901)
        XCTAssertEqual(decoded.hasCredentialReference, true)
        XCTAssertEqual(decoded.diagnosticTrigger, DiagnosticRunTrigger.connect.rawValue)
        XCTAssertEqual(decoded.probeTimeoutSeconds, 3)
        XCTAssertEqual(decoded.verdict, DiagnosticVerdict.failed.rawValue)
        XCTAssertTrue(decoded.profileFingerprint.hasPrefix("sha256:"))
        XCTAssertEqual(decoded.profileFingerprint.count, "sha256:".count + 64)
        XCTAssertEqual(decoded.stageRows, export.stageRows)
        XCTAssertEqual(decoded.stageRows.first?.safeDetail, "TCP reachability stage.")
        XCTAssertEqual(decoded.stageRows.first?.recordedAt, "2024-05-01T00:00:19Z")
        XCTAssertEqual(decoded.stageRows.first?.failureCode, "network.connectionFailed")
        XCTAssertNil(decoded.streamPerformance)
        XCTAssertNil(decoded.viewerStreamPowerMode)
        XCTAssertNil(decoded.viewerStreamEncodingMode)
        XCTAssertNil(decoded.viewerStartupPreflightMode)
        XCTAssertNil(decoded.viewerStartupGlanceScaleMode)
        XCTAssertNil(decoded.helperVideo)
    }

    func testRenderCollectionJSONIncludesSafeStreamPerformanceSummary() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let run = ConnectionDiagnosticRun(
            profileID: profileID,
            finishedAt: Date(timeIntervalSince1970: 1),
            stages: [
                DiagnosticStageResult(
                    stage: .firstFrame,
                    status: .passed,
                    safeTitle: "Streaming",
                    safeDetail: "caller detail must not appear"
                )
            ]
        )
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: DiagnosticDurationBucket.threeToTenSeconds.rawValue,
            deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket.fifteenToTwentyFour.rawValue,
            contentFramesPerSecondBucket: DiagnosticFrameRateBucket.fiveToFifteen.rawValue,
            deliveredFrameCount: 120,
            contentFrameCount: 90,
            emptyUpdateCount: 25,
            transportIdleTimeoutCount: 5,
            contentFramePermille: 750,
            emptyUpdatePermille: 208,
            transportIdleTimeoutPermille: 42,
            adaptiveClientPressurePacingSampleCount: 9,
            adaptiveClientPressurePacingPermille: 75,
            dirtyRectangleSampleCount: 115,
            averageDirtyRectangleCount: 2,
            dirtyRectangleCountMax: 8,
            averageDirtyAreaPermille: 120,
            dirtyAreaPermilleMax: 900,
            averageChangedPixelsPermille: 100,
            changedPixelsPermilleMax: 875,
            rendererUploadSampleCount: 80,
            rendererPartialUploadCount: 70,
            rendererFullUploadCount: 10,
            rendererPartialUploadPermille: 875,
            rendererFullUploadPermille: 125,
            rendererUploadRegionCountMax: 4,
            rendererUploadTimingSampleCount: 80,
            averageRendererUploadTimingBucket: DiagnosticTimingBucket.subFrame.rawValue,
            maxRendererUploadTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            viewportInteractionCount: 3,
            viewportGestureSampleCount: 17,
            viewportGestureLongFrameCount: 4,
            viewportGestureLongFramePermille: 235,
            viewportGestureMaxIntervalBucket: DiagnosticTimingBucket.interactive.rawValue,
            viewportIncomingFrameDeferredCount: 12,
            viewportIncomingFrameDeferredPermille: 167,
            viewportRedrawRequestCount: 60,
            viewportRedrawFlushCount: 30,
            viewportDecelerationFrameCount: 8,
            viewportDisplayRefreshRateBucket: DiagnosticFrameRateBucket.sixtyOrMore.rawValue,
            appFrameApplyTimingSampleCount: 120,
            averageAppFrameApplyTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxAppFrameApplyTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
            streamPacingDelaySampleCount: 120,
            averageStreamPacingDelayBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxStreamPacingDelayBucket: DiagnosticTimingBucket.lagging.rawValue,
            thermalPacingSampleCount: 4,
            powerSaverPacingSampleCount: 9,
            emptyBackoffPacingSampleCount: 20,
            activeInputPacingSampleCount: 7,
            viewportInteractionPacingSampleCount: 11,
            viewportInteractionRequestPauseCount: 4,
            viewportInteractionRequestPausePollCount: 31,
            averageViewportInteractionRequestPauseBucket: DiagnosticTimingBucket.lagging.rawValue,
            maxViewportInteractionRequestPauseBucket: DiagnosticTimingBucket.stalled.rawValue,
            outboundInputEventSampleCount: 6,
            outboundInputEventTimeoutCount: 1,
            averageOutboundInputQueueDelayBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxOutboundInputQueueDelayBucket: DiagnosticTimingBucket.lagging.rawValue,
            averageOutboundInputOperationTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxOutboundInputOperationTimingBucket: DiagnosticTimingBucket.stalled.rawValue,
            startupPreflightRequestedHiddenFrameCount: 1,
            startupPreflightConsumedHiddenFrameCount: 1,
            startupPreflightOutcome: DiagnosticStartupPreflightOutcome.consumed.rawValue,
            actualEncodingMix: RFBFramebufferEncodingMix(
                rawRectangles: 10,
                copyRectRectangles: 70,
                cursorRectangles: 5
            ),
            thermalState: "serious"
        )
        let export = DiagnosticExport(
            run: run,
            streamPerformance: performance,
            viewerStreamPowerMode: .powerSaver,
            viewerStreamEncodingMode: .adaptiveGoodFull,
            viewerStartupPreflightMode: .oneHiddenFrame,
            viewerStartupGlanceScaleMode: .glance025
        )

        let rendered = export.renderCollectionJSON(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(rendered.utf8)
        )

        XCTAssertEqual(decoded.schemaVersion, 34)
        XCTAssertEqual(decoded.streamPerformance, performance)
        XCTAssertEqual(decoded.viewerStreamPowerMode, StreamPowerMode.powerSaver.rawValue)
        XCTAssertEqual(decoded.viewerStreamEncodingMode, StreamEncodingMode.adaptiveGoodFull.rawValue)
        XCTAssertEqual(decoded.viewerStartupPreflightMode, StreamStartupPreflightMode.oneHiddenFrame.rawValue)
        XCTAssertEqual(decoded.viewerStartupGlanceScaleMode, StreamStartupGlanceScaleMode.glance025.rawValue)
        XCTAssertTrue(rendered.contains("\"streamPerformance\""))
        XCTAssertTrue(rendered.contains("\"contentFramesPerSecondBucket\" : \"fiveToFifteen\""))
        XCTAssertTrue(rendered.contains("\"actualEncodingMix\""))
        XCTAssertTrue(rendered.contains("\"averageAppFrameApplyTimingBucket\" : \"interactive\""))
        XCTAssertTrue(rendered.contains("\"averageRendererUploadTimingBucket\" : \"subFrame\""))
        XCTAssertTrue(rendered.contains("\"averageStreamPacingDelayBucket\" : \"interactive\""))
        XCTAssertTrue(rendered.contains("\"adaptiveClientPressurePacingPermille\" : 75"))
        XCTAssertTrue(rendered.contains("\"thermalPacingSampleCount\" : 4"))
        XCTAssertTrue(rendered.contains("\"powerSaverPacingSampleCount\" : 9"))
        XCTAssertTrue(rendered.contains("\"emptyBackoffPacingSampleCount\" : 20"))
        XCTAssertTrue(rendered.contains("\"activeInputPacingSampleCount\" : 7"))
        XCTAssertTrue(rendered.contains("\"viewportInteractionPacingSampleCount\" : 11"))
        XCTAssertTrue(rendered.contains("\"viewportInteractionRequestPauseCount\" : 4"))
        XCTAssertTrue(rendered.contains("\"viewportInteractionRequestPausePollCount\" : 31"))
        XCTAssertTrue(rendered.contains("\"averageViewportInteractionRequestPauseBucket\" : \"lagging\""))
        XCTAssertTrue(rendered.contains("\"maxViewportInteractionRequestPauseBucket\" : \"stalled\""))
        XCTAssertTrue(rendered.contains("\"viewportRequestPauseHint\" : \"activeGestureLoopPressure\""))
        XCTAssertTrue(rendered.contains("\"viewportGestureSampleCount\" : 17"))
        XCTAssertTrue(rendered.contains("\"viewportGestureLongFramePermille\" : 235"))
        XCTAssertTrue(rendered.contains("\"viewportStutterHint\" : \"gestureLoopPressure\""))
        XCTAssertTrue(rendered.contains("\"viewportGestureMaxIntervalBucket\" : \"interactive\""))
        XCTAssertTrue(rendered.contains("\"viewportIncomingFrameDeferredCount\" : 12"))
        XCTAssertTrue(rendered.contains("\"viewportIncomingFrameDeferredPermille\" : 167"))
        XCTAssertTrue(rendered.contains("\"viewportDisplayRefreshRateBucket\" : \"sixtyOrMore\""))
        XCTAssertTrue(rendered.contains("\"startupPreflightRequestedHiddenFrameCount\" : 1"))
        XCTAssertTrue(rendered.contains("\"startupPreflightConsumedHiddenFrameCount\" : 1"))
        XCTAssertTrue(rendered.contains("\"startupPreflightOutcome\" : \"consumed\""))
        XCTAssertTrue(rendered.contains("\"copyRectRectangles\" : 70"))
        XCTAssertTrue(rendered.contains("\"thermalState\" : \"serious\""))
        XCTAssertTrue(rendered.contains("\"viewerStreamPowerMode\" : \"power-saver\""))
        XCTAssertTrue(rendered.contains("\"viewerStreamEncodingMode\" : \"adaptive-good-full\""))
        XCTAssertTrue(rendered.contains("\"viewerStartupPreflightMode\" : \"one-hidden-frame\""))
        XCTAssertTrue(rendered.contains("\"viewerStartupGlanceScaleMode\" : \"glance-025\""))
        XCTAssertFalse(rendered.contains("caller detail"))
        XCTAssertFalse(rendered.contains(profileID.uuidString))
    }

    func testRenderCollectionJSONIncludesSafeHelperVideoReportWithoutUnsafeFields() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let run = ConnectionDiagnosticRun(
            profileID: profileID,
            finishedAt: Date(timeIntervalSince1970: 1),
            stages: [
                DiagnosticStageResult(
                    stage: .firstFrame,
                    status: .passed,
                    safeTitle: "Streaming",
                    safeDetail: "caller detail must not appear"
                )
            ]
        )
        let helperVideo = DiagnosticHelperVideoReport(
            profileState: HelperVideoProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:should-not-export-helper-pairing",
                availability: .available,
                lastFailureCode: .streamStalled,
                lastCheckedBucket: .recent
            ),
            streamDescriptor: HelperVideoStreamDescriptor(
                protocolVersion: 2,
                codec: .h264,
                codecProfile: .high,
                latencyMode: .lowLatency,
                qualityBucket: .readability,
                frameRateBucket: .upTo30,
                colorMode: .standardDynamicRange,
                supportsKeyframeRequest: true,
                supportsFallbackSignal: true
            ),
            streamHealth: HelperVideoStreamHealth(
                state: .stalled,
                startupBand: .usable,
                sustainedUpdateBand: .stalled,
                decodePressure: .medium,
                fallbackCountBucket: .one
            )
        )
        let export = DiagnosticExport(run: run, helperVideo: helperVideo)

        let rendered = export.renderCollectionJSON(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(rendered.utf8)
        )

        XCTAssertEqual(decoded.schemaVersion, 34)
        XCTAssertEqual(decoded.helperVideo, helperVideo)
        XCTAssertEqual(decoded.helperVideo?.isEnabled, true)
        XCTAssertEqual(decoded.helperVideo?.hasPairingFingerprint, true)
        XCTAssertEqual(decoded.helperVideo?.availability, HelperVideoAvailability.available.rawValue)
        XCTAssertEqual(decoded.helperVideo?.lastFailureCode, HelperVideoFailureCode.streamStalled.rawValue)
        XCTAssertEqual(decoded.helperVideo?.lastCheckedBucket, HelperVideoLastCheckedBucket.recent.rawValue)
        XCTAssertEqual(decoded.helperVideo?.canAttemptHelperVideoStream, true)
        XCTAssertEqual(decoded.helperVideo?.profileUsesVNCVisualFallback, false)
        XCTAssertEqual(decoded.helperVideo?.streamProtocolVersion, 2)
        XCTAssertEqual(decoded.helperVideo?.streamCodec, HelperVideoCodec.h264.rawValue)
        XCTAssertEqual(decoded.helperVideo?.streamCodecProfile, HelperVideoCodecProfile.high.rawValue)
        XCTAssertEqual(decoded.helperVideo?.streamLatencyMode, HelperVideoLatencyMode.lowLatency.rawValue)
        XCTAssertEqual(decoded.helperVideo?.streamQualityBucket, HelperVideoQualityBucket.readability.rawValue)
        XCTAssertEqual(decoded.helperVideo?.streamFrameRateBucket, HelperVideoFrameRateBucket.upTo30.rawValue)
        XCTAssertEqual(decoded.helperVideo?.streamState, HelperVideoStreamState.stalled.rawValue)
        XCTAssertEqual(decoded.helperVideo?.sustainedUpdateBand, HelperVideoSustainedUpdateBand.stalled.rawValue)
        XCTAssertEqual(decoded.helperVideo?.decodePressure, HelperVideoDecodePressure.medium.rawValue)
        XCTAssertEqual(decoded.helperVideo?.fallbackCountBucket, HelperVideoFallbackCountBucket.one.rawValue)
        XCTAssertEqual(decoded.helperVideo?.streamUsesVNCVisualFallback, true)
        XCTAssertTrue(rendered.contains("\"helperVideo\""))
        XCTAssertTrue(rendered.contains("\"streamSupportsFallbackSignal\" : true"))
        XCTAssertFalse(rendered.contains("sha256:should-not-export-helper-pairing"))
        XCTAssertFalse(rendered.contains("caller detail"))

        for forbidden in [
            "framePayload",
            "encoded-bytes",
            "displayID-SECRET",
            "displayName-SECRET",
            "1920x1080",
            "10.0.0.10",
            "desk.local",
            "auth-token",
            "authProof",
            "REMOTE_COPY_TEXT",
            "한글과 English"
        ] {
            XCTAssertFalse(rendered.contains(forbidden))
        }
    }

    func testRenderCollectionJSONIncludesSafeInputReportWithoutDraftText() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let run = ConnectionDiagnosticRun(
            profileID: profileID,
            finishedAt: Date(timeIntervalSince1970: 10),
            stages: [
                DiagnosticStageResult(
                    stage: .clipboardText,
                    status: .passed,
                    safeTitle: "Input",
                    safeDetail: "caller detail must not appear"
                )
            ]
        )
        let sessionID = try XCTUnwrap(UUID(uuidString: "22222222-3333-4444-5555-666666666666"))
        let draftText = "한글과 English 😊 SECRETPHRASE"
        let draft = ComposeDraft(
            sessionID: sessionID,
            text: draftText,
            sendState: .unknown,
            lastStatusMessage: "Paste command sent; remote app confirmation unavailable."
        )
        let attempt = TextInjectionAttempt(
            draftID: draft.id,
            sessionID: sessionID,
            path: .vncClipboardPaste,
            pasteCommand: .commandV,
            payloadEncoding: .utf8ExtensionRequired,
            clipboardTransferMode: .legacyClientCutText,
            utf8ClipboardSupport: .unknown,
            startedAt: Date(timeIntervalSince1970: 7),
            finishedAt: Date(timeIntervalSince1970: 8),
            status: .unknown,
            clipboardSetStatus: .succeeded,
            pasteCommandStatus: .succeeded,
            remoteClipboardRestore: .unsupported,
            safeMessage: "Paste command sent; remote app confirmation unavailable."
        )
        let input = DiagnosticInputReport(
            composeDraft: draft,
            latestInjectionAttempt: attempt,
            directKeystrokeModeActive: false,
            composePlannedPath: .helperTextBridge,
            composeUTF8ClipboardSupport: .unknown,
            composeRouteBlocker: .helperPermissionMissing,
            latestComposeSendPreparation: ComposeSendPreparationReport(
                mode: .markedTextStabilization,
                snapshotCount: 30,
                durationBucket: .stalled
            ),
            helperTextBridgeState: HelperTextBridgeProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:should-not-export",
                availability: .permissionMissing,
                lastFailureCode: .permissionMissing,
                lastCheckedBucket: .recent,
                capabilitySummary: HelperTextBridgeCapabilitySummary(
                    nativeInsert: .missing,
                    accessibilityValueInsert: .missing,
                    unicodeKeyboardEvent: .granted,
                    pasteboardFallback: .available
                )
            )
        )
        let export = DiagnosticExport(run: run, input: input)

        let rendered = export.renderCollectionJSON(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(rendered.utf8)
        )

        XCTAssertEqual(decoded.schemaVersion, 34)
        XCTAssertEqual(decoded.input?.directKeystrokeModeActive, false)
        XCTAssertEqual(decoded.input?.hasComposeDraftText, true)
        XCTAssertEqual(decoded.input?.composeSendState, ComposeSendState.unknown.rawValue)
        XCTAssertEqual(
            decoded.input?.composeDraftPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
        )
        XCTAssertEqual(decoded.input?.composePlannedPath, TextInjectionPath.helperTextBridge.rawValue)
        XCTAssertEqual(
            decoded.input?.composeUTF8ClipboardSupport,
            RemoteClipboardUTF8Support.unknown.rawValue
        )
        XCTAssertEqual(
            decoded.input?.composeRouteBlocker,
            DiagnosticComposeRouteBlocker.helperPermissionMissing.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgeAvailability,
            HelperTextBridgeAvailability.permissionMissing.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgeLastFailureCode,
            HelperTextBridgeFailureCode.permissionMissing.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgeLastCheckedBucket,
            HelperTextBridgeLastCheckedBucket.recent.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgeNativeInsert,
            HelperTextBridgeRouteCapability.missing.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgeAccessibilityValueInsert,
            HelperTextBridgeRouteCapability.missing.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgeUnicodeKeyboardEvent,
            HelperTextBridgeRouteCapability.granted.rawValue
        )
        XCTAssertEqual(
            decoded.input?.helperTextBridgePasteboardFallback,
            HelperTextBridgeRouteCapability.available.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestComposeSendPreparationMode,
            ComposeSendPreparationMode.markedTextStabilization.rawValue
        )
        XCTAssertEqual(decoded.input?.latestComposeSendPreparationSnapshotCount, 30)
        XCTAssertEqual(
            decoded.input?.latestComposeSendPreparationDurationBucket,
            DiagnosticTimingBucket.stalled.rawValue
        )
        XCTAssertEqual(decoded.input?.latestInjectionPath, TextInjectionPath.vncClipboardPaste.rawValue)
        XCTAssertEqual(decoded.input?.latestInjectionStatus, TextInjectionStatus.unknown.rawValue)
        XCTAssertEqual(decoded.input?.latestInjectionPasteCommand, PasteCommand.commandV.rawValue)
        XCTAssertEqual(
            decoded.input?.latestInjectionPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestInjectionClipboardTransferMode,
            TextClipboardTransferMode.legacyClientCutText.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestInjectionUTF8ClipboardSupport,
            RemoteClipboardUTF8Support.unknown.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestInjectionClipboardSetStatus,
            TextInjectionStepStatus.succeeded.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestInjectionPasteCommandStatus,
            TextInjectionStepStatus.succeeded.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestInjectionRemoteClipboardRestore,
            RemoteClipboardRestoreStatus.unsupported.rawValue
        )
        XCTAssertEqual(
            decoded.input?.latestInjectionDurationBucket,
            DiagnosticDurationBucket.oneToThreeSeconds.rawValue
        )
        XCTAssertTrue(rendered.contains("\"input\""))
        XCTAssertFalse(rendered.contains(draftText))
        XCTAssertFalse(rendered.contains("SECRETPHRASE"))
        XCTAssertFalse(rendered.contains("should-not-export"))
        XCTAssertFalse(rendered.contains("Paste command sent"))
        XCTAssertFalse(rendered.contains("caller detail"))
        XCTAssertFalse(rendered.contains(sessionID.uuidString))
    }

    func testInputReportExportsHelperDisabledAndRevokedCatalogStates() {
        let disabled = DiagnosticInputReport(
            composeDraft: nil,
            latestInjectionAttempt: nil,
            directKeystrokeModeActive: false,
            helperTextBridgeState: HelperTextBridgeProfileState(
                isEnabled: false,
                pairingFingerprint: "sha256:should-not-export",
                availability: .disabled,
                lastFailureCode: .disabled,
                lastCheckedBucket: .recent
            )
        )

        XCTAssertEqual(
            disabled.helperTextBridgeAvailability,
            HelperTextBridgeAvailability.disabled.rawValue
        )
        XCTAssertEqual(
            disabled.helperTextBridgeLastFailureCode,
            HelperTextBridgeFailureCode.disabled.rawValue
        )
        XCTAssertEqual(
            disabled.helperTextBridgeLastCheckedBucket,
            HelperTextBridgeLastCheckedBucket.recent.rawValue
        )

        let revoked = DiagnosticInputReport(
            composeDraft: nil,
            latestInjectionAttempt: nil,
            directKeystrokeModeActive: false,
            helperTextBridgeState: HelperTextBridgeProfileState(
                isEnabled: false,
                pairingFingerprint: nil,
                availability: .revoked,
                lastFailureCode: .revoked,
                lastCheckedBucket: .recent
            )
        )

        XCTAssertEqual(
            revoked.helperTextBridgeAvailability,
            HelperTextBridgeAvailability.revoked.rawValue
        )
        XCTAssertEqual(
            revoked.helperTextBridgeLastFailureCode,
            HelperTextBridgeFailureCode.revoked.rawValue
        )
        XCTAssertEqual(
            revoked.helperTextBridgeLastCheckedBucket,
            HelperTextBridgeLastCheckedBucket.recent.rawValue
        )
    }

    func testInputReportClampsUnsafeCatalogValues() {
        let input = DiagnosticInputReport(
            directKeystrokeModeActive: true,
            hasComposeDraftText: true,
            composeSendState: "state=SECRET",
            composeDraftPayloadEncoding: "payload=SECRET",
            composePlannedPath: "plannedPath=SECRET",
            composeUTF8ClipboardSupport: "support=SECRET",
            composeRouteBlocker: "blocker=SECRET",
            latestComposeSendPreparationMode: "prep=SECRET",
            latestComposeSendPreparationSnapshotCount: -30,
            latestComposeSendPreparationDurationBucket: "duration=SECRET",
            helperTextBridgeAvailability: "helper=SECRET",
            helperTextBridgeLastFailureCode: "helperFailure=SECRET",
            helperTextBridgeLastCheckedBucket: "helperChecked=SECRET",
            helperTextBridgeNativeInsert: "native=SECRET",
            helperTextBridgeAccessibilityValueInsert: "ax=SECRET",
            helperTextBridgeUnicodeKeyboardEvent: "unicode=SECRET",
            helperTextBridgePasteboardFallback: "pasteboard=SECRET",
            latestInjectionPath: "path=SECRET",
            latestInjectionStatus: "status=SECRET",
            latestInjectionPasteCommand: "paste=SECRET",
            latestInjectionPayloadEncoding: "payload=SECRET",
            latestInjectionClipboardTransferMode: "mode=SECRET",
            latestInjectionUTF8ClipboardSupport: "support=SECRET",
            latestInjectionHelperStrategy: "strategy=SECRET",
            latestInjectionClipboardSetStatus: "clipboard=SECRET",
            latestInjectionPasteCommandStatus: "command=SECRET",
            latestInjectionRemoteClipboardRestore: "restore=SECRET",
            latestInjectionDurationBucket: "duration=SECRET"
        )

        XCTAssertEqual(input.directKeystrokeModeActive, true)
        XCTAssertEqual(input.hasComposeDraftText, true)
        XCTAssertNil(input.composeSendState)
        XCTAssertNil(input.composeDraftPayloadEncoding)
        XCTAssertNil(input.composePlannedPath)
        XCTAssertNil(input.composeUTF8ClipboardSupport)
        XCTAssertNil(input.composeRouteBlocker)
        XCTAssertNil(input.latestComposeSendPreparationMode)
        XCTAssertEqual(input.latestComposeSendPreparationSnapshotCount, 0)
        XCTAssertNil(input.latestComposeSendPreparationDurationBucket)
        XCTAssertNil(input.helperTextBridgeAvailability)
        XCTAssertNil(input.helperTextBridgeLastFailureCode)
        XCTAssertNil(input.helperTextBridgeLastCheckedBucket)
        XCTAssertNil(input.helperTextBridgeNativeInsert)
        XCTAssertNil(input.helperTextBridgeAccessibilityValueInsert)
        XCTAssertNil(input.helperTextBridgeUnicodeKeyboardEvent)
        XCTAssertNil(input.helperTextBridgePasteboardFallback)
        XCTAssertNil(input.latestInjectionPath)
        XCTAssertNil(input.latestInjectionStatus)
        XCTAssertNil(input.latestInjectionPasteCommand)
        XCTAssertNil(input.latestInjectionPayloadEncoding)
        XCTAssertNil(input.latestInjectionClipboardTransferMode)
        XCTAssertNil(input.latestInjectionUTF8ClipboardSupport)
        XCTAssertNil(input.latestInjectionHelperStrategy)
        XCTAssertNil(input.latestInjectionClipboardSetStatus)
        XCTAssertNil(input.latestInjectionPasteCommandStatus)
        XCTAssertNil(input.latestInjectionRemoteClipboardRestore)
        XCTAssertNil(input.latestInjectionDurationBucket)
    }

    func testHelperVideoReportClampsUnsafeCatalogValues() {
        let report = DiagnosticHelperVideoReport(
            isEnabled: true,
            hasPairingFingerprint: true,
            availability: "availability=SECRET",
            lastFailureCode: HelperVideoFailureCode.transportFailed.rawValue,
            lastCheckedBucket: "checked=SECRET",
            canAttemptHelperVideoStream: true,
            profileUsesVNCVisualFallback: false,
            streamProtocolVersion: -3,
            streamCodec: "codec=SECRET",
            streamCodecProfile: "profile=SECRET",
            streamLatencyMode: "latency=SECRET",
            streamQualityBucket: "quality=SECRET",
            streamFrameRateBucket: "frameRate=SECRET",
            streamColorMode: "color=SECRET",
            streamSupportsKeyframeRequest: true,
            streamSupportsFallbackSignal: true,
            streamState: HelperVideoStreamState.fallbackToVNC.rawValue,
            startupBand: "startup=SECRET",
            sustainedUpdateBand: HelperVideoSustainedUpdateBand.choppy.rawValue,
            decodePressure: "decode=SECRET",
            fallbackCountBucket: HelperVideoFallbackCountBucket.many.rawValue,
            streamUsesVNCVisualFallback: true
        )

        XCTAssertEqual(report.isEnabled, true)
        XCTAssertEqual(report.hasPairingFingerprint, true)
        XCTAssertNil(report.availability)
        XCTAssertEqual(report.lastFailureCode, HelperVideoFailureCode.transportFailed.rawValue)
        XCTAssertNil(report.lastCheckedBucket)
        XCTAssertEqual(report.canAttemptHelperVideoStream, true)
        XCTAssertEqual(report.profileUsesVNCVisualFallback, false)
        XCTAssertEqual(
            report.streamProtocolVersion,
            HelperVideoStreamDescriptor.minimumSupportedProtocolVersion
        )
        XCTAssertNil(report.streamCodec)
        XCTAssertNil(report.streamCodecProfile)
        XCTAssertNil(report.streamLatencyMode)
        XCTAssertNil(report.streamQualityBucket)
        XCTAssertNil(report.streamFrameRateBucket)
        XCTAssertNil(report.streamColorMode)
        XCTAssertEqual(report.streamSupportsKeyframeRequest, true)
        XCTAssertEqual(report.streamSupportsFallbackSignal, true)
        XCTAssertEqual(report.streamState, HelperVideoStreamState.fallbackToVNC.rawValue)
        XCTAssertNil(report.startupBand)
        XCTAssertEqual(report.sustainedUpdateBand, HelperVideoSustainedUpdateBand.choppy.rawValue)
        XCTAssertNil(report.decodePressure)
        XCTAssertEqual(report.fallbackCountBucket, HelperVideoFallbackCountBucket.many.rawValue)
        XCTAssertEqual(report.streamUsesVNCVisualFallback, true)
    }

    func testCollectionReportClampsUnsafeViewerStreamPowerMode() throws {
        let report = DiagnosticCollectionReport(
            generatedAt: "2024-05-01T00:00:00Z",
            buildVersion: "0.1.0",
            runID: UUID().uuidString.lowercased(),
            profileFingerprint: "sha256:\(String(repeating: "0", count: 64))",
            startedAt: "2024-05-01T00:00:00Z",
            finishedAt: nil,
            runDurationBucket: DiagnosticDurationBucket.notMeasured.rawValue,
            verdict: DiagnosticVerdict.unknown.rawValue,
            stageRows: [],
            viewerStreamPowerMode: "mode=SECRET",
            viewerStreamEncodingMode: "encoding=SECRET",
            viewerStartupPreflightMode: "preflight=SECRET",
            viewerStartupGlanceScaleMode: "glance=SECRET"
        )

        XCTAssertNil(report.viewerStreamPowerMode)
        XCTAssertNil(report.viewerStreamEncodingMode)
        XCTAssertNil(report.viewerStartupPreflightMode)
        XCTAssertNil(report.viewerStartupGlanceScaleMode)

        let payload = """
        {
          "schemaVersion": 7,
          "generatedAt": "2024-05-01T00:00:00Z",
          "buildVersion": "0.1.0",
          "runID": "\(UUID().uuidString.lowercased())",
          "profileFingerprint": "sha256:\(String(repeating: "0", count: 64))",
          "startedAt": "2024-05-01T00:00:00Z",
          "runDurationBucket": "notMeasured",
          "verdict": "unknown",
          "stageRows": [],
          "viewerStreamPowerMode": "mode=SECRET",
          "viewerStreamEncodingMode": "encoding=SECRET",
          "viewerStartupPreflightMode": "preflight=SECRET",
          "viewerStartupGlanceScaleMode": "glance=SECRET"
        }
        """
        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(decoded.viewerStreamPowerMode)
        XCTAssertNil(decoded.viewerStreamEncodingMode)
        XCTAssertNil(decoded.viewerStartupPreflightMode)
        XCTAssertNil(decoded.viewerStartupGlanceScaleMode)
    }

    func testSustainedSessionAssessmentClassifiesSafeStreamAndInputSignals() throws {
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: DiagnosticDurationBucket.overTenSeconds.rawValue,
            deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket.fiveToFifteen.rawValue,
            contentFramesPerSecondBucket: DiagnosticFrameRateBucket.underFive.rawValue,
            deliveredFrameCount: 20,
            contentFrameCount: 10,
            emptyUpdateCount: 10,
            transportIdleTimeoutCount: 0,
            adaptiveClientPressurePacingSampleCount: 12,
            adaptiveClientPressurePacingPermille: 600,
            dirtyRectangleSampleCount: 10,
            dirtyRectangleCountMax: 1,
            dirtyAreaPermilleMax: 100,
            changedPixelsPermilleMax: 100,
            rendererUploadSampleCount: 10,
            rendererPartialUploadCount: 9,
            rendererFullUploadCount: 1,
            rendererFullUploadPermille: 100,
            viewportInteractionCount: 2,
            viewportGestureSampleCount: 10,
            viewportGestureLongFrameCount: 3,
            viewportIncomingFrameDeferredCount: 4,
            viewportRedrawRequestCount: 10,
            viewportInteractionRequestPauseCount: 2,
            thermalState: "serious"
        )
        let input = DiagnosticInputReport(
            composeRouteBlocker: DiagnosticComposeRouteBlocker.helperNotConfigured.rawValue,
            latestComposeSendPreparationDurationBucket: DiagnosticTimingBucket.stalled.rawValue
        )

        let assessment = try XCTUnwrap(
            DiagnosticSustainedSessionAssessment.assess(
                streamPerformance: performance,
                input: input,
                contentFramesPerSecond: 2.5
            )
        )

        XCTAssertEqual(assessment.targetName, DiagnosticSustainedSessionAssessment.target.rawValue)
        XCTAssertEqual(assessment.verdict, DiagnosticSustainedSessionVerdict.fail.rawValue)
        XCTAssertEqual(
            assessment.issueCodes,
            [
                DiagnosticSustainedSessionIssueCode.contentFrameRateFailed.rawValue,
                DiagnosticSustainedSessionIssueCode.rendererFullUploadFailed.rawValue,
                DiagnosticSustainedSessionIssueCode.adaptivePressureFailed.rawValue,
                DiagnosticSustainedSessionIssueCode.seriousThermalState.rawValue,
                DiagnosticSustainedSessionIssueCode.viewportGesturePressure.rawValue,
                DiagnosticSustainedSessionIssueCode.viewportIncomingFramePressure.rawValue,
                DiagnosticSustainedSessionIssueCode.viewportRequestPauseActive.rawValue,
                DiagnosticSustainedSessionIssueCode.composeRouteBlocked.rawValue,
                DiagnosticSustainedSessionIssueCode.composeSendPreparationStalled.rawValue
            ]
        )
        XCTAssertEqual(
            assessment.primaryIssueCode,
            DiagnosticSustainedSessionIssueCode.seriousThermalState.rawValue
        )
        XCTAssertEqual(
            assessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.thermal.rawValue
        )
        XCTAssertEqual(
            assessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runPowerSaverThermalPass.rawValue
        )
        XCTAssertEqual(
            assessment.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.blocked.rawValue
        )
    }

    func testSustainedSessionAssessmentPassesCleanMeasuredSession() {
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: DiagnosticDurationBucket.overTenSeconds.rawValue,
            deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket.fifteenToTwentyFour.rawValue,
            contentFramesPerSecondBucket: DiagnosticFrameRateBucket.fiveToFifteen.rawValue,
            deliveredFrameCount: 16,
            contentFrameCount: 12,
            emptyUpdateCount: 4,
            transportIdleTimeoutCount: 0,
            dirtyRectangleSampleCount: 12,
            dirtyRectangleCountMax: 1,
            dirtyAreaPermilleMax: 100,
            changedPixelsPermilleMax: 100,
            rendererUploadSampleCount: 12,
            rendererPartialUploadCount: 12,
            rendererFullUploadCount: 0,
            rendererFullUploadPermille: 0,
            thermalState: "nominal"
        )
        let input = DiagnosticInputReport(
            composeRouteBlocker: DiagnosticComposeRouteBlocker.emptyDraft.rawValue
        )

        let assessment = DiagnosticSustainedSessionAssessment.assess(
            streamPerformance: performance,
            input: input,
            contentFramesPerSecond: 12
        )

        XCTAssertEqual(assessment?.verdict, DiagnosticSustainedSessionVerdict.pass.rawValue)
        XCTAssertEqual(assessment?.issueCodes, [])
        XCTAssertNil(assessment?.primaryIssueCode)
        XCTAssertEqual(
            assessment?.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.none.rawValue
        )
        XCTAssertEqual(
            assessment?.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.none.rawValue
        )
        XCTAssertEqual(
            assessment?.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.pass.rawValue
        )
    }

    func testSustainedSessionAssessmentTriagePrioritizesViewportHandFeel() {
        let assessment = DiagnosticSustainedSessionAssessment(
            issueCodes: [
                DiagnosticSustainedSessionIssueCode.contentFrameRateFailed.rawValue,
                DiagnosticSustainedSessionIssueCode.viewportGesturePressure.rawValue,
                DiagnosticSustainedSessionIssueCode.composeSendPreparationStalled.rawValue
            ]
        )

        XCTAssertEqual(assessment.verdict, DiagnosticSustainedSessionVerdict.fail.rawValue)
        XCTAssertEqual(
            assessment.primaryIssueCode,
            DiagnosticSustainedSessionIssueCode.viewportGesturePressure.rawValue
        )
        XCTAssertEqual(
            assessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.viewportInteraction.rawValue
        )
        XCTAssertEqual(
            assessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runViewportInteractionTrace.rawValue
        )
        XCTAssertEqual(
            assessment.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.blocked.rawValue
        )
    }

    func testSustainedSessionAssessmentCodableIncludesTriageSurface() throws {
        let assessment = DiagnosticSustainedSessionAssessment(
            issueCodes: [
                DiagnosticSustainedSessionIssueCode.clientProcessingStalled.rawValue,
                DiagnosticSustainedSessionIssueCode.composeRouteBlocked.rawValue
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = String(decoding: try encoder.encode(assessment), as: UTF8.self)

        XCTAssertTrue(payload.contains("\"primaryIssueCode\":\"clientProcessingStalled\""))
        XCTAssertTrue(payload.contains("\"primaryConstraint\":\"clientDecode\""))
        XCTAssertTrue(payload.contains("\"recommendedNextProbe\":\"compareEncodingProfileGate\""))
        XCTAssertTrue(payload.contains("\"physicalGateVerdict\":\"blocked\""))

        let decoded = try JSONDecoder().decode(
            DiagnosticSustainedSessionAssessment.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(decoded, assessment)
    }

    func testSustainedSessionAssessmentDecodesV27PayloadWithoutTriageFields() throws {
        let payload = """
        {
          "targetName": "iphone-sustained-usability-v2",
          "verdict": "warning",
          "issueCodes": [
            "contentFrameRateWarning",
            "viewportIncomingFramePressure"
          ]
        }
        """

        let decoded = try JSONDecoder().decode(
            DiagnosticSustainedSessionAssessment.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(decoded.verdict, DiagnosticSustainedSessionVerdict.warning.rawValue)
        XCTAssertEqual(
            decoded.primaryIssueCode,
            DiagnosticSustainedSessionIssueCode.viewportIncomingFramePressure.rawValue
        )
        XCTAssertEqual(
            decoded.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.viewportInteraction.rawValue
        )
        XCTAssertEqual(
            decoded.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runViewportInteractionTrace.rawValue
        )
        XCTAssertEqual(
            decoded.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.blocked.rawValue
        )
    }

    func testSustainedSessionAssessmentRecomputesMismatchedDecodedTriageFields() throws {
        let payload = """
        {
          "targetName": "iphone-sustained-usability-v2",
          "verdict": "warning",
          "issueCodes": [
            "contentFrameRateWarning"
          ],
          "primaryIssueCode": "contentFrameRateWarning",
          "primaryConstraint": "thermal",
          "recommendedNextProbe": "inspectComposeRoute",
          "physicalGateVerdict": "pass"
        }
        """

        let decoded = try JSONDecoder().decode(
            DiagnosticSustainedSessionAssessment.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(
            decoded.primaryIssueCode,
            DiagnosticSustainedSessionIssueCode.contentFrameRateWarning.rawValue
        )
        XCTAssertEqual(
            decoded.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.contentCadence.rawValue
        )
        XCTAssertEqual(
            decoded.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runSustainedV2ProfileGate.rawValue
        )
        XCTAssertEqual(
            decoded.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.blocked.rawValue
        )
    }

    func testSustainedSessionAssessmentSanitizesUnsafeCatalogValues() {
        let assessment = DiagnosticSustainedSessionAssessment(
            targetName: "target=SECRET",
            verdict: "verdict=SECRET",
            issueCodes: [
                DiagnosticSustainedSessionIssueCode.contentFrameRateFailed.rawValue,
                "issue=SECRET",
                DiagnosticSustainedSessionIssueCode.contentFrameRateFailed.rawValue,
                DiagnosticSustainedSessionIssueCode.elevatedThermalState.rawValue
            ]
        )

        XCTAssertEqual(assessment.targetName, DiagnosticSustainedSessionAssessment.target.rawValue)
        XCTAssertEqual(assessment.verdict, DiagnosticSustainedSessionVerdict.fail.rawValue)
        XCTAssertEqual(
            assessment.issueCodes,
            [
                DiagnosticSustainedSessionIssueCode.contentFrameRateFailed.rawValue,
                DiagnosticSustainedSessionIssueCode.elevatedThermalState.rawValue
            ]
        )
        XCTAssertEqual(
            assessment.primaryIssueCode,
            DiagnosticSustainedSessionIssueCode.elevatedThermalState.rawValue
        )
        XCTAssertEqual(
            assessment.primaryConstraint,
            DiagnosticSustainedSessionPrimaryConstraint.thermal.rawValue
        )
        XCTAssertEqual(
            assessment.recommendedNextProbe,
            DiagnosticSustainedSessionNextProbe.runPowerSaverThermalPass.rawValue
        )
        XCTAssertEqual(
            assessment.physicalGateVerdict,
            DiagnosticSustainedSessionPhysicalGateVerdict.blocked.rawValue
        )
    }

    func testStreamPerformanceReportClampsUnsafeCatalogValues() {
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: "duration=SECRET",
            deliveredFramesPerSecondBucket: "fps=SECRET",
            contentFramesPerSecondBucket: "contentFps=SECRET",
            deliveredFrameCount: -1,
            contentFrameCount: -2,
            emptyUpdateCount: -3,
            transportIdleTimeoutCount: -4,
            contentFramePermille: 2_000,
            emptyUpdatePermille: -10,
            transportIdleTimeoutPermille: 42,
            adaptiveClientPressurePacingSampleCount: 50,
            adaptiveClientPressurePacingPermille: 2_000,
            dirtyRectangleSampleCount: -5,
            averageDirtyRectangleCount: -6,
            dirtyRectangleCountMax: -7,
            averageDirtyAreaPermille: 3_000,
            dirtyAreaPermilleMax: -8,
            averageChangedPixelsPermille: -9,
            changedPixelsPermilleMax: 4_000,
            rendererUploadSampleCount: -10,
            rendererPartialUploadCount: -11,
            rendererFullUploadCount: -12,
            rendererPartialUploadPermille: 4_000,
            rendererFullUploadPermille: -20,
            rendererUploadRegionCountMax: -13,
            rendererUploadTimingSampleCount: -16,
            averageRendererUploadTimingBucket: "timing=SECRET",
            maxRendererUploadTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
            viewportInteractionCount: -17,
            viewportGestureSampleCount: -18,
            viewportGestureLongFrameCount: -19,
            viewportGestureLongFramePermille: 2_000,
            viewportGestureMaxIntervalBucket: "timing=SECRET",
            viewportIncomingFrameDeferredCount: -18,
            viewportIncomingFrameDeferredPermille: -20,
            viewportStutterHint: "hint=SECRET",
            viewportRedrawRequestCount: -19,
            viewportRedrawFlushCount: -20,
            viewportDecelerationFrameCount: -21,
            viewportDisplayRefreshRateBucket: "fps=SECRET",
            receiveTimingSampleCount: -14,
            averageReceiveTotalTimingBucket: "timing=SECRET",
            maxReceiveTotalTimingBucket: DiagnosticTimingBucket.stalled.rawValue,
            averageNetworkReadTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
            maxNetworkReadTimingBucket: "timing=SECRET",
            averageClientProcessingTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxClientProcessingTimingBucket: "timing=SECRET",
            appFrameApplyTimingSampleCount: -15,
            averageAppFrameApplyTimingBucket: "timing=SECRET",
            maxAppFrameApplyTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
            streamPacingDelaySampleCount: -16,
            averageStreamPacingDelayBucket: "timing=SECRET",
            maxStreamPacingDelayBucket: DiagnosticTimingBucket.stalled.rawValue,
            thermalPacingSampleCount: 100,
            powerSaverPacingSampleCount: -1,
            emptyBackoffPacingSampleCount: 100,
            viewportInteractionPacingSampleCount: 100,
            viewportInteractionRequestPauseCount: -22,
            viewportInteractionRequestPausePollCount: -23,
            averageViewportInteractionRequestPauseBucket: "timing=SECRET",
            maxViewportInteractionRequestPauseBucket: DiagnosticTimingBucket.stalled.rawValue,
            viewportRequestPauseHint: "hint=SECRET",
            outboundInputEventSampleCount: -24,
            outboundInputEventTimeoutCount: 500,
            averageOutboundInputQueueDelayBucket: "timing=SECRET",
            maxOutboundInputQueueDelayBucket: DiagnosticTimingBucket.lagging.rawValue,
            averageOutboundInputOperationTimingBucket: "timing=SECRET",
            maxOutboundInputOperationTimingBucket: DiagnosticTimingBucket.stalled.rawValue,
            mainActorResponsivenessSampleCount: -25,
            averageMainActorResponsivenessDelayBucket: "timing=SECRET",
            maxMainActorResponsivenessDelayBucket: DiagnosticTimingBucket.stalled.rawValue,
            startupPreflightRequestedHiddenFrameCount: 9,
            startupPreflightConsumedHiddenFrameCount: 8,
            startupPreflightOutcome: "outcome=SECRET",
            actualEncodingMix: RFBFramebufferEncodingMix(
                rawRectangles: -100,
                copyRectRectangles: 2,
                zrleRectangles: -3,
                endOfContinuousUpdatesEvents: 1
            ),
            thermalState: "thermal=SECRET"
        )

        XCTAssertEqual(performance.observedDurationBucket, DiagnosticDurationBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.deliveredFramesPerSecondBucket, DiagnosticFrameRateBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.contentFramesPerSecondBucket, DiagnosticFrameRateBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.deliveredFrameCount, 0)
        XCTAssertEqual(performance.contentFrameCount, 0)
        XCTAssertEqual(performance.emptyUpdateCount, 0)
        XCTAssertEqual(performance.transportIdleTimeoutCount, 0)
        XCTAssertEqual(performance.contentFramePermille, 1_000)
        XCTAssertEqual(performance.emptyUpdatePermille, 0)
        XCTAssertEqual(performance.transportIdleTimeoutPermille, 42)
        XCTAssertEqual(performance.adaptiveClientPressurePacingSampleCount, 0)
        XCTAssertEqual(performance.adaptiveClientPressurePacingPermille, 0)
        XCTAssertEqual(performance.dirtyRectangleSampleCount, 0)
        XCTAssertEqual(performance.averageDirtyRectangleCount, 0)
        XCTAssertEqual(performance.dirtyRectangleCountMax, 0)
        XCTAssertEqual(performance.averageDirtyAreaPermille, 1_000)
        XCTAssertEqual(performance.dirtyAreaPermilleMax, 0)
        XCTAssertEqual(performance.averageChangedPixelsPermille, 0)
        XCTAssertEqual(performance.changedPixelsPermilleMax, 1_000)
        XCTAssertEqual(performance.rendererUploadSampleCount, 0)
        XCTAssertEqual(performance.rendererPartialUploadCount, 0)
        XCTAssertEqual(performance.rendererFullUploadCount, 0)
        XCTAssertEqual(performance.rendererPartialUploadPermille, 1_000)
        XCTAssertEqual(performance.rendererFullUploadPermille, 0)
        XCTAssertEqual(performance.rendererUploadRegionCountMax, 0)
        XCTAssertEqual(performance.rendererUploadTimingSampleCount, 0)
        XCTAssertEqual(performance.averageRendererUploadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxRendererUploadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.viewportInteractionCount, 0)
        XCTAssertEqual(performance.viewportGestureSampleCount, 0)
        XCTAssertEqual(performance.viewportGestureLongFrameCount, 0)
        XCTAssertNil(performance.viewportGestureLongFramePermille)
        XCTAssertEqual(performance.viewportGestureMaxIntervalBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.viewportIncomingFrameDeferredCount, 0)
        XCTAssertNil(performance.viewportIncomingFrameDeferredPermille)
        XCTAssertEqual(performance.viewportStutterHint, DiagnosticViewportStutterHint.notMeasured.rawValue)
        XCTAssertEqual(performance.viewportRedrawRequestCount, 0)
        XCTAssertEqual(performance.viewportRedrawFlushCount, 0)
        XCTAssertEqual(performance.viewportDecelerationFrameCount, 0)
        XCTAssertEqual(performance.viewportDisplayRefreshRateBucket, DiagnosticFrameRateBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.receiveTimingSampleCount, 0)
        XCTAssertEqual(performance.averageReceiveTotalTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxReceiveTotalTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.averageNetworkReadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxNetworkReadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.averageClientProcessingTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxClientProcessingTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.appFrameApplyTimingSampleCount, 0)
        XCTAssertEqual(performance.averageAppFrameApplyTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxAppFrameApplyTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.streamPacingDelaySampleCount, 0)
        XCTAssertEqual(performance.averageStreamPacingDelayBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxStreamPacingDelayBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.thermalPacingSampleCount, 0)
        XCTAssertEqual(performance.powerSaverPacingSampleCount, 0)
        XCTAssertEqual(performance.emptyBackoffPacingSampleCount, 0)
        XCTAssertEqual(performance.activeInputPacingSampleCount, 0)
        XCTAssertEqual(performance.viewportInteractionPacingSampleCount, 0)
        XCTAssertEqual(performance.viewportInteractionRequestPauseCount, 0)
        XCTAssertEqual(performance.viewportInteractionRequestPausePollCount, 0)
        XCTAssertEqual(
            performance.averageViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.viewportRequestPauseHint,
            DiagnosticViewportRequestPauseHint.notMeasured.rawValue
        )
        XCTAssertEqual(performance.outboundInputEventSampleCount, 0)
        XCTAssertEqual(performance.outboundInputEventTimeoutCount, 0)
        XCTAssertEqual(
            performance.averageOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.averageOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(performance.mainActorResponsivenessSampleCount, 0)
        XCTAssertEqual(
            performance.averageMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(performance.startupPreflightRequestedHiddenFrameCount, 1)
        XCTAssertEqual(performance.startupPreflightConsumedHiddenFrameCount, 1)
        XCTAssertEqual(performance.startupPreflightOutcome, DiagnosticStartupPreflightOutcome.consumed.rawValue)
        XCTAssertEqual(
            performance.actualEncodingMix,
            RFBFramebufferEncodingMix(copyRectRectangles: 2, endOfContinuousUpdatesEvents: 1)
        )
        XCTAssertEqual(performance.thermalState, "unknown")
    }

    func testStreamPerformanceReportDerivesViewportStutterPermille() {
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: DiagnosticDurationBucket.threeToTenSeconds.rawValue,
            deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket.fifteenToTwentyFour.rawValue,
            deliveredFrameCount: 30,
            contentFrameCount: 24,
            emptyUpdateCount: 6,
            transportIdleTimeoutCount: 0,
            dirtyRectangleSampleCount: 24,
            dirtyRectangleCountMax: 2,
            dirtyAreaPermilleMax: 600,
            changedPixelsPermilleMax: 500,
            viewportGestureSampleCount: 20,
            viewportGestureLongFrameCount: 5,
            viewportIncomingFrameDeferredCount: 3,
            viewportRedrawRequestCount: 9,
            thermalState: "nominal"
        )

        XCTAssertEqual(performance.viewportGestureLongFramePermille, 250)
        XCTAssertEqual(performance.viewportIncomingFrameDeferredPermille, 250)
        XCTAssertEqual(performance.viewportStutterHint, DiagnosticViewportStutterHint.mixedViewportPressure.rawValue)
        XCTAssertEqual(performance.viewportRequestPauseHint, DiagnosticViewportRequestPauseHint.notMeasured.rawValue)
    }

    func testViewportStutterHintClassifiesFixedCatalogSignals() {
        XCTAssertEqual(
            DiagnosticViewportStutterHint.classify(
                gestureLongFramePermille: nil,
                incomingFrameDeferredPermille: nil
            ),
            .notMeasured
        )
        XCTAssertEqual(
            DiagnosticViewportStutterHint.classify(
                gestureLongFramePermille: 199,
                incomingFrameDeferredPermille: 0
            ),
            .none
        )
        XCTAssertEqual(
            DiagnosticViewportStutterHint.classify(
                gestureLongFramePermille: 200,
                incomingFrameDeferredPermille: 0
            ),
            .gestureLoopPressure
        )
        XCTAssertEqual(
            DiagnosticViewportStutterHint.classify(
                gestureLongFramePermille: 0,
                incomingFrameDeferredPermille: 200
            ),
            .incomingFrameDeferral
        )
        XCTAssertEqual(
            DiagnosticViewportStutterHint.classify(
                gestureLongFramePermille: 200,
                incomingFrameDeferredPermille: 200
            ),
            .mixedViewportPressure
        )
    }

    func testViewportRequestPauseHintClassifiesFixedCatalogSignals() {
        XCTAssertEqual(
            DiagnosticViewportRequestPauseHint.classify(
                viewportInteractionCount: 0,
                viewportInteractionRequestPauseCount: 0,
                gestureLongFramePermille: nil,
                incomingFrameDeferredPermille: nil
            ),
            .notMeasured
        )
        XCTAssertEqual(
            DiagnosticViewportRequestPauseHint.classify(
                viewportInteractionCount: 2,
                viewportInteractionRequestPauseCount: 0,
                gestureLongFramePermille: 250,
                incomingFrameDeferredPermille: 0
            ),
            .notObservedDuringInteraction
        )
        XCTAssertEqual(
            DiagnosticViewportRequestPauseHint.classify(
                viewportInteractionCount: 2,
                viewportInteractionRequestPauseCount: 1,
                gestureLongFramePermille: 199,
                incomingFrameDeferredPermille: 0
            ),
            .activeNoViewportPressure
        )
        XCTAssertEqual(
            DiagnosticViewportRequestPauseHint.classify(
                viewportInteractionCount: 2,
                viewportInteractionRequestPauseCount: 1,
                gestureLongFramePermille: 200,
                incomingFrameDeferredPermille: 0
            ),
            .activeGestureLoopPressure
        )
        XCTAssertEqual(
            DiagnosticViewportRequestPauseHint.classify(
                viewportInteractionCount: 2,
                viewportInteractionRequestPauseCount: 1,
                gestureLongFramePermille: 0,
                incomingFrameDeferredPermille: 200
            ),
            .activeIncomingFrameDeferral
        )
        XCTAssertEqual(
            DiagnosticViewportRequestPauseHint.classify(
                viewportInteractionCount: 2,
                viewportInteractionRequestPauseCount: 1,
                gestureLongFramePermille: 200,
                incomingFrameDeferredPermille: 200
            ),
            .activeMixedViewportPressure
        )
    }

    func testStreamPerformanceReportSanitizesReceiveTimingBuckets() {
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: DiagnosticDurationBucket.threeToTenSeconds.rawValue,
            deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket.fiveToFifteen.rawValue,
            deliveredFrameCount: 10,
            contentFrameCount: 8,
            emptyUpdateCount: 2,
            transportIdleTimeoutCount: 0,
            dirtyRectangleSampleCount: 8,
            dirtyRectangleCountMax: 1,
            dirtyAreaPermilleMax: 100,
            changedPixelsPermilleMax: 100,
            receiveTimingSampleCount: 4,
            averageReceiveTotalTimingBucket: "timing=SECRET",
            maxReceiveTotalTimingBucket: DiagnosticTimingBucket.stalled.rawValue,
            averageNetworkReadTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
            maxNetworkReadTimingBucket: "timing=SECRET",
            averageClientProcessingTimingBucket: DiagnosticTimingBucket.subFrame.rawValue,
            maxClientProcessingTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            appFrameApplyTimingSampleCount: 3,
            averageAppFrameApplyTimingBucket: "timing=SECRET",
            maxAppFrameApplyTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
            streamPacingDelaySampleCount: 6,
            averageStreamPacingDelayBucket: "timing=SECRET",
            maxStreamPacingDelayBucket: DiagnosticTimingBucket.interactive.rawValue,
            thermalPacingSampleCount: 2,
            powerSaverPacingSampleCount: 1,
            emptyBackoffPacingSampleCount: 7,
            activeInputPacingSampleCount: 9,
            viewportInteractionPacingSampleCount: 8,
            outboundInputEventSampleCount: 4,
            outboundInputEventTimeoutCount: 9,
            averageOutboundInputQueueDelayBucket: "timing=SECRET",
            maxOutboundInputQueueDelayBucket: DiagnosticTimingBucket.lagging.rawValue,
            averageOutboundInputOperationTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxOutboundInputOperationTimingBucket: "timing=SECRET",
            mainActorResponsivenessSampleCount: 3,
            averageMainActorResponsivenessDelayBucket: "timing=SECRET",
            maxMainActorResponsivenessDelayBucket: DiagnosticTimingBucket.stalled.rawValue,
            thermalState: "nominal"
        )

        XCTAssertEqual(performance.receiveTimingSampleCount, 4)
        XCTAssertEqual(performance.averageReceiveTotalTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxReceiveTotalTimingBucket, DiagnosticTimingBucket.stalled.rawValue)
        XCTAssertEqual(performance.averageNetworkReadTimingBucket, DiagnosticTimingBucket.lagging.rawValue)
        XCTAssertEqual(performance.maxNetworkReadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.averageClientProcessingTimingBucket, DiagnosticTimingBucket.subFrame.rawValue)
        XCTAssertEqual(performance.maxClientProcessingTimingBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(performance.appFrameApplyTimingSampleCount, 3)
        XCTAssertEqual(performance.averageAppFrameApplyTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxAppFrameApplyTimingBucket, DiagnosticTimingBucket.lagging.rawValue)
        XCTAssertEqual(performance.streamPacingDelaySampleCount, 6)
        XCTAssertEqual(performance.averageStreamPacingDelayBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxStreamPacingDelayBucket, DiagnosticTimingBucket.interactive.rawValue)
        XCTAssertEqual(performance.outboundInputEventSampleCount, 4)
        XCTAssertEqual(performance.outboundInputEventTimeoutCount, 4)
        XCTAssertEqual(
            performance.averageOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.lagging.rawValue
        )
        XCTAssertEqual(
            performance.averageOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.interactive.rawValue
        )
        XCTAssertEqual(
            performance.maxOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(performance.mainActorResponsivenessSampleCount, 3)
        XCTAssertEqual(
            performance.averageMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.stalled.rawValue
        )
        XCTAssertEqual(performance.thermalPacingSampleCount, 2)
        XCTAssertEqual(performance.powerSaverPacingSampleCount, 1)
        XCTAssertEqual(performance.emptyBackoffPacingSampleCount, 6)
        XCTAssertEqual(performance.activeInputPacingSampleCount, 6)
        XCTAssertEqual(performance.viewportInteractionPacingSampleCount, 6)
    }

    func testStreamPerformanceReportDecodesMissingNewerFieldsAsSafeDefaults() throws {
        let payload = """
        {
          "observedDurationBucket": "threeToTenSeconds",
          "deliveredFramesPerSecondBucket": "fiveToFifteen",
          "deliveredFrameCount": 20,
          "contentFrameCount": 18,
          "emptyUpdateCount": 2,
          "transportIdleTimeoutCount": 0,
          "contentFramePermille": 900,
          "emptyUpdatePermille": 100,
          "transportIdleTimeoutPermille": 0,
          "dirtyRectangleSampleCount": 18,
          "averageDirtyRectangleCount": 1,
          "dirtyRectangleCountMax": 2,
          "averageDirtyAreaPermille": 40,
          "dirtyAreaPermilleMax": 80,
          "averageChangedPixelsPermille": 35,
          "changedPixelsPermilleMax": 70,
          "thermalState": "fair"
        }
        """

        let performance = try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(performance.rendererUploadSampleCount, 0)
        XCTAssertEqual(performance.rendererPartialUploadCount, 0)
        XCTAssertEqual(performance.rendererFullUploadCount, 0)
        XCTAssertNil(performance.rendererPartialUploadPermille)
        XCTAssertNil(performance.rendererFullUploadPermille)
        XCTAssertEqual(performance.rendererUploadRegionCountMax, 0)
        XCTAssertEqual(performance.viewportInteractionCount, 0)
        XCTAssertEqual(performance.viewportGestureSampleCount, 0)
        XCTAssertEqual(performance.viewportGestureLongFrameCount, 0)
        XCTAssertEqual(performance.viewportGestureMaxIntervalBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.viewportIncomingFrameDeferredCount, 0)
        XCTAssertEqual(performance.viewportRedrawRequestCount, 0)
        XCTAssertEqual(performance.viewportRedrawFlushCount, 0)
        XCTAssertEqual(performance.viewportDecelerationFrameCount, 0)
        XCTAssertEqual(performance.viewportDisplayRefreshRateBucket, DiagnosticFrameRateBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.adaptiveClientPressurePacingSampleCount, 0)
        XCTAssertEqual(performance.adaptiveClientPressurePacingPermille, 0)
        XCTAssertEqual(performance.receiveTimingSampleCount, 0)
        XCTAssertEqual(performance.averageReceiveTotalTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxReceiveTotalTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.averageNetworkReadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxNetworkReadTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.averageClientProcessingTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxClientProcessingTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.appFrameApplyTimingSampleCount, 0)
        XCTAssertEqual(performance.averageAppFrameApplyTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxAppFrameApplyTimingBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.streamPacingDelaySampleCount, 0)
        XCTAssertEqual(performance.averageStreamPacingDelayBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.maxStreamPacingDelayBucket, DiagnosticTimingBucket.notMeasured.rawValue)
        XCTAssertEqual(performance.thermalPacingSampleCount, 0)
        XCTAssertEqual(performance.powerSaverPacingSampleCount, 0)
        XCTAssertEqual(performance.emptyBackoffPacingSampleCount, 0)
        XCTAssertEqual(performance.viewportInteractionPacingSampleCount, 0)
        XCTAssertEqual(performance.viewportInteractionRequestPauseCount, 0)
        XCTAssertEqual(performance.viewportInteractionRequestPausePollCount, 0)
        XCTAssertEqual(
            performance.averageViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxViewportInteractionRequestPauseBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.viewportRequestPauseHint,
            DiagnosticViewportRequestPauseHint.notMeasured.rawValue
        )
        XCTAssertEqual(performance.outboundInputEventSampleCount, 0)
        XCTAssertEqual(performance.outboundInputEventTimeoutCount, 0)
        XCTAssertEqual(
            performance.averageOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxOutboundInputQueueDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.averageOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxOutboundInputOperationTimingBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(performance.mainActorResponsivenessSampleCount, 0)
        XCTAssertEqual(
            performance.averageMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(
            performance.maxMainActorResponsivenessDelayBucket,
            DiagnosticTimingBucket.notMeasured.rawValue
        )
        XCTAssertEqual(performance.startupPreflightRequestedHiddenFrameCount, 0)
        XCTAssertEqual(performance.startupPreflightConsumedHiddenFrameCount, 0)
        XCTAssertEqual(performance.startupPreflightOutcome, DiagnosticStartupPreflightOutcome.notRequested.rawValue)
        XCTAssertEqual(performance.actualEncodingMix, RFBFramebufferEncodingMix())
        XCTAssertEqual(performance.thermalState, "fair")
    }

    func testStreamPerformanceReportDerivesRequestPauseHintFromV21Payload() throws {
        let payload = """
        {
          "observedDurationBucket": "threeToTenSeconds",
          "deliveredFramesPerSecondBucket": "fiveToFifteen",
          "deliveredFrameCount": 20,
          "contentFrameCount": 18,
          "emptyUpdateCount": 2,
          "transportIdleTimeoutCount": 0,
          "dirtyRectangleSampleCount": 18,
          "dirtyRectangleCountMax": 2,
          "dirtyAreaPermilleMax": 80,
          "changedPixelsPermilleMax": 70,
          "viewportInteractionCount": 2,
          "viewportGestureSampleCount": 10,
          "viewportGestureLongFrameCount": 3,
          "viewportIncomingFrameDeferredCount": 1,
          "viewportRedrawRequestCount": 9,
          "viewportInteractionRequestPauseCount": 1,
          "viewportInteractionRequestPausePollCount": 6,
          "averageViewportInteractionRequestPauseBucket": "interactive",
          "maxViewportInteractionRequestPauseBucket": "interactive",
          "thermalState": "fair"
        }
        """

        let performance = try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(
            performance.viewportRequestPauseHint,
            DiagnosticViewportRequestPauseHint.activeGestureLoopPressure.rawValue
        )
    }

    func testStreamPerformanceReportSanitizesDecodedEncodingMixCounts() throws {
        let payload = """
        {
          "observedDurationBucket": "threeToTenSeconds",
          "deliveredFramesPerSecondBucket": "fiveToFifteen",
          "deliveredFrameCount": 20,
          "contentFrameCount": 18,
          "emptyUpdateCount": 2,
          "transportIdleTimeoutCount": 0,
          "dirtyRectangleSampleCount": 18,
          "dirtyRectangleCountMax": 2,
          "dirtyAreaPermilleMax": 80,
          "changedPixelsPermilleMax": 70,
          "actualEncodingMix": {
            "rawRectangles": -1,
            "copyRectRectangles": 2,
            "hextileRectangles": -3,
            "zrleRectangles": 4,
            "tightRectangles": -5,
            "cursorRectangles": 6,
            "xCursorRectangles": -7,
            "desktopSizeRectangles": 8,
            "extendedDesktopSizeRectangles": -9,
            "lastRectRectangles": 10,
            "endOfContinuousUpdatesEvents": -11
          },
          "thermalState": "fair"
        }
        """

        let performance = try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(
            performance.actualEncodingMix,
            RFBFramebufferEncodingMix(
                copyRectRectangles: 2,
                zrleRectangles: 4,
                cursorRectangles: 6,
                desktopSizeRectangles: 8,
                lastRectRectangles: 10
            )
        )
    }

    // MARK: - Frame presentation ledger (spec 028)

    /// The export's required identity fields, so the ledger tests below can name
    /// only what they are actually asserting.
    private func makeLedgerReport(
        published: Int = 0,
        presented: Int = 0,
        presentedPermille: Int? = nil,
        heldReason: String = FramePresentationHeldReasonCatalog.none,
        watchdogReleases: Int = 0,
        downscaleRung: String = AppleServerDownscaleRungCatalog.full
    ) -> DiagnosticStreamPerformanceReport {
        DiagnosticStreamPerformanceReport(
            observedDurationBucket: DiagnosticTimingBucket.notMeasured.rawValue,
            deliveredFramesPerSecondBucket: DiagnosticFrameRateBucket.notMeasured.rawValue,
            deliveredFrameCount: 0,
            contentFrameCount: 0,
            emptyUpdateCount: 0,
            transportIdleTimeoutCount: 0,
            dirtyRectangleSampleCount: 0,
            dirtyRectangleCountMax: 0,
            dirtyAreaPermilleMax: 0,
            changedPixelsPermilleMax: 0,
            appleServerDownscaleRung: downscaleRung,
            framePresentationPublishedCount: published,
            framePresentationPresentedCount: presented,
            framePresentationPresentedPermille: presentedPermille,
            framePresentationHeldReason: heldReason,
            framePresentationWatchdogReleaseCount: watchdogReleases,
            thermalState: "nominal"
        )
    }


    func testFramePresentationFieldsAreWrittenNotJustRead() throws {
        // Spec 027 shipped summary fields that `init(from:)` read and
        // `encode(to:)` never wrote, so an archived run showed them absent while
        // the in-memory value was correct. A frozen session whose export reports
        // a clean ledger would be the same failure with worse consequences.
        let report = makeLedgerReport(
            published: 120,
            presented: 4,
            presentedPermille: 33,
            heldReason: FramePresentationOutcome.heldBySuspension.rawValue,
            watchdogReleases: 2
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = String(decoding: try encoder.encode(report), as: UTF8.self)

        XCTAssertTrue(payload.contains("\"framePresentationPublishedCount\":120"))
        XCTAssertTrue(payload.contains("\"framePresentationPresentedCount\":4"))
        XCTAssertTrue(payload.contains("\"framePresentationPresentedPermille\":33"))
        XCTAssertTrue(payload.contains("\"framePresentationHeldReason\":\"heldBySuspension\""))
        XCTAssertTrue(payload.contains("\"framePresentationWatchdogReleaseCount\":2"))

        let decoded = try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(decoded.framePresentationPublishedCount, 120)
        XCTAssertEqual(decoded.framePresentationPresentedCount, 4)
        XCTAssertEqual(decoded.framePresentationHeldReason, "heldBySuspension")
        XCTAssertEqual(decoded.framePresentationWatchdogReleaseCount, 2)
    }

    func testAnOlderExportWithoutTheLedgerDecodesToSafeDefaults() throws {
        // Built by stripping the ledger keys out of a valid payload rather than
        // hand-writing a minimal one, so this keeps testing the right thing as
        // the report's required fields change.
        let decoded = try decodeLedgerReport(strippingLedgerKeysFrom: makeLedgerReport())

        XCTAssertEqual(decoded.framePresentationPublishedCount, 0)
        XCTAssertEqual(decoded.framePresentationPresentedCount, 0)
        XCTAssertNil(decoded.framePresentationPresentedPermille)
        XCTAssertEqual(decoded.framePresentationHeldReason, "none")
        XCTAssertEqual(decoded.framePresentationWatchdogReleaseCount, 0)
    }

    func testTheHeldReasonIsRestrictedToTheSafeCatalog() throws {
        // Constitution §IV: exports carry fixed vocabulary, never
        // caller-provided strings. The reason originates from a closed enum, but
        // it crosses the boundary as a String, so it is re-checked rather than
        // trusted — on the way in as well as on the way out.
        XCTAssertEqual(
            makeLedgerReport(heldReason: "user typed: hunter2").framePresentationHeldReason,
            "unknown"
        )

        let decoded = try decodeLedgerReport(
            replacingHeldReasonWith: "192.168.1.4",
            in: makeLedgerReport()
        )
        XCTAssertEqual(decoded.framePresentationHeldReason, "unknown")

        for outcome in FramePresentationOutcome.allCases {
            XCTAssertEqual(
                makeLedgerReport(heldReason: outcome.rawValue).framePresentationHeldReason,
                outcome.rawValue
            )
        }
    }

    private func ledgerReportObject(
        _ report: DiagnosticStreamPerformanceReport
    ) throws -> [String: Any] {
        let data = try JSONEncoder().encode(report)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func decodeLedgerReport(
        strippingLedgerKeysFrom report: DiagnosticStreamPerformanceReport
    ) throws -> DiagnosticStreamPerformanceReport {
        var object = try ledgerReportObject(report)
        for key in object.keys where key.hasPrefix("framePresentation") {
            object.removeValue(forKey: key)
        }
        return try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
    }

    private func decodeLedgerReport(
        replacingHeldReasonWith reason: String,
        in report: DiagnosticStreamPerformanceReport
    ) throws -> DiagnosticStreamPerformanceReport {
        var object = try ledgerReportObject(report)
        object["framePresentationHeldReason"] = reason
        return try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
    }

    // MARK: - Applied server downscale (spec 031)

    func testTheAppliedDownscaleRungIsWrittenAsAFixedLabel() throws {
        // Its absence is why the founder's soft-picture report could not be
        // attributed from an export, and why establishing what the server was
        // even serving needed a direct RFB probe.
        XCTAssertEqual(
            AppleServerDownscaleRungCatalog.label(
                forAppliedRung: AppleServerDownscalePolicy.fullRung
            ),
            "full"
        )
        XCTAssertEqual(
            AppleServerDownscaleRungCatalog.label(
                forAppliedRung: AppleServerDownscalePolicy.downscaledRung
            ),
            "half"
        )
        // A rung the policy cannot apply reads as unknown rather than being
        // rounded into a claim.
        XCTAssertEqual(AppleServerDownscaleRungCatalog.label(forAppliedRung: 0.73), "unknown")
        // Constitution §IV: a caller-supplied string never reaches the export.
        XCTAssertEqual(
            makeLedgerReport(downscaleRung: "3024x1964").appleServerDownscaleRung,
            "unknown"
        )

        let report = makeLedgerReport(downscaleRung: "half")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = String(decoding: try encoder.encode(report), as: UTF8.self)
        XCTAssertTrue(payload.contains("\"appleServerDownscaleRung\":\"half\""))

        let decoded = try JSONDecoder().decode(
            DiagnosticStreamPerformanceReport.self,
            from: Data(payload.utf8)
        )
        XCTAssertEqual(decoded.appleServerDownscaleRung, "half")
    }

    func testRenderSharePayloadIncludesPlainTextAndCollectionJSON() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(timeIntervalSince1970: 1),
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "caller detail must not appear"
                )
            ]
        )
        let export = DiagnosticExport(run: run)

        let payload = export.renderSharePayload(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )

        XCTAssertTrue(payload.hasPrefix("Naru Remote Diagnostic Summary"))
        XCTAssertTrue(payload.contains("[dns] passed"))
        XCTAssertTrue(payload.contains("--- Naru Remote Diagnostic JSON v34 ---"))
        XCTAssertTrue(payload.contains("\"schemaVersion\" : 34"))
        XCTAssertTrue(payload.contains("\"stageID\" : \"dns\""))
        XCTAssertFalse(payload.contains("caller detail"))
    }

    func testCollectionJSONAndPayloadAreSafeCatalogOnlyAcrossSensitiveSentinels() throws {
        let hostSentinel = "desk.tailnet.ts.net"
        let endpointSentinel = "\(hostSentinel):5900"
        let credentialRefSentinel = "vnc-password:hunter2-credential"
        let composedDraftSentinel = "한글과 English 😊 SECRETPHRASE"
        let rawClipboardSentinel = "REMOTE_COPY_TEXT_DEADBEEF"
        let rawErrorSentinel = "NWError.posix(ECONNREFUSED) 10.0.0.42:5900"
        let pixelSentinel = "\u{ED}\u{C3}\u{AB}\u{FE}"
        let thumbnailSentinel = "iVBORw0KGgoAAAANSUhEUgAA-secret-thumbnail"
        let rawLatencySentinel = "latency=123.456ms"
        let nextActionSentinel = "Reset password 12345 on the host"

        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: hostSentinel,
            credentialRef: credentialRefSentinel
        )
        let rawBlob = [
            endpointSentinel,
            credentialRefSentinel,
            composedDraftSentinel,
            rawClipboardSentinel,
            rawErrorSentinel,
            pixelSentinel,
            thumbnailSentinel,
            rawLatencySentinel
        ].joined(separator: " | ")
        let stages = DiagnosticStage.allCases.map { stage in
            DiagnosticStageResult(
                stage: stage,
                status: stage == .authentication ? .failed : .passed,
                safeTitle: "Raw title \(rawBlob)",
                safeDetail: "Raw detail \(rawBlob)",
                nextAction: "\(nextActionSentinel) \(rawBlob)",
                metadata: DiagnosticStageMetadata(failureCode: rawErrorSentinel)
            )
        }
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(timeIntervalSince1970: 1_714_521_620),
            stages: stages
        )
        let export = DiagnosticExport(run: run)

        let pinnedDate = Date(timeIntervalSince1970: 1_714_521_600)
        let json = export.renderCollectionJSON(buildVersion: "0.1.0", now: pinnedDate)
        let payload = export.renderSharePayload(buildVersion: "0.1.0", now: pinnedDate)

        XCTAssertTrue(json.contains("Authentication stage."))
        XCTAssertTrue(json.contains("\"failureCode\" : \"error.unknown\""))
        XCTAssertTrue(payload.contains("Authentication stage."))
        XCTAssertTrue(payload.contains("Naru Remote Diagnostic Summary"))

        let forbidden = [
            hostSentinel,
            endpointSentinel,
            credentialRefSentinel,
            composedDraftSentinel,
            rawClipboardSentinel,
            rawErrorSentinel,
            pixelSentinel,
            thumbnailSentinel,
            rawLatencySentinel,
            nextActionSentinel,
            profile.id.uuidString,
            profile.id.uuidString.lowercased(),
            "hunter2",
            "12345",
            "DEADBEEF",
            "SECRETPHRASE",
            "ECONNREFUSED",
            "secret-thumbnail"
        ]

        for sentinel in forbidden {
            XCTAssertFalse(json.contains(sentinel), "collection JSON leaked \(sentinel)")
            XCTAssertFalse(payload.contains(sentinel), "share payload leaked \(sentinel)")
        }

        let jsonBytes = Array(json.utf8)
        let payloadBytes = Array(payload.utf8)
        for sentinel in forbidden {
            let sequence = Array(sentinel.utf8)
            XCTAssertFalse(
                Self.bytesContain(jsonBytes, subsequence: sequence),
                "collection JSON leaked a forbidden byte sequence"
            )
            XCTAssertFalse(
                Self.bytesContain(payloadBytes, subsequence: sequence),
                "share payload leaked a forbidden byte sequence"
            )
        }
    }

    private static func bytesContain(_ haystack: [UInt8], subsequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return false
        }
        let lastStart = haystack.count - needle.count
        for start in 0...lastStart {
            var matched = true
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                matched = false
                break
            }
            if matched {
                return true
            }
        }
        return false
    }
}
