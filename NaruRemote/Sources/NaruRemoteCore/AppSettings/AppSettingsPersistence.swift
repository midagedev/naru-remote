import Foundation

/// Boundary for loading and saving the app-level `AppSettings`
/// document.  Mirrors `ConnectionProfilePersisting` so the app
/// model can swap in a file-backed implementation in production
/// and an in-memory double in tests.
///
/// Both methods are `async` so concrete implementations can be
/// `actor`-isolated (the `InMemoryAppSettingsPersistence` test
/// double now is) without forcing `@unchecked Sendable` on the
/// caller side.  The file-backed implementation does not need
/// internal state, but its methods are `async` to match the
/// protocol — the actual disk I/O remains synchronous inside the
/// `async` body.
public protocol AppSettingsPersisting: Sendable {
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
}

/// In-memory implementation used by tests.  Migrated from a
/// `final class … @unchecked Sendable` with internal `NSLock` to
/// a Swift `actor` so concurrency is enforced by the language.
/// Mirrors the `InMemoryConnectionProfilePersistence` migration
/// in PR #17.
public actor InMemoryAppSettingsPersistence: AppSettingsPersisting {
    private var settings: AppSettings

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    public func load() throws -> AppSettings {
        settings
    }

    public func save(_ settings: AppSettings) throws {
        self.settings = settings
    }
}
