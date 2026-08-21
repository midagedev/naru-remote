import XCTest
@testable import VNCLiveBenchmarkKit

final class BenchmarkBuildConfigurationTests: XCTestCase {
    /// `swift test` runs debug, so this asserts the debug branch of `current`
    /// directly — the branch that a report must not be allowed to present as a
    /// measurement (spec 025).
    func testCurrentReportsTheConfigurationItWasCompiledWith() {
        #if DEBUG
        XCTAssertEqual(BenchmarkBuildConfiguration.current, .debug)
        #else
        XCTAssertEqual(BenchmarkBuildConfiguration.current, .release)
        #endif
    }

    func testOnlyReleaseTimingsAreTrustworthy() {
        XCTAssertFalse(BenchmarkBuildConfiguration.debug.producesTrustworthyTimings)
        XCTAssertTrue(BenchmarkBuildConfiguration.release.producesTrustworthyTimings)
    }

    func testRawValuesAreStableForArchivedReports() {
        XCTAssertEqual(BenchmarkBuildConfiguration.debug.rawValue, "debug")
        XCTAssertEqual(BenchmarkBuildConfiguration.release.rawValue, "release")
        XCTAssertEqual(BenchmarkBuildConfiguration.usageDescription, "debug|release")
    }
}
