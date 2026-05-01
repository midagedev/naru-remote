import XCTest
@testable import NaruRemoteCore

final class AppSettingsCodableTests: XCTestCase {
    func testRoundTripWithDefaultValuesPreservesDefaults() throws {
        let settings = AppSettings()

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertFalse(decoded.dismissedOnboardingChecklist)
    }

    func testEmptyJSONObjectDecodesAsDefaults() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, AppSettings())
    }

    func testDecodingTolratesUnknownKeysForForwardCompat() throws {
        // A future build may add fields this build does not know
        // about.  Older binaries must still load the file rather
        // than fail and force the user to start fresh.
        let json = """
        {
          "dismissedOnboardingChecklist": true,
          "futureFeatureToggle": "speedrun",
          "phase9DirectKeystrokes": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.dismissedOnboardingChecklist)
    }

    func testRoundTripWithDismissedOnboardingChecklistTrue() throws {
        let settings = AppSettings(dismissedOnboardingChecklist: true)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(decoded.dismissedOnboardingChecklist)
    }
}
