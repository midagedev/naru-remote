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
}
