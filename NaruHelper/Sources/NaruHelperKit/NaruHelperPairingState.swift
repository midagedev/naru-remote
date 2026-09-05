import Foundation
import NaruRemoteCore

/// Pairing state persisted on the Mac (spec 040 FR-002): the token the
/// listeners currently accept, and its non-secret fingerprint.
///
/// `NaruHelper --pair` rotates this on every run, so a photographed QR's
/// helper credentials die on the next pairing. Listeners read the file
/// **per connection** (via ``NaruHelperPairingStateStore/currentSecret``),
/// never a launch-time snapshot — rotation takes effect without a
/// listener restart and a superseded token is refused from its next
/// handshake.
public struct NaruHelperPairingState: Codable, Equatable, Sendable {
    public var token: String
    public var fingerprint: String
    public var createdAt: Date

    public init(token: String, fingerprint: String, createdAt: Date = Date()) {
        self.token = token
        self.fingerprint = fingerprint
        self.createdAt = createdAt
    }
}

public enum NaruHelperPairingStateError: Error, Equatable, Sendable {
    /// No state file — the Mac has never run `--pair`.
    case notPaired
    /// The file exists but does not decode; re-running `--pair` repairs it.
    case malformedState
    case unreadable
    case unwritable
}

/// File-backed pairing state with rotation. The path is injectable so
/// tests never touch `~/.naru`; the default is the production location.
public final class NaruHelperPairingStateStore: @unchecked Sendable {
    /// Backing file location. Public read-only for tests asserting the
    /// 0600 permission — the file path is not secret, its contents are.
    public private(set) var fileURL: URL
    private let lock = NSLock()
    private var cache: NaruHelperPairingState?

    public static func defaultFileURL() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".naru/helper-pairing-state.json")
    }

    public init(fileURL: URL = NaruHelperPairingStateStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// Loads (and caches) the current state; throws `notPaired` when no
    /// state exists yet.
    public func load() throws -> NaruHelperPairingState {
        try lock.withLock {
            if let cache {
                return cache
            }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw NaruHelperPairingStateError.notPaired
            }
            do {
                let data = try Data(contentsOf: fileURL)
                let state = try JSONDecoder().decode(NaruHelperPairingState.self, from: data)
                cache = state
                return state
            } catch let error as NaruHelperPairingStateError {
                throw error
            } catch {
                throw NaruHelperPairingStateError.malformedState
            }
        }
    }

    /// Mints a fresh 256-bit token, persists it (0600), and returns the
    /// new state. The previous token is implicitly superseded — callers
    /// that cached it (an old QR, a stale phone credential) are refused
    /// on their next handshake.
    @discardableResult
    public func rotate() throws -> NaruHelperPairingState {
        let token = HelperPairingSecret.generate()
        let state = NaruHelperPairingState(token: token, fingerprint: HelperPairingSecret.fingerprint(for: token))
        try persist(state)
        return state
    }

    /// Persists an explicit state (used by `--pair` tests and future
    /// per-device token rounds).
    public func persist(_ state: NaruHelperPairingState) throws {
        try lock.withLock {
            let directory = fileURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(state)
                try data.write(to: fileURL, options: [.atomic])
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: fileURL.path
                )
                cache = state
            } catch {
                throw NaruHelperPairingStateError.unwritable
            }
        }
    }

    /// Re-reads the file, bypassing the cache, so a rotation performed by
    /// another process (`--pair` while a listener runs) is observed.
    ///
    /// Spec 041 FR-007: an **absent** file means not paired — the answer is
    /// `nil` and the cache is dropped, so deleting the file revokes every
    /// holder of the old token from its next handshake. Only a *transient*
    /// failure (present but unreadable or undecodable) keeps the last known
    /// state rather than locking every client out.
    public func currentSecret() -> String? {
        lock.withLock {
            switch readStateFile() {
            case .state(let state):
                return state.token
            case .absent:
                return nil
            case .transientFailure:
                return cache?.token
            }
        }
    }

    public func currentFingerprint() -> String? {
        lock.withLock {
            switch readStateFile() {
            case .state(let state):
                return state.fingerprint
            case .absent:
                return nil
            case .transientFailure:
                return cache?.fingerprint
            }
        }
    }

    /// Revocation (spec 041 FR-007): removes the state file and drops the
    /// cache, so `currentSecret()`/`currentFingerprint()` answer `nil` and
    /// the listeners refuse every subsequent handshake. Absent file is not
    /// an error — revoking an unpaired Mac is a no-op.
    public func revoke() throws {
        try lock.withLock {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                throw NaruHelperPairingStateError.unreadable
            }
            cache = nil
        }
    }

    /// Classification of one file read for the per-connection path.
    /// Caller must hold `lock`.
    private func readStateFile() -> StateFileRead {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let nsError = error as NSError
            let isAbsent = (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError)
                || (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT)
            return isAbsent ? .absent : .transientFailure
        }
        guard let state = try? JSONDecoder().decode(NaruHelperPairingState.self, from: data) else {
            return .transientFailure
        }
        // Re-normalize on load: the fingerprint is derived from the token
        // (``HelperPairingSecret/fingerprint(for:)``), so a mismatch is a
        // corrupted or hand-edited file — treated as transient, the cache
        // keeps serving the last known-good state.
        guard !state.token.isEmpty,
              state.fingerprint == HelperPairingSecret.fingerprint(for: state.token)
        else {
            return .transientFailure
        }
        cache = state
        return .state(state)
    }

    private enum StateFileRead {
        case state(NaruHelperPairingState)
        case absent
        case transientFailure
    }
}
