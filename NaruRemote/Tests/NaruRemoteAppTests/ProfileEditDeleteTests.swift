import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class ProfileEditDeleteTests: XCTestCase {
    // MARK: - editProfile

    func testEditProfileReplacesFieldsAndPersistsThroughStore() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let original = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            port: 5900,
            allowsPiPWatch: true
        )
        model.addProfile(original)

        let edited = try ConnectionProfile(
            id: original.id,
            displayName: "Desk Renamed",
            host: "renamed.tailnet.ts.net",
            port: 5905,
            allowsPiPWatch: false
        )

        model.editProfile(edited, password: nil)

        let stored = try ConnectionProfileStore(persistence: persistence).allProfiles()
        XCTAssertEqual(stored.count, 1)
        let storedProfile = try XCTUnwrap(stored.first)
        XCTAssertEqual(storedProfile.id, original.id)
        XCTAssertEqual(storedProfile.displayName, "Desk Renamed")
        XCTAssertEqual(storedProfile.host, "renamed.tailnet.ts.net")
        XCTAssertEqual(storedProfile.port, 5905)
        XCTAssertFalse(storedProfile.allowsPiPWatch)
        XCTAssertNil(model.profilePersistenceError)
        XCTAssertEqual(model.snapshot.profiles, [storedProfile])
    }

    func testEditProfileWithNilPasswordPreservesExistingCredential() throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(original, password: "secret")
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)

        let edited = try ConnectionProfile(
            id: savedProfile.id,
            displayName: "Desk Renamed",
            host: savedProfile.host,
            credentialRef: credentialRef
        )

        model.editProfile(edited, password: nil)

        XCTAssertEqual(try credentialStore.password(for: credentialRef), "secret")
        XCTAssertEqual(model.snapshot.profiles.first?.credentialRef, credentialRef)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithEmptyPasswordRemovesExistingCredential() throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(original, password: "secret")
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)

        let edited = try ConnectionProfile(
            id: savedProfile.id,
            displayName: savedProfile.displayName,
            host: savedProfile.host,
            credentialRef: credentialRef
        )

        model.editProfile(edited, password: "")

        XCTAssertNil(try credentialStore.password(for: credentialRef))
        XCTAssertNil(model.snapshot.profiles.first?.credentialRef)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithNonEmptyPasswordUpdatesCredential() throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(original, password: "old-secret")
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)

        let edited = try ConnectionProfile(
            id: savedProfile.id,
            displayName: savedProfile.displayName,
            host: savedProfile.host,
            credentialRef: credentialRef
        )

        model.editProfile(edited, password: "new-secret")

        XCTAssertEqual(try credentialStore.password(for: credentialRef), "new-secret")
        XCTAssertEqual(model.snapshot.profiles.first?.credentialRef, credentialRef)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithPasswordOnProfileMissingCredentialRefAddsOne() throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(original)
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        XCTAssertNil(savedProfile.credentialRef)

        model.editProfile(savedProfile, password: "fresh-secret")

        let updated = try XCTUnwrap(model.snapshot.profiles.first)
        let credentialRef = try XCTUnwrap(updated.credentialRef)
        XCTAssertEqual(try credentialStore.password(for: credentialRef), "fresh-secret")
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileIgnoresUnknownProfileId() throws {
        let model = NaruRemoteAppModel()
        let unknown = try ConnectionProfile(displayName: "Ghost", host: "ghost.tailnet.ts.net")

        model.editProfile(unknown, password: "irrelevant")

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.profilePersistenceError)
    }

    // MARK: - deleteProfile

    func testDeleteProfileClearsSessionAndSelectionWhenActiveProfileWasRemoved() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(profile)

        XCTAssertEqual(model.snapshot.selectedProfileID, profile.id)
        XCTAssertEqual(model.snapshot.session?.profileID, profile.id)

        model.deleteProfile(id: profile.id)

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.snapshot.selectedProfileID)
        XCTAssertNil(model.snapshot.session)
        XCTAssertNil(model.snapshot.composeDraft)
        XCTAssertNil(model.snapshot.diagnosticRun)
        XCTAssertNil(model.snapshot.latestInjectionAttempt)
        XCTAssertNil(model.snapshot.pipWatchSession)
        XCTAssertNil(model.profilePersistenceError)
        XCTAssertTrue(try ConnectionProfileStore(persistence: persistence).allProfiles().isEmpty)
    }

    func testDeleteProfileRemovesKeychainCredential() throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(profile, password: "secret")
        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(saved.credentialRef)
        XCTAssertEqual(try credentialStore.password(for: credentialRef), "secret")

        model.deleteProfile(id: saved.id)

        XCTAssertNil(try credentialStore.password(for: credentialRef))
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileLeavesSelectionWhenInactiveProfileIsRemoved() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let active = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let bystander = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        model.addProfile(active)
        model.addProfile(bystander)
        // The model selects the most recently added profile by
        // default (`addProfile` sets `selectedProfileID`).  Re-pin
        // selection to `active` so the test reflects the
        // inactive-deletion scenario.
        model.selectProfile(id: active.id)
        let activeSessionID = model.snapshot.session?.id

        model.deleteProfile(id: bystander.id)

        XCTAssertEqual(model.snapshot.profiles.count, 1)
        XCTAssertEqual(model.snapshot.profiles.first?.id, active.id)
        XCTAssertEqual(model.snapshot.selectedProfileID, active.id)
        // Session for the still-selected profile is preserved.
        XCTAssertEqual(model.snapshot.session?.id, activeSessionID)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileWithUnknownIdIsNoop() throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let active = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(active)
        let activeSessionID = model.snapshot.session?.id

        model.deleteProfile(id: UUID())

        XCTAssertEqual(model.snapshot.profiles, [active])
        XCTAssertEqual(model.snapshot.selectedProfileID, active.id)
        XCTAssertEqual(model.snapshot.session?.id, activeSessionID)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileWithoutCredentialDoesNotErrorWhenKeychainEntryIsMissing() throws {
        // Constitution §IV: keychain delete-of-missing must be
        // treated as success.  A profile that never had a saved
        // password should still delete cleanly without raising the
        // user-facing error string.
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        model.addProfile(profile) // no password

        model.deleteProfile(id: profile.id)

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.profilePersistenceError)
    }

    // MARK: - Diagnostic export safe-catalog invariance

    func testDiagnosticExportSafeCatalogStaysOpaqueAfterEditAndDeleteEvents() throws {
        let model = NaruRemoteAppModel(
            credentialStore: InMemoryConnectionCredentialStore()
        )
        let profile = try ConnectionProfile(
            displayName: "Desk hunter2",
            host: "desk-hunter2.tailnet.ts.net"
        )
        model.addProfile(profile, password: "hunter2")
        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let renamed = try ConnectionProfile(
            id: saved.id,
            displayName: "Desk hunter2 renamed 한글",
            host: saved.host,
            credentialRef: saved.credentialRef
        )
        model.editProfile(renamed, password: "another-secret")
        model.deleteProfile(id: saved.id)

        // Build a representative diagnostic run.  The export must
        // not surface user-entered display names, hosts, or
        // passwords — only the fixed safe-detail catalog.
        let stage = DiagnosticStageResult(
            stage: .authentication,
            status: .failed,
            safeTitle: "Authentication failed",
            safeDetail: "Rejected hunter2 against \(renamed.host)",
            nextAction: "Retry hunter2"
        )
        let run = ConnectionDiagnosticRun(profileID: renamed.id, stages: [stage])

        let summary = DiagnosticExport(run: run, detailLevel: .stageSummary).summary

        XCTAssertFalse(summary.contains("hunter2"))
        XCTAssertFalse(summary.contains("한글"))
        XCTAssertFalse(summary.contains("Retry"))
        XCTAssertFalse(summary.contains("desk-hunter2"))
        XCTAssertTrue(summary.contains("Authentication stage."))
    }
}
