import XCTest
@testable import VNCLiveBenchmarkKit

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
