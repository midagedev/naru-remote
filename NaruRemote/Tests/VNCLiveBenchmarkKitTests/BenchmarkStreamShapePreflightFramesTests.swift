import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkStreamShapePreflightFramesTests: XCTestCase {
    func testDefaultAndMaximumAreStableForCliContract() {
        XCTAssertEqual(BenchmarkStreamShapePreflightFrames.defaultValue, 0)
        XCTAssertEqual(BenchmarkStreamShapePreflightFrames.maximum, 5)
        XCTAssertEqual(BenchmarkStreamShapePreflightFrames.usageDescription, "0...5")
    }

    func testParseAcceptsZeroAndMaximum() throws {
        XCTAssertEqual(try BenchmarkStreamShapePreflightFrames.parse("0"), 0)
        XCTAssertEqual(try BenchmarkStreamShapePreflightFrames.parse("5"), 5)
    }

    func testParseRejectsNegativeOverflowAndNonIntegerValues() {
        XCTAssertThrowsError(try BenchmarkStreamShapePreflightFrames.parse("-1")) { error in
            XCTAssertEqual(error as? BenchmarkStreamShapePreflightFramesError, .outOfRange)
        }
        XCTAssertThrowsError(try BenchmarkStreamShapePreflightFrames.parse("6")) { error in
            XCTAssertEqual(error as? BenchmarkStreamShapePreflightFramesError, .outOfRange)
        }
        XCTAssertThrowsError(try BenchmarkStreamShapePreflightFrames.parse("one")) { error in
            XCTAssertEqual(error as? BenchmarkStreamShapePreflightFramesError, .outOfRange)
        }
    }

    func testClampedKeepsReportFieldWithinWireRange() {
        XCTAssertEqual(BenchmarkStreamShapePreflightFrames.clamped(-1), 0)
        XCTAssertEqual(BenchmarkStreamShapePreflightFrames.clamped(3), 3)
        XCTAssertEqual(BenchmarkStreamShapePreflightFrames.clamped(6), 5)
    }

    func testErrorMessageMatchesCliUsage() {
        XCTAssertEqual(
            BenchmarkStreamShapePreflightFramesError.outOfRange.message,
            "stream-shape-preflight-frames must be an integer from 0 to 5."
        )
    }
}
