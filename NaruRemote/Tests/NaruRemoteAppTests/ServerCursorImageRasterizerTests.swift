import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class ServerCursorImageRasterizerTests: XCTestCase {
    func testRasterizerPreservesRGBAOrderAndTransparency() throws {
        let cursor = RFBServerCursor(
            width: 2,
            height: 2,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: [
                RFBColor(red: 10, green: 20, blue: 30, alpha: 255),
                RFBColor(red: 40, green: 50, blue: 60, alpha: 128),
                RFBColor(red: 70, green: 80, blue: 90, alpha: 0),
                RFBColor(red: 100, green: 110, blue: 120, alpha: 255)
            ]
        )

        let raster = try XCTUnwrap(ServerCursorImageRasterizer.rasterize(cursor))

        XCTAssertEqual(raster.width, 2)
        XCTAssertEqual(raster.height, 2)
        XCTAssertEqual(
            raster.rgbaBytes,
            [
                10, 20, 30, 255,
                40, 50, 60, 128,
                0, 0, 0, 0,
                100, 110, 120, 255
            ]
        )
    }

    func testRasterizerRejectsEmptyCursor() {
        let cursor = RFBServerCursor(
            width: 0,
            height: 2,
            hotSpotX: 0,
            hotSpotY: 0,
            pixels: []
        )

        XCTAssertNil(ServerCursorImageRasterizer.rasterize(cursor))
    }
}
