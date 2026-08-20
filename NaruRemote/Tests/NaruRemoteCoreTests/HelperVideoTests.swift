import XCTest
@testable import NaruRemoteCore

final class HelperVideoTests: XCTestCase {
    func testHelperVideoAvailabilityUsesStableCatalogValues() {
        XCTAssertEqual(HelperVideoAvailability.notConfigured.rawValue, "notConfigured")
        XCTAssertEqual(HelperVideoAvailability.disabled.rawValue, "disabled")
        XCTAssertEqual(HelperVideoAvailability.checking.rawValue, "checking")
        XCTAssertEqual(HelperVideoAvailability.available.rawValue, "available")
        XCTAssertEqual(HelperVideoAvailability.permissionMissing.rawValue, "permissionMissing")
        XCTAssertEqual(HelperVideoAvailability.codecUnsupported.rawValue, "codecUnsupported")
        XCTAssertEqual(HelperVideoAvailability.revoked.rawValue, "revoked")
        XCTAssertEqual(HelperVideoAvailability.unreachable.rawValue, "unreachable")
        XCTAssertEqual(HelperVideoAvailability.failed.rawValue, "failed")
        XCTAssertEqual(HelperVideoAvailability.privateNetworkRequired.rawValue, "privateNetworkRequired")
    }

    func testHelperVideoStreamDefaultPortIsStable() {
        XCTAssertEqual(naruHelperVideoStreamDefaultPort, 5975)
    }

    func testHelperVideoFailureCodesAreNamespacedAndStable() {
        XCTAssertEqual(HelperVideoFailureCode.notConfigured.rawValue, "helperVideo.notConfigured")
        XCTAssertEqual(HelperVideoFailureCode.disabled.rawValue, "helperVideo.disabled")
        XCTAssertEqual(HelperVideoFailureCode.authFailed.rawValue, "helperVideo.authFailed")
        XCTAssertEqual(HelperVideoFailureCode.permissionMissing.rawValue, "helperVideo.permissionMissing")
        XCTAssertEqual(HelperVideoFailureCode.codecUnsupported.rawValue, "helperVideo.codecUnsupported")
        XCTAssertEqual(HelperVideoFailureCode.streamStalled.rawValue, "helperVideo.streamStalled")
        XCTAssertEqual(HelperVideoFailureCode.decoderRejected.rawValue, "helperVideo.decoderRejected")
        XCTAssertEqual(HelperVideoFailureCode.revoked.rawValue, "helperVideo.revoked")
        XCTAssertEqual(HelperVideoFailureCode.transportFailed.rawValue, "helperVideo.transportFailed")
        XCTAssertEqual(HelperVideoFailureCode.fallbackToVNC.rawValue, "helperVideo.fallbackToVNC")
        XCTAssertEqual(
            HelperVideoFailureCode.privateNetworkRequired.rawValue,
            "helperVideo.privateNetworkRequired"
        )
        XCTAssertEqual(
            HelperVideoFailureCode.transportProtectionRequired.rawValue,
            "helperVideo.transportProtectionRequired"
        )
    }

    func testHelperVideoTransportProtectionRequiresEncryptedOrExplicitlyProtectedFrames() {
        XCTAssertEqual(HelperVideoTransportProtection.encrypted.rawValue, "encrypted")
        XCTAssertEqual(
            HelperVideoTransportProtection.authenticatedPrivateProfile.rawValue,
            "authenticatedPrivateProfile"
        )
        XCTAssertEqual(HelperVideoTransportProtection.unprotected.rawValue, "unprotected")

        XCTAssertTrue(HelperVideoTransportProtection.encrypted.allowsEncodedFramePayloads)
        XCTAssertTrue(
            HelperVideoTransportProtection.authenticatedPrivateProfile.allowsEncodedFramePayloads
        )
        XCTAssertFalse(HelperVideoTransportProtection.unprotected.allowsEncodedFramePayloads)
    }

    func testProfileStateDefaultsToNoHelperVideoConfigured() throws {
        let state = HelperVideoProfileState()

        XCTAssertFalse(state.isEnabled)
        XCTAssertNil(state.pairingFingerprint)
        XCTAssertEqual(state.availability, .notConfigured)
        XCTAssertNil(state.lastFailureCode)
        XCTAssertEqual(state.lastCheckedBucket, .never)

        let decoded = try roundTrip(state)
        XCTAssertEqual(decoded, state)
    }

