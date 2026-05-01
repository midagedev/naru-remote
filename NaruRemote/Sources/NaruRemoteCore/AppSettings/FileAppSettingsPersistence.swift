import Foundation

/// File-backed implementation of `AppSettingsPersisting`.  Writes
/// JSON to a single document (in production: `Application
/// Support/NaruRemote/settings.json`).  Mirrors the
/// `FileConnectionProfilePersistence` style for path discovery,
/// missing-file handling, atomic write, and a pretty/sorted
/// encoder so `settings.json` diffs stay reviewable — but is a
/// `struct` with no stored mutable state so it can be `Sendable`
/// without `@unchecked Sendable`.
///
/// Encoder and decoder are constructed per-call rather than
/// cached.  The cost is negligible at the cadence of settings
/// load/save (init + occasional dismiss), and avoids the
/// non-`Sendable` `JSONEncoder`/`JSONDecoder` instance state that
/// forces `@unchecked Sendable` elsewhere.  Concurrent `save`
/// calls are serialized through `data.write(options: [.atomic])`
/// at the filesystem layer; if a higher-level store needs
/// stronger ordering it should hold its own lock above this
/// boundary (the way `ConnectionProfileStore` does).
public struct FileAppSettingsPersistence: AppSettingsPersisting, Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return AppSettings()
        }

        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }
}
