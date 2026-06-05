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
        let encodings = try Self.decodeSetEncodings(message)

        let zrleIndex = encodings.firstIndex(of: RFBEncoding.zrle)
        let tightIndex = encodings.firstIndex(of: RFBEncoding.tight)
        let hextileIndex = encodings.firstIndex(of: RFBEncoding.hextile)
        let copyRectIndex = encodings.firstIndex(of: RFBEncoding.copyRect)
        let rawIndex = encodings.firstIndex(of: RFBEncoding.raw)
        XCTAssertNotNil(rawIndex, "Raw must always be advertised as the floor")
        XCTAssertNotNil(zrleIndex)
        XCTAssertNil(tightIndex)
        XCTAssertNotNil(hextileIndex)
        XCTAssertNotNil(copyRectIndex)
        XCTAssertTrue(encodings.contains(RFBEncoding.cursor))
        XCTAssertTrue(encodings.contains(RFBEncoding.xCursor))
        XCTAssertTrue(encodings.contains(RFBEncoding.tightCompressionLevel(0)))
        XCTAssertEqual(zrleIndex, 0, "Default app negotiation should favor benchmark-backed ZRLE compression 0")
        XCTAssertLessThan(zrleIndex!, rawIndex!)
        XCTAssertLessThan(hextileIndex!, rawIndex!)
        XCTAssertLessThan(copyRectIndex!, rawIndex!)
    }

    func testClientUsesInjectedEncodingPreferenceForNegotiation() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let recorder = FakeRFBClientMessageRecorder()
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthHandshake,
            clientMessageRecorder: recorder
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient(encodingPreference: .increment1)
        try client.connectNoAuthFirstFrame(host: "127.0.0.1", port: port)

        let encodings = try Self.decodeSetEncodings([UInt8](recorder.waitForControlMessages(1)[0]))
        XCTAssertFalse(encodings.contains(RFBEncoding.zrle))
        XCTAssertEqual(encodings.first, RFBEncoding.hextile)
        XCTAssertTrue(encodings.contains(RFBEncoding.raw))
    }

    func testClientCanRenegotiateEncodingsAfterSessionConnect() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let recorder = FakeRFBClientMessageRecorder()
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([]),
            clientMessageRecorder: recorder
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        _ = try recorder.waitForControlMessages(1)
        XCTAssertFalse(client.canEnableContinuousUpdates)

        let preference = RFBEncodingPreference.adaptive(
            supported: RFBEncodingSupport(zrle: true, fence: true, continuousUpdates: true),
            requestedPseudoEncodings: .withPacingExtensions,
            connectionQuality: .poor
        )
        try client.renegotiateEncodings(preference)
        XCTAssertFalse(client.canEnableContinuousUpdates)

        let expected = RFBClientMessageEncoder.setEncodings(preference.encodingList())
        let recorded = try recorder.waitForByteCount(expected.count)
        XCTAssertEqual(Data(recorded.prefix(expected.count)), expected)

        let encodings = try Self.decodeSetEncodings([UInt8](recorded.prefix(expected.count)))
        XCTAssertEqual(encodings.first, RFBEncoding.zrle)
        XCTAssertTrue(encodings.contains(RFBEncoding.fence))
        XCTAssertTrue(encodings.contains(RFBEncoding.continuousUpdates))
        XCTAssertTrue(encodings.contains(RFBEncoding.tightCompressionLevel(8)))
    }

    func testClientCanRenegotiatePowerSaverSustainedEncodingsAfterSessionConnect() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let recorder = FakeRFBClientMessageRecorder()
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([]),
            clientMessageRecorder: recorder
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        _ = try recorder.waitForControlMessages(1)

        let preference = RFBEncodingPreference.powerSaverSustained
        try client.renegotiateEncodings(preference)

        let expected = RFBClientMessageEncoder.setEncodings(preference.encodingList())
        let recorded = try recorder.waitForByteCount(expected.count)
        XCTAssertEqual(Data(recorded.prefix(expected.count)), expected)

        let encodings = try Self.decodeSetEncodings([UInt8](recorded.prefix(expected.count)))
        XCTAssertEqual(encodings.first, RFBEncoding.zrle)
        XCTAssertTrue(encodings.contains(RFBEncoding.cursor))
        XCTAssertTrue(encodings.contains(RFBEncoding.xCursor))
        XCTAssertTrue(encodings.contains(RFBEncoding.tightCompressionLevel(0)))
        XCTAssertFalse(encodings.contains(RFBEncoding.tight))
        XCTAssertFalse(encodings.contains(RFBEncoding.fence))
        XCTAssertFalse(encodings.contains(RFBEncoding.continuousUpdates))
    }

    func testClientSendsContinuousUpdatesAndFenceControlFramesAfterSessionConnect() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 4, height: 2))
        let recorder = FakeRFBClientMessageRecorder()
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthServerMessages([
                Data([150]),
                Self.rawFourByTwoFirstFrame()
            ]),
            clientMessageRecorder: recorder
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient(encodingPreference: RFBEncodingPreference(continuousUpdates: true))
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        _ = try recorder.waitForControlMessages(1)
        XCTAssertFalse(client.canEnableContinuousUpdates)

        _ = try client.requestFramebufferUpdate()
        XCTAssertTrue(client.canEnableContinuousUpdates)
        _ = try recorder.waitForByteCount(10)

        try client.enableContinuousUpdates(
            true,
            region: RFBFramebufferUpdateRegion(x: 1, y: 2, width: 3, height: 4)
        )
        try client.sendFence(flags: [.request, .syncNext], payload: Data([0x6e, 0x72]))

        var expected = RFBClientMessageEncoder.enableContinuousUpdates(
            true,
            x: 1,
            y: 2,
            width: 3,
            height: 4
        )
        expected.append(try RFBClientMessageEncoder.fence(
            flags: [.request, .syncNext],
            payload: Data([0x6e, 0x72])
        ))

        let recorded = try recorder.waitForByteCount(10 + expected.count)
        XCTAssertEqual(Data(recorded.suffix(expected.count)), expected)
    }

    func testTransportControlThrowsWhenDisconnected() throws {
        let client = RFBNetworkClient()

        XCTAssertThrowsError(try client.renegotiateEncodings(.increment1)) { error in
            XCTAssertEqual(error as? RFBNetworkClientError, .notConnected)
        }
        XCTAssertThrowsError(try client.enableContinuousUpdates(true)) { error in
            XCTAssertEqual(error as? RFBNetworkClientError, .notConnected)
        }
        XCTAssertThrowsError(try client.sendFence(flags: .request)) { error in
            XCTAssertEqual(error as? RFBNetworkClientError, .notConnected)
        }
    }

    func testContinuousUpdatesEnableRequiresServerConfirmation() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let recorder = FakeRFBClientMessageRecorder()
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([]),
            clientMessageRecorder: recorder
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient(encodingPreference: RFBEncodingPreference(continuousUpdates: true))
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        _ = try recorder.waitForControlMessages(1)

        XCTAssertFalse(client.canEnableContinuousUpdates)
        XCTAssertThrowsError(try client.enableContinuousUpdates(true)) { error in
            XCTAssertEqual(error as? RFBNetworkClientError, .continuousUpdatesNotConfirmed)
        }
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

    // MARK: - ZRLE decode end-to-end (Increment 2)

    func testClientDecodesZRLEUpdateFromServer() throws {
        // The production client decodes a real zlib-compressed ZRLE
        // rectangle off the socket using its per-session inflate stream.
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([
                try Self.binFixture("zrle-integration")
            ])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)

        let frame = try client.requestRawFramebufferUpdate()
        for x in 0..<2 {
            for y in 0..<2 {
                XCTAssertEqual(frame[x, y], RFBColor(red: 255, green: 0, blue: 0))
            }
        }
    }

    private static func binFixture(_ name: String) throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            root.deleteLastPathComponent()
        }
        return try Data(contentsOf: root
            .appendingPathComponent("TestFixtures/FakeRFBServer/Fixtures")
            .appendingPathComponent("\(name).bin"))
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

    private static func decodeSetEncodings(_ message: [UInt8]) throws -> [Int32] {
        XCTAssertGreaterThanOrEqual(message.count, 4)
        XCTAssertEqual(message[0], 2)
        XCTAssertEqual(message[1], 0)
        let count = Int(message[2]) << 8 | Int(message[3])
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(message.count, 4 + count * 4)

        return (0..<count).map { index in
            let offset = 4 + index * 4
            let value = UInt32(message[offset]) << 24
                | UInt32(message[offset + 1]) << 16
                | UInt32(message[offset + 2]) << 8
                | UInt32(message[offset + 3])
            return Int32(bitPattern: value)
        }
    }
}
