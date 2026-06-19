import Foundation
import NaruHelperKit
import NaruRemoteCore
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

    func testProbeOnlyReportWrapsComparisonWithoutLiveTargetFields() throws {
        let report = BenchmarkHelperVideoProbeOnlyReport.make(
            selection: try .parse("helper-video"),
            probeMode: .syntheticTCP
        )

        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.helperVideoProbeMode, .syntheticTCP)
        XCTAssertEqual(report.visualTransportComparison.selectedVisualTransports, [.helperVideo])
        XCTAssertEqual(report.visualTransportComparison.helperVideoReports.first?.verdict, .pass)
        XCTAssertTrue(object.keys.contains("helperVideoProbeMode"))
        XCTAssertTrue(object.keys.contains("visualTransportComparison"))
        XCTAssertFalse(json.contains("NARU_LIVE_MAC_HOST"))
        XCTAssertFalse(json.contains("NARU_LIVE_MAC_PASSWORD"))
        XCTAssertFalse(json.contains("NARU_HELPER_EXECUTABLE"))
        XCTAssertFalse(json.contains("benchmark-helper-video-external-secret"))
    }

    func testHelperVideoProbeModeParsesStableCLILabels() {
        XCTAssertEqual(BenchmarkHelperVideoProbeMode.parse("disabled"), .disabled)
        XCTAssertEqual(BenchmarkHelperVideoProbeMode.parse("synthetic-tcp"), .syntheticTCP)
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("synthetic-encoded-tcp"),
            .syntheticEncodedTCP
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("screen-capturekit-tcp"),
            .screenCaptureKitTCP
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("external-helper-synthetic-encoded-tcp"),
            .externalHelperSyntheticEncodedTCP
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("external-helper-sustained-synthetic-encoded-tcp"),
            .externalHelperSustainedSyntheticEncodedTCP
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("external-helper-screen-capturekit-tcp"),
            .externalHelperScreenCaptureKitTCP
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("external-helper-sustained-screen-capturekit-tcp"),
            .externalHelperSustainedScreenCaptureKitTCP
        )
        XCTAssertNil(BenchmarkHelperVideoProbeMode.parse("local"))
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.usageDescription,
            "disabled|synthetic-tcp|synthetic-encoded-tcp|screen-capturekit-tcp|external-helper-synthetic-encoded-tcp|external-helper-sustained-synthetic-encoded-tcp|external-helper-screen-capturekit-tcp|external-helper-sustained-screen-capturekit-tcp"
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

    func testScreenCaptureKitTCPProbeCanUseInjectedSourceAndReportsPass() throws {
        let report = BenchmarkHelperVideoProbe.makeComparison(
            selection: try .parse("helper-video"),
            probeMode: .screenCaptureKitTCP,
            screenCaptureKitAccessUnitSource: NaruHelperVideoStaticAccessUnitSource(
                accessUnits: [
                    NaruHelperVideoAccessUnit(
                        sequence: 0,
                        kind: .parameterSet,
                        binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x67])
                    ),
                    NaruHelperVideoAccessUnit(
                        sequence: 1,
                        kind: .keyframe,
                        binaryPayload: Data([0x00, 0x00, 0x00, 0x01, 0x65])
                    )
                ]
            )
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

    func testScreenCaptureKitTCPProbeMapsInjectedCaptureTimeoutToSafeIssueCode() throws {
        let report = BenchmarkHelperVideoProbe.makeComparison(
            selection: try .parse("helper-video"),
            probeMode: .screenCaptureKitTCP,
            screenCaptureKitAccessUnitSource: FailingHelperVideoAccessUnitSource(
                error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError.captureTimedOut
            )
        )
        let helperReport = try XCTUnwrap(report.helperVideoReports.first)
        let json = String(decoding: try JSONEncoder().encode(helperReport), as: UTF8.self)

        XCTAssertEqual(helperReport.verdict, .fail)
        XCTAssertTrue(
            helperReport.issueCodes.contains(.captureTimedOut),
            "\(helperReport.issueCodes) \(json)"
        )
        XCTAssertEqual(helperReport.recommendedAction, .inspectHelperVideoCaptureSource)
        XCTAssertTrue(
            helperReport.issueCodes.contains(.streamUnhealthy),
            "\(helperReport.issueCodes) \(json)"
        )
        XCTAssertTrue(json.contains("helper-video-capture-timed-out"), json)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("screencapturekit"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("raw"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("error"))
    }

    func testScreenCaptureKitTCPProbeMapsInjectedNoCallbackTimeoutToSafeIssueCode() throws {
        let report = BenchmarkHelperVideoProbe.makeComparison(
            selection: try .parse("helper-video"),
            probeMode: .screenCaptureKitTCP,
            screenCaptureKitAccessUnitSource: FailingHelperVideoAccessUnitSource(
                error: NaruHelperVideoScreenCaptureKitAccessUnitSourceError
                    .captureNoOutputCallbacks
            )
        )
        let helperReport = try XCTUnwrap(report.helperVideoReports.first)
        let json = String(decoding: try JSONEncoder().encode(helperReport), as: UTF8.self)

        XCTAssertEqual(helperReport.verdict, .fail)
        XCTAssertTrue(
            helperReport.issueCodes.contains(.captureNoOutputCallbacks),
            "\(helperReport.issueCodes) \(json)"
        )
        XCTAssertEqual(helperReport.recommendedAction, .inspectHelperVideoCaptureSource)
        XCTAssertTrue(json.contains("helper-video-capture-no-output-callbacks"), json)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("screencapturekit"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("callbackCount"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("raw"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("error"))
    }

    func testExternalHelperSyntheticEncodedTCPProbeFailsSafelyWhenExecutableIsMissing() throws {
        let missingPath = "/tmp/naru-helper-missing-\(UUID().uuidString)"
        let helperReport = BenchmarkHelperVideoProbe.externalHelperSyntheticEncodedTCPHelperVideoReport(
            helperExecutablePath: missingPath
        )

        XCTAssertEqual(helperReport.streamState, .failed)
        XCTAssertEqual(helperReport.startupBand, .failed)
        XCTAssertEqual(helperReport.verdict, .fail)
        XCTAssertTrue(helperReport.issueCodes.contains(.streamUnhealthy))
        XCTAssertTrue(helperReport.issueCodes.contains(.startupFailed))

        let json = String(
            decoding: try JSONEncoder().encode(helperReport),
            as: UTF8.self
        )
        XCTAssertFalse(json.contains(missingPath))
        XCTAssertFalse(json.contains("NARU_HELPER_VIDEO_BENCHMARK_TOKEN"))
        XCTAssertFalse(json.contains("NARU_HELPER_VIDEO_BENCHMARK_PROFILE_FINGERPRINT"))
        XCTAssertFalse(json.contains("benchmark-helper-video-external-secret"))
        XCTAssertFalse(json.contains("sha256:benchmark-helper-video-external"))
    }

    func testExternalHelperScreenCaptureKitTCPProbeFailsSafelyWhenUnavailable() throws {
        let missingPath = "/tmp/naru-helper-screen-missing-\(UUID().uuidString)"
        let helperReport = BenchmarkHelperVideoProbe.externalHelperScreenCaptureKitTCPHelperVideoReport(
            helperExecutablePath: missingPath
        )

        XCTAssertEqual(helperReport.streamState, .failed)
        XCTAssertEqual(helperReport.startupBand, .failed)
        XCTAssertEqual(helperReport.verdict, .fail)
        XCTAssertTrue(helperReport.issueCodes.contains(.streamUnhealthy))
        XCTAssertTrue(helperReport.issueCodes.contains(.startupFailed))
        XCTAssertFalse(helperReport.issueCodes.contains(.permissionMissing))

        let json = String(
            decoding: try JSONEncoder().encode(helperReport),
            as: UTF8.self
        )
        XCTAssertFalse(json.contains(missingPath))
        XCTAssertFalse(json.contains("NARU_HELPER_VIDEO_BENCHMARK_TOKEN"))
        XCTAssertFalse(json.contains("NARU_HELPER_VIDEO_BENCHMARK_PROFILE_FINGERPRINT"))
        XCTAssertFalse(json.contains("benchmark-helper-video-external-secret"))
        XCTAssertFalse(json.contains("sha256:benchmark-helper-video-external"))
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

private final class FailingHelperVideoAccessUnitSource:
    NaruHelperVideoAccessUnitSource,
    @unchecked Sendable
{
    private let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func accessUnits(
        for request: HelperVideoStartStreamRequestBody
    ) throws -> [NaruHelperVideoAccessUnit] {
        throw error
    }
}
