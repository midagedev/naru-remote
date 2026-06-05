import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkLiveEnvironmentPreflightTests: XCTestCase {
    func testConfiguredEnvironmentCanRunLiveBenchmark() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret",
                "NARU_LIVE_STIMULUS_COMMAND": "secret command"
            ],
            askPassword: false,
            stimulusMode: .externalCommand
        )

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.hostStatus, .configured)
        XCTAssertEqual(report.portStatus, .configured)
        XCTAssertEqual(report.credentialStatus, .environment)
        XCTAssertEqual(report.stimulusMode, .externalCommand)
        XCTAssertEqual(report.stimulusCommandStatus, .configured)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
    }

    func testMissingRequiredFieldsReportStableIssueCodes() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [:],
            askPassword: false,
            stimulusMode: .externalCommand
        )

        XCTAssertEqual(report.hostStatus, .missing)
        XCTAssertEqual(report.portStatus, .defaulted)
        XCTAssertEqual(report.credentialStatus, .missing)
        XCTAssertEqual(report.stimulusCommandStatus, .requiredMissing)
        XCTAssertFalse(report.canRunLiveBenchmark)
        XCTAssertEqual(
            report.issueCodes,
            [.missingHost, .missingCredential, .missingStimulusCommand]
        )
    }

    func testPromptRequestCountsAsCredentialSourceWithoutReadingPassword() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target"
            ],
            askPassword: true,
            stimulusMode: .off
        )

        XCTAssertEqual(report.hostStatus, .configured)
        XCTAssertEqual(report.portStatus, .defaulted)
        XCTAssertEqual(report.credentialStatus, .promptRequested)
        XCTAssertEqual(report.stimulusCommandStatus, .notRequired)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
    }

    func testInvalidPortBlocksLiveBenchmark() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "not-a-port",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off
        )

        XCTAssertEqual(report.portStatus, .invalid)
        XCTAssertFalse(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [.invalidPort])
    }

    func testJSONDoesNotExposeEnvironmentValues() throws {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret",
                "NARU_LIVE_STIMULUS_COMMAND": "secret command"
            ],
            askPassword: false,
            stimulusMode: .externalCommand
        )

        let data = try JSONEncoder().encode(report)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("private-target"))
        XCTAssertFalse(json.contains("5900"))
        XCTAssertFalse(json.contains("secret"))
        XCTAssertFalse(json.contains("secret command"))
    }
}
