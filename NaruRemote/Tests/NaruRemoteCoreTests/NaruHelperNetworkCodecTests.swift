import XCTest
import NaruRemoteCore

final class NaruHelperNetworkCodecTests: XCTestCase {
    func testFramedNetworkRequestRoundTripsThroughLengthPrefixedJSON() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let insertRequest = NaruHelperInsertTextRequest(
            requestID: requestID,
            payloadEncoding: .utf8ExtensionRequired,
            payloadSizeBucket: .small,
            text: "한글과 English"
        )
        let request = NaruHelperNetworkRequest(
            requestID: requestID,
            command: .insertText,
            pairingSecret: "secret",
            insertRequest: insertRequest
        )

        let frame = try NaruHelperNetworkCodec.frame(request)
        let header = frame.prefix(NaruHelperNetworkCodec.headerByteCount)
        let payload = frame.dropFirst(NaruHelperNetworkCodec.headerByteCount)

        XCTAssertEqual(try NaruHelperNetworkCodec.payloadLength(from: Data(header)), payload.count)
        XCTAssertEqual(
            try NaruHelperNetworkCodec.decode(NaruHelperNetworkRequest.self, from: Data(payload)),
            request
        )
    }

    func testZeroLengthFrameIsRejected() throws {
        XCTAssertThrowsError(
            try NaruHelperNetworkCodec.payloadLength(from: Data([0, 0, 0, 0]))
        ) { error in
            XCTAssertEqual(error as? NaruHelperNetworkCodecError, .oversizedFrame)
        }
    }
}
