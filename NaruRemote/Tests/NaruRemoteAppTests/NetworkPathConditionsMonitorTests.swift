import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class NetworkPathConditionsMonitorTests: XCTestCase {
    func testUnknownIsBothFalse() {
        XCTAssertEqual(
            NetworkPathConditions.unknown,
            NetworkPathConditions(isExpensive: false, isConstrained: false)
        )
    }

    func testCurrentIsUnknownBeforeFirstUpdate() {
        let monitor = NetworkPathConditionsMonitor()
        XCTAssertEqual(monitor.current, .unknown)
        XCTAssertFalse(monitor.current.isExpensive)
        XCTAssertFalse(monitor.current.isConstrained)
    }

    func testNoteUpdateFlipsSnapshotWithoutLivePath() {
        let monitor = NetworkPathConditionsMonitor()
        monitor.noteUpdate(isExpensive: true, isConstrained: true)
        XCTAssertEqual(
            monitor.current,
            NetworkPathConditions(isExpensive: true, isConstrained: true)
        )
        monitor.noteUpdate(isExpensive: true, isConstrained: false)
        XCTAssertEqual(
            monitor.current,
            NetworkPathConditions(isExpensive: true, isConstrained: false)
        )
    }
}
