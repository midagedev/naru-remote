import XCTest
@testable import NaruRemoteCore

final class ConnectionProfileStoreTests: XCTestCase {
    func testProfileValidationTrimsNameAndHost() throws {
        let profile = try ConnectionProfile(
            displayName: "  Studio Mac  ",
            host: " studio.tailnet.ts.net ",
            username: "  hckim  "
        )

        XCTAssertEqual(profile.displayName, "Studio Mac")
        XCTAssertEqual(profile.host, "studio.tailnet.ts.net")
        XCTAssertEqual(profile.endpoint, "studio.tailnet.ts.net:5900")
        XCTAssertEqual(profile.username, "hckim")
        XCTAssertTrue(profile.allowsPiPWatch)
    }

    func testProfileCanDisablePiPWatchAndRoundTripThroughJSON() throws {
        let profile = try ConnectionProfile(
            displayName: "Sensitive Desk",
            host: "sensitive.tailnet.ts.net",
            allowsPiPWatch: false
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertFalse(decoded.allowsPiPWatch)
        XCTAssertEqual(decoded, profile)
    }

    func testLegacyDecodedProfileAllowsPiPWatchByDefault() throws {
        let legacyJSON = """
        {
          "id": "A2A70C3D-D223-4871-9F29-16729D95E9F0",
          "displayName": "Legacy Desk",
          "host": "legacy.tailnet.ts.net",
          "port": 5900
        }
        """

        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertTrue(decoded.allowsPiPWatch)
        XCTAssertEqual(decoded.hostKind, .magicDNS)
        XCTAssertFalse(decoded.favorite)
    }

    func testProfileRejectsInvalidPort() {
        XCTAssertThrowsError(
            try ConnectionProfile(displayName: "Bad", host: "bad.tailnet.ts.net", port: 0)
        ) { error in
            XCTAssertEqual(error as? ConnectionProfileValidationError, .invalidPort(0))
        }
    }

    func testStoreRoundTripsProfiles() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            favorite: true
        )

        try store.save(profile)

        let reloaded = try ConnectionProfileStore(persistence: persistence)
        XCTAssertEqual(reloaded.allProfiles(), [profile])
        XCTAssertEqual(reloaded.profile(id: profile.id), profile)
    }

    func testFilePersistenceReturnsEmptyProfilesWhenFileIsMissing() throws {
        let fileURL = try Self.temporaryProfileStoreURL()
        let persistence = FileConnectionProfilePersistence(fileURL: fileURL)

        XCTAssertEqual(try persistence.loadProfiles(), [])
    }

    func testFilePersistenceRoundTripsProfiles() throws {
        let fileURL = try Self.temporaryProfileStoreURL()
        let persistence = FileConnectionProfilePersistence(fileURL: fileURL)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            port: 5901,
            allowsPiPWatch: false
        )

        try persistence.saveProfiles([profile])

        let reloaded = try FileConnectionProfilePersistence(fileURL: fileURL).loadProfiles()
        XCTAssertEqual(reloaded, [profile])
    }

    func testStoreDeletesProfileAndPersistsRemoval() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        try store.save(profile)
        let removed = try store.deleteProfile(id: profile.id)

        XCTAssertEqual(removed, profile)
        XCTAssertTrue(try ConnectionProfileStore(persistence: persistence).allProfiles().isEmpty)
    }

    func testStoreAllowsConcurrentSavesWithoutLosingProfiles() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let profiles = try (0..<50).map { index in
            try ConnectionProfile(
                displayName: "Desk \(index)",
                host: "desk-\(index).tailnet.ts.net"
            )
        }
        let queue = DispatchQueue(label: "naru.profile.store.tests", attributes: .concurrent)
        let group = DispatchGroup()
        let saveErrors = ThreadSafeErrorRecorder()

        for profile in profiles {
            group.enter()
            queue.async {
                do {
                    _ = try store.save(profile)
                } catch {
                    saveErrors.record(error)
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(saveErrors.isEmpty)
        XCTAssertEqual(try ConnectionProfileStore(persistence: persistence).allProfiles().count, profiles.count)
    }
}

private extension ConnectionProfileStoreTests {
    static func temporaryProfileStoreURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("naru-profile-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appendingPathComponent("profiles.json")
    }
}

private final class ThreadSafeErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return errors.isEmpty
    }

    func record(_ error: Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }
}
