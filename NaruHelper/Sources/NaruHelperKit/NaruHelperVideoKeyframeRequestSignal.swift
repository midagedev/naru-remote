import Foundation

/// Per-stream coalescing latch for client `requestKeyframe` messages.
///
/// Multiple `request()` calls before the next encoded frame collapse into a
/// single `consumePending() == true`. The encode loop owns consumption.
public final class NaruHelperVideoKeyframeRequestSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    public init() {}

    public func request() {
        lock.lock()
        pending = true
        lock.unlock()
    }

    public func consumePending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasPending = pending
        pending = false
        return wasPending
    }
}
