import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class AppSettingsAppModelTests: XCTestCase {
    func testDefaultSettingsAreLoadedWhenNoPersistenceProvided() {
        let model = NaruRemoteAppModel()

        XCTAssertFalse(model.appSettings.dismissedOnboardingChecklist)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testDismissOnboardingChecklistFlipsPublishedFlag() async {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        XCTAssertFalse(model.appSettings.dismissedOnboardingChecklist)

        await model.dismissOnboardingChecklist()

        XCTAssertTrue(model.appSettings.dismissedOnboardingChecklist)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testDismissOnboardingChecklistWritesThroughToPersistence() async throws {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        await model.dismissOnboardingChecklist()

        let stored = try await persistence.load()
        XCTAssertTrue(stored.dismissedOnboardingChecklist)
    }

    func testInitLoadsPreSavedDismissedSettings() async throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(dismissedOnboardingChecklist: true)
        )

        let model = NaruRemoteAppModel(settingsPersistence: persistence)
        // Settings load is now async (the in-memory persistence is
        // an `actor`); the iOS shell calls `loadStoredSettings()`
        // from a `.task` modifier, the test mirrors that step here.
        await model.loadStoredSettings()

        XCTAssertTrue(model.appSettings.dismissedOnboardingChecklist)
    }

    func testDismissOnboardingChecklistSurvivesPersistenceFailureWithoutCrashing() async {
        let persistence = ThrowingAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        await model.dismissOnboardingChecklist()

        // The in-memory flag still flips so the current session
        // honors the user's dismissal even when the disk write
        // fails.  The error surfaces through
        // `settingsPersistenceError` for the shell to show.
        XCTAssertTrue(model.appSettings.dismissedOnboardingChecklist)
        XCTAssertNotNil(model.settingsPersistenceError)
    }
}

private struct ThrowingAppSettingsPersistence: AppSettingsPersisting {
    enum Failure: Error {
        case diskUnavailable
    }

    func load() async throws -> AppSettings {
        AppSettings()
    }

    func save(_ settings: AppSettings) async throws {
        throw Failure.diskUnavailable
    }
}
