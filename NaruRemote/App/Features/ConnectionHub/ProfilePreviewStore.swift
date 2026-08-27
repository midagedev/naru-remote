import CoreGraphics
import Foundation
import NaruRemoteCore

public struct ProfilePreviewThumbnail: Codable, Equatable, Sendable {
    /// Spec 038 FR-011: enough pixels that the card is not magnifying a
    /// thumbnail, without turning a thumbnail into a photograph.
    ///
    /// A grid card is about half an iPhone's width — ~190pt on a 402pt screen —
    /// so at 3× it draws ~570 device pixels wide and the old 320 cap meant a
    /// permanent 1.8× upscale. 480 brings that to 1.19×, which after FR-010's
    /// filtering is not visible.
    ///
    /// It stops there rather than at 570 because this is stored as raw RGBA in
    /// a JSON file, per profile: 480×300 is 576KB where 640×400 would be 1MB,
    /// and the aliasing was always the larger half of the defect.
    public static let defaultMaxWidth = 480
    public static let defaultMaxHeight = 300

    public let width: Int
    public let height: Int
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let capturedAt: Date
    public let rgbaData: Data

    private init(
        width: Int,
        height: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        capturedAt: Date,
        rgbaData: Data
    ) {
        let normalizedWidth = max(width, 0)
        let normalizedHeight = max(height, 0)
        let expectedByteCount = normalizedWidth * normalizedHeight * 4
        self.width = normalizedWidth
        self.height = normalizedHeight
        self.sourceWidth = max(sourceWidth, 0)
        self.sourceHeight = max(sourceHeight, 0)
        self.capturedAt = capturedAt
        if rgbaData.count == expectedByteCount {
            self.rgbaData = rgbaData
        } else if rgbaData.count > expectedByteCount {
            self.rgbaData = Data(rgbaData.prefix(expectedByteCount))
        } else {
            var padded = rgbaData
            padded.append(
                contentsOf: repeatElement(UInt8(0), count: expectedByteCount - rgbaData.count)
            )
            self.rgbaData = padded
        }
    }

