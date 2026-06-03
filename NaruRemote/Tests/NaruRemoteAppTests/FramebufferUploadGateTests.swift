import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

final class FramebufferUploadGateTests: XCTestCase {
    func testSkipsSameFramebufferAndDirtyRectangles() {
        var gate = FramebufferUploadGate()
        let framebuffer = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let dirtyRectangles = [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)]

        XCTAssertTrue(gate.shouldEnqueue(framebuffer: framebuffer, dirtyRectangles: dirtyRectangles))
        XCTAssertFalse(gate.shouldEnqueue(framebuffer: framebuffer, dirtyRectangles: dirtyRectangles))
    }

    func testEnqueuesWhenDirtyRectanglesChange() {
        var gate = FramebufferUploadGate()
        let framebuffer = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )

        XCTAssertTrue(gate.shouldEnqueue(framebuffer: framebuffer))
        XCTAssertTrue(
            gate.shouldEnqueue(
                framebuffer: framebuffer,
                dirtyRectangles: [RFBFrameDamageRect(x: 0, y: 0, width: 1, height: 1)]
            )
        )
    }

    func testEnqueuesNewFramebufferWithSameDimensions() {
        var gate = FramebufferUploadGate()
        let first = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        let second = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 11, green: 20, blue: 30)
        )

        XCTAssertTrue(gate.shouldEnqueue(framebuffer: first))
        XCTAssertTrue(gate.shouldEnqueue(framebuffer: second))
    }

    func testResetAllowsSameFramebufferAgain() {
        var gate = FramebufferUploadGate()
        let framebuffer = RFBRawFramebuffer(
            width: 4,
            height: 4,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )

        XCTAssertTrue(gate.shouldEnqueue(framebuffer: framebuffer))
        XCTAssertFalse(gate.shouldEnqueue(framebuffer: framebuffer))

        gate.reset()

        XCTAssertTrue(gate.shouldEnqueue(framebuffer: framebuffer))
    }
}
