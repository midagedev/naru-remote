import FakeRFBServerKit
import Foundation
import NaruRemoteCore
import XCTest

final class FakeRFBServerIntegrationTests: XCTestCase {
    func testNetworkedFakeServerServesNoAuthFirstFrameTranscript() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let server = try FakeRFBServer(transcript: transcript)
        let port = try server.start()
        defer { server.stop() }

        let received = try FakeRFBProbeClient.readTranscript(
            port: port,
            expectedByteCount: transcript.bytes.count
        )

        let version = try RFBProtocolDecoder.parseVersion(received[safe: 0..<12])
        let securityTypes = try RFBProtocolDecoder.parseSecurityTypes(received[safe: 12..<14])
        let securityResult = received[safe: 14..<18]
        let serverInit = try RFBProtocolDecoder.parseServerInit(received[safe: 18..<46])
        let framebufferUpdate = try RFBProtocolDecoder.parseFramebufferUpdateHeader(received[safe: 46..<62])

        try RFBProtocolDecoder.parseSecurityResult(securityResult)

        XCTAssertEqual(version, RFBProtocolVersion(major: 3, minor: 8))
        XCTAssertTrue(securityTypes.supportsNone)
        XCTAssertEqual(serverInit.frameMetadata().width, 1024)
        XCTAssertEqual(serverInit.frameMetadata().height, 768)
        XCTAssertEqual(framebufferUpdate.firstUpdatedRectangle?.encodingType, 0)
    }

    func testProductionRFBNetworkClientUpdatesBoundaryStateFromFakeServer() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let server = try FakeRFBServer(transcript: transcript)
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()

        let serverInit = try client.connectNoAuthTranscript(
            host: "127.0.0.1",
            port: port,
            expectedByteCount: transcript.bytes.count
        )

        XCTAssertEqual(serverInit.name, "Desk")
        XCTAssertEqual(client.state, .receivingFrames)
        XCTAssertEqual(client.lastFrame?.width, 1024)
        XCTAssertEqual(client.lastFrame?.height, 768)
    }

    func testProductionRFBNetworkClientCompletesInteractiveNoAuthFirstFrameHandshake() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let server = try FakeRFBServer(transcript: transcript, mode: .noAuthHandshake)
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()

        let serverInit = try client.connectNoAuthFirstFrame(
            host: "127.0.0.1",
            port: port
        )

        XCTAssertEqual(serverInit.name, "Desk")
        XCTAssertEqual(client.state, .receivingFrames)
        XCTAssertEqual(client.lastFrame?.width, 1024)
        XCTAssertEqual(client.lastFrame?.height, 768)
    }

    func testProductionRFBNetworkClientSendsClipboardAndPasteMessagesAfterInteractiveHandshake() throws {
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

        try client.setClipboardText("한글과 English 😊")
        try client.sendPasteCommand(.controlV)

        let expectedMessages = RFBClientMessageEncoder.clientCutText("한글과 English 😊") +
            RFBClientMessageEncoder.pasteCommand(.controlV)
        let receivedMessages = try recorder.waitForByteCount(expectedMessages.count)

        XCTAssertTrue(receivedMessages.starts(with: expectedMessages))
    }

    func testProductionRFBNetworkClientRequestsAndDecodesRepeatedRawFramebufferUpdates() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([
                Self.rawTwoByTwoUpdateData(),
                Self.secondRawTwoByTwoUpdateData()
            ])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        let serverInit = try client.connectNoAuthSession(host: "127.0.0.1", port: port)

        XCTAssertEqual(serverInit.width, 2)
        XCTAssertEqual(serverInit.height, 2)
        XCTAssertEqual(client.state, .authenticated)
        XCTAssertNil(client.lastFrame)

        let firstFrame = try client.requestRawFramebufferUpdate()

        XCTAssertEqual(firstFrame[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(firstFrame[1, 0], RFBColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(firstFrame[0, 1], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(firstFrame[1, 1], RFBColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(client.state, .receivingFrames)
        XCTAssertEqual(client.lastFrame?.width, 2)
        XCTAssertEqual(client.lastFrame?.height, 2)

        let secondFrame = try client.requestRawFramebufferUpdate(incremental: true)

        XCTAssertEqual(secondFrame[0, 0], RFBColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(secondFrame[1, 0], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(secondFrame[0, 1], RFBColor(red: 0, green: 255, blue: 0))
        XCTAssertEqual(secondFrame[1, 1], RFBColor(red: 255, green: 0, blue: 0))
    }

    func testProductionRFBNetworkClientCompositesIncrementalRawFramebufferUpdate() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([
                Self.rawTwoByTwoUpdateData(),
                Self.singleBluePixelUpdateData(x: 1, y: 0)
            ])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)
        _ = try client.requestRawFramebufferUpdate()
        let secondFrame = try client.requestRawFramebufferUpdate(incremental: true)

        XCTAssertEqual(secondFrame[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(secondFrame[1, 0], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(secondFrame[0, 1], RFBColor(red: 0, green: 0, blue: 255))
        XCTAssertEqual(secondFrame[1, 1], RFBColor(red: 255, green: 255, blue: 255))
    }

    func testProductionRFBNetworkClientReportsFramebufferDamageMetadata() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthFramebufferUpdates([
                Self.rawTwoByTwoUpdateData(),
                Self.singleBluePixelUpdateData(x: 1, y: 0)
            ])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)
        _ = try client.requestFramebufferUpdate()
        let secondResult = try client.requestFramebufferUpdate(incremental: true)

        XCTAssertEqual(secondResult.dirtyRectangles, [
            RFBFrameDamageRect(x: 1, y: 0, width: 1, height: 1)
        ])
        XCTAssertEqual(secondResult.changedPixelCount, 1)
        XCTAssertEqual(secondResult.changeActivity, .high)
    }

    func testProductionRFBNetworkClientCompletesVNCAuthenticationSession() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let challenge = Data(hex: "00112233445566778899aabbccddeeff")
        let expectedResponse = try RFBVNCAuthentication.response(password: "secret", challenge: challenge)
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .vncAuthentication(
                challenge: challenge,
                expectedResponse: expectedResponse,
                securityResult: 0,
                frameUpdates: [Self.rawTwoByTwoUpdateData()]
            )
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        let serverInit = try client.connectSession(
            host: "127.0.0.1",
            port: port,
            credential: .vncPassword("secret")
        )

        XCTAssertEqual(serverInit.width, 2)
        XCTAssertEqual(serverInit.height, 2)
        XCTAssertEqual(client.state, .authenticated)

        let frame = try client.requestRawFramebufferUpdate()

        XCTAssertEqual(frame[0, 0], RFBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(frame[1, 1], RFBColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(client.state, .receivingFrames)
    }

    func testProductionRFBNetworkClientReportsAuthenticationRequiredWithoutPassword() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let challenge = Data(hex: "00112233445566778899aabbccddeeff")
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .vncAuthentication(
                challenge: challenge,
                expectedResponse: Data(),
                securityResult: 0,
                frameUpdates: nil
            )
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()

        XCTAssertThrowsError(
            try client.connectSession(
                host: "127.0.0.1",
                port: port,
                credential: .none
            )
        ) { error in
            XCTAssertEqual(error as? RFBNetworkClientError, .authenticationRequired([2]))
        }

        XCTAssertEqual(client.state, .failed)
        XCTAssertNil(client.lastFrame)
    }

    func testProductionRFBNetworkClientFailsRejectedVNCPassword() throws {
        let transcript = FakeRFBTranscript(bytes: Self.noAuthTranscript(width: 2, height: 2))
        let challenge = Data(hex: "00112233445566778899aabbccddeeff")
        let expectedResponse = try RFBVNCAuthentication.response(password: "correct", challenge: challenge)
        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .vncAuthentication(
                challenge: challenge,
                expectedResponse: expectedResponse,
                securityResult: 0,
                frameUpdates: nil
            )
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()

        XCTAssertThrowsError(
            try client.connectSession(
                host: "127.0.0.1",
                port: port,
                credential: .vncPassword("wrong")
            )
        ) { error in
            XCTAssertEqual(error as? RFBProtocolDecoderError, .securityFailed(1))
        }

        XCTAssertEqual(client.state, .failed)
        XCTAssertNil(client.lastFrame)
    }

    func testProductionRFBNetworkClientClearsLastFrameAfterFailedReconnect() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let firstServer = try FakeRFBServer(transcript: transcript)
        let firstPort = try firstServer.start()
        defer { firstServer.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthTranscript(
            host: "127.0.0.1",
            port: firstPort,
            expectedByteCount: transcript.bytes.count
        )
        XCTAssertNotNil(client.lastFrame)

        var unsupportedSecurityBytes = transcript.bytes
        unsupportedSecurityBytes[13] = 2
        let unsupportedSecurityTranscript = FakeRFBTranscript(bytes: unsupportedSecurityBytes)
        let secondServer = try FakeRFBServer(transcript: unsupportedSecurityTranscript)
        let secondPort = try secondServer.start()
        defer { secondServer.stop() }

        XCTAssertThrowsError(
            try client.connectNoAuthTranscript(
                host: "127.0.0.1",
                port: secondPort,
                expectedByteCount: unsupportedSecurityTranscript.bytes.count
            )
        ) { error in
            XCTAssertEqual(error as? RFBNetworkClientError, .unsupportedSecurityTypes([2]))
        }

        XCTAssertEqual(client.state, .failed)
        XCTAssertNil(client.lastFrame)
    }

    func testProductionRFBNetworkClientReceivesServerCutTextWithCJKPayload() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("serv-cuttext-utf8"))
        // Handshake bytes occupy 0..<46; everything after is the ServerCutText
        // message that the fake server pushes after the no-auth handshake.
        let handshakeByteCount = 46
        let serverCutTextBytes = transcript.bytes.subdata(in: handshakeByteCount..<transcript.bytes.count)

        let server = try FakeRFBServer(
            transcript: transcript,
            mode: .noAuthServerMessages([serverCutTextBytes])
        )
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()
        try client.connectNoAuthSession(host: "127.0.0.1", port: port)

        let received = try client.receiveServerCutText(timeout: 2)
        XCTAssertEqual(received, "안녕 클립보드")
    }

    func testProductionRFBNetworkClientRejectsShortTranscriptWithoutTrapping() throws {
        let transcript = try FakeRFBTranscript.loadHexFile(at: Self.fixtureURL("noauth-first-frame"))
        let shortTranscript = FakeRFBTranscript(bytes: transcript.bytes.prefix(18))
        let server = try FakeRFBServer(transcript: shortTranscript)
        let port = try server.start()
        defer { server.stop() }

        let client = RFBNetworkClient()

        XCTAssertThrowsError(
            try client.connectNoAuthTranscript(
                host: "127.0.0.1",
                port: port,
                expectedByteCount: shortTranscript.bytes.count
            )
        ) { error in
            XCTAssertEqual(
                error as? RFBNetworkClientError,
                .incompleteTranscript(expected: 62, actual: shortTranscript.bytes.count)
            )
        }

        XCTAssertEqual(client.state, .failed)
        XCTAssertNil(client.lastFrame)
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

    private static func noAuthTranscript(width: Int, height: Int) -> Data {
        var bytes = Data("RFB 003.008\n".utf8)
        bytes.append(contentsOf: [1, 1])
        bytes.append(contentsOf: [0, 0, 0, 0])
        bytes.append(contentsOf: uint16Bytes(UInt16(width)))
        bytes.append(contentsOf: uint16Bytes(UInt16(height)))
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

    private static func rawTwoByTwoUpdateData() -> Data {
        Data([
            0, 0, 0, 1,
            0, 0, 0, 0, 0, 2, 0, 2,
            0, 0, 0, 0,
            0, 0, 255, 0,
            0, 255, 0, 0,
            255, 0, 0, 0,
            255, 255, 255, 0
        ])
    }

    private static func secondRawTwoByTwoUpdateData() -> Data {
        Data([
            0, 0, 0, 1,
            0, 0, 0, 0, 0, 2, 0, 2,
            0, 0, 0, 0,
            255, 255, 255, 0,
            255, 0, 0, 0,
            0, 255, 0, 0,
            0, 0, 255, 0
        ])
    }

    private static func singleBluePixelUpdateData(x: UInt16, y: UInt16) -> Data {
        Data([
            0, 0, 0, 1,
            UInt8(x >> 8), UInt8(x & 0x00ff),
            UInt8(y >> 8), UInt8(y & 0x00ff),
            0, 1,
            0, 1,
            0, 0, 0, 0,
            255, 0, 0, 0
        ])
    }

    private static func uint16Bytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0x00ff)]
    }
}

private extension Data {
    init(hex: String) {
        let bytes = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }

        self.init(bytes)
    }

    subscript(safe range: Range<Int>) -> Data {
        precondition(range.lowerBound >= 0)
        precondition(range.upperBound <= count)

        return subdata(in: range)
    }
}
