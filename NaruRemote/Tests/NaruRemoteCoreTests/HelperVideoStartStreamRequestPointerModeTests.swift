import XCTest
@testable import NaruRemoteCore

// Spec 042 FR-007 (Round C, wire half): `HelperVideoStartStreamRequestBody`
// carries the phone's pointer mode; nil is omitted, unknown or wrong-typed
// values decode as nil (the handshake never breaks), and a pre-042 phone's
// body — no `pointerMode` key — decodes exactly as before.

final class HelperVideoStartStreamRequestPointerModeTests: XCTestCase {
    func testPointerModeRawValuesMatchWireContract() {
        XCTAssertEqual(HelperVideoPointerMode.trackpad.rawValue, "trackpad")
        XCTAssertEqual(HelperVideoPointerMode.directTouch.rawValue, "directTouch")
        XCTAssertEqual(HelperVideoPointerMode.allCases, [.trackpad, .directTouch])
    }

    func testPointerModeRoundTripsThroughJSON() throws {
        for mode in HelperVideoPointerMode.allCases {
            let body = HelperVideoStartStreamRequestBody(pointerMode: mode)
            let encoded = try JSONEncoder().encode(body)
            let encodedJSON = try XCTUnwrap(String(data: encoded, encoding: .utf8))

            XCTAssertTrue(encodedJSON.contains("\"pointerMode\":\"\(mode.rawValue)\""))

            let decoded = try JSONDecoder().decode(
                HelperVideoStartStreamRequestBody.self,
                from: encoded
            )
            XCTAssertEqual(decoded, body)
            XCTAssertEqual(decoded.pointerMode, mode)
            XCTAssertEqual(decoded.codec, .h264)
        }
    }

    func testStartStreamRequestOmitsPointerModeWhenNil() throws {
        let encoded = try JSONEncoder().encode(HelperVideoStartStreamRequestBody())
        let encodedJSON = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(encodedJSON.contains("pointerMode"))
        let decoded = try JSONDecoder().decode(
            HelperVideoStartStreamRequestBody.self,
            from: encoded
        )
        XCTAssertNil(decoded.pointerMode)
    }

    func testStartStreamRequestWithoutPointerModeKeyDecodesAsNil() throws {
        let json = Data(
            """
            {"codec":"h264","latencyMode":"lowLatency","qualityBucket":"readability","maxFrameRateBucket":"upTo30"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(HelperVideoStartStreamRequestBody.self, from: json)

        XCTAssertNil(decoded.pointerMode)
        XCTAssertEqual(decoded.codec, .h264)
        XCTAssertEqual(decoded.latencyMode, .lowLatency)
        XCTAssertEqual(decoded.qualityBucket, .readability)
        XCTAssertEqual(decoded.maxFrameRateBucket, .upTo30)
    }

    func testUnknownPointerModeStringValueDecodesAsNil() throws {
        let json = Data(
            """
            {"codec":"h264","latencyMode":"lowLatency","qualityBucket":"readability","maxFrameRateBucket":"upTo30","pointerMode":"telepathic"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(HelperVideoStartStreamRequestBody.self, from: json)

        XCTAssertNil(decoded.pointerMode)
        XCTAssertEqual(decoded.codec, .h264)
    }

    func testWrongTypedPointerModeJSONValuesDecodeAsNil() throws {
        for value in ["3", "true", "{\"mode\":\"trackpad\"}", "[\"trackpad\"]"] {
            let json = Data(
                """
                {"codec":"h264","latencyMode":"lowLatency","qualityBucket":"readability","maxFrameRateBucket":"upTo30","pointerMode":\(value)}
                """.utf8
            )

            let decoded = try JSONDecoder().decode(
                HelperVideoStartStreamRequestBody.self,
                from: json
            )

            XCTAssertNil(decoded.pointerMode, "pointerMode:\(value) must decode as nil")
            XCTAssertEqual(decoded.codec, .h264)
        }
    }

    func testLegacyStartStreamBodyDecodingIgnoresPointerModeKey() throws {
        struct LegacyStartStreamRequestBody: Codable, Equatable {
            var codec: HelperVideoCodec
            var latencyMode: HelperVideoLatencyMode
            var qualityBucket: HelperVideoQualityBucket
            var maxFrameRateBucket: HelperVideoFrameRateBucket
        }

        let encoded = try JSONEncoder().encode(
            HelperVideoStartStreamRequestBody(pointerMode: .trackpad)
        )
        let legacy = try JSONDecoder().decode(LegacyStartStreamRequestBody.self, from: encoded)

        XCTAssertEqual(legacy.codec, .h264)
        XCTAssertEqual(legacy.latencyMode, .lowLatency)
        XCTAssertEqual(legacy.qualityBucket, .readability)
        XCTAssertEqual(legacy.maxFrameRateBucket, .upTo30)
    }
}
