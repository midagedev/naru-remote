import Dispatch
import Foundation
import NaruRemoteCore

public struct BenchmarkVisualFreshnessSidecarEvent: Codable, Equatable, Sendable {
    public let sequence: Int
    public let generatedAtUptimeNanoseconds: UInt64

    public init(sequence: Int, generatedAtUptimeNanoseconds: UInt64) {
        self.sequence = max(sequence, 0)
        self.generatedAtUptimeNanoseconds = generatedAtUptimeNanoseconds
    }
}

public enum BenchmarkVisualFreshnessSidecar {
    public static let environmentKey = "NARU_LIVE_STIMULUS_VISUAL_FRESHNESS_FILE"

    public static func currentUptimeNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    public static func append(sequence: Int, to path: String) {
        let event = BenchmarkVisualFreshnessSidecarEvent(
            sequence: sequence,
            generatedAtUptimeNanoseconds: currentUptimeNanoseconds()
        )
        guard let line = try? String(data: JSONEncoder().encode(event), encoding: .utf8) else {
            return
        }
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return
        }
        defer {
            try? handle.close()
        }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}

public struct BenchmarkVisualFreshnessMarker: Equatable, Sendable {
    public static let markerCellCount = 13
    public static let markerPointCellSize = 20
    public static let sentinelNibbles = [15, 0, 10, 5]

    public static let palette: [RFBColor] = [
        RFBColor(red: 8, green: 8, blue: 8),
        RFBColor(red: 238, green: 54, blue: 68),
        RFBColor(red: 32, green: 168, blue: 84),
        RFBColor(red: 24, green: 116, blue: 220),
        RFBColor(red: 246, green: 199, blue: 44),
        RFBColor(red: 226, green: 86, blue: 214),
        RFBColor(red: 38, green: 214, blue: 224),
        RFBColor(red: 247, green: 247, blue: 247),
        RFBColor(red: 126, green: 73, blue: 230),
        RFBColor(red: 244, green: 124, blue: 33),
        RFBColor(red: 98, green: 197, blue: 77),
        RFBColor(red: 74, green: 145, blue: 235),
        RFBColor(red: 186, green: 58, blue: 58),
        RFBColor(red: 58, green: 142, blue: 142),
        RFBColor(red: 170, green: 170, blue: 170),
        RFBColor(red: 255, green: 255, blue: 255)
    ]

    public static func nibbles(for sequence: Int) -> [Int] {
        let safeSequence = UInt32(clamping: max(sequence, 0))
        let sequenceNibbles = stride(from: 28, through: 0, by: -4).map { shift in
            Int((safeSequence >> UInt32(shift)) & 0xF)
        }
        let checksum = sequenceNibbles.reduce(0, +) & 0xF
        return sentinelNibbles + sequenceNibbles + [checksum]
    }

    public static func decodeSequence(in framebuffer: RFBRawFramebuffer) -> Int? {
        guard framebuffer.width >= markerCellCount * 12,
              framebuffer.height >= 24 else {
            return nil
        }

        let cellSizes = [96, 80, 72, 64, 56, 48, 40, 32, 28, 24, 20, 16, 12]
        let bands = searchBands(for: framebuffer)

        for cellSize in cellSizes {
            for band in bands where band.width >= markerCellCount * cellSize && band.height >= cellSize {
                let step = max(cellSize, 6)
                let maxX = band.maxX - markerCellCount * cellSize
                let maxY = band.maxY - cellSize
                guard maxX >= band.minX, maxY >= band.minY else {
                    continue
                }
                var y = band.minY
                while y <= maxY {
                    var x = band.minX
                    while x <= maxX {
                        if let sequence = decodeSequence(
                            in: framebuffer,
                            x: x,
                            y: y,
                            cellSize: cellSize
                        ) {
                            return sequence
                        }
                        x += step
                    }
                    y += step
                }
            }
        }

        return nil
    }

    private static func searchBands(for framebuffer: RFBRawFramebuffer) -> [SearchBand] {
        let fullWidth = framebuffer.width
        let fullHeight = framebuffer.height
        let topBandHeight = min(fullHeight, 1_200)
        let leftBandWidth = min(fullWidth, 1_800)
        let rightBandMinX = max(0, fullWidth - 1_800)
        let bottomBandMinY = max(0, fullHeight - 1_200)
        var bands: [SearchBand] = [
            SearchBand(minX: 0, minY: 0, maxX: leftBandWidth, maxY: topBandHeight),
            SearchBand(minX: rightBandMinX, minY: 0, maxX: fullWidth, maxY: topBandHeight),
            SearchBand(minX: 0, minY: bottomBandMinY, maxX: leftBandWidth, maxY: fullHeight),
            SearchBand(minX: rightBandMinX, minY: bottomBandMinY, maxX: fullWidth, maxY: fullHeight)
        ]

        if fullWidth <= 1_800 || fullHeight <= 1_200 {
            bands.append(SearchBand(minX: 0, minY: 0, maxX: fullWidth, maxY: fullHeight))
        } else {
            let centerMinX = max(0, (fullWidth / 2) - 900)
            let centerMaxX = min(fullWidth, centerMinX + 1_800)
            let centerMinY = max(0, (fullHeight / 2) - 600)
            let centerMaxY = min(fullHeight, centerMinY + 1_200)
            bands.append(SearchBand(minX: centerMinX, minY: centerMinY, maxX: centerMaxX, maxY: centerMaxY))
        }

        var uniqueBands: [SearchBand] = []
        for band in bands where band.width > 0 && band.height > 0 && !uniqueBands.contains(band) {
            uniqueBands.append(band)
        }
        return uniqueBands
    }

