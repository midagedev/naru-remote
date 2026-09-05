import Darwin
import XCTest
import NaruHelperKit
import NaruRemoteCore

/// Spec 041 T-A3: both listeners in one process, with their state surfaced
/// as fixed-catalog values — a taken port reports `.portInUse(port)`, never
/// a silently dead listener (US-2 scenario 3).
///
/// Ports follow the repo idiom (see `NaruHelperVideoListenRuntimeTests`):
/// ephemeral port 0 everywhere except the one deliberately held port, and
/// readiness is polled off the listener's own `port` property — never the
/// production ports 5974/5975.
final class NaruHelperListenerRuntimeTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("naru-listener-runtime-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        super.tearDown()
    }

    private func makeStore() -> NaruHelperPairingStateStore {
        NaruHelperPairingStateStore(
            fileURL: temporaryDirectory.appendingPathComponent("helper-pairing-state.json")
        )
    }

    private func makeRuntime(
        store: NaruHelperPairingStateStore,
        textPort: UInt16,
        videoPort: UInt16
    ) throws -> NaruHelperListenerRuntime {
        try NaruHelperListenerRuntime(
            store: store,
            textPort: textPort,
            videoPort: videoPort,
            capabilityProvider: {
                NaruHelperCapabilityResponse(
                    availability: .reachable,
                    permissionState: NaruHelperPermissionState(
                        accessibility: "granted",
                        inputMonitoring: "notRequired",
                        pasteboardFallback: "available",
                        activeUserSession: "available"
                    ),
                    supportedStrategies: [.pasteboardPasteWithRestore]
                )
            },
            insertHandler: { request in
                NaruHelperInsertTextResponse(
                    requestID: request.requestID,
                    status: .failed,
                    strategyUsed: .unsupported
                )
            },
            videoSourceMode: .syntheticEncoded
        )
    }

    /// Thread-safe sink for the runtime's two-listener callback.
    private final class StateRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [(NaruHelperListenerKind, NaruHelperListenerState)] = []

        func record(_ kind: NaruHelperListenerKind, _ state: NaruHelperListenerState) {
            lock.lock()
            defer { lock.unlock() }
            events.append((kind, state))
        }

        func states(for kind: NaruHelperListenerKind) -> [NaruHelperListenerState] {
            lock.lock()
            defer { lock.unlock() }
            return events.filter { $0.0 == kind }.map(\.1)
        }
    }

    /// Holds one OS-assigned ephemeral port open with a plain BSD socket —
    /// the OS picks the port (`bind(:0)`), so the production ports 5974/5975
    /// are never touched, and an actively listening socket guarantees the
    /// runtime's bind fails with EADDRINUSE. (A raw `NWListener` is not used
    /// here: the no-port init fails with EINVAL inside this test class's
    /// process, while the Kit's own servers bind fine.)
    private final class HeldPort {
        let fileDescriptor: Int32
        let port: UInt16

        init() throws {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw StubError.socketSetupFailed }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = 0 // INADDR_ANY
            address.sin_port = 0
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bound == 0 else {
                close(fd)
                throw StubError.socketSetupFailed
            }
            var nameLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    getsockname(fd, sockaddrPointer, &nameLength)
                }
            }
            guard named == 0, address.sin_port != 0 else {
                close(fd)
                throw StubError.socketSetupFailed
            }
            guard listen(fd, 16) == 0 else {
                close(fd)
                throw StubError.socketSetupFailed
            }
            self.fileDescriptor = fd
            self.port = UInt16(bigEndian: address.sin_port)
        }

        deinit {
            close(fileDescriptor)
        }

        private enum StubError: Error {
            case socketSetupFailed
        }
    }

    private func containsListening(_ states: [NaruHelperListenerState]) -> Bool {
        states.contains { state in
            if case .listening = state { return true }
            return false
        }
    }

    @discardableResult
    private func waitFor(
        _ predicate: @autoclosure () -> Bool,
        timeout seconds: TimeInterval,
        _ message: String
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if predicate() {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        if predicate() {
            return true
        }
        XCTFail("timed out waiting: \(message)")
        return false
    }

    func testTakenPortSurfacesAsPortInUseForTheTextListener() async throws {
        let holder = try HeldPort()
        let takenPort = holder.port

        let store = makeStore()
        try store.rotate()
        let runtime = try makeRuntime(store: store, textPort: takenPort, videoPort: 0)
        let recorder = StateRecorder()
        runtime.onStateChange = { recorder.record($0, $1) }
        runtime.start()
        defer { runtime.stop() }

        let reached = try await waitFor(
            recorder.states(for: .text).contains(.portInUse(port: takenPort)),
            timeout: 5,
            "text listener must report portInUse(\(takenPort))"
        )
        XCTAssertTrue(reached)
        XCTAssertFalse(
            containsListening(recorder.states(for: .text)),
            "a failed bind must never be reported as listening"
        )
    }

    func testBothListenersReachListeningOnFreePorts() async throws {
        let store = makeStore()
        try store.rotate()
        let runtime = try makeRuntime(store: store, textPort: 0, videoPort: 0)
        let recorder = StateRecorder()
        runtime.onStateChange = { recorder.record($0, $1) }
        runtime.start()
        defer { runtime.stop() }

        let reached = try await waitFor(
            containsListening(recorder.states(for: .text))
                && containsListening(recorder.states(for: .video)),
            timeout: 5,
            "both listeners must reach listening on ephemeral ports"
        )
        XCTAssertTrue(reached)
    }

    func testStateChangeWiredAfterStartIsStillDelivered() async throws {
        // The app may set the callback after start(); wiring order must not
        // decide whether listener state is observable.
        let store = makeStore()
        try store.rotate()
        let runtime = try makeRuntime(store: store, textPort: 0, videoPort: 0)
        runtime.start()
        defer { runtime.stop() }

        let recorder = StateRecorder()
        runtime.onStateChange = { recorder.record($0, $1) }

        let delivered = try await waitFor(
            containsListening(recorder.states(for: .text))
                && containsListening(recorder.states(for: .video)),
            timeout: 5,
            "a listener already .ready must still deliver its state to a late subscriber"
        )
        XCTAssertTrue(delivered)
    }

    func testStopStopsBothListeners() async throws {
        let store = makeStore()
        try store.rotate()
        let runtime = try makeRuntime(store: store, textPort: 0, videoPort: 0)
        let recorder = StateRecorder()
        runtime.onStateChange = { recorder.record($0, $1) }
        runtime.start()

        let bothUp = try await waitFor(
            containsListening(recorder.states(for: .text))
                && containsListening(recorder.states(for: .video)),
            timeout: 5,
            "both listeners must be up before stop"
        )
        XCTAssertTrue(bothUp)
        runtime.stop()
        let bothStopped = try await waitFor(
            recorder.states(for: .text).contains(.stopped) && recorder.states(for: .video).contains(.stopped),
            timeout: 5,
            "stop must stop both listeners"
        )
        XCTAssertTrue(bothStopped)
    }
}
