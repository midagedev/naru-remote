import XCTest
@testable import NaruRemoteCore

final class ReconnectPolicyTests: XCTestCase {
    func testDefaultPolicyMatchesDocumentedConstants() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.initialBackoff, .milliseconds(500))
        XCTAssertEqual(policy.maxBackoff, .seconds(8))
    }

    func testBackoffDoublesUntilMaxBackoff() {
        let policy = ReconnectPolicy(
            maxAttempts: 5,
            initialBackoff: .milliseconds(500),
            maxBackoff: .seconds(8)
        )
        // attempt 1: initial * 2^0 = 500ms
        XCTAssertEqual(policy.backoffForAttempt(1), .milliseconds(500))
        // attempt 2: initial * 2^1 = 1000ms
        XCTAssertEqual(policy.backoffForAttempt(2), .milliseconds(1000))
        // attempt 3: initial * 2^2 = 2000ms
        XCTAssertEqual(policy.backoffForAttempt(3), .milliseconds(2000))
        // attempt 4: initial * 2^3 = 4000ms
        XCTAssertEqual(policy.backoffForAttempt(4), .milliseconds(4000))
        // attempt 5: initial * 2^4 = 8000ms = maxBackoff (clamps)
        XCTAssertEqual(policy.backoffForAttempt(5), .seconds(8))
    }

    func testBackoffClampsAtMaxBackoffOnceExceeded() {
        let policy = ReconnectPolicy(
            maxAttempts: 10,
            initialBackoff: .milliseconds(500),
            maxBackoff: .seconds(8)
        )
        // 500 -> 1000 -> 2000 -> 4000 -> 8000 -> would be 16000, clamps.
        XCTAssertEqual(policy.backoffForAttempt(6), .seconds(8))
        XCTAssertEqual(policy.backoffForAttempt(7), .seconds(8))
        XCTAssertEqual(policy.backoffForAttempt(99), .seconds(8))
    }

    func testBackoffTreatsZeroAndNegativeAsAttemptOne() {
        let policy = ReconnectPolicy(
            maxAttempts: 3,
            initialBackoff: .milliseconds(500),
            maxBackoff: .seconds(8)
        )
        XCTAssertEqual(policy.backoffForAttempt(0), .milliseconds(500))
        XCTAssertEqual(policy.backoffForAttempt(-1), .milliseconds(500))
    }

    func testPolicyIsEquatable() {
        let a = ReconnectPolicy(maxAttempts: 3, initialBackoff: .milliseconds(500), maxBackoff: .seconds(8))
        let b = ReconnectPolicy(maxAttempts: 3, initialBackoff: .milliseconds(500), maxBackoff: .seconds(8))
        let c = ReconnectPolicy(maxAttempts: 4, initialBackoff: .milliseconds(500), maxBackoff: .seconds(8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
