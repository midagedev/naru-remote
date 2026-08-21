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
    public static let minimumDecodedCellSize = 8
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
        decodeObservation(in: framebuffer)?.sequence
    }

    public static func decodeObservation(in framebuffer: RFBRawFramebuffer) -> BenchmarkVisualFreshnessMarkerObservation? {
        decodeObservation(in: framebuffer, hint: nil)
    }

    /// Decodes the marker, trying `hint`'s placement before searching.
    ///
    /// The search is the expensive part of this whole probe by a wide margin: it
    /// walks every cell size from 96 down to 8 over several framebuffer bands,
    /// stepping a fraction of a cell each time, which is millions of candidate
    /// positions per frame. Measured 2026-08-21 against the live target, running
    /// it on every received update cost **more than half of the benchmark's wall
    /// clock** — content frames per second read 8.1 with the probe enabled and
    /// 17.8 with it disabled, and the share of elapsed time the report could
    /// account for went from 32–55% to 97–98%. Every frame-rate number ever
    /// taken from a freshness-enabled run was depressed by roughly half by the
    /// instrument itself.
    ///
    /// The marker does not move within a run, so the placement of the last
    /// successful decode is tried first and the search is the fallback. That
    /// turns the steady state into thirteen samples per frame.
    public static func decodeObservation(
        in framebuffer: RFBRawFramebuffer,
        hint: BenchmarkVisualFreshnessMarkerObservation?
    ) -> BenchmarkVisualFreshnessMarkerObservation? {
        guard framebuffer.width >= markerCellCount * minimumDecodedCellSize,
              framebuffer.height >= minimumDecodedCellSize else {
            return nil
        }

        if let hint, let hinted = decodeObservation(in: framebuffer, at: hint) {
            return hinted
        }

        let cellSizes = stride(from: 96, through: minimumDecodedCellSize, by: -4)
            .flatMap { [$0, $0 - 2] }
            .filter { $0 >= minimumDecodedCellSize }
        let bands = searchBands(for: framebuffer)

        for cellSize in cellSizes {
            for band in bands where band.width >= markerCellCount * cellSize && band.height >= cellSize {
                let step = cellSize <= 24 ? max(cellSize / 2, 4) : max(cellSize, 6)
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
                            return BenchmarkVisualFreshnessMarkerObservation(
                                sequence: sequence,
                                centerX: x + (markerCellCount * cellSize) / 2,
                                centerY: y + cellSize / 2,
                                originX: x,
                                originY: y,
                                cellSize: cellSize
                            )
                        }
                        x += step
                    }
                    y += step
                }
            }
        }

        return nil
    }

    /// Decodes at exactly one known placement, with no search.
    ///
    /// The search is the whole cost of this probe, so a caller that already knows
    /// where the marker is must be able to ask without risking it.
    public static func decodeObservation(
        in framebuffer: RFBRawFramebuffer,
        at placement: BenchmarkVisualFreshnessMarkerObservation
    ) -> BenchmarkVisualFreshnessMarkerObservation? {
        guard placement.cellSize >= minimumDecodedCellSize,
              placement.originX >= 0,
              placement.originY >= 0,
              placement.originX + markerCellCount * placement.cellSize <= framebuffer.width,
              placement.originY + placement.cellSize <= framebuffer.height,
              let sequence = decodeSequence(
                  in: framebuffer,
                  x: placement.originX,
                  y: placement.originY,
                  cellSize: placement.cellSize
              )
        else {
            return nil
        }
        return BenchmarkVisualFreshnessMarkerObservation(
            sequence: sequence,
            centerX: placement.originX + (markerCellCount * placement.cellSize) / 2,
            centerY: placement.originY + placement.cellSize / 2,
            originX: placement.originX,
            originY: placement.originY,
            cellSize: placement.cellSize
        )
    }

    private static func searchBands(for framebuffer: RFBRawFramebuffer) -> [SearchBand] {
        let fullWidth = framebuffer.width
        let fullHeight = framebuffer.height
        let topBandHeight = min(fullHeight, 1_200)
        let leftBandWidth = min(fullWidth, 1_800)
        let rightBandMinX = max(0, fullWidth - 1_800)
        let bottomBandMinY = max(0, fullHeight - 1_200)
        var bands: [SearchBand] = []

        if fullWidth <= 1_800 || fullHeight <= 1_200 {
            bands.append(SearchBand(minX: 0, minY: 0, maxX: fullWidth, maxY: fullHeight))
        } else {
            bands.append(SearchBand(minX: 0, minY: 0, maxX: fullWidth, maxY: topBandHeight))
            bands.append(SearchBand(minX: 0, minY: bottomBandMinY, maxX: fullWidth, maxY: fullHeight))
            if topBandHeight < bottomBandMinY {
                bands.append(SearchBand(minX: 0, minY: topBandHeight, maxX: leftBandWidth, maxY: bottomBandMinY))
                bands.append(SearchBand(minX: rightBandMinX, minY: topBandHeight, maxX: fullWidth, maxY: bottomBandMinY))
            }
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
                radius: sampleRadius(for: cellSize)
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

    private static func sampleRadius(for cellSize: Int) -> Int {
        guard cellSize > 10 else {
            return 0
        }
        return min(max(cellSize / 8, 1), 3)
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

public struct BenchmarkVisualFreshnessMarkerObservation: Equatable, Sendable {
    public let sequence: Int
    public let centerX: Int
    public let centerY: Int
    /// Where the marker was found, so the next decode can look there first
    /// instead of searching. In-memory only — the encoded observation
    /// (`BenchmarkVisualFreshnessObservation`) has never carried a coordinate,
    /// and must not (constitution §IV).
    public let originX: Int
    public let originY: Int
    public let cellSize: Int

    public init(
        sequence: Int,
        centerX: Int,
        centerY: Int,
        originX: Int = 0,
        originY: Int = 0,
        cellSize: Int = 0
    ) {
        self.sequence = max(sequence, 0)
        self.centerX = max(centerX, 0)
        self.centerY = max(centerY, 0)
        self.originX = max(originX, 0)
        self.originY = max(originY, 0)
        self.cellSize = max(cellSize, 0)
    }
}

public final class BenchmarkVisualFreshnessProbe {
    private let sidecarPath: String
    private var eventsBySequence: [Int: UInt64] = [:]
    private var lastReportedSequence: Int?
    private var highestObservedSequence: Int?
    /// Placement of the last accepted decode, tried first on the next frame.
    /// Only accepted observations become hints, so a false match cannot pin the
    /// search to a position that is not the marker.
    private var placementHint: BenchmarkVisualFreshnessMarkerObservation?
    private var consumedByteCount: UInt64 = 0
    private var newestGeneratedSequence: Int?
    private var searchBackoffObservations = 0

    /// How many observations to skip before searching again after a search that
    /// found nothing, or after the known placement stopped decoding.
    ///
    /// The exhaustive search costs more than everything else this probe does
    /// combined, and the case that matters is not the happy one — it is the
    /// frame where the marker is *not* decodable, because then the full search
    /// runs and finds nothing, and pays the maximum price to learn that. Live
    /// measurement 2026-08-21 showed the probe roughly halving the frame rate it
    /// was measuring: content frames per second read 6-8 with it enabled against
    /// 17.8 with it disabled, and the elapsed time the report could account for
    /// fell to 19-37%. Neither caching the placement nor reading the sidecar
    /// incrementally moved that, because the misses were where the cost lived.
    ///
    /// So a failed search buys silence for this many observations. Freshness is
    /// sampled per delivery anyway, so skipping observations costs sample count,
    /// not correctness — and an instrument that halves the number it reports is
    /// not a trade worth making.
    private static let searchBackoffInterval = 60

    /// Decodes at the known placement when there is one, and rations the
    /// exhaustive search.
    private func decodeMarker(
        in framebuffer: RFBRawFramebuffer
    ) -> BenchmarkVisualFreshnessMarkerObservation? {
        if let placementHint,
           let hinted = BenchmarkVisualFreshnessMarker.decodeObservation(
               in: framebuffer,
               at: placementHint
           ) {
            return hinted
        }
        if searchBackoffObservations > 0 {
            searchBackoffObservations -= 1
            return nil
        }
        guard let found = BenchmarkVisualFreshnessMarker.decodeObservation(in: framebuffer) else {
            searchBackoffObservations = Self.searchBackoffInterval
            return nil
        }
        return found
    }
    /// Observations rejected because their sequence went backwards. Exposed so a
    /// caller can tell "the marker was not found" from "the decoder found
    /// something that cannot be the marker".
    public private(set) var regressedObservationCount = 0

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

    /// One freshness sample per marker **delivery**, not per received update.
    ///
    /// The framebuffer is persistent, so a marker the server has not re-sent
    /// stays on it and can be decoded again and again. Timing every one of those
    /// re-reads turns a single undelivered marker into a run of samples whose
    /// age only grows, and the average and p95 built from them describe the
    /// probe's own sampling rate rather than the picture. Measured 2026-08-21 by
    /// varying only the run length, that is exactly what was happening: peak
    /// reported staleness tracked the run — 0.98 s in a 5 s run, 6.8 s in 15 s,
    /// 31.8 s in 40 s. A 31.8 s stale region in a 40 s run of continuously
    /// animating content is not a plausible reading.
    ///
    /// So an observation whose sequence has already been timed returns no
    /// freshness value. It still returns the sequence, which is what lets the
    /// summary separate "the picture is stale" from "the marker stopped being
    /// repainted on the host" — an occluded or unfocused stimulus window
    /// produces one sequence forever, and that must not read as staleness.
    public func observe(framebuffer: RFBRawFramebuffer) -> BenchmarkVisualFreshnessObservation? {
        guard let markerObservation = decodeMarker(in: framebuffer) else {
            return nil
        }
        // Reject decodes that cannot be the marker.
        //
        // The decoder scans every cell size from 96 down to 8 across several
        // framebuffer bands and returns the first match, and the match test is
        // four sentinel nibbles plus a four-bit checksum — twenty bits against
        // millions of candidate positions per frame, which makes accidental
        // matches expected rather than exceptional. A false match preempts the
        // real marker because it is found first, and if its bogus sequence
        // happens to exist in the sidecar the probe charges the whole elapsed run
        // to the transport as staleness. That is what was left after spec 027:
        // reported maxima kept tracking the run length (0.2 s in a 5 s run,
        // 9.2 s in 15 s, 35.2 s in 40 s) even with each marker timed once, at
        // render.
        //
        // Three properties of the stimulus reject them, in this order, and the
        // order matters. A sequence the host has not rendered cannot be on
        // screen, and a sequence beyond the newest rendered one cannot exist
        // yet; both are checked *before* the monotonic high-water mark is
        // touched. Doing it the other way round is a trap this went through: a
        // single false match with a huge sequence sets the high-water mark out of
        // reach and every later true read is rejected forever, which looked like
        // a fixed metric (maxima collapsed) while actually reporting almost
        // nothing (deliveries fell from 22–37 to 1–8 per run).
        refreshEvents()
        let sequence = markerObservation.sequence
        let generatedAt = eventsBySequence[sequence]
        let isImpossibleSequence = generatedAt == nil
            || (newestGeneratedSequence.map { sequence > $0 } ?? true)
        let hasRegressed = highestObservedSequence.map { sequence < $0 } ?? false
        guard !isImpossibleSequence, !hasRegressed else {
            regressedObservationCount += 1
            return nil
        }
        highestObservedSequence = Swift.max(highestObservedSequence ?? sequence, sequence)
        placementHint = markerObservation

        let markerLocation = BenchmarkVisualFreshnessMarkerLocation(
            centerX: markerObservation.centerX,
            centerY: markerObservation.centerY
        )
        guard sequence != lastReportedSequence, let generatedAt else {
            return BenchmarkVisualFreshnessObservation(
                sequence: sequence,
                freshnessMilliseconds: nil,
                markerLocation: markerLocation
            )
        }
        lastReportedSequence = sequence
        let now = BenchmarkVisualFreshnessSidecar.currentUptimeNanoseconds()
        let elapsedNanoseconds = now >= generatedAt ? now - generatedAt : 0
        return BenchmarkVisualFreshnessObservation(
            sequence: markerObservation.sequence,
            freshnessMilliseconds: Int(elapsedNanoseconds / 1_000_000),
            markerLocation: markerLocation
        )
    }

    /// Reads only the sidecar lines appended since the last call.
    ///
    /// This used to re-read and re-decode the whole file on every observation.
    /// The stimulus appends a line per rendered frame, so on a 40 s run at 30 Hz
    /// that is on the order of a thousand JSON decodes per observation and
    /// hundreds of thousands per run — a cost the probe charges to the very
    /// frame rate it is measuring. Same failure family as the unhinted marker
    /// search: the instrument competing with the thing under test.
    private func refreshEvents() {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: sidecarPath)) else {
            return
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: consumedByteCount)) != nil,
              let appended = try? handle.readToEnd(),
              !appended.isEmpty else {
            return
        }

        // Keep a trailing partial line for the next call rather than dropping it.
        let lastNewline = appended.lastIndex(of: UInt8(ascii: "\n"))
        guard let lastNewline else {
            return
        }
        let complete = appended[appended.startIndex...lastNewline]
        consumedByteCount += UInt64(complete.count)

        let decoder = JSONDecoder()
        for line in complete.split(separator: UInt8(ascii: "\n")) {
            guard !line.isEmpty,
                  let event = try? decoder.decode(
                      BenchmarkVisualFreshnessSidecarEvent.self,
                      from: Data(line)
                  ) else {
                continue
            }
            eventsBySequence[event.sequence] = event.generatedAtUptimeNanoseconds
            newestGeneratedSequence = Swift.max(
                newestGeneratedSequence ?? event.sequence,
                event.sequence
            )
        }
    }
}

