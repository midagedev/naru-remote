import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkHelperVideoReportTests: XCTestCase {
    func testHelperVideoProbeModeParsesSustainedExternalSyntheticMode() {
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("external-helper-sustained-synthetic-encoded-tcp"),
            .externalHelperSustainedSyntheticEncodedTCP
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeMode.parse("external-helper-sustained-screen-capturekit-tcp"),
            .externalHelperSustainedScreenCaptureKitTCP
        )
        XCTAssertTrue(
            BenchmarkHelperVideoProbeMode.usageDescription
                .contains("external-helper-sustained-synthetic-encoded-tcp")
        )
        XCTAssertTrue(
            BenchmarkHelperVideoProbeMode.usageDescription
                .contains("external-helper-sustained-screen-capturekit-tcp")
        )
    }

    func testSustainedExternalHelperFrameBudgetClampsAndScalesTimeouts() {
        XCTAssertEqual(
            BenchmarkHelperVideoProbeTiming.externalHelperSustainedFrameCount(
                environment: [:]
            ),
            30
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeTiming.externalHelperSustainedFrameCount(
                environment: ["NARU_HELPER_VIDEO_SUSTAINED_FRAME_COUNT": "2"]
            ),
            6
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeTiming.externalHelperSustainedFrameCount(
                environment: ["NARU_HELPER_VIDEO_SUSTAINED_FRAME_COUNT": "999"]
            ),
            120
        )
        XCTAssertEqual(
            BenchmarkHelperVideoProbeTiming.maxServerFrames(forExternalHelperFrameCount: 30),
            32
        )
        XCTAssertGreaterThan(
            BenchmarkHelperVideoProbeTiming.clientTimeout(
                forExternalHelperFrameCount: BenchmarkHelperVideoProbeTiming.externalHelperSmokeFrameCount
            ),
            3.0,
            "ScreenCaptureKit smoke probes must wait long enough for the helper to emit a typed capture-source stall instead of collapsing to a transport timeout."
        )
        XCTAssertGreaterThan(
            BenchmarkHelperVideoProbeTiming.startStreamTimeout(
                forExternalHelperFrameCount: 30
            ),
            BenchmarkHelperVideoProbeTiming.startStreamTimeout
        )
    }

    func testExternalHelperUnavailableUsesFixedSafeIssueCode() throws {
        let report = BenchmarkHelperVideoProbe
            .externalHelperSustainedSyntheticEncodedTCPHelperVideoReport(
                helperExecutablePath: "/tmp/naru-remote-missing-helper"
            )

        let json = String(data: try JSONEncoder().encode(report), encoding: .utf8) ?? ""

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertTrue(report.issueCodes.contains(.externalHelperUnavailable))
        XCTAssertTrue(json.contains("helper-video-external-helper-unavailable"))
        XCTAssertFalse(json.contains("/tmp/naru-remote-missing-helper"))
    }

    func testSustainedScreenCaptureKitHelperUnavailableUsesFixedSafeIssueCode() throws {
        let report = BenchmarkHelperVideoProbe
            .externalHelperSustainedScreenCaptureKitTCPHelperVideoReport(
                helperExecutablePath: "/tmp/naru-remote-missing-screen-helper"
            )

        let json = String(data: try JSONEncoder().encode(report), encoding: .utf8) ?? ""

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertTrue(report.issueCodes.contains(.externalHelperUnavailable))
        XCTAssertTrue(json.contains("helper-video-external-helper-unavailable"))
        XCTAssertFalse(json.contains("/tmp/naru-remote-missing-screen-helper"))
    }

    func testHelperVideoReportFixtureRoundTripsThroughSafeSchema() throws {
        let descriptor = HelperVideoStreamDescriptor(
            protocolVersion: 1,
            codec: .h264,
            codecProfile: .baseline,
            latencyMode: .lowLatency,
            qualityBucket: .readability,
            frameRateBucket: .upTo30,
            colorMode: .standardDynamicRange,
            supportsKeyframeRequest: true,
            supportsFallbackSignal: true
        )
        let health = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low,
            fallbackCountBucket: .none
        )
        let report = BenchmarkHelperVideoReport(
            descriptor: descriptor,
            health: health
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkHelperVideoReport.self, from: encoded)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.visualTransport, .helperVideo)
        XCTAssertEqual(decoded.streamProtocolVersion, 1)
        XCTAssertEqual(decoded.codec, .h264)
        XCTAssertEqual(decoded.codecProfile, .baseline)
        XCTAssertEqual(decoded.latencyMode, .lowLatency)
        XCTAssertEqual(decoded.qualityBucket, .readability)
        XCTAssertEqual(decoded.frameRateBucket, .upTo30)
        XCTAssertEqual(decoded.colorMode, .standardDynamicRange)
        XCTAssertEqual(decoded.streamState, .healthy)
        XCTAssertEqual(decoded.startupBand, .fast)
        XCTAssertEqual(decoded.sustainedUpdateBand, .smooth)
        XCTAssertEqual(decoded.decodePressure, .low)
        XCTAssertEqual(decoded.fallbackCountBucket, .none)
        XCTAssertEqual(decoded.verdict, .pass)
        XCTAssertEqual(decoded.issueCodes, [])
        XCTAssertEqual(decoded.readinessState, .readyForPhysicalGate)
        XCTAssertEqual(decoded.recommendedAction, .runPhysicalIPhoneHelperVideoGate)
    }

    func testHelperVideoReportDerivesFixedIssueCodesFromHealthBands() {
        let report = BenchmarkHelperVideoReport(
            streamProtocolVersion: -7,
            streamState: .stalled,
            startupBand: .failed,
            sustainedUpdateBand: .choppy,
            decodePressure: .high,
            fallbackCountBucket: .few,
            issueCodes: [.startupSlow, .startupSlow]
        )

        XCTAssertEqual(report.streamProtocolVersion, HelperVideoStreamDescriptor.minimumSupportedProtocolVersion)
        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.readinessState, .startupBlocked)
        XCTAssertEqual(report.recommendedAction, .inspectHelperVideoStartup)
        XCTAssertEqual(
            report.issueCodes,
            [
                .startupSlow,
                .streamUnhealthy,
                .startupFailed,
                .sustainedChoppy,
                .decodePressureHigh,
                .fallbackObserved
            ]
        )
    }

    func testIdleHelperVideoReportUsesDisabledVerdict() {
        let report = BenchmarkHelperVideoReport(issueCodes: [.startupSlow])

        XCTAssertEqual(report.streamState, .idle)
        XCTAssertEqual(report.verdict, .disabled)
        XCTAssertEqual(report.issueCodes, [.startupSlow, .streamDisabled])
        XCTAssertEqual(report.readinessState, .disabled)
        XCTAssertEqual(report.recommendedAction, .enableHelperVideo)
    }

    func testPermissionMissingIssueCodeUsesFixedSafeLabel() throws {
        let report = BenchmarkHelperVideoReport(
            streamState: .failed,
            startupBand: .failed,
            sustainedUpdateBand: .stalled,
            issueCodes: [.permissionMissing]
        )

        let json = String(data: try JSONEncoder().encode(report), encoding: .utf8) ?? ""

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.issueCodes, [.permissionMissing])
        XCTAssertEqual(report.readinessState, .permissionBlocked)
        XCTAssertEqual(report.recommendedAction, .grantScreenRecordingPermission)
        XCTAssertTrue(json.contains("helper-video-permission-missing"))
        XCTAssertTrue(json.contains("permissionBlocked"))
        XCTAssertTrue(json.contains("grant-helper-video-app-screen-recording-permission"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("screenrecording"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("cgpreflight"))
    }

    func testPermissionMissingTakesPriorityOverIdleDisabledState() {
        let report = BenchmarkHelperVideoReport(
            streamState: .idle,
            startupBand: .notMeasured,
            sustainedUpdateBand: .notMeasured,
            issueCodes: [.permissionMissing]
        )

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.issueCodes, [.permissionMissing])
        XCTAssertEqual(report.readinessState, .permissionBlocked)
        XCTAssertEqual(report.recommendedAction, .grantScreenRecordingPermission)
    }

    func testPermissionMissingDoesNotInventStreamHealthFailures() {
        let report = BenchmarkHelperVideoReport(
            streamState: .failed,
            startupBand: .failed,
            sustainedUpdateBand: .stalled,
            decodePressure: .high,
            fallbackCountBucket: .one,
            issueCodes: [.permissionMissing]
        )

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.issueCodes, [.permissionMissing])
        XCTAssertEqual(report.readinessState, .permissionBlocked)
        XCTAssertEqual(report.recommendedAction, .grantScreenRecordingPermission)
    }

    func testPermissionMissingOverridesOtherExplicitIssueCodes() {
        let report = BenchmarkHelperVideoReport(
            streamState: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .smooth,
            decodePressure: .low,
            issueCodes: [.transportFailed, .permissionMissing, .externalHelperTimedOut]
        )

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.issueCodes, [.permissionMissing])
        XCTAssertEqual(report.readinessState, .permissionBlocked)
        XCTAssertEqual(report.recommendedAction, .grantScreenRecordingPermission)
    }

    func testSustainedChoppyReportRoutesToSustainedCadenceInspection() {
        let report = BenchmarkHelperVideoReport(
            streamState: .healthy,
            startupBand: .fast,
            sustainedUpdateBand: .choppy,
            decodePressure: .low,
            fallbackCountBucket: .none
        )

        XCTAssertEqual(report.verdict, .warning)
        XCTAssertEqual(report.issueCodes, [.sustainedChoppy])
        XCTAssertEqual(report.readinessState, .sustainedDegraded)
        XCTAssertEqual(report.recommendedAction, .inspectHelperVideoSustainedCadence)
    }

    func testCaptureSourceUnavailableRoutesToCaptureSourceInspection() {
        let report = BenchmarkHelperVideoReport(
            streamState: .stalled,
            startupBand: .fast,
            sustainedUpdateBand: .stalled,
            decodePressure: .low,
            fallbackCountBucket: .one,
            issueCodes: [.captureSourceUnavailable]
        )

        XCTAssertEqual(report.verdict, .fail)
        XCTAssertEqual(report.readinessState, .sustainedDegraded)
        XCTAssertEqual(report.recommendedAction, .inspectHelperVideoCaptureSource)
        XCTAssertTrue(report.issueCodes.contains(.captureSourceUnavailable))
    }

    func testCaptureCallbackStageIssuesUseFixedSafeLabels() throws {
        let cases: [(BenchmarkHelperVideoIssueCode, String)] = [
            (.captureNoOutputCallbacks, "helper-video-capture-no-output-callbacks"),
            (.captureNonScreenCallbacks, "helper-video-capture-non-screen-callbacks"),
            (.captureNonDisplayableFrames, "helper-video-capture-non-displayable-frames"),
            (.captureMissingImageBuffer, "helper-video-capture-missing-image-buffer"),
            (
                .captureInsufficientDisplayableFrames,
                "helper-video-capture-insufficient-displayable-frames"
            )
        ]

        for (issueCode, safeLabel) in cases {
            let report = BenchmarkHelperVideoReport(
                streamState: .stalled,
                startupBand: .fast,
                sustainedUpdateBand: .stalled,
                decodePressure: .low,
                fallbackCountBucket: .one,
                issueCodes: [issueCode]
            )
            let json = String(data: try JSONEncoder().encode(report), encoding: .utf8) ?? ""

            XCTAssertEqual(report.verdict, .fail)
            XCTAssertEqual(report.readinessState, .sustainedDegraded)
            XCTAssertEqual(report.recommendedAction, .inspectHelperVideoCaptureSource)
            XCTAssertTrue(report.issueCodes.contains(issueCode))
            XCTAssertTrue(json.contains(safeLabel), json)
            XCTAssertFalse(json.localizedCaseInsensitiveContains("screencapturekit"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("callbackCount"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("displayid"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("width"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("height"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("raw"))
            XCTAssertFalse(json.localizedCaseInsensitiveContains("error"))
        }
    }

    func testHelperVideoReportFixtureOmitsUnsafeFieldsAndPayloadSentinels() throws {
        let descriptor = HelperVideoStreamDescriptor(
            protocolVersion: 1,
            codec: .h264,
            codecProfile: .main,
            latencyMode: .balanced,
            qualityBucket: .balanced,
            frameRateBucket: .upTo15,
            colorMode: .standardDynamicRange,
            supportsKeyframeRequest: false,
            supportsFallbackSignal: true
        )
        let health = HelperVideoStreamHealth(
            state: .fallbackToVNC,
            startupBand: .usable,
            sustainedUpdateBand: .stalled,
            decodePressure: .medium,
            fallbackCountBucket: .one
        )
        let report = BenchmarkHelperVideoReport(
            descriptor: descriptor,
            health: health
        )

        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fieldNames = Set(object.keys)

        XCTAssertTrue(fieldNames.contains("visualTransport"))
        XCTAssertTrue(fieldNames.contains("startupBand"))
        XCTAssertTrue(fieldNames.contains("sustainedUpdateBand"))
        XCTAssertTrue(fieldNames.contains("decodePressure"))
        XCTAssertTrue(fieldNames.contains("fallbackCountBucket"))
        XCTAssertTrue(fieldNames.contains("issueCodes"))

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
            XCTAssertFalse(json.contains(sentinel), "helper-video benchmark report leaked \(sentinel)")
        }
    }
}
