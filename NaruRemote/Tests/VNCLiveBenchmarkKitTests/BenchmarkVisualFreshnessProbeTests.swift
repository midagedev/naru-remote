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

    func testMarkerDecodeScansRetinaScaleAwayFromTopLeft() throws {
        let sequence = 0x0000_FF31
        var framebuffer = RFBRawFramebuffer(
            width: 2_400,
            height: 1_600,
            fill: RFBColor(red: 19, green: 20, blue: 21)
        )
        drawMarker(
            sequence: sequence,
            x: 1_520,
            y: 1_160,
            cellSize: 64,
            framebuffer: &framebuffer
        )

        XCTAssertEqual(BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer), sequence)
    }

    func testMarkerObservationIncludesDecodedMarkerLocation() throws {
        let sequence = 0x0000_FF31
        let originX = 1_520
        let originY = 1_160
        let cellSize = 64
        var framebuffer = RFBRawFramebuffer(
            width: 2_400,
            height: 1_600,
            fill: RFBColor(red: 19, green: 20, blue: 21)
        )
        drawMarker(
            sequence: sequence,
            x: originX,
            y: originY,
            cellSize: cellSize,
            framebuffer: &framebuffer
        )

        let observation = try XCTUnwrap(BenchmarkVisualFreshnessMarker.decodeObservation(in: framebuffer))
        XCTAssertEqual(observation.sequence, sequence)
        XCTAssertGreaterThanOrEqual(observation.centerX, originX)
        XCTAssertLessThan(observation.centerX, originX + BenchmarkVisualFreshnessMarker.markerCellCount * cellSize)
        XCTAssertGreaterThanOrEqual(observation.centerY, originY)
        XCTAssertLessThan(observation.centerY, originY + cellSize)
    }

    func testMarkerDecodeScansFractionalVNCDisplayScales() throws {
        let sequence = 0x0000_9A4C
        var framebuffer = RFBRawFramebuffer(
            width: 3_024,
            height: 1_964,
            fill: RFBColor(red: 19, green: 20, blue: 21)
        )
        drawMarker(
            sequence: sequence,
            x: 164,
            y: 132,
            cellSize: 30,
            framebuffer: &framebuffer
        )
        drawMarker(
            sequence: sequence,
            x: 2_080,
            y: 1_560,
            cellSize: 36,
            framebuffer: &framebuffer
        )

        XCTAssertEqual(BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer), sequence)
    }

    func testMarkerDecodeScansDownsampledRetinaVNCScale() throws {
        let sequence = 0x0000_10AC
        var framebuffer = RFBRawFramebuffer(
            width: 1_512,
            height: 982,
            fill: RFBColor(red: 19, green: 20, blue: 21)
        )
        drawMarker(
            sequence: sequence,
            x: 58,
            y: 76,
            cellSize: 10,
            framebuffer: &framebuffer
        )

        let observation = try XCTUnwrap(BenchmarkVisualFreshnessMarker.decodeObservation(in: framebuffer))
        XCTAssertEqual(observation.sequence, sequence)
        XCTAssertGreaterThanOrEqual(observation.centerX, 58)
        XCTAssertLessThan(observation.centerX, 58 + BenchmarkVisualFreshnessMarker.markerCellCount * 10)
        XCTAssertGreaterThanOrEqual(observation.centerY, 76)
        XCTAssertLessThan(observation.centerY, 86)
    }

    func testMarkerDecodeScansWideTopBandForCompositeFramebuffers() throws {
        let sequence = 0x0000_0BEE
        var framebuffer = RFBRawFramebuffer(
            width: 5_600,
            height: 1_800,
            fill: RFBColor(red: 19, green: 20, blue: 21)
        )
        drawMarker(
            sequence: sequence,
            x: 2_440,
            y: 88,
            cellSize: 40,
            framebuffer: &framebuffer
        )

        XCTAssertEqual(BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer), sequence)
    }

    func testMarkerDecodeToleratesNoisySentinelCenterPixel() throws {
        let sequence = 0x0000_00A7
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
        replacePixel(
            x: 36 + 10,
            y: 48 + 10,
            color: RFBColor(red: 12, green: 12, blue: 12),
            framebuffer: &framebuffer
        )

        XCTAssertEqual(BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer), sequence)
    }

    func testMarkerDecodeReturnsNilForLargeFrameWithoutMarker() throws {
        let framebuffer = RFBRawFramebuffer(
            width: 1_920,
            height: 1_080,
            fill: RFBColor(red: 19, green: 20, blue: 21)
        )

        XCTAssertNil(BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer))
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
        XCTAssertNotNil(observation.markerLocation)
    }

    /// One sample per delivery. Re-reading a marker the server has not re-sent
    /// must not produce a second, older sample — that is what made reported
    /// staleness track the run length instead of the picture (peak 0.98 s in a
    /// 5 s run, 31.8 s in a 40 s run, measured 2026-08-21).
    func testRepeatedObservationsOfOneMarkerYieldASingleFreshnessSample() throws {
        let sidecarURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("naru-freshness-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        BenchmarkVisualFreshnessSidecar.append(sequence: 11, to: sidecarURL.path)
        BenchmarkVisualFreshnessSidecar.append(sequence: 12, to: sidecarURL.path)
        var framebuffer = RFBRawFramebuffer(
            width: 360,
            height: 160,
            fill: RFBColor(red: 0, green: 0, blue: 0)
        )
        drawMarker(sequence: 11, x: 20, y: 20, cellSize: 20, framebuffer: &framebuffer)

        let probe = BenchmarkVisualFreshnessProbe(sidecarPath: sidecarURL.path)
        let first = try XCTUnwrap(probe.observe(framebuffer: framebuffer))
        XCTAssertNotNil(first.freshnessMilliseconds)

        for _ in 0..<5 {
            let repeated = try XCTUnwrap(probe.observe(framebuffer: framebuffer))
            XCTAssertEqual(repeated.sequence, 11)
            XCTAssertNil(
                repeated.freshnessMilliseconds,
                "An update that carried no new marker is not a freshness sample"
            )
        }

        // A genuinely new delivery is timed again.
        drawMarker(sequence: 12, x: 20, y: 20, cellSize: 20, framebuffer: &framebuffer)
        let next = try XCTUnwrap(probe.observe(framebuffer: framebuffer))
        XCTAssertEqual(next.sequence, 12)
        XCTAssertNotNil(next.freshnessMilliseconds)
    }

    /// A false marker match is rejected, and — this is the part that bit once —
    /// rejecting it must not poison the probe. An accidental decode can carry an
    /// arbitrarily large sequence, so if the monotonic high-water mark were
    /// raised before checking that the sequence was actually rendered, every
    /// later true read would be rejected forever.
    func testAnImpossibleSequenceIsRejectedWithoutBlindingTheProbe() throws {
        let sidecarURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("naru-freshness-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        BenchmarkVisualFreshnessSidecar.append(sequence: 5, to: sidecarURL.path)
        let probe = BenchmarkVisualFreshnessProbe(sidecarPath: sidecarURL.path)

        // A decode of something the host never rendered, with a huge sequence.
        var bogus = RFBRawFramebuffer(
            width: 360,
            height: 160,
            fill: RFBColor(red: 0, green: 0, blue: 0)
        )
        drawMarker(sequence: 0x0FFF_FFF0, x: 20, y: 20, cellSize: 20, framebuffer: &bogus)
        XCTAssertNil(probe.observe(framebuffer: bogus))
        XCTAssertEqual(probe.regressedObservationCount, 1)

        // The real marker is still measurable afterwards.
        var real = RFBRawFramebuffer(
            width: 360,
            height: 160,
            fill: RFBColor(red: 0, green: 0, blue: 0)
        )
        drawMarker(sequence: 5, x: 20, y: 20, cellSize: 20, framebuffer: &real)
        let observation = try XCTUnwrap(probe.observe(framebuffer: real))
        XCTAssertEqual(observation.sequence, 5)
        XCTAssertNotNil(observation.freshnessMilliseconds)
    }

    func testASequenceThatGoesBackwardsIsRejected() throws {
        let sidecarURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("naru-freshness-\(UUID().uuidString).jsonl")
        defer {
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        BenchmarkVisualFreshnessSidecar.append(sequence: 3, to: sidecarURL.path)
        BenchmarkVisualFreshnessSidecar.append(sequence: 9, to: sidecarURL.path)
        let probe = BenchmarkVisualFreshnessProbe(sidecarPath: sidecarURL.path)

        var framebuffer = RFBRawFramebuffer(
            width: 360,
            height: 160,
            fill: RFBColor(red: 0, green: 0, blue: 0)
        )
        drawMarker(sequence: 9, x: 20, y: 20, cellSize: 20, framebuffer: &framebuffer)
        XCTAssertNotNil(try XCTUnwrap(probe.observe(framebuffer: framebuffer)).freshnessMilliseconds)

        // The on-screen marker never counts down, so this is not the marker.
        var earlier = RFBRawFramebuffer(
            width: 360,
            height: 160,
            fill: RFBColor(red: 0, green: 0, blue: 0)
        )
        drawMarker(sequence: 3, x: 20, y: 20, cellSize: 20, framebuffer: &earlier)
        XCTAssertNil(probe.observe(framebuffer: earlier))
        XCTAssertEqual(probe.regressedObservationCount, 1)
    }

    func testMarkerStatusSeparatesAStalledMarkerFromAStalePicture() {
        XCTAssertEqual(
            BenchmarkVisualFreshnessMarkerStatus(observationCount: 0, deliveredSequenceCount: 0),
            .notObserved
        )
        XCTAssertEqual(
            BenchmarkVisualFreshnessMarkerStatus(observationCount: 40, deliveredSequenceCount: 1),
            .stalled
        )
        XCTAssertEqual(
            BenchmarkVisualFreshnessMarkerStatus(observationCount: 40, deliveredSequenceCount: 12),
            .tracking
        )
        // Too few observations to condemn a marker that simply had little to do.
        XCTAssertEqual(
            BenchmarkVisualFreshnessMarkerStatus(observationCount: 2, deliveredSequenceCount: 1),
            .tracking
        )
        XCTAssertEqual(
            BenchmarkVisualFreshnessMarkerStatus.usageDescription,
            "not-observed|stalled|tracking"
        )
    }

    func testFreshnessObservationOmitsMarkerLocationFromJSON() throws {
        let observation = BenchmarkVisualFreshnessObservation(
            sequence: 42,
            freshnessMilliseconds: 17,
            markerLocation: BenchmarkVisualFreshnessMarkerLocation(centerX: 123, centerY: 456)
        )

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(observation), encoding: .utf8))
        XCTAssertTrue(json.contains("\"sequence\":42"))
        XCTAssertTrue(json.contains("\"freshnessMilliseconds\":17"))
        XCTAssertFalse(json.contains("markerLocation"))
        XCTAssertFalse(json.contains("centerX"))
        XCTAssertFalse(json.contains("centerY"))

        let decoded = try JSONDecoder().decode(BenchmarkVisualFreshnessObservation.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.sequence, 42)
        XCTAssertEqual(decoded.freshnessMilliseconds, 17)
        XCTAssertNil(decoded.markerLocation)
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

    private func replacePixel(
        x: Int,
        y: Int,
        color: RFBColor,
        framebuffer: inout RFBRawFramebuffer
    ) {
        var pixels = framebuffer.pixels
        pixels[y * framebuffer.width + x] = color
        framebuffer = RFBRawFramebuffer(
            width: framebuffer.width,
            height: framebuffer.height,
            pixels: pixels
        )
    }
}
