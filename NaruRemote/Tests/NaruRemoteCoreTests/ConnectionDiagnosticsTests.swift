import XCTest
@testable import NaruRemoteCore

final class ConnectionDiagnosticsTests: XCTestCase {
    func testDiagnosticRunReportsFirstFailedStage() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let dns = DiagnosticStageResult(
            stage: .dns,
            status: .passed,
            safeTitle: "MagicDNS resolved",
            safeDetail: "Host resolved."
        )
        let tcp = DiagnosticMessageCatalog.failure(for: .tcp)
        let handshake = DiagnosticStageResult(
            stage: .rfbHandshake,
            status: .skipped,
            safeTitle: "Handshake skipped",
            safeDetail: "TCP failed first."
        )

        let run = ConnectionDiagnosticRun(profileID: profile.id, stages: [dns, tcp, handshake])

        XCTAssertEqual(run.firstFailedStage?.stage, .tcp)
        XCTAssertTrue(run.safeSummary.contains("VNC port closed"))
    }

    func testFailureCatalogUsesDistinctUserSafeMessages() {
        let stages = DiagnosticStage.allCases
        let titles = stages.map { DiagnosticMessageCatalog.failure(for: $0).safeTitle }

        XCTAssertEqual(Set(titles).count, DiagnosticStage.allCases.count)
        XCTAssertTrue(titles.contains("MagicDNS did not resolve"))
        XCTAssertTrue(titles.contains("Text clipboard unavailable"))
    }

    // MARK: - DiagnosticVerdict (UX punch-list #109)

    func testVerdictUnknownWhenRunInFlight() throws {
        // Mid-flight run: no `finishedAt`, mix of passed + running.
        // Sidebar dot must stay neutral until the network attempt
        // resolves — never optimistically green.
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            stages: [
                DiagnosticStageResult(
                    stage: .dns,
                    status: .passed,
                    safeTitle: "Profile ready",
                    safeDetail: "Private profile is selected."
                ),
                DiagnosticStageResult(
                    stage: .tcp,
                    status: .running,
                    safeTitle: "Checking",
                    safeDetail: "Probing port."
                )
            ]
        )

        XCTAssertEqual(run.verdict, .unknown)
    }

    func testVerdictPassedOnlyWhenAllStagesPassedAndRunFinished() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(timeIntervalSince1970: 100),
            stages: [
                DiagnosticStageResult(stage: .dns, status: .passed, safeTitle: "ok", safeDetail: ""),
                DiagnosticStageResult(stage: .tcp, status: .passed, safeTitle: "ok", safeDetail: ""),
                DiagnosticStageResult(stage: .firstFrame, status: .passed, safeTitle: "ok", safeDetail: "")
            ]
        )

        XCTAssertEqual(run.verdict, .passed)
    }

    func testVerdictFailedAsSoonAsAnyStageFails() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        // Even with a missing finishedAt — a failure is observable
        // immediately and should drive the dot red.
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            stages: [
                DiagnosticStageResult(stage: .dns, status: .passed, safeTitle: "ok", safeDetail: ""),
                DiagnosticMessageCatalog.failure(for: .tcp)
            ]
        )

        XCTAssertEqual(run.verdict, .failed)
    }

    func testVerdictWarningWhenStageSkippedWithoutHardFailure() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let run = ConnectionDiagnosticRun(
            profileID: profile.id,
            finishedAt: Date(timeIntervalSince1970: 100),
            stages: [
                DiagnosticStageResult(stage: .dns, status: .passed, safeTitle: "ok", safeDetail: ""),
                DiagnosticStageResult(stage: .tcp, status: .passed, safeTitle: "ok", safeDetail: ""),
                DiagnosticStageResult(
                    stage: .clipboardText,
                    status: .skipped,
                    safeTitle: "Clipboard skipped",
                    safeDetail: "Server did not advertise the text path."
                )
            ]
        )

        XCTAssertEqual(run.verdict, .warning)
    }
}
