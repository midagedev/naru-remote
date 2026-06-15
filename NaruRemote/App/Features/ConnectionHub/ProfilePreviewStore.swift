import CoreGraphics
import Foundation
import NaruRemoteCore

public struct ProfilePreviewThumbnail: Codable, Equatable, Sendable {
    public static let defaultMaxWidth = 320
    public static let defaultMaxHeight = 200

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
            let clear = RFBColor(red: 0, green: 0, blue: 0, alpha: 0)
            var pixelIndex = 0
            for y in 0..<thumbnailHeight {
                let sourceY = min(
                    framebuffer.height - 1,
                    Int(Double(y) * sourceYScale)
                )
                let sourceRowOffset = sourceY * framebuffer.width
                for x in 0..<thumbnailWidth {
                    let sourceX = min(
                        framebuffer.width - 1,
                        Int(Double(x) * sourceXScale)
                    )
                    let sourceIndex = sourceRowOffset + sourceX
                    Self.write(
                        sourceIndex < sourcePixels.count ? sourcePixels[sourceIndex] : clear,
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
