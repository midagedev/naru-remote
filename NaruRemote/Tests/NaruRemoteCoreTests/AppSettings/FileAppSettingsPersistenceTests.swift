import XCTest
@testable import NaruRemoteCore

final class FileAppSettingsPersistenceTests: XCTestCase {
    func testSaveThenLoadReturnsSameSettings() throws {
        let fileURL = try Self.temporarySettingsStoreURL()
        let persistence = FileAppSettingsPersistence(fileURL: fileURL)
        let settings = AppSettings(dismissedOnboardingChecklist: true)

        try persistence.save(settings)

        let reloaded = try FileAppSettingsPersistence(fileURL: fileURL).load()
        XCTAssertEqual(reloaded, settings)
    }

    func testLoadOnMissingFileReturnsDefaults() throws {
        let fileURL = try Self.temporarySettingsStoreURL()
        let persistence = FileAppSettingsPersistence(fileURL: fileURL)

        // Sanity: the file must not exist yet for the missing-file
        // branch to be exercised.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try persistence.load()

        XCTAssertEqual(loaded, AppSettings())
    }

    func testSaveCreatesParentDirectory() throws {
        // Mirrors `FileConnectionProfilePersistence`: the
        // `Application Support/NaruRemote/` directory may not
        // exist on first launch.  Save must create it.
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-app-settings-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = baseDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("settings.json")
        let persistence = FileAppSettingsPersistence(fileURL: fileURL)

        try persistence.save(AppSettings(dismissedOnboardingChecklist: true))

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let reloaded = try FileAppSettingsPersistence(fileURL: fileURL).load()
        XCTAssertTrue(reloaded.dismissedOnboardingChecklist)
    }

    func testInMemoryPersistenceRoundTripsSettings() throws {
        let persistence = InMemoryAppSettingsPersistence()
        let settings = AppSettings(dismissedOnboardingChecklist: true)

        try persistence.save(settings)

        XCTAssertEqual(try persistence.load(), settings)
    }
}

private extension FileAppSettingsPersistenceTests {
    static func temporarySettingsStoreURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-app-settings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appendingPathComponent("settings.json")
    }
}
