import Foundation
import XCTest
import NaruHelperKit
import NaruRemoteCore

#if os(macOS) && canImport(VideoToolbox)
import VideoToolbox
#endif

final class NaruHelperVideoEncoderPrototypeTests: XCTestCase {
    func testFeatureFlagParsesOnlyExplicitEnabledValues() {
        XCTAssertTrue(
            NaruHelperVideoEncoderFeatureFlag.fromEnvironment(
                [NaruHelperVideoEncoderFeatureFlag.environmentKey: "1"]
            ).isEnabled
        )
        XCTAssertTrue(
            NaruHelperVideoEncoderFeatureFlag.fromEnvironment(
                [NaruHelperVideoEncoderFeatureFlag.environmentKey: "videotoolbox"]
            ).isEnabled
        )
        XCTAssertFalse(
            NaruHelperVideoEncoderFeatureFlag.fromEnvironment(
                [NaruHelperVideoEncoderFeatureFlag.environmentKey: "0"]
            ).isEnabled
        )
        XCTAssertFalse(NaruHelperVideoEncoderFeatureFlag.fromEnvironment([:]).isEnabled)
    }

    func testDisabledFeatureFlagDoesNotPrepareSession() {
        let recorder = VideoEncoderSessionProbeRecorder(result: .prepared)
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: false) },
            sessionProvider: {
                recorder.record()
            }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .disabled)
        XCTAssertEqual(response.featureFlagState, .disabled)
        XCTAssertEqual(response.encoderAPI, .videoToolbox)
        XCTAssertEqual(response.codec, .h264)
        XCTAssertEqual(response.codecProfile, .high)
        XCTAssertEqual(response.latencyMode, .lowLatency)
        XCTAssertEqual(response.qualityBucket, .readability)
        XCTAssertEqual(response.sessionState, .notStarted)
        XCTAssertEqual(response.safeFailureCode, .disabled)
        XCTAssertEqual(recorder.callCount, 0)
    }

    func testEnabledFeatureFlagWithPreparedSessionReportsAvailable() {
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: true) },
            sessionProvider: { .prepared }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .available)
        XCTAssertEqual(response.featureFlagState, .enabled)
        XCTAssertEqual(response.encoderAPI, .videoToolbox)
        XCTAssertEqual(response.codec, .h264)
        XCTAssertEqual(response.codecProfile, .high)
        XCTAssertEqual(response.latencyMode, .lowLatency)
        XCTAssertEqual(response.qualityBucket, .readability)
        XCTAssertEqual(response.sessionState, .prepared)
        XCTAssertNil(response.safeFailureCode)
    }

    func testEnabledFeatureFlagWithUnavailableSessionReportsCodecUnsupported() {
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: true) },
            sessionProvider: { .unavailable }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .codecUnsupported)
        XCTAssertEqual(response.featureFlagState, .enabled)
        XCTAssertEqual(response.encoderAPI, .videoToolbox)
        XCTAssertEqual(response.sessionState, .unavailable)
        XCTAssertEqual(response.safeFailureCode, .codecUnsupported)
    }

    func testUnsupportedPlatformOmitsEncoderAPI() {
        let probe = NaruHelperVideoEncoderPrototypeProbe(
            encoderAPI: nil,
            featureFlagProvider: { NaruHelperVideoEncoderFeatureFlag(isEnabled: true) },
            sessionProvider: { .unsupported }
        )

        let response = probe.capability()

        XCTAssertEqual(response.availability, .codecUnsupported)
        XCTAssertEqual(response.featureFlagState, .enabled)
        XCTAssertNil(response.encoderAPI)
        XCTAssertEqual(response.sessionState, .unsupported)
        XCTAssertEqual(response.safeFailureCode, .codecUnsupported)
    }

    func testEncoderPrototypeJSONUsesOnlyFixedCatalogValues() throws {
        let response = NaruHelperVideoEncoderPrototypeResponse(
            availability: .available,
            featureFlagState: .enabled,
            encoderAPI: .videoToolbox,
            sessionState: .prepared
        )

        let json = String(data: try JSONEncoder().encode(response), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"availability\":\"available\""))
        XCTAssertTrue(json.contains("\"featureFlagState\":\"enabled\""))
        XCTAssertTrue(json.contains("\"encoderAPI\":\"videoToolbox\""))
        XCTAssertTrue(json.contains("\"codec\":\"h264\""))
        XCTAssertTrue(json.contains("\"codecProfile\":\"high\""))
        XCTAssertTrue(json.contains("\"latencyMode\":\"lowLatency\""))
        XCTAssertTrue(json.contains("\"qualityBucket\":\"readability\""))
        XCTAssertTrue(json.contains("\"sessionState\":\"prepared\""))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("display"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("dimension"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("endpoint"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("host"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("byte"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("payload"))
    }

    #if os(macOS) && canImport(VideoToolbox)
    func testToolboxSyntheticAccessUnitSourceEmitsRealAnnexBParameterSetsAndFrame() throws {
        let source = NaruHelperVideoToolboxSyntheticAccessUnitSource(
            frameCount: 2,
            width: 64,
            height: 64
        )

        let accessUnits = try source.accessUnits(
            for: HelperVideoStartStreamRequestBody(maxFrameRateBucket: .upTo15)
        )

        XCTAssertGreaterThanOrEqual(accessUnits.count, 2)
        XCTAssertEqual(accessUnits[0].sequence, 0)
        XCTAssertEqual(accessUnits[0].kind, .parameterSet)
        XCTAssertTrue(Self.nalTypes(in: accessUnits[0].binaryPayload).contains(7))
        XCTAssertTrue(Self.nalTypes(in: accessUnits[0].binaryPayload).contains(8))
        XCTAssertTrue(accessUnits[0].binaryPayload.starts(with: Self.annexBStartCode))

        let mediaAccessUnits = accessUnits.dropFirst()
        XCTAssertTrue(mediaAccessUnits.contains { $0.kind == .keyframe })
        XCTAssertTrue(mediaAccessUnits.allSatisfy { $0.binaryPayload.starts(with: Self.annexBStartCode) })
        XCTAssertFalse(accessUnits.map(\.binaryPayload).contains(Data([0x65, 0x88])))
    }
    #endif

    private static let annexBStartCode = Data([0x00, 0x00, 0x00, 0x01])

    private static func nalTypes(in annexBPayload: Data) -> [UInt8] {
        let bytes = [UInt8](annexBPayload)
        var index = 0
        var types: [UInt8] = []
        while index + 2 < bytes.count {
            guard bytes[index] == 0, bytes[index + 1] == 0 else {
                index += 1
                continue
            }

            if bytes[index + 2] == 1 {
                if index + 3 < bytes.count {
                    types.append(bytes[index + 3] & 0x1F)
                }
                index += 3
                continue
            }

            if index + 3 < bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                if index + 4 < bytes.count {
                    types.append(bytes[index + 4] & 0x1F)
                }
                index += 4
                continue
            }

            index += 1
        }
        return types
    }
}

private final class VideoEncoderSessionProbeRecorder: @unchecked Sendable {
    private let result: NaruHelperVideoEncoderSessionState
    private let lock = NSLock()
    private var count = 0

    init(result: NaruHelperVideoEncoderSessionState) {
        self.result = result
    }

    var callCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }
        return count
    }

    func record() -> NaruHelperVideoEncoderSessionState {
        lock.lock()
        defer {
            lock.unlock()
        }
        count += 1
        return result
    }
}
