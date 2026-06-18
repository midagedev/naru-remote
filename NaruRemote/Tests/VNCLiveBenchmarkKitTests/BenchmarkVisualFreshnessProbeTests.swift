import XCTest
import NaruRemoteCore
@testable import VNCLiveBenchmarkKit

final class BenchmarkVisualFreshnessProbeTests: XCTestCase {
    func testMarkerRoundTripsSequenceFromFramebufferPixels() throws {
        let sequence = 0x00AB_12CD
        var framebuffer = RFBRawFramebuffer(
            width: 420,
            height: 180,
            fill: RFBColor(red: 12, green: 12, blue: 12)
        )
        drawMarker(
            sequence: sequence,
            x: 36,
            y: 48,
            cellSize: 20,
            framebuffer: &framebuffer
        )

        XCTAssertEqual(BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer), sequence)
    }

    func testSidecarProbeCalculatesFreshnessForDecodedSequence() throws {
        let sidecarURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("naru-freshness-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        let sequence = 7
        BenchmarkVisualFreshnessSidecar.append(sequence: sequence, to: sidecarURL.path)
        var framebuffer = RFBRawFramebuffer(
            width: 360,
            height: 160,
            fill: RFBColor(red: 0, green: 0, blue: 0)
        )
        drawMarker(sequence: sequence, x: 20, y: 20, cellSize: 20, framebuffer: &framebuffer)

        let observation = try XCTUnwrap(
            BenchmarkVisualFreshnessProbe(sidecarPath: sidecarURL.path)
                .observe(framebuffer: framebuffer)
        )
        XCTAssertEqual(observation.sequence, sequence)
        XCTAssertNotNil(observation.freshnessMilliseconds)
    }

    private func drawMarker(
        sequence: Int,
        x originX: Int,
        y originY: Int,
        cellSize: Int,
        framebuffer: inout RFBRawFramebuffer
    ) {
        let nibbles = BenchmarkVisualFreshnessMarker.nibbles(for: sequence)
        var pixels = framebuffer.pixels
        for (cellIndex, nibble) in nibbles.enumerated() {
            let color = BenchmarkVisualFreshnessMarker.palette[nibble]
            let minX = originX + cellIndex * cellSize
            let maxX = min(minX + cellSize, framebuffer.width)
            let maxY = min(originY + cellSize, framebuffer.height)
            guard minX < maxX, originY < maxY else {
                continue
            }
            for y in originY..<maxY {
                for x in minX..<maxX {
                    pixels[y * framebuffer.width + x] = color
                }
            }
        }
        framebuffer = RFBRawFramebuffer(
            width: framebuffer.width,
            height: framebuffer.height,
            pixels: pixels
        )
    }
}
