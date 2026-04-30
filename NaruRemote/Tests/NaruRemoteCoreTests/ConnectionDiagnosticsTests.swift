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
}