/// Whether the freshness marker was actually being repainted on the host while
/// a run measured it.
///
/// This exists so a stalled marker can never be read as a stale picture. If the
/// stimulus window is occluded, unfocused, or off-screen, the last visible
/// marker stays on the captured screen forever: the client keeps decoding one
/// sequence, and a probe that timed every decode would report a staleness that
/// grows with the run length. `stalled` says the run measured the host's
/// painting, not the transport, and its freshness numbers mean nothing.
public enum BenchmarkVisualFreshnessMarkerStatus: String, Codable, Equatable, Sendable, CaseIterable {
    /// No marker was decoded at all.
    case notObserved = "not-observed"
    /// A marker was decoded but never advanced across repeated observations.
    case stalled
    /// The marker advanced, so freshness describes the delivered picture.
    case tracking

    /// How many observations of a single sequence it takes before calling a
    /// marker stalled rather than merely slow. Four, so that a run which simply
    /// received very few updates is not condemned by one or two repeats.
    public static let stalledObservationThreshold = 4

    public init(observationCount: Int, deliveredSequenceCount: Int) {
        if observationCount <= 0 || deliveredSequenceCount <= 0 {
            self = .notObserved
        } else if deliveredSequenceCount == 1,
                  observationCount >= Self.stalledObservationThreshold {
            self = .stalled
        } else {
            self = .tracking
        }
    }

