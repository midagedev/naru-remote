import XCTest
@testable import NaruRemoteCore

/// `AppSettings` is currently empty (the only field,
/// `dismissedOnboardingChecklist`, was removed when first-run
/// onboarding was reduced to a stateless empty-state CTA per spec
/// FR-015).  These tests still exercise the persistence pipeline
/// end-to-end so the next setting added here can plug in without
/// re-validating the file/in-memory backends.
final class FileAppSettingsPersistenceTests: XCTestCase {
    func testSaveThenLoadReturnsSameSettings() async throws {
        let fileURL = try Self.temporarySettingsStoreURL()
        let persistence = FileAppSettingsPersistence(fileURL: fileURL)
        let settings = AppSettings()

        try await persistence.save(settings)

        let reloaded = try await FileAppSettingsPersistence(fileURL: fileURL).load()
        XCTAssertEqual(reloaded, settings)
    }

    func testLoadOnMissingFileReturnsDefaults() async throws {
        let fileURL = try Self.temporarySettingsStoreURL()
        let persistence = FileAppSettingsPersistence(fileURL: fileURL)

        // Sanity: the file must not exist yet for the missing-file
        // branch to be exercised.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try await persistence.load()

        XCTAssertEqual(loaded, AppSettings())
    }

    func testSaveCreatesParentDirectory() async throws {
        // Mirrors `FileConnectionProfilePersistence`: the
        // `Application Support/NaruRemote/` directory may not
        // exist on first launch.  Save must create it.
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-app-settings-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = baseDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("settings.json")
        let persistence = FileAppSettingsPersistence(fileURL: fileURL)

        try await persistence.save(AppSettings())

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let reloaded = try await FileAppSettingsPersistence(fileURL: fileURL).load()
        XCTAssertEqual(reloaded, AppSettings())
    }

    func testInMemoryPersistenceRoundTripsSettings() async throws {
        let persistence = InMemoryAppSettingsPersistence()
        let settings = AppSettings()

        try await persistence.save(settings)

        let loaded = try await persistence.load()
        XCTAssertEqual(loaded, settings)
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
