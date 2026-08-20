#if canImport(Network)
import Network
#endif
import Foundation
import NaruRemoteCore

/// Lock-guarded `NWPath` snapshot for stream-cap decisions.
///
/// Stores only `isExpensive` / `isConstrained` (constitution §IV). The
/// shared instance is started once lazily; before the first path update
/// `current` is `.unknown`. Tests drive `noteUpdate` with synthetic Bool
/// pairs and must not start a live `NWPathMonitor`. Public so the app
/// model's initializer default can name the live snapshot.
public final class NetworkPathConditionsMonitor: @unchecked Sendable {
    public static let shared: NetworkPathConditionsMonitor = {
        let monitor = NetworkPathConditionsMonitor()
        monitor.start()
        return monitor
    }()

    private let lock = NSLock()
    private var snapshot = NetworkPathConditions.unknown
    private var didStart = false

    #if canImport(Network)
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "naru.network-path-conditions",
        qos: .utility
    )
    #endif

    /// Unstarted instance. Production uses `shared`, which starts the
    /// live `NWPathMonitor` once. Tests construct this and drive
    /// `noteUpdate` without a live path.
    init() {}

    public var current: NetworkPathConditions {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    /// Live-handler sink and unit-test seam. Replaces the snapshot with
    /// the two Bools only; no path details are retained.
    func noteUpdate(isExpensive: Bool, isConstrained: Bool) {
        lock.lock()
        snapshot = NetworkPathConditions(
            isExpensive: isExpensive,
            isConstrained: isConstrained
        )
        lock.unlock()
    }

    private func start() {
        lock.lock()
        let alreadyStarted = didStart
        if !alreadyStarted {
            didStart = true
        }
        lock.unlock()
        guard !alreadyStarted else {
            return
        }

        #if canImport(Network)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.noteUpdate(
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
        }
        pathMonitor.start(queue: queue)
        #endif
    }
}