    public static var usageDescription: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }
}

public struct BenchmarkVisualFreshnessMarkerLocation: Equatable, Sendable {
    public let centerX: Int
    public let centerY: Int

    public init(centerX: Int, centerY: Int) {
        self.centerX = max(centerX, 0)
        self.centerY = max(centerY, 0)
    }
}

public struct BenchmarkVisualFreshnessObservation: Codable, Equatable, Sendable {
    public let sequence: Int
    public let freshnessMilliseconds: Int?
    public let markerLocation: BenchmarkVisualFreshnessMarkerLocation?

    public init(
        sequence: Int,
        freshnessMilliseconds: Int?,
        markerLocation: BenchmarkVisualFreshnessMarkerLocation? = nil
    ) {
        self.sequence = max(sequence, 0)
        self.freshnessMilliseconds = freshnessMilliseconds.map { max($0, 0) }
        self.markerLocation = markerLocation
    }

    private enum CodingKeys: String, CodingKey {
        case sequence
        case freshnessMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = max(try container.decode(Int.self, forKey: .sequence), 0)
        freshnessMilliseconds = try container
            .decodeIfPresent(Int.self, forKey: .freshnessMilliseconds)
            .map { max($0, 0) }
        markerLocation = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encodeIfPresent(freshnessMilliseconds, forKey: .freshnessMilliseconds)
    }
}
