import Foundation

public protocol ConnectionProfilePersisting: Sendable {
    func loadProfiles() async throws -> [ConnectionProfile]
    func saveProfiles(_ profiles: [ConnectionProfile]) async throws
}

public actor InMemoryConnectionProfilePersistence: ConnectionProfilePersisting {
    private var profiles: [ConnectionProfile]

    public init(profiles: [ConnectionProfile] = []) {
        self.profiles = profiles
    }

    public func loadProfiles() throws -> [ConnectionProfile] {
        profiles
    }

    public func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        self.profiles = profiles
    }
}

public actor FileConnectionProfilePersistence: ConnectionProfilePersisting {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadProfiles() throws -> [ConnectionProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try decoder.decode([ConnectionProfile].self, from: data)
    }

    public func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public actor ConnectionProfileStore {
    private let persistence: ConnectionProfilePersisting
    private var profiles: [ConnectionProfile]
    /// Serializes mutating operations against actor reentrancy.  An
    /// `actor` only guarantees that one body runs to its next `await`
    /// — across the `await persistence.saveProfiles(...)` suspension
    /// point another `save`/`deleteProfile` can interleave and read a
    /// stale `profiles` snapshot, which would lose writes under
    /// concurrent calls.  Chaining mutating bodies through this
    /// trailing `Task` makes the read-modify-write
    /// (including the persistence write) sequential without
    /// re-introducing `NSLock`.
    private var pendingMutation: Task<Void, Never>?

    public init(persistence: ConnectionProfilePersisting = InMemoryConnectionProfilePersistence()) async throws {
        self.persistence = persistence
        self.profiles = try await persistence.loadProfiles()
    }

    public func allProfiles() -> [ConnectionProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.favorite != rhs.favorite {
                return lhs.favorite && !rhs.favorite
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    @discardableResult
    public func save(_ profile: ConnectionProfile) async throws -> ConnectionProfile {
        let slot = enqueueMutationSlot()
        defer { slot.complete() }
        await slot.predecessor?.value

        var updatedProfiles = profiles
        if let index = updatedProfiles.firstIndex(where: { $0.id == profile.id }) {
            updatedProfiles[index] = profile
        } else {
            updatedProfiles.append(profile)
        }

        try await persistence.saveProfiles(updatedProfiles)
        profiles = updatedProfiles
        return profile
    }

    public func deleteProfile(id: ConnectionProfile.ID) async throws -> ConnectionProfile? {
        let slot = enqueueMutationSlot()
        defer { slot.complete() }
        await slot.predecessor?.value

        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        var updatedProfiles = profiles
        let removed = updatedProfiles.remove(at: index)
        try await persistence.saveProfiles(updatedProfiles)
        profiles = updatedProfiles
        return removed
    }

    public func profile(id: ConnectionProfile.ID) -> ConnectionProfile? {
        profiles.first { $0.id == id }
    }

    /// Atomically capture the current tail and install a new tail in
    /// one synchronous step on the actor.  Concurrent mutating
    /// callers therefore form a strict queue: each one waits on the
    /// returned `predecessor` before reading mutable state, then
    /// signals its own slot via `complete()` once the read-modify-
    /// write (including any `await persistence.saveProfiles`) is
    /// done.  See `pendingMutation` for rationale.
    private func enqueueMutationSlot() -> MutationSlot {
        let predecessor = pendingMutation
        let slot = MutationSlot(predecessor: predecessor)
        pendingMutation = slot.completion
        return slot
    }
}

/// Owner-side handle for one slot in `ConnectionProfileStore`'s
/// serialized mutation chain.  `predecessor.value` blocks until every
/// earlier slot has called `complete()`; `complete()` resolves this
/// slot so the next caller can proceed.
private final class MutationSlot: Sendable {
    let predecessor: Task<Void, Never>?
    let completion: Task<Void, Never>
    private let resume: @Sendable () -> Void

    init(predecessor: Task<Void, Never>?) {
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.predecessor = predecessor
        self.resume = {
            stream.continuation.yield()
            stream.continuation.finish()
        }
        self.completion = Task {
            for await _ in stream.stream {
                return
            }
        }
    }

    func complete() {
        resume()
    }
}
