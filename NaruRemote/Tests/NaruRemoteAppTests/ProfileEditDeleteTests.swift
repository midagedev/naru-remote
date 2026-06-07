import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class ProfileEditDeleteTests: XCTestCase {
    // MARK: - editProfile

    func testEditProfileReplacesFieldsAndPersistsThroughStore() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let original = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            port: 5900,
            allowsPiPWatch: true
        )
        await model.addProfile(original)

        let edited = try ConnectionProfile(
            id: original.id,
            displayName: "Desk Renamed",
            host: "renamed.tailnet.ts.net",
            port: 5905,
            allowsPiPWatch: false
        )

        await model.editProfile(edited, password: nil)

        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let stored = await reloaded.allProfiles()
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

    func testEditProfilePreservesExistingHelperVideoConfiguration() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let helperVideo = HelperVideoConnectionConfiguration(
            isEnabled: true,
            pairingSecretRef: "helper-video-token:desk",
            pairingFingerprint: "sha256:helper-video"
        )
        let original = try ConnectionProfile(
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: helperVideo
        )
        let model = NaruRemoteAppModel(profileStore: store)
        await model.addProfile(original)

        let editedFromProfileEditor = try ConnectionProfile(
            id: original.id,
            displayName: "Desk Renamed",
            host: "renamed.tailnet.ts.net",
            port: 5905
        )

        await model.editProfile(editedFromProfileEditor, password: nil)

        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let storedOrNil = await reloaded.profile(id: original.id)
        let stored = try XCTUnwrap(storedOrNil)
        XCTAssertEqual(stored.helperVideo, helperVideo)
        XCTAssertEqual(model.snapshot.selectedProfile?.helperVideo, helperVideo)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[original.id]?.isEnabled, true)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[original.id]?.availability, .checking)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testAddProfileSavesHelperVideoPairingSecretAndPublishesCheckingState() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let profile = try ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video"
            )
        )

        await model.addProfile(profile, helperVideoPairingSecret: "helper-video-secret")

        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let secretRef = try XCTUnwrap(saved.helperVideo?.pairingSecretRef)
        let storedSecret = try await credentialStore.password(for: secretRef)
        XCTAssertEqual(secretRef, "helper-video-token:\(profileID.uuidString)")
        XCTAssertEqual(storedSecret, "helper-video-secret")
        XCTAssertEqual(saved.helperVideo?.isEnabled, true)
        XCTAssertEqual(saved.helperVideo?.isRevoked, false)
        XCTAssertEqual(saved.helperVideo?.pairingFingerprint, "sha256:helper-video")
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profileID]?.isEnabled, true)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profileID]?.availability, .checking)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileDisablesHelperVideoButKeepsSavedToken() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profileID = try XCTUnwrap(UUID(uuidString: "22222222-3333-4444-5555-666666666666"))
        let secretRef = "helper-video-token:\(profileID.uuidString)"
        let original = try ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: secretRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        await model.addProfile(original, helperVideoPairingSecret: "helper-video-secret")

        let disabledFromProfileEditor = try ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: false,
                isRevoked: false,
                pairingSecretRef: secretRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )

        await model.editProfile(
            disabledFromProfileEditor,
            password: nil,
            helperVideoPairingSecret: nil
        )

        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let storedSecret = try await credentialStore.password(for: secretRef)
        XCTAssertEqual(saved.helperVideo?.isEnabled, false)
        XCTAssertEqual(saved.helperVideo?.isRevoked, false)
        XCTAssertEqual(saved.helperVideo?.pairingSecretRef, secretRef)
        XCTAssertEqual(storedSecret, "helper-video-secret")
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profileID]?.isEnabled, false)
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profileID]?.availability, .disabled)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileReplacesHelperVideoPairingSecret() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profileID = try XCTUnwrap(UUID(uuidString: "33333333-4444-5555-6666-777777777777"))
        let secretRef = "helper-video-token:\(profileID.uuidString)"
        let original = try ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: secretRef,
                pairingFingerprint: "sha256:old-helper-video"
            )
        )
        await model.addProfile(original, helperVideoPairingSecret: "old-helper-video-secret")

        let edited = try ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                isRevoked: false,
                pairingSecretRef: secretRef,
                pairingFingerprint: "sha256:new-helper-video"
            )
        )

        await model.editProfile(
            edited,
            password: nil,
            helperVideoPairingSecret: "new-helper-video-secret"
        )

        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let storedSecret = try await credentialStore.password(for: secretRef)
        XCTAssertEqual(saved.helperVideo?.isEnabled, true)
        XCTAssertEqual(saved.helperVideo?.pairingSecretRef, secretRef)
        XCTAssertEqual(saved.helperVideo?.pairingFingerprint, "sha256:new-helper-video")
        XCTAssertEqual(storedSecret, "new-helper-video-secret")
        XCTAssertEqual(model.snapshot.helperVideoProfileState[profileID]?.availability, .checking)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithNilPasswordPreservesExistingCredential() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(original, password: "secret")
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)

        let edited = try ConnectionProfile(
            id: savedProfile.id,
            displayName: "Desk Renamed",
            host: savedProfile.host,
            credentialRef: credentialRef
        )

        await model.editProfile(edited, password: nil)

        let storedPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertEqual(storedPassword, "secret")
        XCTAssertEqual(model.snapshot.profiles.first?.credentialRef, credentialRef)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithEmptyPasswordRemovesExistingCredential() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(original, password: "secret")
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)

        let edited = try ConnectionProfile(
            id: savedProfile.id,
            displayName: savedProfile.displayName,
            host: savedProfile.host,
            credentialRef: credentialRef
        )

        await model.editProfile(edited, password: "")

        let storedPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertNil(storedPassword)
        XCTAssertNil(model.snapshot.profiles.first?.credentialRef)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithNonEmptyPasswordUpdatesCredential() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(original, password: "old-secret")
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(savedProfile.credentialRef)

        let edited = try ConnectionProfile(
            id: savedProfile.id,
            displayName: savedProfile.displayName,
            host: savedProfile.host,
            credentialRef: credentialRef
        )

        await model.editProfile(edited, password: "new-secret")

        let storedPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertEqual(storedPassword, "new-secret")
        XCTAssertEqual(model.snapshot.profiles.first?.credentialRef, credentialRef)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileWithPasswordOnProfileMissingCredentialRefAddsOne() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let original = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(original)
        let savedProfile = try XCTUnwrap(model.snapshot.selectedProfile)
        XCTAssertNil(savedProfile.credentialRef)

        await model.editProfile(savedProfile, password: "fresh-secret")

        let updated = try XCTUnwrap(model.snapshot.profiles.first)
        let credentialRef = try XCTUnwrap(updated.credentialRef)
        let storedPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertEqual(storedPassword, "fresh-secret")
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileIgnoresUnknownProfileId() async throws {
        let model = NaruRemoteAppModel()
        let unknown = try ConnectionProfile(displayName: "Ghost", host: "ghost.tailnet.ts.net")

        await model.editProfile(unknown, password: "irrelevant")

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.profilePersistenceError)
    }

    // MARK: - deleteProfile

    func testDeleteProfileClearsSessionAndSelectionWhenActiveProfileWasRemoved() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(profile)

        XCTAssertEqual(model.snapshot.selectedProfileID, profile.id)
        XCTAssertEqual(model.snapshot.session?.profileID, profile.id)

        await model.deleteProfile(id: profile.id)

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.snapshot.selectedProfileID)
        XCTAssertNil(model.snapshot.session)
        XCTAssertNil(model.snapshot.composeDraft)
        XCTAssertNil(model.snapshot.diagnosticRun)
        XCTAssertNil(model.snapshot.latestInjectionAttempt)
        XCTAssertNil(model.snapshot.pipWatchSession)
        XCTAssertNil(model.profilePersistenceError)
        let reloaded = try await ConnectionProfileStore(persistence: persistence)
        let allProfiles = await reloaded.allProfiles()
        XCTAssertTrue(allProfiles.isEmpty)
    }

    func testDeleteProfileRemovesKeychainCredential() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(profile, password: "secret")
        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let credentialRef = try XCTUnwrap(saved.credentialRef)
        let initialPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertEqual(initialPassword, "secret")

        await model.deleteProfile(id: saved.id)

        let storedPassword = try await credentialStore.password(for: credentialRef)
        XCTAssertNil(storedPassword)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileRemovesHelperVideoPairingSecret() async throws {
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profileID = try XCTUnwrap(UUID(uuidString: "44444444-5555-6666-7777-888888888888"))
        let profile = try ConnectionProfile(
            id: profileID,
            displayName: "Desk",
            host: "desk.tailnet.ts.net",
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video"
            )
        )

        await model.addProfile(profile, helperVideoPairingSecret: "helper-video-secret")
        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let secretRef = try XCTUnwrap(saved.helperVideo?.pairingSecretRef)
        let initialSecret = try await credentialStore.password(for: secretRef)
        XCTAssertEqual(secretRef, "helper-video-token:\(profileID.uuidString)")
        XCTAssertEqual(initialSecret, "helper-video-secret")

        await model.deleteProfile(id: saved.id)

        let storedSecret = try await credentialStore.password(for: secretRef)
        XCTAssertNil(storedSecret)
        XCTAssertNil(model.snapshot.helperVideoProfileState[saved.id])
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileLeavesSelectionWhenInactiveProfileIsRemoved() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let active = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let bystander = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        await model.addProfile(active)
        await model.addProfile(bystander)
        // The model selects the most recently added profile by
        // default (`addProfile` sets `selectedProfileID`).  Re-pin
        // selection to `active` so the test reflects the
        // inactive-deletion scenario.
        model.selectProfile(id: active.id)
        let activeSessionID = model.snapshot.session?.id

        await model.deleteProfile(id: bystander.id)

        XCTAssertEqual(model.snapshot.profiles.count, 1)
        XCTAssertEqual(model.snapshot.profiles.first?.id, active.id)
        XCTAssertEqual(model.snapshot.selectedProfileID, active.id)
        // Session for the still-selected profile is preserved.
        XCTAssertEqual(model.snapshot.session?.id, activeSessionID)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileWithUnknownIdIsNoop() async throws {
        let persistence = InMemoryConnectionProfilePersistence()
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let active = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(active)
        let activeSessionID = model.snapshot.session?.id

        await model.deleteProfile(id: UUID())

        XCTAssertEqual(model.snapshot.profiles, [active])
        XCTAssertEqual(model.snapshot.selectedProfileID, active.id)
        XCTAssertEqual(model.snapshot.session?.id, activeSessionID)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteProfileWithoutCredentialDoesNotErrorWhenKeychainEntryIsMissing() async throws {
        // Constitution §IV: keychain delete-of-missing must be
        // treated as success.  A profile that never had a saved
        // password should still delete cleanly without raising the
        // user-facing error string.
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(credentialStore: credentialStore)
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        await model.addProfile(profile) // no password

        await model.deleteProfile(id: profile.id)

        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.profilePersistenceError)
    }

    // MARK: - Diagnostic export safe-catalog invariance

    func testDiagnosticExportSafeCatalogStaysOpaqueAfterEditAndDeleteEvents() async throws {
        let model = NaruRemoteAppModel(
            credentialStore: InMemoryConnectionCredentialStore()
        )
        let profile = try ConnectionProfile(
            displayName: "Desk hunter2",
            host: "desk-hunter2.tailnet.ts.net"
        )
        await model.addProfile(profile, password: "hunter2")
        let saved = try XCTUnwrap(model.snapshot.selectedProfile)
        let renamed = try ConnectionProfile(
            id: saved.id,
            displayName: "Desk hunter2 renamed 한글",
            host: saved.host,
            credentialRef: saved.credentialRef
        )
        await model.editProfile(renamed, password: "another-secret")
        await model.deleteProfile(id: saved.id)

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