    func testProfileStateControlsHelperVideoAttemptAndVNCFallback() {
        let available = HelperVideoProfileState(isEnabled: true, availability: .available)
        XCTAssertTrue(available.canAttemptHelperVideoStream)
        XCTAssertFalse(available.shouldUseVNCVisualFallback)

        let disabled = HelperVideoProfileState(isEnabled: false, availability: .available)
        XCTAssertFalse(disabled.canAttemptHelperVideoStream)
        XCTAssertTrue(disabled.shouldUseVNCVisualFallback)

        let unreachable = HelperVideoProfileState(isEnabled: true, availability: .unreachable)
        XCTAssertFalse(unreachable.canAttemptHelperVideoStream)
        XCTAssertTrue(unreachable.shouldUseVNCVisualFallback)
    }

    func testStreamDescriptorDefaultsToLowLatencyH264WithoutUnsafeDetails() throws {
        let descriptor = HelperVideoStreamDescriptor(protocolVersion: 0)

        XCTAssertEqual(HelperVideoStreamDescriptor.minimumSupportedProtocolVersion, 1)
        XCTAssertEqual(descriptor.protocolVersion, HelperVideoStreamDescriptor.minimumSupportedProtocolVersion)
        XCTAssertEqual(descriptor.codec, .h264)
        XCTAssertEqual(descriptor.codecProfile, .unknown)
        XCTAssertEqual(descriptor.latencyMode, .lowLatency)
        XCTAssertEqual(descriptor.qualityBucket, .readability)
        XCTAssertEqual(descriptor.frameRateBucket, .upTo30)
        XCTAssertEqual(descriptor.colorMode, .standardDynamicRange)
        XCTAssertTrue(descriptor.supportsKeyframeRequest)
        XCTAssertTrue(descriptor.supportsFallbackSignal)

        let encoded = try JSONEncoder().encode(descriptor)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        assertDoesNotContainUnsafeDiagnosticTerms(json)
        XCTAssertFalse(json.contains("width"))
        XCTAssertFalse(json.contains("height"))
        XCTAssertFalse(json.contains("endpoint"))

        let decoded = try JSONDecoder().decode(HelperVideoStreamDescriptor.self, from: encoded)
        XCTAssertEqual(decoded, descriptor)
    }

    func testStreamHealthUsesCoarseBandsAndFallbackDecision() throws {
        let healthy = HelperVideoStreamHealth(
            state: .healthy,
            startupBand: .usable,
            sustainedUpdateBand: .smooth,
            decodePressure: .low,
            fallbackCountBucket: .none
        )
        XCTAssertFalse(healthy.shouldUseVNCVisualFallback)

        let stalled = HelperVideoStreamHealth(
            state: .stalled,
            startupBand: .slow,
            sustainedUpdateBand: .stalled,
            decodePressure: .medium,
            fallbackCountBucket: .one
        )
        XCTAssertTrue(stalled.shouldUseVNCVisualFallback)

        let decoded = try roundTrip(stalled)
        XCTAssertEqual(decoded, stalled)
    }

    func testHelperVideoCodecIncludesHEVC() {
        XCTAssertEqual(HelperVideoCodec.hevc.rawValue, "hevc")
        XCTAssertTrue(HelperVideoCodec.allCases.contains(.hevc))
    }

