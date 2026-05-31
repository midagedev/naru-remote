import FakeRFBServerKit
import Foundation
import NaruRemoteCore
import XCTest

/// End-to-end negotiation + variable-length encoding decode against the
/// fake server, driving the production `RFBNetworkClient` over a real
/// localhost socket (spec 004 Increment 1, SC-001 / SC-004).
final class FakeRFBServerEncodingTests: XCTestCase {
    // MARK: - SetEncodings negotiation (SC-004)

    func testClientSendsWellFormedSetEncodingsAfterHandshake() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let recorder = FakeRFBClientMessageRecorder()
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthHandshake,
            clientMessageRecorder: recorder
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthFirstFrame(host: "127.0.0.1", port: port)

        let control = try recorder.waitForControlMessages(1)
        let message = [UInt8](control[0])

        // message type 2, padding 0, u16 count, then count × s32.
        XCTAssertEqual(message[0], 2)
        XCTAssertEqual(message[1], 0)
        let count = Int(message[2]) << 8 | Int(message[3])
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(message.count, 4 + count * 4)

        var encodings: [Int32] = []
        for index in 0..<count {
            let offset = 4 + index * 4
            let value = UInt32(message[offset]) << 24
                | UInt32(message[offset + 1]) << 16
                | UInt32(message[offset + 2]) << 8
                | UInt32(message[offset + 3])
            encodings.append(Int32(bitPattern: value))
        }

        let hextileIndex = encodings.firstIndex(of: RFBEncoding.hextile)
        let copyRectIndex = encodings.firstIndex(of: RFBEncoding.copyRect)
        let rawIndex = encodings.firstIndex(of: RFBEncoding.raw)
        XCTAssertNotNil(rawIndex, "Raw must always be advertised as the floor")
        XCTAssertNotNil(hextileIndex)
        XCTAssertNotNil(copyRectIndex)
        XCTAssertLessThan(hextileIndex!, rawIndex!)
        XCTAssertLessThan(copyRectIndex!, rawIndex!)
    }

    // MARK: - CopyRect decode end-to-end (SC-001)

    func testClientDecodesCopyRectUpdateFromServer() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 4, height: 2))
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([
                Self.rawFourByTwoFirstFrame(),
                Self.copyRowZeroToRowOneUpdate()
            ])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)

        _ = try client.requestRawFramebufferUpdate()
        let second = try client.requestRawFramebufferUpdate(incremental: true)

        // Row 0 (red, green, blue, white) was copied down onto row 1.
        XCTAssertEqual(second[0, 1], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(second[1, 1], RFBColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(second[2, 1], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(second[3, 1], RFBColor(red: 255, green: 255, blue: 255))
    }

    // MARK: - Hextile decode end-to-end (SC-002)

    func testClientDecodesHextileUpdateFromServer() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([
                Self.hextileRawTileTwoByTwoUpdate()
            ])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)

        let frame = try client.requestRawFramebufferUpdate()
        XCTAssertEqual(frame[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(frame[1, 0], RFBColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(frame[0, 1], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(frame[1, 1], RFBColor(red: 255, green: 255, blue: 255))
    }

    // MARK: - Fixtures

    private static func rawFourByTwoFirstFrame() -> Data {
        var bytes: [UInt8] = [0, 0, 0, 1] // FramebufferUpdate, one rectangle
        bytes += rectangleHeader(x: 0, y: 0, width: 4, height: 2, encoding: 0)
        // row0 coloured, row1 black
        for color in [red, green, blue, white, black, black, black, black] {
            bytes += pixelBytes(color)
        }
        return Data(bytes)
    }

    private static func copyRowZeroToRowOneUpdate() -> Data {
        var bytes: [UInt8] = [0, 0, 0, 1]
        bytes += rectangleHeader(x: 0, y: 1, width: 4, height: 1, encoding: 1) // CopyRect
        bytes += [0, 0, 0, 0] // src (0, 0)
        return Data(bytes)
    }

    private static func hextileRawTileTwoByTwoUpdate() -> Data {
        var bytes: [UInt8] = [0, 0, 0, 1]
        bytes += rectangleHeader(x: 0, y: 0, width: 2, height: 2, encoding: 5) // Hextile
        bytes += [0x01] // single Raw tile
        for color in [red, green, blue, white] {
            bytes += pixelBytes(color)
        }
        return Data(bytes)
    }

    // MARK: - Colours / byte helpers

    private static let red = RFBColor(red: 255, green: 0, blue: 0)
    private static let green = RFBColor(red: 0, green: 255, blue: 0)
    private static let blue = RFBColor(red: 0, green: 0, blue: 255)
    private static let white = RFBColor(red: 255, green: 255, blue: 255)
    private static let black = RFBColor(red: 0, green: 0, blue: 0)

    private static func pixelBytes(_ color: RFBColor) -> [UInt8] {
        [color.blue, color.green, color.red, 0]
    }

    private static func rectangleHeader(x: Int, y: Int, width: Int, height: Int, encoding: Int32) -> [UInt8] {
        var bytes: [UInt8] = [
            UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF),
            UInt8((y >> 8) & 0xFF), UInt8(y & 0xFF),
            UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF),
            UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF)
        ]
        let unsigned = UInt32(bitPattern: encoding)
        bytes += [
            UInt8((unsigned >> 24) & 0xFF),
            UInt8((unsigned >> 16) & 0xFF),
            UInt8((unsigned >> 8) & 0xFF),
            UInt8(unsigned & 0xFF)
        ]
        return bytes
    }

    private static func noAuthTranscript(width: Int, height: Int) -> Data {
        var bytes = Data("RFB 003.008\n".utf8)
        bytes.append(contentsOf: [1, 1])
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: [UInt8(width >> 8), UInt8(width & 0xFF)])
        bytes.append(contentsOf: [UInt8(height >> 8), UInt8(height & 0xFF)])
        bytes.append(
            contentsOf: [
                32, 24, 0, 1,
                0, 255, 0, 255, 0, 255,
                16, 8, 0,
                0, 0, 0
            ]
        )
        bytes.append(contentsOf: [0, 0, 0, 4])
        bytes.append(Data("Desk".utf8))
        return bytes
    }

    private static func fixtureURL(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            root.deleteLastPathComponent()
        }
        return root
            .appendingPathComponent("TestFixtures/FakeRFBServer/Fixtures")
            .appendingPathComponent("\(name).hex")
    }
}
