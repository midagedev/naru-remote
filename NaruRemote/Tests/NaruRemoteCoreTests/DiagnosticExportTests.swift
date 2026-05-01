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