    func testStartStreamRequestDecodesMissingAcceptsHEVCAsNil() throws {
        let json = Data(
            """
            {"codec":"h264","latencyMode":"lowLatency","qualityBucket":"readability","maxFrameRateBucket":"upTo30"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(HelperVideoStartStreamRequestBody.self, from: json)

        XCTAssertEqual(decoded.codec, .h264)
        XCTAssertNil(decoded.acceptsHEVC)
    }

    func testStartStreamRequestOmitsAcceptsHEVCWhenNilAndKeepsCodecH264WhenOffering() throws {
        let omitted = try JSONEncoder().encode(HelperVideoStartStreamRequestBody())
        let omittedJSON = try XCTUnwrap(String(data: omitted, encoding: .utf8))
        XCTAssertFalse(omittedJSON.contains("acceptsHEVC"))

        let offering = HelperVideoStartStreamRequestBody(acceptsHEVC: true)
        let offeringJSON = try XCTUnwrap(String(data: try JSONEncoder().encode(offering), encoding: .utf8))
        XCTAssertEqual(offering.codec, .h264)
        XCTAssertTrue(offeringJSON.contains("\"codec\":\"h264\""))
        XCTAssertTrue(offeringJSON.contains("\"acceptsHEVC\":true"))
    }

    func testOldHelperIgnoresUnknownAcceptsHEVCKey() throws {
        struct LegacyStartStreamRequestBody: Codable, Equatable {
            var codec: HelperVideoCodec
            var latencyMode: HelperVideoLatencyMode
            var qualityBucket: HelperVideoQualityBucket
            var maxFrameRateBucket: HelperVideoFrameRateBucket
        }

        let encoded = try JSONEncoder().encode(HelperVideoStartStreamRequestBody(acceptsHEVC: true))
        let legacy = try JSONDecoder().decode(LegacyStartStreamRequestBody.self, from: encoded)

        XCTAssertEqual(legacy.codec, .h264)
        XCTAssertEqual(legacy.latencyMode, .lowLatency)
    }

    func testOldCapabilityAndDescriptorJSONStillDecode() throws {
        let capabilityJSON = Data(
            """
            {"availability":"available","screenRecordingPermission":"granted","codecSupport":"h264","latencyModes":["lowLatency"]}
            """.utf8
        )
        let capability = try JSONDecoder().decode(
            HelperVideoCapabilityResponseBody.self,
            from: capabilityJSON
        )
        XCTAssertEqual(capability.codecSupport, .h264)

        let descriptorJSON = Data(
            """
            {"protocolVersion":1,"codec":"h264","codecProfile":"high","latencyMode":"lowLatency","qualityBucket":"readability","frameRateBucket":"upTo30","colorMode":"standardDynamicRange","supportsKeyframeRequest":true,"supportsFallbackSignal":true}
            """.utf8
        )
        let descriptor = try JSONDecoder().decode(HelperVideoStreamDescriptor.self, from: descriptorJSON)
        XCTAssertEqual(descriptor.codec, .h264)
        XCTAssertEqual(descriptor.codecProfile, .high)
    }

    func testCatalogValuesAvoidSensitiveDiagnosticTerms() {
        let values = HelperVideoAvailability.allCases.map(\.rawValue)
            + HelperVideoFailureCode.allCases.map(\.rawValue)
            + HelperVideoCodec.allCases.map(\.rawValue)
            + HelperVideoCodecProfile.allCases.map(\.rawValue)
            + HelperVideoLatencyMode.allCases.map(\.rawValue)
            + HelperVideoQualityBucket.allCases.map(\.rawValue)
            + HelperVideoFrameRateBucket.allCases.map(\.rawValue)
            + HelperVideoColorMode.allCases.map(\.rawValue)
            + HelperVideoTransportProtection.allCases.map(\.rawValue)
            + HelperVideoStreamState.allCases.map(\.rawValue)
            + HelperVideoStartupBand.allCases.map(\.rawValue)
            + HelperVideoSustainedUpdateBand.allCases.map(\.rawValue)
            + HelperVideoDecodePressure.allCases.map(\.rawValue)
            + HelperVideoFallbackCountBucket.allCases.map(\.rawValue)

        for value in values {
            assertDoesNotContainUnsafeDiagnosticTerms(value)
        }
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoded = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: encoded)
    }

    private func assertDoesNotContainUnsafeDiagnosticTerms(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercased = value.lowercased()
        for forbidden in [
            "password",
            "token",
            "endpoint",
            "hostname",
            "host:",
            "displayid",
            "displayname",
            "coordinate",
            "pixel",
            "bytecount",
            "framepayload"
        ] {
            XCTAssertFalse(
                lowercased.contains(forbidden),
                "Unexpected unsafe diagnostic term \(forbidden) in \(value)",
                file: file,
                line: line
            )
        }
    }
}
