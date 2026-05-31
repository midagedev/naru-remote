import Foundation
import XCTest
@testable import NaruRemoteCore

/// Validates the persistent zlib inflate plumbing (spec 004 FR-005)
/// against ground-truth fixtures produced by real zlib (Python
/// `zlib.compressobj` + `Z_SYNC_FLUSH` per "rectangle"), so the Apple
/// Compression-framework approach is proven to handle RFB's continuous,
/// non-finalized, SYNC_FLUSH'd stream before the ZRLE tile decoder is
/// built on top of it.
final class RFBZlibInflateStreamTests: XCTestCase {
    func testInflatesFirstRectangleChunk() throws {
        let comp1 = try fixture("zlib-stream-comp1")
        let plain1 = try fixture("zlib-stream-plain1")

        let stream = try RFBZlibInflateStream()
        let out1 = try stream.inflate([UInt8](comp1))
        XCTAssertEqual(out1, [UInt8](plain1))
    }

    func testPersistsWindowAcrossRectangles() throws {
        // The crux of FR-005: a SINGLE stream must decode rectangle 2,
        // whose DEFLATE back-references rectangle 1's window.
        let comp1 = try fixture("zlib-stream-comp1")
        let comp2 = try fixture("zlib-stream-comp2")
        let plain1 = try fixture("zlib-stream-plain1")
        let plain2 = try fixture("zlib-stream-plain2")

        let stream = try RFBZlibInflateStream()
        XCTAssertEqual(try stream.inflate([UInt8](comp1)), [UInt8](plain1))
        XCTAssertEqual(try stream.inflate([UInt8](comp2)), [UInt8](plain2))
    }

    func testFreshStreamCannotDecodeSecondChunk() throws {
        // Proves the persistence requirement is real: a fresh context
        // fed only rectangle 2's bytes does NOT reproduce plain2 (it
        // mis-strips a "header", lacks the window, and yields wrong or
        // no output) — so resetting per rectangle would corrupt frame 2+.
        let comp2 = try fixture("zlib-stream-comp2")
        let plain2 = try fixture("zlib-stream-plain2")

        let stream = try RFBZlibInflateStream()
        let wrong = (try? stream.inflate([UInt8](comp2))) ?? []
        XCTAssertNotEqual(wrong, [UInt8](plain2))
    }

    private func fixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            root.deleteLastPathComponent()
        }
        let url = root
            .appendingPathComponent("TestFixtures/FakeRFBServer/Fixtures")
            .appendingPathComponent("\(name).bin")
        return try Data(contentsOf: url)
    }
}
