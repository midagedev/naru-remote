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

        let searchWidth = min(framebuffer.width, 1_400)
        let searchHeight = min(framebuffer.height, 900)
        let cellSizes = [48, 40, 32, 28, 24, 20, 16, 12]

        for cellSize in cellSizes where searchWidth >= markerCellCount * cellSize {
            let step = max(cellSize / 2, 6)
            let maxX = searchWidth - (markerCellCount * cellSize)
            let maxY = searchHeight - cellSize
            guard maxX >= 0, maxY >= 0 else {
                continue
            }
            var y = 0
            while y <= maxY {
                var x = 0
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

        return nil
    }

    private static func decodeSequence(
        in framebuffer: RFBRawFramebuffer,
        x: Int,
        y: Int,
        cellSize: Int
    ) -> Int? {
        let nibbles = (0..<markerCellCount).compactMap { cellIndex in
            nearestPaletteIndex(
                in: framebuffer,
                x: x + cellIndex * cellSize + cellSize / 2,
                y: y + cellSize / 2,
                radius: max(cellSize / 6, 1)
            )
        }
        guard nibbles.count == markerCellCount,
              Array(nibbles.prefix(sentinelNibbles.count)) == sentinelNibbles else {
            return nil
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

        let averaged = RFBColor(
            red: UInt8(clamping: redTotal / sampleCount),
            green: UInt8(clamping: greenTotal / sampleCount),
            blue: UInt8(clamping: blueTotal / sampleCount)
        )
        let candidate = palette.enumerated().min { lhs, rhs in
            squaredDistance(averaged, lhs.element) < squaredDistance(averaged, rhs.element)
        }
        guard let candidate,
              squaredDistance(averaged, candidate.element) <= 10_000 else {
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
