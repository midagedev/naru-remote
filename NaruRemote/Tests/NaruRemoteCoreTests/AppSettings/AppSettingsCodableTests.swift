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

    func testEncodingProducesEmptyJSONObject() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let json = String(decoding: data, as: UTF8.self)

        // Stable on-disk shape so the persistence pipeline is
        // unambiguous when the next setting is added.
        XCTAssertEqual(json, "{}")
    }
}
