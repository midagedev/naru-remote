import NaruRemoteApp
import NaruRemoteCore
import SwiftUI

@main
struct NaruRemoteApplication: App {
    @StateObject private var model = Self.makeModel()

    var body: some Scene {
        WindowGroup {
            NaruRemoteAppShell(model: model)
                .accessibilityIdentifier("naru.app.shell")
        }
    }

    private static func makeModel() -> NaruRemoteAppModel {
        do {
            let persistence = FileConnectionProfilePersistence(fileURL: profileStoreURL())
            let store = try ConnectionProfileStore(persistence: persistence)
            return NaruRemoteAppModel(
                profileStore: store,
                credentialStore: KeychainConnectionCredentialStore(),
                pipWatchController: PiPWatchPictureInPictureController()
            )
        } catch {
            return NaruRemoteAppModel(
                credentialStore: KeychainConnectionCredentialStore(),
                pipWatchController: PiPWatchPictureInPictureController()
            )
        }
    }

    private static func profileStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NARU_PROFILE_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupportURL
            .appendingPathComponent("NaruRemote", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }
}
