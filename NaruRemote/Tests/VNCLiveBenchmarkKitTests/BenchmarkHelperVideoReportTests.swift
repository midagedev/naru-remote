import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkHelperVideoReportTests: XCTestCase {
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
        XCTAssertEqual(decoded.schemaVersion, 1)
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
