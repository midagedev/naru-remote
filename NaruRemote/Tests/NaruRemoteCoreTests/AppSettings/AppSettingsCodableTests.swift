import XCTest
@testable import NaruRemoteCore

final class AppSettingsCodableTests: XCTestCase {
    func testEmptyStructRoundTrips() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, AppSettings())
    }

    func testEmptyJSONObjectDecodes() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, AppSettings())
    }

    func testDecodingTolratesUnknownAndLegacyKeysForForwardCompat() throws {
        // A future build may add fields this build does not know
        // about.  A legacy file written by an older build that still
        // had `dismissedOnboardingChecklist` (removed when first-run
        // onboarding was reduced to a stateless empty-state CTA per
        // spec FR-015) must still load rather than fail and force the
        // user to start fresh.
        let json = """
        {
          "dismissedOnboardingChecklist": true,
          "futureFeatureToggle": "speedrun",
          "phase9DirectKeystrokes": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, AppSettings())
    }

    func testStreamPowerModeDecodesWhenPresent() throws {
        let json = """
        {
          "streamPowerMode": "power-saver"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.streamPowerMode, .powerSaver)
    }

    func testStartupPreflightModeDecodesWhenPresent() throws {
        let json = """
        {
          "startupPreflightMode": "one-hidden-frame"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.startupPreflightMode, .oneHiddenFrame)
        XCTAssertEqual(decoded.startupPreflightMode.requestedHiddenFrameCount, 1)
    }

    func testStreamEncodingModeDecodesPersistedLabels() throws {
        let cases: [(rawValue: String, mode: StreamEncodingMode)] = [
            (StreamEncodingMode.tightFirstCursor.rawValue, .tightFirstCursor),
            (StreamEncodingMode.localLowLatencyRGB565.rawValue, .localLowLatencyRGB565),
            (StreamEncodingMode.zrleCompressionZero.rawValue, .zrleCompressionZero),
            (StreamEncodingMode.zrleCompressionZeroRGB565.rawValue, .zrleCompressionZeroRGB565),
            (StreamEncodingMode.adaptiveGoodFull.rawValue, .adaptiveGoodFull)
        ]

        for testCase in cases {
            let json = """
            {
              "streamEncodingMode": "\(testCase.rawValue)"
            }
            """
            let data = try XCTUnwrap(json.data(using: .utf8))

            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

            XCTAssertEqual(decoded.streamEncodingMode, testCase.mode)
        }
    }

    func testStartupGlanceScaleModeDecodesPersistedLabels() throws {
        let cases: [(rawValue: String, mode: StreamStartupGlanceScaleMode, scale: Double)] = [
            (StreamStartupGlanceScaleMode.standard045.rawValue, .standard045, 0.45),
            (StreamStartupGlanceScaleMode.minimal035.rawValue, .minimal035, 0.35),
            (StreamStartupGlanceScaleMode.glance025.rawValue, .glance025, 0.25)
        ]

        for testCase in cases {
            let json = """
            {
              "startupGlanceScaleMode": "\(testCase.rawValue)"
            }
            """
            let data = try XCTUnwrap(json.data(using: .utf8))

            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

            XCTAssertEqual(decoded.startupGlanceScaleMode, testCase.mode)
            XCTAssertEqual(decoded.startupGlanceScaleMode.scale, testCase.scale, accuracy: 0.0001)
        }
    }

    func testEncodingProducesEmptyJSONObject() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let json = String(decoding: data, as: UTF8.self)

        // Stable on-disk shape so the persistence pipeline is
        // unambiguous when the next setting is added.
        XCTAssertEqual(json, "{}")
    }

    func testEncodingNonDefaultStreamPowerMode() throws {
        let data = try JSONEncoder().encode(AppSettings(streamPowerMode: .powerSaver))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded.streamPowerMode, .powerSaver)
        XCTAssertTrue(json.contains("\"streamPowerMode\""))
        XCTAssertTrue(json.contains("\"power-saver\""))
    }

    func testEncodingNonDefaultStartupPreflightMode() throws {
        let data = try JSONEncoder().encode(AppSettings(startupPreflightMode: .oneHiddenFrame))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded.startupPreflightMode, .oneHiddenFrame)
        XCTAssertTrue(json.contains("\"startupPreflightMode\""))
        XCTAssertTrue(json.contains("\"one-hidden-frame\""))
    }

    func testEncodingNonDefaultStreamEncodingModes() throws {
        let modes: [StreamEncodingMode] = [
            .tightFirstCursor,
            .localLowLatencyRGB565,
            .zrleCompressionZero,
            .zrleCompressionZeroRGB565,
            .adaptiveGoodFull
        ]

        for mode in modes {
            let data = try JSONEncoder().encode(AppSettings(streamEncodingMode: mode))
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
            let json = String(decoding: data, as: UTF8.self)

            XCTAssertEqual(decoded.streamEncodingMode, mode)
            XCTAssertTrue(json.contains("\"streamEncodingMode\""))
            XCTAssertTrue(json.contains("\"\(mode.rawValue)\""))
        }
    }

    func testEncodingNonDefaultStartupGlanceScaleModes() throws {
        let modes: [StreamStartupGlanceScaleMode] = [
            .minimal035,
            .glance025
        ]

        for mode in modes {
            let data = try JSONEncoder().encode(AppSettings(startupGlanceScaleMode: mode))
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
            let json = String(decoding: data, as: UTF8.self)

            XCTAssertEqual(decoded.startupGlanceScaleMode, mode)
            XCTAssertTrue(json.contains("\"startupGlanceScaleMode\""))
            XCTAssertTrue(json.contains("\"\(mode.rawValue)\""))
        }
    }

    func testStartupPreflightModeTogglesBetweenExperimentAndDisabled() {
        XCTAssertEqual(StreamStartupPreflightMode.disabled.toggled, .oneHiddenFrame)
        XCTAssertEqual(StreamStartupPreflightMode.oneHiddenFrame.toggled, .disabled)
        XCTAssertEqual(StreamStartupPreflightMode.disabled.requestedHiddenFrameCount, 0)
    }

    func testStreamEncodingModeTogglesThroughBenchmarkCandidates() {
        XCTAssertEqual(StreamEncodingMode.standard.toggled, .tightFirstCursor)
        XCTAssertEqual(StreamEncodingMode.tightFirstCursor.toggled, .localLowLatencyRGB565)
        XCTAssertEqual(StreamEncodingMode.localLowLatencyRGB565.toggled, .zrleCompressionZero)
        XCTAssertEqual(StreamEncodingMode.zrleCompressionZero.toggled, .zrleCompressionZeroRGB565)
        XCTAssertEqual(StreamEncodingMode.zrleCompressionZeroRGB565.toggled, .adaptiveGoodFull)
        XCTAssertEqual(StreamEncodingMode.adaptiveGoodFull.toggled, .standard)
    }

    func testStartupGlanceScaleModeTogglesThroughBenchmarkCandidates() {
        XCTAssertEqual(StreamStartupGlanceScaleMode.standard045.toggled, .minimal035)
        XCTAssertEqual(StreamStartupGlanceScaleMode.minimal035.toggled, .glance025)
        XCTAssertEqual(StreamStartupGlanceScaleMode.glance025.toggled, .standard045)
    }
}
