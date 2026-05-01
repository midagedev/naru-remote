import Foundation

/// Boundary for loading and saving the app-level `AppSettings`
/// document.  Mirrors `ConnectionProfilePersisting` so the app
/// model can swap in a file-backed implementation in production
/// and an in-memory double in tests.
public protocol AppSettingsPersisting: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

/// In-memory implementation used by tests.  Mirrors the
/// `InMemoryConnectionProfilePersistence` style — `NSLock` plus
/// `@unchecked Sendable` so the same instance can cross actor
/// boundaries safely.
public final class InMemoryAppSettingsPersistence: AppSettingsPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    public func load() throws -> AppSettings {
        lock.withAppSettingsLock {
            settings
        }
    }

    public func save(_ settings: AppSettings) throws {
        lock.withAppSettingsLock {
            self.settings = settings
        }
    }
}

extension NSLock {
    /// Internal lock helper shared by the in-memory and file-backed
    /// `AppSettings` persistence implementations.  Kept fileprivate
    /// in spirit (extension on a Foundation type, but only used in
    /// this subdomain) by being marked `internal`.
    func withAppSettingsLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
