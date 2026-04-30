import Foundation
import NaruRemoteCore
import XCTest

final class RFBVNCAuthenticationTests: XCTestCase {
    func testBuildsVNCAuthResponseWithBitReversedDESKey() throws {
        let challenge = Data(hex: "00112233445566778899aabbccddeeff")

        let response = try RFBVNCAuthentication.response(password: "secret", challenge: challenge)

        XCTAssertEqual(response, Data(hex: "f19b50471f60f42298e5c0147db50e1e"))
    }

    func testRejectsInvalidChallengeLength() {
        XCTAssertThrowsError(
            try RFBVNCAuthentication.response(password: "secret", challenge: Data([0, 1, 2]))
        ) { error in
            XCTAssertEqual(error as? RFBVNCAuthenticationError, .invalidChallengeLength(3))
        }
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
}
