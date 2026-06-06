import XCTest
@testable import VNCLiveBenchmarkKit

#if os(macOS) && canImport(VideoToolbox)
import VideoToolbox
#endif

final class BenchmarkVisualTransportComparisonReportTests: XCTestCase {
    func testFakeHelperComparisonUsesFixedTransportLabelsAndSafeDisabledReport() throws {
        let report = BenchmarkVisualTransportComparisonReport.fakeHelperComparison(
            selection: try .parse("vnc,helper-video")
        )

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.selectedVisualTransports, [.vnc, .helperVideo])
        XCTAssertEqual(report.vncReportShape, .existingLiveBenchmarkReport)
        XCTAssertEqual(report.helperVideoReports.count, 1)
        XCTAssertEqual(report.helperVideoReports.first?.visualTransport, .helperVideo)
        XCTAssertEqual(report.helperVideoReports.first?.streamState.rawValue, "idle")
        XCTAssertEqual(report.helperVideoReports.first?.verdict.rawValue, "disabled")
        XCTAssertEqual(report.helperVideoReports.first?.issueCodes, [.streamDisabled])
    }

    func testVNCOnlyComparisonDoesNotInventAHelperVideoReport() throws {
        let report = BenchmarkVisualTransportComparisonReport.fakeHelperComparison(
            selection: try .parse("vnc")
        )

        XCTAssertEqual(report.selectedVisualTransports, [.vnc])
        XCTAssertEqual(report.helperVideoReports, [])
    }

    func testHelperComparisonUsesProvidedSyntheticHelperReport() throws {
        let helperReport = BenchmarkHelperVideoReport(
            streamState: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low,
            fallbackCountBucket: .none
        )

        let report = BenchmarkVisualTransportComparisonReport.helperComparison(
            selection: try .parse("vnc,helper-video"),
            helperVideoReport: helperReport
        )

        XCTAssertEqual(report.selectedVisualTransports, [.vnc, .helperVideo])
        XCTAssertEqual(report.helperVideoReports, [helperReport])
        XCTAssertEqual(report.helperVideoReports.first?.verdict, .pass)
        XCTAssertEqual(report.helperVideoReports.first?.issueCodes, [])
    }

    func testHelperVideoProbeModeParsesStableCLILabels() {
        XCTAssertEqual(BenchmarkHelperVideoProbeMode.parse("disabled"), .disabled)
        XCTAssertEqual(BenchmarkHelperVideoProbeMode.parse("synthetic-tcp"), .syntheticTCP)
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("synthetic-encoded-tcp"),
            .syntheticEncodedTCP
        )
        XCTAssertNil(BenchmarkHelperVideoProbeMode.parse("local"))
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.usageDescription,
            "disabled|synthetic-tcp|synthetic-encoded-tcp"
        )
    }

    func testSyntheticTCPProbeExercisesLocalHarnessAndReportsPass() throws {
        let report = BenchmarkHelperVideoProbe.makeComparison(
            selection: try .parse("helper-video"),
            probeMode: .syntheticTCP
        )
        let helperReport = try XCTUnwrap(report.helperVideoReports.first)

        XCTAssertEqual(report.selectedVisualTransports, [.helperVideo])
        XCTAssertEqual(helperReport.visualTransport, .helperVideo)
        XCTAssertEqual(helperReport.streamState, .healthy)
        XCTAssertEqual(helperReport.startupBand, .fast)
        XCTAssertEqual(helperReport.sustainedUpdateBand, .smooth)
        XCTAssertEqual(helperReport.decodePressure, .low)
        XCTAssertEqual(helperReport.fallbackCountBucket, .none)
        XCTAssertEqual(helperReport.verdict, .pass)
        XCTAssertEqual(helperReport.issueCodes, [])
    }

    #if os(macOS) && canImport(VideoToolbox)
    func testSyntheticEncodedTCPProbeExercisesVideoToolboxPayloadSourceAndReportsPass() throws {
        let report = BenchmarkHelperVideoProbe.makeComparison(
            selection: try .parse("helper-video"),
            probeMode: .syntheticEncodedTCP
        )
        let helperReport = try XCTUnwrap(report.helperVideoReports.first)

        XCTAssertEqual(report.selectedVisualTransports, [.helperVideo])
        XCTAssertEqual(helperReport.visualTransport, .helperVideo)
        XCTAssertEqual(helperReport.streamState, .healthy)
        XCTAssertEqual(helperReport.startupBand, .fast)
        XCTAssertEqual(helperReport.sustainedUpdateBand, .smooth)
        XCTAssertEqual(helperReport.decodePressure, .low)
        XCTAssertEqual(helperReport.fallbackCountBucket, .none)
        XCTAssertEqual(helperReport.verdict, .pass)
        XCTAssertEqual(helperReport.issueCodes, [])
    }
    #endif

    func testComparisonReportOmitsUnsafeHelperVideoFieldsAndPayloadSentinels() throws {
        let report = BenchmarkVisualTransportComparisonReport.fakeHelperComparison(
            selection: try .parse("vnc,helper-video")
        )
        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fieldNames = Set(object.keys)

        XCTAssertTrue(fieldNames.contains("selectedVisualTransports"))
        XCTAssertTrue(fieldNames.contains("vncReportShape"))
        XCTAssertTrue(fieldNames.contains("helperVideoReports"))

        let forbiddenFieldNames: Set<String> = [
            "host",
            "hostname",
            "endpoint",
            "address",
            "token",
            "password",
            "framePayload",
            "frameData",
            "encodedFrame",
            "decodedFrame",
            "screenshot",
            "thumbnail",
            "byteCount",
            "payloadBytes",
            "width",
            "height",
            "displayWidth",
            "displayHeight",
            "coordinates",
            "exactTimingMilliseconds",
            "startupMilliseconds",
            "perFrameTimings"
        ]
        XCTAssertTrue(fieldNames.isDisjoint(with: forbiddenFieldNames))

        let forbiddenSentinels = [
            "desk.tailnet.ts.net",
            "100.64.0.7",
            "5900",
            "hunter2",
            "token-secret",
            "FRAME_PAYLOAD_SENTINEL",
            "1920",
            "1080",
            "x=42",
            "y=24"
        ]
        for sentinel in forbiddenSentinels {
            XCTAssertFalse(json.contains(sentinel), "visual transport comparison leaked \(sentinel)")
        }
    }
}
