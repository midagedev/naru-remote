import XCTest
import NaruHelperKit

/// Spec 041 T-A7 / FR-006: the login-item toggle is a pure transition over
/// a controller — the reported state is what the system said, never what
/// the toggle hoped for.
final class NaruHelperLoginItemTests: XCTestCase {
    private struct StubError: Error {}

    private final class FakeLoginItemController: NaruHelperLoginItemControlling, @unchecked Sendable {
        private let lock = NSLock()
        private var registerCallCount = 0
        private var unregisterCallCount = 0
        var registerError: Error?
        var unregisterError: Error?
        var reportedStatus: NaruHelperLoginItemState = .off

        func register() throws {
            lock.lock()
            defer { lock.unlock() }
            registerCallCount += 1
            if let registerError {
                throw registerError
            }
        }

        func unregister() throws {
            lock.lock()
            defer { lock.unlock() }
            unregisterCallCount += 1
            if let unregisterError {
                throw unregisterError
            }
        }

        func status() -> NaruHelperLoginItemState {
            lock.lock()
            defer { lock.unlock() }
            return reportedStatus
        }

        var registerCalls: Int {
            lock.lock()
            defer { lock.unlock() }
            return registerCallCount
        }

        var unregisterCalls: Int {
            lock.lock()
            defer { lock.unlock() }
            return unregisterCallCount
        }
    }

    func testTurningOnReportsSystemEnabledState() {
        let controller = FakeLoginItemController()
        controller.reportedStatus = .on

        let result = NaruHelperLoginItemToggle(desiredEnabled: true).apply(controller: controller)

        XCTAssertEqual(result, .on)
        XCTAssertEqual(controller.registerCalls, 1)
    }

    func testRequiresApprovalIsSurfacedNotRetried() {
        let controller = FakeLoginItemController()
        controller.reportedStatus = .requiresApproval

        let result = NaruHelperLoginItemToggle(desiredEnabled: true).apply(controller: controller)

        XCTAssertEqual(result, .requiresApproval)
        XCTAssertEqual(
            controller.registerCalls,
            1,
            "approval is a user decision — the toggle must not retry registration"
        )
    }

    func testThrowingRegisterMapsToUnavailable() {
        let controller = FakeLoginItemController()
        controller.registerError = StubError()

        let result = NaruHelperLoginItemToggle(desiredEnabled: true).apply(controller: controller)

        XCTAssertEqual(result, .unavailable)
    }

    func testTurningOffReportsOffAndUnregisters() {
        let controller = FakeLoginItemController()
        controller.reportedStatus = .off

        let result = NaruHelperLoginItemToggle(desiredEnabled: false).apply(controller: controller)

        XCTAssertEqual(result, .off)
        XCTAssertEqual(controller.unregisterCalls, 1)
        XCTAssertEqual(controller.registerCalls, 0)
    }

    func testThrowingUnregisterMapsToUnavailable() {
        let controller = FakeLoginItemController()
        controller.unregisterError = StubError()

        let result = NaruHelperLoginItemToggle(desiredEnabled: false).apply(controller: controller)

        XCTAssertEqual(result, .unavailable)
    }
}
