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

    func testStoreRoundTripsProfiles() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            favorite: true
        )

        try await store.save(profile)

        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let allProfiles = await reloaded.allProfiles()
        let fetched = await reloaded.profile(id: profile.id)
        XCTAssertEqual(allProfiles, [profile])
        XCTAssertEqual(fetched, profile)
    }

    func testFilePersistenceReturnsEmptyProfilesWhenFileIsMissing() async throws {
        let fileURL = try Self.temporaryProfileStoreURL()
        let persistence = FileConnectionProfilePersistence(fileURL: fileURL)

        let loaded = try await persistence.loadProfiles()
        XCTAssertEqual(loaded, [])
    }

    func testFilePersistenceRoundTripsProfiles() async throws {
        let fileURL = try Self.temporaryProfileStoreURL()
        let persistence = FileConnectionProfilePersistence(fileURL: fileURL)
        let profile = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            port: 5901,
            allowsPiPWatch: false
        )

        try await persistence.saveProfiles([profile])

        let reloaded = try await FileConnectionProfilePersistence(fileURL: fileURL).loadProfiles()
        XCTAssertEqual(reloaded, [profile])
    }

    func testStoreDeletesProfileAndPersistsRemoval() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")

        try await store.save(profile)
        let removed = try await store.deleteProfile(id: profile.id)

        XCTAssertEqual(removed, profile)
        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let allProfiles = await reloaded.allProfiles()
        XCTAssertTrue(allProfiles.isEmpty)
    }

    func testStoreAllowsConcurrentSavesWithoutLosingProfiles() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let profiles = try (0..<50).map { index in
            try ConnectionProfile(
                displayName: "Desk \(index)",
                host: "desk-\(index).tailnet.ts.net"
            )
        }

        // Issue 50 concurrent saves through `withTaskGroup` so the
        // actor's serialization point is exercised.  Equivalent to
        // the prior `DispatchQueue` race; the actor's mailbox
        // guarantees the same atomicity per save without any
        // explicit lock.
        await withTaskGroup(of: Result<Void, Error>.self) { group in
            for profile in profiles {
                group.addTask {
                    do {
                        _ = try await store.save(profile)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                if case .failure(let error) = result {
                    XCTFail("Concurrent save failed: \(error)")
                }
            }
        }

        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let allProfiles = await reloaded.allProfiles()
        XCTAssertEqual(allProfiles.count, profiles.count)
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