    public init(
        width: Int,
        height: Int,
        sourceWidth: Int,
        sourceHeight: Int,
        capturedAt: Date,
        pixels: [RFBColor]
    ) {
        let normalizedWidth = max(width, 0)
        let normalizedHeight = max(height, 0)
        let expectedCount = normalizedWidth * normalizedHeight
        self.width = normalizedWidth
        self.height = normalizedHeight
        self.sourceWidth = max(sourceWidth, 0)
        self.sourceHeight = max(sourceHeight, 0)
        self.capturedAt = capturedAt
        var rgbaData = Data(count: expectedCount * 4)
        rgbaData.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            guard !bytes.isEmpty else {
                return
            }
            let clear = RFBColor(red: 0, green: 0, blue: 0, alpha: 0)
            for index in 0..<expectedCount {
                let pixel = index < pixels.count ? pixels[index] : clear
                Self.write(pixel, into: bytes, atPixelIndex: index)
            }
        }
        self.rgbaData = rgbaData
    }

    public init?(
        framebuffer: RFBRawFramebuffer,
        capturedAt: Date = Date(),
        maxWidth: Int = Self.defaultMaxWidth,
        maxHeight: Int = Self.defaultMaxHeight
    ) {
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            return nil
        }

        let boundedMaxWidth = max(maxWidth, 1)
        let boundedMaxHeight = max(maxHeight, 1)
        let scale = min(
            1.0,
            Double(boundedMaxWidth) / Double(framebuffer.width),
            Double(boundedMaxHeight) / Double(framebuffer.height)
        )
        let thumbnailWidth = max(1, Int((Double(framebuffer.width) * scale).rounded()))
        let thumbnailHeight = max(1, Int((Double(framebuffer.height) * scale).rounded()))

        let pixelCount = thumbnailWidth * thumbnailHeight
        let sourcePixels = framebuffer.pixels
        let sourceXScale = Double(framebuffer.width) / Double(thumbnailWidth)
        let sourceYScale = Double(framebuffer.height) / Double(thumbnailHeight)
        var rgbaData = Data(count: pixelCount * 4)
        rgbaData.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            guard !bytes.isEmpty else {
                return
            }
            var pixelIndex = 0
            for y in 0..<thumbnailHeight {
                // Spec 038 FR-010: average the source block this destination
                // pixel covers, rather than sampling one pixel out of it.
                //
                // Point sampling a 3024-wide desktop down to a card keeps one
                // pixel in ninety-four and throws away the rest, and what these
                // desktops are full of is text — so strokes appeared, doubled
                // or vanished depending on where the sample happened to land.
                // That is not softness, it is aliasing, and no amount of
                // interpolation at draw time can undo it.
                let sourceYStart = min(
                    framebuffer.height - 1,
                    Int(Double(y) * sourceYScale)
                )
                let sourceYEnd = max(
                    sourceYStart + 1,
                    min(framebuffer.height, Int((Double(y) + 1) * sourceYScale))
                )
                for x in 0..<thumbnailWidth {
                    let sourceXStart = min(
                        framebuffer.width - 1,
                        Int(Double(x) * sourceXScale)
                    )
                    let sourceXEnd = max(
                        sourceXStart + 1,
                        min(framebuffer.width, Int((Double(x) + 1) * sourceXScale))
                    )
                    Self.write(
                        Self.averageColor(
                            of: sourcePixels,
                            framebufferWidth: framebuffer.width,
                            xRange: sourceXStart..<sourceXEnd,
                            yRange: sourceYStart..<sourceYEnd
                        ),
                        into: bytes,
                        atPixelIndex: pixelIndex
                    )
                    pixelIndex += 1
                }
            }
        }

        self.init(
            width: thumbnailWidth,
            height: thumbnailHeight,
            sourceWidth: framebuffer.width,
            sourceHeight: framebuffer.height,
            capturedAt: capturedAt,
            rgbaData: rgbaData
        )
    }

    public var isRenderable: Bool {
        width > 0 && height > 0 && rgbaData.count == width * height * 4
    }

    public var pixels: [RFBColor] {
        guard isRenderable else {
            return []
        }

        return rgbaData.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var decodedPixels: [RFBColor] = []
            decodedPixels.reserveCapacity(width * height)
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                decodedPixels.append(
                    RFBColor(
                        red: bytes[offset],
                        green: bytes[offset + 1],
                        blue: bytes[offset + 2],
                        alpha: bytes[offset + 3]
                    )
                )
            }
            return decodedPixels
        }
    }

    public var cgImage: CGImage? {
        guard isRenderable else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let provider = CGDataProvider(data: rgbaData as CFData) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// The mean of one source block, in straight (non-premultiplied) RGBA.
    ///
    /// Accumulating in `Int` and dividing once keeps this exact for any block
    /// a phone-sized framebuffer can produce, and avoids the rounding drift a
    /// running average would leave across a 3000-pixel row.
    static func averageColor(
        of pixels: [RFBColor],
        framebufferWidth: Int,
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> RFBColor {
        var red = 0
        var green = 0
        var blue = 0
        var alpha = 0
        var count = 0

        for y in yRange {
            let rowOffset = y * framebufferWidth
            for x in xRange {
                let index = rowOffset + x
                guard index >= 0, index < pixels.count else {
                    continue
                }
                let pixel = pixels[index]
                red += Int(pixel.red)
                green += Int(pixel.green)
                blue += Int(pixel.blue)
                alpha += Int(pixel.alpha)
                count += 1
            }
        }

        guard count > 0 else {
            return RFBColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        return RFBColor(
            red: UInt8((red + count / 2) / count),
            green: UInt8((green + count / 2) / count),
            blue: UInt8((blue + count / 2) / count),
            alpha: UInt8((alpha + count / 2) / count)
        )
    }

    private static func write(
        _ pixel: RFBColor,
        into bytes: UnsafeMutableBufferPointer<UInt8>,
        atPixelIndex pixelIndex: Int
    ) {
        let offset = pixelIndex * 4
        bytes[offset] = pixel.red
        bytes[offset + 1] = pixel.green
        bytes[offset + 2] = pixel.blue
        bytes[offset + 3] = pixel.alpha
    }
}

public protocol ProfilePreviewStore: Sendable {
    func loadThumbnail(for profileID: ConnectionProfile.ID) async throws -> ProfilePreviewThumbnail?
    func saveThumbnail(
        _ thumbnail: ProfilePreviewThumbnail,
        for profileID: ConnectionProfile.ID
    ) async throws
    func deleteThumbnail(for profileID: ConnectionProfile.ID) async throws
}

public actor InMemoryProfilePreviewStore: ProfilePreviewStore {
    private var thumbnails: [ConnectionProfile.ID: ProfilePreviewThumbnail]

    public init(thumbnails: [ConnectionProfile.ID: ProfilePreviewThumbnail] = [:]) {
        self.thumbnails = thumbnails
    }

    public func loadThumbnail(for profileID: ConnectionProfile.ID) async throws -> ProfilePreviewThumbnail? {
        thumbnails[profileID]
    }

    public func saveThumbnail(
        _ thumbnail: ProfilePreviewThumbnail,
        for profileID: ConnectionProfile.ID
    ) async throws {
        thumbnails[profileID] = thumbnail
    }

    public func deleteThumbnail(for profileID: ConnectionProfile.ID) async throws {
        thumbnails.removeValue(forKey: profileID)
    }
}

/// Marks an on-device directory so iCloud / Finder backups skip it.
/// Thumbnails and profile/settings files under Application Support must
/// not leave the device via backup (constitution §IV).
public enum FileBackupExclusion {
    public static func excludeFromBackupBestEffort(_ directoryURL: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directoryURL
        // Simulator and `swift test` hosts can reject this resource key;
        // backup exclusion is a privacy best-effort and must not fail setup.
        try? mutableURL.setResourceValues(values)
    }
}

public actor FileProfilePreviewStore: ProfilePreviewStore {
    private let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func loadThumbnail(for profileID: ConnectionProfile.ID) async throws -> ProfilePreviewThumbnail? {
        let fileURL = fileURL(for: profileID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }

        let thumbnail = try JSONDecoder().decode(ProfilePreviewThumbnail.self, from: data)
        return thumbnail.isRenderable ? thumbnail : nil
    }

    public func saveThumbnail(
        _ thumbnail: ProfilePreviewThumbnail,
        for profileID: ConnectionProfile.ID
    ) async throws {
        guard thumbnail.isRenderable else {
            return
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        FileBackupExclusion.excludeFromBackupBestEffort(directoryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(thumbnail)
        try data.write(to: fileURL(for: profileID), options: [.atomic])
    }

    public func deleteThumbnail(for profileID: ConnectionProfile.ID) async throws {
        let fileURL = fileURL(for: profileID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for profileID: ConnectionProfile.ID) -> URL {
        directoryURL
            .appendingPathComponent(profileID.uuidString, isDirectory: false)
            .appendingPathExtension("json")
    }
}
