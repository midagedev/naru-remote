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

        XCTAssertEqual(report.schemaVersion, 4)
        XCTAssertEqual(report.hostStatus, .configured)
        XCTAssertEqual(report.portStatus, .configured)
        XCTAssertEqual(report.credentialStatus, .environment)
        XCTAssertEqual(report.stimulusMode, .externalCommand)
        XCTAssertEqual(report.stimulusCommandStatus, .configured)
        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
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
        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertFalse(report.canRunLiveBenchmark)
        XCTAssertEqual(
            report.issueCodes,
            [.missingHost, .missingCredential, .missingStimulusCommand]
        )
        XCTAssertEqual(
            report.setupActionLabels,
            [.setHost, .provideCredentialOrAskPassword, .setStimulusCommand]
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
        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
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
        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertFalse(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [.invalidPort])
        XCTAssertEqual(report.setupActionLabels, [.fixPort])
    }

    func testInProcessScreenCaptureKitHelperProbeRequiresPermissionWhenSelected() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off,
            visualTransports: .helperVideo,
            helperVideoProbeMode: .screenCaptureKitTCP,
            screenCapturePermissionStatusProvider: { .missing }
        )

        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .missing)
        XCTAssertFalse(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [.helperVideoPermissionMissing])
        XCTAssertEqual(report.setupActionLabels, [.requestHelperVideoScreenRecordingPermission])
    }

    func testExternalHelperScreenCaptureKitProbeDelegatesPermissionToHelperProcess() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off,
            visualTransports: .helperVideo,
            helperVideoProbeMode: .externalHelperScreenCaptureKitTCP,
            screenCapturePermissionStatusProvider: {
                XCTFail("external helper permission must not be checked in the benchmark process")
                return .missing
            }
        )

        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .delegatedToHelper)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
    }

    func testScreenCaptureKitHelperProbeCanRunWhenPermissionGranted() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off,
            visualTransports: .all,
            helperVideoProbeMode: .screenCaptureKitTCP,
            screenCapturePermissionStatusProvider: { .granted }
        )

        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .granted)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
    }

    func testScreenCaptureKitPermissionIsNotRequiredWhenHelperVideoIsNotSelected() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off,
            visualTransports: .vnc,
            helperVideoProbeMode: .externalHelperScreenCaptureKitTCP,
            screenCapturePermissionStatusProvider: { .missing }
        )

        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
    }

    func testSyntheticHelperVideoProbeDoesNotRequireScreenCapturePermission() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off,
            visualTransports: .helperVideo,
            helperVideoProbeMode: .externalHelperSyntheticEncodedTCP,
            screenCapturePermissionStatusProvider: { .missing }
        )

        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertTrue(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [])
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
    }

    func testUnsupportedScreenCaptureKitHelperProbeRoutesToSyntheticAction() {
        let report = BenchmarkLiveEnvironmentPreflightReport.make(
            environment: [
                "NARU_LIVE_MAC_HOST": "private-target",
                "NARU_LIVE_MAC_PORT": "5900",
                "NARU_LIVE_MAC_PASSWORD": "secret"
            ],
            askPassword: false,
            stimulusMode: .off,
            visualTransports: .helperVideo,
            helperVideoProbeMode: .screenCaptureKitTCP,
            screenCapturePermissionStatusProvider: { .unsupported }
        )

        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .unsupported)
        XCTAssertFalse(report.canRunLiveBenchmark)
        XCTAssertEqual(report.issueCodes, [.helperVideoCaptureUnsupported])
        XCTAssertEqual(report.setupActionLabels, [.useSyntheticHelperVideoProbe])
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
        XCTAssertTrue(json.contains("notRequired"))
        XCTAssertTrue(json.contains("run-live-gate"))
    }

    func testDecodesV1PayloadWithoutSetupActions() throws {
        let json = Data(
            """
            {
              "schemaVersion": 1,
              "hostStatus": "missing",
              "portStatus": "defaulted",
              "credentialStatus": "promptRequested",
              "stimulusMode": "external-command",
              "stimulusCommandStatus": "requiredMissing",
              "canRunLiveBenchmark": false,
              "issueCodes": [
                "missing-host",
                "missing-stimulus-command"
              ]
            }
            """.utf8
        )

        let report = try JSONDecoder().decode(
            BenchmarkLiveEnvironmentPreflightReport.self,
            from: json
        )

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.issueCodes, [.missingHost, .missingStimulusCommand])
        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertEqual(report.setupActionLabels, [.setHost, .setStimulusCommand])
    }

    func testDecodesV2PayloadWithoutHelperVideoPermissionStatus() throws {
        let json = Data(
            """
            {
              "schemaVersion": 2,
              "hostStatus": "configured",
              "portStatus": "configured",
              "credentialStatus": "environment",
              "stimulusMode": "off",
              "stimulusCommandStatus": "notRequired",
              "canRunLiveBenchmark": true,
              "issueCodes": [],
              "setupActionLabels": [
                "run-live-gate"
              ]
            }
            """.utf8
        )

        let report = try JSONDecoder().decode(
            BenchmarkLiveEnvironmentPreflightReport.self,
            from: json
        )

        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.helperVideoScreenCapturePermissionStatus, .notRequired)
        XCTAssertEqual(report.setupActionLabels, [.runLiveGate])
    }
}