    private static func decodeSequence(
        in framebuffer: RFBRawFramebuffer,
        x: Int,
        y: Int,
        cellSize: Int
    ) -> Int? {
        var nibbles: [Int] = []
        nibbles.reserveCapacity(markerCellCount)
        for cellIndex in 0..<markerCellCount {
            let sampleX = x + cellIndex * cellSize + cellSize / 2
            let sampleY = y + cellSize / 2
            let nibble = nearestPaletteIndex(
                in: framebuffer,
                x: sampleX,
                y: sampleY,
                radius: min(max(cellSize / 8, 1), 3)
            )
            guard let nibble else {
                return nil
            }
            if cellIndex < sentinelNibbles.count, nibble != sentinelNibbles[cellIndex] {
                return nil
            }
            nibbles.append(nibble)
        }

        let sequenceNibbles = Array(nibbles.dropFirst(sentinelNibbles.count).prefix(8))
        let checksum = sequenceNibbles.reduce(0, +) & 0xF
        guard nibbles.last == checksum else {
            return nil
        }

        return sequenceNibbles.reduce(0) { partial, nibble in
            (partial << 4) | nibble
        }
    }

    private static func nearestPaletteIndex(
        in framebuffer: RFBRawFramebuffer,
        x: Int,
        y: Int,
        radius: Int
    ) -> Int? {
        var redTotal = 0
        var greenTotal = 0
        var blueTotal = 0
        var sampleCount = 0
        for sampleY in max(y - radius, 0)...min(y + radius, framebuffer.height - 1) {
            for sampleX in max(x - radius, 0)...min(x + radius, framebuffer.width - 1) {
                guard let color = framebuffer[sampleX, sampleY] else {
                    continue
                }
                redTotal += Int(color.red)
                greenTotal += Int(color.green)
                blueTotal += Int(color.blue)
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else {
            return nil
        }

        return nearestPaletteIndex(for: RFBColor(
            red: UInt8(clamping: redTotal / sampleCount),
            green: UInt8(clamping: greenTotal / sampleCount),
            blue: UInt8(clamping: blueTotal / sampleCount)
        ))
    }

    private static func nearestPaletteIndex(for color: RFBColor) -> Int? {
        let candidate = palette.enumerated().min { lhs, rhs in
            squaredDistance(color, lhs.element) < squaredDistance(color, rhs.element)
        }
        guard let candidate,
              squaredDistance(color, candidate.element) <= 10_000 else {
            return nil
        }
        return candidate.offset
    }

    private static func squaredDistance(_ lhs: RFBColor, _ rhs: RFBColor) -> Int {
        let red = Int(lhs.red) - Int(rhs.red)
        let green = Int(lhs.green) - Int(rhs.green)
        let blue = Int(lhs.blue) - Int(rhs.blue)
        return red * red + green * green + blue * blue
    }

    private struct SearchBand: Equatable {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int

        var width: Int { maxX - minX }
        var height: Int { maxY - minY }
    }
}

public final class BenchmarkVisualFreshnessProbe {
    private let sidecarPath: String
    private var eventsBySequence: [Int: UInt64] = [:]

    public init(sidecarPath: String) {
        self.sidecarPath = sidecarPath
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> BenchmarkVisualFreshnessProbe? {
        guard let path = environment[BenchmarkVisualFreshnessSidecar.environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty else {
            return nil
        }
        return BenchmarkVisualFreshnessProbe(sidecarPath: path)
    }

    public func observe(framebuffer: RFBRawFramebuffer) -> BenchmarkVisualFreshnessObservation? {
        guard let sequence = BenchmarkVisualFreshnessMarker.decodeSequence(in: framebuffer) else {
            return nil
        }
        refreshEvents()
        guard let generatedAt = eventsBySequence[sequence] else {
            return BenchmarkVisualFreshnessObservation(
                sequence: sequence,
                freshnessMilliseconds: nil
            )
        }
        let now = BenchmarkVisualFreshnessSidecar.currentUptimeNanoseconds()
        let elapsedNanoseconds = now >= generatedAt ? now - generatedAt : 0
        return BenchmarkVisualFreshnessObservation(
            sequence: sequence,
            freshnessMilliseconds: Int(elapsedNanoseconds / 1_000_000)
        )
    }

    private func refreshEvents() {
        guard let contents = try? String(contentsOfFile: sidecarPath, encoding: .utf8) else {
            return
        }
        let decoder = JSONDecoder()
        for line in contents.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(BenchmarkVisualFreshnessSidecarEvent.self, from: data) else {
                continue
            }
            eventsBySequence[event.sequence] = event.generatedAtUptimeNanoseconds
        }
    }
}

public struct BenchmarkVisualFreshnessObservation: Codable, Equatable, Sendable {
    public let sequence: Int
    public let freshnessMilliseconds: Int?

    public init(sequence: Int, freshnessMilliseconds: Int?) {
        self.sequence = max(sequence, 0)
        self.freshnessMilliseconds = freshnessMilliseconds.map { max($0, 0) }
    }
}
