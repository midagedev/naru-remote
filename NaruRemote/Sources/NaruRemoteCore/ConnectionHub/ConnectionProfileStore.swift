import Foundation

public protocol ConnectionProfilePersisting: Sendable {
    func loadProfiles() throws -> [ConnectionProfile]
    func saveProfiles(_ profiles: [ConnectionProfile]) throws
}

public final class InMemoryConnectionProfilePersistence: ConnectionProfilePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var profiles: [ConnectionProfile]

    public init(profiles: [ConnectionProfile] = []) {
        self.profiles = profiles
    }

    public func loadProfiles() throws -> [ConnectionProfile] {
        lock.withProfileStoreLock {
            profiles
        }
    }

    public func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        lock.withProfileStoreLock {
            self.profiles = profiles
        }
    }
}

public final class FileConnectionProfilePersistence: ConnectionProfilePersisting, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadProfiles() throws -> [ConnectionProfile] {
        try lock.withProfileStoreLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else {
                return []
            }

            return try decoder.decode([ConnectionProfile].self, from: data)
        }
    }

    public func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        try lock.withProfileStoreLock {
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: [.atomic])
        }
    }
}

public final class ConnectionProfileStore: @unchecked Sendable {
    private let lock = NSLock()
    private let persistence: ConnectionProfilePersisting
    private var profiles: [ConnectionProfile]

    public init(persistence: ConnectionProfilePersisting = InMemoryConnectionProfilePersistence()) throws {
        self.persistence = persistence
        self.profiles = try persistence.loadProfiles()
    }

    public func allProfiles() -> [ConnectionProfile] {
        lock.withProfileStoreLock {
            profiles.sorted { lhs, rhs in
                if lhs.favorite != rhs.favorite {
                    return lhs.favorite && !rhs.favorite
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    @discardableResult
    public func save(_ profile: ConnectionProfile) throws -> ConnectionProfile {
        try lock.withProfileStoreLock {
            var updatedProfiles = profiles
            if let index = updatedProfiles.firstIndex(where: { $0.id == profile.id }) {
                updatedProfiles[index] = profile
            } else {
                updatedProfiles.append(profile)
            }

            try persistence.saveProfiles(updatedProfiles)
            profiles = updatedProfiles
            return profile
        }
    }

    public func deleteProfile(id: ConnectionProfile.ID) throws -> ConnectionProfile? {
        try lock.withProfileStoreLock {
            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                return nil
            }

            var updatedProfiles = profiles
            let removed = updatedProfiles.remove(at: index)
            try persistence.saveProfiles(updatedProfiles)
            profiles = updatedProfiles
            return removed
        }
    }

    public func profile(id: ConnectionProfile.ID) -> ConnectionProfile? {
        lock.withProfileStoreLock {
            profiles.first { $0.id == id }
        }
    }
}

private extension NSLock {
    func withProfileStoreLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
