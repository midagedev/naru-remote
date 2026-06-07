import Foundation
import NaruRemoteCore

public struct ServerCursorImageRaster: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgbaBytes: [UInt8]

    public init(width: Int, height: Int, rgbaBytes: [UInt8]) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        self.rgbaBytes = rgbaBytes
    }
}

enum ServerCursorImageRasterizer {
    static func rasterize(_ cursor: RFBServerCursor) -> ServerCursorImageRaster? {
        guard cursor.width > 0,
              cursor.height > 0,
              cursor.width <= Int.max / cursor.height,
              cursor.width * cursor.height <= Int.max / 4
        else {
            return nil
        }

        var bytes = [UInt8](
            repeating: 0,
            count: cursor.width * cursor.height * 4
        )
        for y in 0..<cursor.height {
            for x in 0..<cursor.width {
                guard let color = cursor[x, y], color.alpha > 0 else {
                    continue
                }
                let offset = ((y * cursor.width) + x) * 4
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
                bytes[offset + 3] = color.alpha
            }
        }

        return ServerCursorImageRaster(
            width: cursor.width,
            height: cursor.height,
            rgbaBytes: bytes
        )
    }
}
