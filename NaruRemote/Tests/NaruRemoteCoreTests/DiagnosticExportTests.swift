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

    func testRenderCollectionJSONIsDeterministicSchemaV6() throws {
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
        XCTAssertTrue(rendered.contains("\"schemaVersion\" : 13"))
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
        XCTAssertEqual(decoded.schemaVersion, 13)
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
            viewportIncomingFrameDeferredCount: 12,
            viewportRedrawRequestCount: 60,
            viewportRedrawFlushCount: 30,
            viewportDecelerationFrameCount: 8,
            viewportDisplayRefreshRateBucket: DiagnosticFrameRateBucket.sixtyOrMore.rawValue,
            appFrameApplyTimingSampleCount: 120,
            averageAppFrameApplyTimingBucket: DiagnosticTimingBucket.interactive.rawValue,
            maxAppFrameApplyTimingBucket: DiagnosticTimingBucket.lagging.rawValue,
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
            viewerStreamPowerMode: .powerSaver
        )

        let rendered = export.renderCollectionJSON(
            buildVersion: "0.1.0",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(rendered.utf8)
        )

        XCTAssertEqual(decoded.schemaVersion, 13)
        XCTAssertEqual(decoded.streamPerformance, performance)
        XCTAssertEqual(decoded.viewerStreamPowerMode, StreamPowerMode.powerSaver.rawValue)
        XCTAssertTrue(rendered.contains("\"streamPerformance\""))
        XCTAssertTrue(rendered.contains("\"actualEncodingMix\""))
        XCTAssertTrue(rendered.contains("\"averageAppFrameApplyTimingBucket\" : \"interactive\""))
        XCTAssertTrue(rendered.contains("\"averageRendererUploadTimingBucket\" : \"subFrame\""))
        XCTAssertTrue(rendered.contains("\"adaptiveClientPressurePacingPermille\" : 75"))
        XCTAssertTrue(rendered.contains("\"viewportIncomingFrameDeferredCount\" : 12"))
        XCTAssertTrue(rendered.contains("\"viewportDisplayRefreshRateBucket\" : \"sixtyOrMore\""))
        XCTAssertTrue(rendered.contains("\"copyRectRectangles\" : 70"))
        XCTAssertTrue(rendered.contains("\"thermalState\" : \"serious\""))
        XCTAssertTrue(rendered.contains("\"viewerStreamPowerMode\" : \"power-saver\""))
        XCTAssertFalse(rendered.contains("caller detail"))
        XCTAssertFalse(rendered.contains(profileID.uuidString))
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
            directKeystrokeModeActive: false
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

        XCTAssertEqual(decoded.schemaVersion, 13)
        XCTAssertEqual(decoded.input?.directKeystrokeModeActive, false)
        XCTAssertEqual(decoded.input?.hasComposeDraftText, true)
        XCTAssertEqual(decoded.input?.composeSendState, ComposeSendState.unknown.rawValue)
        XCTAssertEqual(decoded.input?.latestInjectionPath, TextInjectionPath.vncClipboardPaste.rawValue)
        XCTAssertEqual(decoded.input?.latestInjectionStatus, TextInjectionStatus.unknown.rawValue)
        XCTAssertEqual(decoded.input?.latestInjectionPasteCommand, PasteCommand.commandV.rawValue)
        XCTAssertEqual(
            decoded.input?.latestInjectionPayloadEncoding,
            TextInjectionPayloadEncoding.utf8ExtensionRequired.rawValue
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
        XCTAssertFalse(rendered.contains("Paste command sent"))
        XCTAssertFalse(rendered.contains("caller detail"))
        XCTAssertFalse(rendered.contains(sessionID.uuidString))
    }

    func testInputReportClampsUnsafeCatalogValues() {
        let input = DiagnosticInputReport(
            directKeystrokeModeActive: true,
            hasComposeDraftText: true,
            composeSendState: "state=SECRET",
            latestInjectionPath: "path=SECRET",
            latestInjectionStatus: "status=SECRET",
            latestInjectionPasteCommand: "paste=SECRET",
            latestInjectionPayloadEncoding: "payload=SECRET",
            latestInjectionClipboardSetStatus: "clipboard=SECRET",
            latestInjectionPasteCommandStatus: "command=SECRET",
            latestInjectionRemoteClipboardRestore: "restore=SECRET",
            latestInjectionDurationBucket: "duration=SECRET"
        )

        XCTAssertEqual(input.directKeystrokeModeActive, true)
        XCTAssertEqual(input.hasComposeDraftText, true)
        XCTAssertNil(input.composeSendState)
        XCTAssertNil(input.latestInjectionPath)
        XCTAssertNil(input.latestInjectionStatus)
        XCTAssertNil(input.latestInjectionPasteCommand)
        XCTAssertNil(input.latestInjectionPayloadEncoding)
        XCTAssertNil(input.latestInjectionClipboardSetStatus)
        XCTAssertNil(input.latestInjectionPasteCommandStatus)
        XCTAssertNil(input.latestInjectionRemoteClipboardRestore)
        XCTAssertNil(input.latestInjectionDurationBucket)
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
            viewerStreamPowerMode: "mode=SECRET"
        )

        XCTAssertNil(report.viewerStreamPowerMode)

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
          "viewerStreamPowerMode": "mode=SECRET"
        }
        """
        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(payload.utf8)
        )
        XCTAssertNil(decoded.viewerStreamPowerMode)
    }

    func testStreamPerformanceReportClampsUnsafeCatalogValues() {
        let performance = DiagnosticStreamPerformanceReport(
            observedDurationBucket: "duration=SECRET",
            deliveredFramesPerSecondBucket: "fps=SECRET",
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
            viewportIncomingFrameDeferredCount: -18,
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
        XCTAssertEqual(performance.viewportIncomingFrameDeferredCount, 0)
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
        XCTAssertEqual(
            performance.actualEncodingMix,
            RFBFramebufferEncodingMix(copyRectRectangles: 2, endOfContinuousUpdatesEvents: 1)
        )
        XCTAssertEqual(performance.thermalState, "unknown")
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
        XCTAssertEqual(performance.actualEncodingMix, RFBFramebufferEncodingMix())
        XCTAssertEqual(performance.thermalState, "fair")
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
        XCTAssertTrue(payload.contains("--- Naru Remote Diagnostic JSON v13 ---"))
        XCTAssertTrue(payload.contains("\"schemaVersion\" : 13"))
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
