import XCTest
@testable import NaruRemoteCore

final class DiagnosticExportTests: XCTestCase {
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

    func testRenderCollectionJSONIsDeterministicSchemaV1() throws {
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let runID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let run = ConnectionDiagnosticRun(
            id: runID,
            profileID: profileID,
            finishedAt: Date(timeIntervalSince1970: 1_714_521_620),
            stages: [
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .failed,
                    safeTitle: "Host reached, VNC port closed",
                    safeDetail: "caller detail must not appear"
                )
            ]
        )
        let export = DiagnosticExport(run: run)
        let pinnedDate = Date(timeIntervalSince1970: 1_714_521_600)

        let rendered = export.renderCollectionJSON(buildVersion: "0.1.0", now: pinnedDate)
        let renderedAgain = export.renderCollectionJSON(buildVersion: "0.1.0", now: pinnedDate)

        XCTAssertEqual(rendered, renderedAgain)
        XCTAssertTrue(rendered.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(rendered.contains("\"generatedAt\" : \"2024-05-01T00:00:00Z\""))
        XCTAssertFalse(rendered.contains(profileID.uuidString))
        XCTAssertFalse(rendered.contains(profileID.uuidString.lowercased()))
        XCTAssertFalse(rendered.contains("caller detail"))

        let decoded = try JSONDecoder().decode(
            DiagnosticCollectionReport.self,
            from: Data(rendered.utf8)
        )
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.generatedAt, "2024-05-01T00:00:00Z")
        XCTAssertEqual(decoded.buildVersion, "0.1.0")
        XCTAssertEqual(decoded.runID, runID.uuidString.lowercased())
        XCTAssertEqual(decoded.verdict, DiagnosticVerdict.failed.rawValue)
        XCTAssertTrue(decoded.profileFingerprint.hasPrefix("sha256:"))
        XCTAssertEqual(decoded.profileFingerprint.count, "sha256:".count + 64)
        XCTAssertEqual(decoded.stageRows, export.stageRows)
        XCTAssertEqual(decoded.stageRows.first?.safeDetail, "TCP reachability stage.")
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
        XCTAssertTrue(payload.contains("--- Naru Remote Diagnostic JSON v1 ---"))
        XCTAssertTrue(payload.contains("\"schemaVersion\" : 1"))
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
                nextAction: "\(nextActionSentinel) \(rawBlob)"
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
