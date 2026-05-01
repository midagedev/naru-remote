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

    func testDismissOnboardingChecklistFlipsPublishedFlag() {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        XCTAssertFalse(model.appSettings.dismissedOnboardingChecklist)

        model.dismissOnboardingChecklist()

        XCTAssertTrue(model.appSettings.dismissedOnboardingChecklist)
        XCTAssertNil(model.settingsPersistenceError)
    }

    func testDismissOnboardingChecklistWritesThroughToPersistence() throws {
        let persistence = InMemoryAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.dismissOnboardingChecklist()

        let stored = try persistence.load()
        XCTAssertTrue(stored.dismissedOnboardingChecklist)
    }

    func testInitLoadsPreSavedDismissedSettings() throws {
        let persistence = InMemoryAppSettingsPersistence(
            settings: AppSettings(dismissedOnboardingChecklist: true)
        )

        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        XCTAssertTrue(model.appSettings.dismissedOnboardingChecklist)
    }

    func testDismissOnboardingChecklistSurvivesPersistenceFailureWithoutCrashing() {
        let persistence = ThrowingAppSettingsPersistence()
        let model = NaruRemoteAppModel(settingsPersistence: persistence)

        model.dismissOnboardingChecklist()

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

    func load() throws -> AppSettings {
        AppSettings()
    }

    func save(_ settings: AppSettings) throws {
        throw Failure.diskUnavailable
    }
}
