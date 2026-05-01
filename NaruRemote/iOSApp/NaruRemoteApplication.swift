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
        let settingsPersistence = FileAppSettingsPersistence(fileURL: settingsStoreURL())
        do {
            let persistence = FileConnectionProfilePersistence(fileURL: profileStoreURL())
            let store = try ConnectionProfileStore(persistence: persistence)
            return NaruRemoteAppModel(
                profileStore: store,
                credentialStore: KeychainConnectionCredentialStore(),
                settingsPersistence: settingsPersistence,
                pipWatchController: PiPWatchPictureInPictureController(),
                localClipboardWriter: UIPasteboardClipboardWriter()
            )
        } catch {
            return NaruRemoteAppModel(
                credentialStore: KeychainConnectionCredentialStore(),
                settingsPersistence: settingsPersistence,
                pipWatchController: PiPWatchPictureInPictureController(),
                localClipboardWriter: UIPasteboardClipboardWriter()
            )
        }
    }

    private static func profileStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NARU_PROFILE_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        return applicationSupportURL().appendingPathComponent("profiles.json")
    }

    private static func settingsStoreURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["NARU_SETTINGS_STORE_URL"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }

        return applicationSupportURL().appendingPathComponent("settings.json")
    }

    private static func applicationSupportURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL.appendingPathComponent("NaruRemote", isDirectory: true)
    }
}
