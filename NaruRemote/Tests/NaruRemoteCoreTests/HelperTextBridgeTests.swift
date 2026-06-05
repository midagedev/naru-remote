import XCTest
@testable import NaruRemoteCore

final class HelperTextBridgeTests: XCTestCase {
    func testHelperFailureCodesUseStableDiagnosticCatalogValues() {
        XCTAssertEqual(HelperTextBridgeFailureCode.none.rawValue, "none")
        XCTAssertEqual(HelperTextBridgeFailureCode.notConfigured.rawValue, "helper.notConfigured")
        XCTAssertEqual(HelperTextBridgeFailureCode.permissionMissing.rawValue, "helper.permissionMissing")
        XCTAssertEqual(HelperTextBridgeFailureCode.restoreFailed.rawValue, "helper.restoreFailed")
    }

    func testPayloadSizeBucketUsesCoarseNonExactRanges() {
        XCTAssertEqual(HelperTextPayloadSizeBucket.bucket(utf8ByteCount: -1), .empty)
        XCTAssertEqual(HelperTextPayloadSizeBucket.bucket(utf8ByteCount: 0), .empty)
        XCTAssertEqual(HelperTextPayloadSizeBucket.bucket(utf8ByteCount: 256), .small)
        XCTAssertEqual(HelperTextPayloadSizeBucket.bucket(utf8ByteCount: 257), .medium)
        XCTAssertEqual(HelperTextPayloadSizeBucket.bucket(utf8ByteCount: 4_096), .medium)
        XCTAssertEqual(HelperTextPayloadSizeBucket.bucket(utf8ByteCount: 4_097), .large)
    }

    func testInsertRequestMetadataDoesNotStoreRawText() throws {
        let sessionID = UUID()
        let requestID = UUID()
        let metadata = HelperTextInsertRequestMetadata(
            id: requestID,
            sessionID: sessionID,
            payloadEncoding: .utf8ExtensionRequired,
            payloadSizeBucket: .small
        )

        let data = try JSONEncoder().encode(metadata)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains(requestID.uuidString.uppercased()) || json.contains(requestID.uuidString.lowercased()))
        XCTAssertFalse(json.contains("text"))
        XCTAssertFalse(json.contains("한글"))
        XCTAssertFalse(json.contains("emoji"))
    }

    func testHelperTextBridgePathUsesStableDiagnosticValue() {
        XCTAssertEqual(TextInjectionPath.helperTextBridge.rawValue, "helperTextBridge")
    }

    func testHelperFailureMessagesStaySafeCatalogOnly() {
        XCTAssertEqual(
            HelperTextBridgeError.safeMessage(for: .permissionMissing),
            "Helper text bridge needs permission on the Mac."
        )
        XCTAssertFalse(
            HelperTextBridgeError.safeMessage(for: .insertRejected)
                .localizedCaseInsensitiveContains("AXError")
        )
    }
}
