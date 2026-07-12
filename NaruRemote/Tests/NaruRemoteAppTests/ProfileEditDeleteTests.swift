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
            host: savedProfile.host
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
            host: savedProfile.host
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

    // MARK: - Persistence completion + retry

    func testAddProfileFailureReturnsFixedResultAndDoesNotPublishProfile() async throws {
        let persistence = RetryableConnectionProfilePersistence(shouldFail: true)
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        let profile = try ConnectionProfile(
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net"
        )

        let result = await model.addProfile(profile)

        XCTAssertEqual(result, .failed(.profileSave))
        XCTAssertEqual(model.profilePersistenceError, ProfilePersistenceFailure.profileSave.safeMessage)
        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.snapshot.selectedProfileID)

        await persistence.setShouldFail(false)
        let retryResult = await model.addProfile(profile)

        XCTAssertEqual(retryResult, .succeeded)
        XCTAssertEqual(model.snapshot.profiles, [profile])
        XCTAssertEqual(model.snapshot.selectedProfileID, profile.id)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testAddProfileFailureRollsBackAllNewCredentialEntries() async throws {
        let profileID = try XCTUnwrap(
            UUID(uuidString: "77777777-8888-9999-AAAA-BBBBBBBBBBBB")
        )
        let profile = try ConnectionProfile(
            id: profileID,
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net",
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = RetryableConnectionProfilePersistence(shouldFail: true)
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore()
        let model = NaruRemoteAppModel(
            profileStore: store,
            credentialStore: credentialStore
        )

        let result = await model.addProfile(
            profile,
            password: "vnc-secret",
            helperPairingSecret: "helper-text-secret",
            helperVideoPairingSecret: "helper-video-secret"
        )

        let vncPassword = try await credentialStore.password(
            for: "vnc-password:\(profileID.uuidString)"
        )
        let helperTextSecret = try await credentialStore.password(
            for: "helper-token:\(profileID.uuidString)"
        )
        let helperVideoSecret = try await credentialStore.password(
            for: "helper-video-token:\(profileID.uuidString)"
        )
        XCTAssertEqual(result, .failed(.profileSave))
        XCTAssertNil(vncPassword)
        XCTAssertNil(helperTextSecret)
        XCTAssertNil(helperVideoSecret)
        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.snapshot.selectedProfileID)
    }

    func testEditProfileFailureKeepsPersistedAndPublishedProfileUntilRetry() async throws {
        let original = try ConnectionProfile(
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net"
        )
        let persistence = RetryableConnectionProfilePersistence(
            profiles: [original],
            shouldFail: true
        )
        let store = try await ConnectionProfileStore(persistence: persistence)
        let model = NaruRemoteAppModel(profileStore: store)
        await model.loadStoredProfiles()
        let edited = try ConnectionProfile(
            id: original.id,
            displayName: "Renamed Desk",
            host: original.host
        )

        let result = await model.editProfile(edited, password: nil)
        let storedAfterFailure = await store.profile(id: original.id)

        XCTAssertEqual(result, .failed(.profileSave))
        XCTAssertEqual(model.snapshot.profiles, [original])
        XCTAssertEqual(storedAfterFailure, original)

        await persistence.setShouldFail(false)
        let retryResult = await model.editProfile(edited, password: nil)
        let storedAfterRetry = await store.profile(id: original.id)

        XCTAssertEqual(retryResult, .succeeded)
        XCTAssertEqual(model.snapshot.profiles, [edited])
        XCTAssertEqual(storedAfterRetry, edited)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testEditProfileFailureRestoresReplacedCredentials() async throws {
        let passwordRef = "vnc-password:private-desk"
        let helperTextRef = "helper-token:private-desk"
        let helperVideoRef = "helper-video-token:private-desk"
        let original = try ConnectionProfile(
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net",
            credentialRef: passwordRef,
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperTextRef,
                pairingFingerprint: "sha256:old-helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoRef,
                pairingFingerprint: "sha256:old-helper-video"
            )
        )
        let persistence = RetryableConnectionProfilePersistence(
            profiles: [original],
            shouldFail: true
        )
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore(
            passwords: [
                passwordRef: "old-vnc-secret",
                helperTextRef: "old-helper-text-secret",
                helperVideoRef: "old-helper-video-secret"
            ]
        )
        let model = NaruRemoteAppModel(
            profileStore: store,
            credentialStore: credentialStore
        )
        await model.loadStoredProfiles()
        let edited = try ConnectionProfile(
            id: original.id,
            displayName: "Renamed Desk",
            host: original.host,
            credentialRef: passwordRef,
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperTextRef,
                pairingFingerprint: "sha256:new-helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoRef,
                pairingFingerprint: "sha256:new-helper-video"
            )
        )

        let result = await model.editProfile(
            edited,
            password: "new-vnc-secret",
            helperPairingSecret: "new-helper-text-secret",
            helperVideoPairingSecret: "new-helper-video-secret"
        )

        let vncPassword = try await credentialStore.password(for: passwordRef)
        let helperTextSecret = try await credentialStore.password(for: helperTextRef)
        let helperVideoSecret = try await credentialStore.password(for: helperVideoRef)
        let persistedProfile = await store.profile(id: original.id)
        XCTAssertEqual(result, .failed(.profileSave))
        XCTAssertEqual(vncPassword, "old-vnc-secret")
        XCTAssertEqual(helperTextSecret, "old-helper-text-secret")
        XCTAssertEqual(helperVideoSecret, "old-helper-video-secret")
        XCTAssertEqual(model.snapshot.profiles, [original])
        XCTAssertEqual(persistedProfile, original)
    }

    func testEditProfileFailureRestoresExplicitlyRemovedCredentials() async throws {
        let passwordRef = "vnc-password:private-desk"
        let helperTextRef = "helper-token:private-desk"
        let helperVideoRef = "helper-video-token:private-desk"
        let original = try ConnectionProfile(
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net",
            credentialRef: passwordRef,
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperTextRef,
                pairingFingerprint: "sha256:helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = RetryableConnectionProfilePersistence(
            profiles: [original],
            shouldFail: true
        )
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore(
            passwords: [
                passwordRef: "old-vnc-secret",
                helperTextRef: "old-helper-text-secret",
                helperVideoRef: "old-helper-video-secret"
            ]
        )
        let model = NaruRemoteAppModel(
            profileStore: store,
            credentialStore: credentialStore
        )
        await model.loadStoredProfiles()
        let edited = try ConnectionProfile(
            id: original.id,
            displayName: original.displayName,
            host: original.host
        )

        let result = await model.editProfile(
            edited,
            password: "",
            helperPairingSecret: "",
            helperVideoPairingSecret: ""
        )

        let vncPassword = try await credentialStore.password(for: passwordRef)
        let helperTextSecret = try await credentialStore.password(for: helperTextRef)
        let helperVideoSecret = try await credentialStore.password(for: helperVideoRef)
        XCTAssertEqual(result, .failed(.profileSave))
        XCTAssertEqual(vncPassword, "old-vnc-secret")
        XCTAssertEqual(helperTextSecret, "old-helper-text-secret")
        XCTAssertEqual(helperVideoSecret, "old-helper-video-secret")
        XCTAssertEqual(model.snapshot.profiles, [original])
    }

    func testDeleteProfileFailureKeepsProfileSessionAndCredentialForRetry() async throws {
        let credentialRef = "vnc-password:private-desk"
        let helperTextRef = "helper-token:private-desk"
        let helperVideoRef = "helper-video-token:private-desk"
        let profile = try ConnectionProfile(
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net",
            credentialRef: credentialRef,
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperTextRef,
                pairingFingerprint: "sha256:helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = RetryableConnectionProfilePersistence(
            profiles: [profile],
            shouldFail: true
        )
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore(
            passwords: [
                credentialRef: "private-secret",
                helperTextRef: "helper-text-secret",
                helperVideoRef: "helper-video-secret"
            ]
        )
        let model = NaruRemoteAppModel(
            profileStore: store,
            credentialStore: credentialStore
        )
        await model.loadStoredProfiles()
        let sessionID = model.snapshot.session?.id

        let result = await model.deleteProfile(id: profile.id)
        let credentialAfterFailure = try await credentialStore.password(for: credentialRef)
        let helperTextAfterFailure = try await credentialStore.password(for: helperTextRef)
        let helperVideoAfterFailure = try await credentialStore.password(for: helperVideoRef)

        XCTAssertEqual(result, .failed(.profileRemoval))
        XCTAssertEqual(model.snapshot.profiles, [profile])
        XCTAssertEqual(model.snapshot.selectedProfileID, profile.id)
        XCTAssertEqual(model.snapshot.session?.id, sessionID)
        XCTAssertEqual(credentialAfterFailure, "private-secret")
        XCTAssertEqual(helperTextAfterFailure, "helper-text-secret")
        XCTAssertEqual(helperVideoAfterFailure, "helper-video-secret")

        await persistence.setShouldFail(false)
        let retryResult = await model.deleteProfile(id: profile.id)
        let credentialAfterRetry = try await credentialStore.password(for: credentialRef)
        let helperTextAfterRetry = try await credentialStore.password(for: helperTextRef)
        let helperVideoAfterRetry = try await credentialStore.password(for: helperVideoRef)

        XCTAssertEqual(retryResult, .succeeded)
        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(model.snapshot.selectedProfileID)
        XCTAssertNil(model.snapshot.session)
        XCTAssertNil(credentialAfterRetry)
        XCTAssertNil(helperTextAfterRetry)
        XCTAssertNil(helperVideoAfterRetry)
        XCTAssertNil(model.profilePersistenceError)
    }

    func testDeleteCredentialFailureRollsBackEarlierDeletesAndKeepsProfile() async throws {
        let passwordRef = "vnc-password:private-desk"
        let helperTextRef = "helper-token:private-desk"
        let helperVideoRef = "helper-video-token:private-desk"
        let profile = try ConnectionProfile(
            displayName: "Private Desk",
            host: "private-desk.tailnet.ts.net",
            credentialRef: passwordRef,
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperTextRef,
                pairingFingerprint: "sha256:helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = InMemoryConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = DeleteFailingCredentialStore(
            passwords: [
                passwordRef: "vnc-secret",
                helperTextRef: "helper-text-secret",
                helperVideoRef: "helper-video-secret"
            ],
            failingDeleteRef: helperTextRef
        )
        let model = NaruRemoteAppModel(
            profileStore: store,
            credentialStore: credentialStore
        )
        await model.loadStoredProfiles()

        let result = await model.deleteProfile(id: profile.id)

        let storedProfile = await store.profile(id: profile.id)
        let vncSecret = await credentialStore.password(for: passwordRef)
        let helperTextSecret = await credentialStore.password(for: helperTextRef)
        let helperVideoSecret = await credentialStore.password(for: helperVideoRef)
        XCTAssertEqual(result, .failed(.helperTokenRemoval))
        XCTAssertEqual(model.snapshot.profiles, [profile])
        XCTAssertEqual(storedProfile, profile)
        XCTAssertEqual(vncSecret, "vnc-secret")
        XCTAssertEqual(helperTextSecret, "helper-text-secret")
        XCTAssertEqual(helperVideoSecret, "helper-video-secret")
    }

    func testConcurrentDeleteFailureThenSuccessLeavesNoOrphanCredentials() async throws {
        let passwordRef = "vnc-password:concurrent-desk"
        let helperTextRef = "helper-token:concurrent-desk"
        let helperVideoRef = "helper-video-token:concurrent-desk"
        let profile = try ConnectionProfile(
            displayName: "Concurrent Desk",
            host: "concurrent-desk.tailnet.ts.net",
            credentialRef: passwordRef,
            helperTextBridge: HelperTextBridgeConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperTextRef,
                pairingFingerprint: "sha256:helper-text"
            ),
            helperVideo: HelperVideoConnectionConfiguration(
                isEnabled: true,
                pairingSecretRef: helperVideoRef,
                pairingFingerprint: "sha256:helper-video"
            )
        )
        let persistence = FailFirstConnectionProfilePersistence(profiles: [profile])
        let store = try await ConnectionProfileStore(persistence: persistence)
        let credentialStore = InMemoryConnectionCredentialStore(passwords: [
            passwordRef: "vnc-secret",
            helperTextRef: "helper-text-secret",
            helperVideoRef: "helper-video-secret"
        ])
        let model = NaruRemoteAppModel(
            profileStore: store,
            credentialStore: credentialStore
        )
        await model.loadStoredProfiles()

        async let first = model.deleteProfile(id: profile.id)
        async let second = model.deleteProfile(id: profile.id)
        let results = await [first, second]
        let storedProfile = await store.profile(id: profile.id)
        let storedPassword = try await credentialStore.password(for: passwordRef)
        let storedHelperText = try await credentialStore.password(for: helperTextRef)
        let storedHelperVideo = try await credentialStore.password(for: helperVideoRef)

        XCTAssertTrue(results.contains(.failed(.profileRemoval)))
        XCTAssertTrue(results.contains(.succeeded))
        XCTAssertTrue(model.snapshot.profiles.isEmpty)
        XCTAssertNil(storedProfile)
        XCTAssertNil(storedPassword)
        XCTAssertNil(storedHelperText)
        XCTAssertNil(storedHelperVideo)
    }

    func testNilProfileStoreRemainsAnExplicitSuccessfulFixturePath() async throws {
        let model = NaruRemoteAppModel()
        let profile = try ConnectionProfile(
            displayName: "Fixture Desk",
            host: "fixture.tailnet.ts.net"
        )

        let addResult = await model.addProfile(profile)
        XCTAssertEqual(addResult, .succeeded)

        let edited = try ConnectionProfile(
            id: profile.id,
            displayName: "Fixture Desk Renamed",
            host: profile.host
        )
        let editResult = await model.editProfile(edited, password: nil)
        XCTAssertEqual(editResult, .succeeded)
        XCTAssertEqual(model.snapshot.selectedProfile, edited)

        let deleteResult = await model.deleteProfile(id: profile.id)
        XCTAssertEqual(deleteResult, .succeeded)
        XCTAssertTrue(model.snapshot.profiles.isEmpty)
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

private struct RetryableConnectionProfilePersistenceError: Error {}

private struct DeleteFailingCredentialStoreError: Error {}

private actor DeleteFailingCredentialStore: ConnectionCredentialStoreProtocol {
    private var passwords: [String: String]
    private let failingDeleteRef: String

    init(passwords: [String: String], failingDeleteRef: String) {
        self.passwords = passwords
        self.failingDeleteRef = failingDeleteRef
    }

    func savePassword(_ password: String, for credentialRef: String) {
        passwords[credentialRef] = password
    }

    func password(for credentialRef: String) -> String? {
        passwords[credentialRef]
    }

    func deletePassword(for credentialRef: String) throws {
        guard credentialRef != failingDeleteRef else {
            throw DeleteFailingCredentialStoreError()
        }
        passwords.removeValue(forKey: credentialRef)
    }
}

private struct FailFirstConnectionProfilePersistenceError: Error {}

private actor FailFirstConnectionProfilePersistence: ConnectionProfilePersisting {
    private var profiles: [ConnectionProfile]
    private var saveCount = 0

    init(profiles: [ConnectionProfile]) {
        self.profiles = profiles
    }

    func loadProfiles() -> [ConnectionProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        saveCount += 1
        guard saveCount > 1 else {
            throw FailFirstConnectionProfilePersistenceError()
        }
        self.profiles = profiles
    }
}

private actor RetryableConnectionProfilePersistence: ConnectionProfilePersisting {
    private var profiles: [ConnectionProfile]
    private var shouldFail: Bool

    init(
        profiles: [ConnectionProfile] = [],
        shouldFail: Bool
    ) {
        self.profiles = profiles
        self.shouldFail = shouldFail
    }

    func loadProfiles() -> [ConnectionProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        guard !shouldFail else {
            throw RetryableConnectionProfilePersistenceError()
        }
        self.profiles = profiles
    }

    func setShouldFail(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }
}
