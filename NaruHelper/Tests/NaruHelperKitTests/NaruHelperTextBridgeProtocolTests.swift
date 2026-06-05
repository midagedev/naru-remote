import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperTextBridgeProtocolTests: XCTestCase {
    func testInsertRequestUsesStableContractKeys() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"))
        let request = NaruHelperInsertTextRequest(
            requestID: requestID,
            payloadEncoding: .utf8ExtensionRequired,
            payloadSizeBucket: .small,
            strategyPreference: [.nativeInsert, .pasteboardPasteWithRestore],
            text: "한글과 English"
        )

        let json = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"schemaVersion\":1"))
        XCTAssertTrue(json.contains("\"requestID\":\"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB\""))
        XCTAssertTrue(json.contains("\"payloadEncoding\":\"utf8ExtensionRequired\""))
        XCTAssertTrue(json.contains("\"payloadSizeBucket\":\"small\""))
        XCTAssertTrue(json.contains("\"strategyPreference\""))
        XCTAssertTrue(json.contains("\"pasteboardPasteWithRestore\""))
    }

    func testInsertResponseNeverContainsRawText() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"))
        let response = NaruHelperInsertTextResponse(
            requestID: requestID,
            status: .sent,
            strategyUsed: .pasteboardPasteWithRestore,
            safeFailureCode: .none
        )

        let json = String(data: try JSONEncoder().encode(response), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"status\":\"sent\""))
        XCTAssertTrue(json.contains("\"strategyUsed\":\"pasteboardPasteWithRestore\""))
        XCTAssertFalse(json.contains("한글"))
        XCTAssertFalse(json.contains("text"))
    }

    func testCapabilityResponseUsesFixedCatalogValues() throws {
        let response = NaruHelperCapabilityResponse(
            availability: .permissionMissing,
            permissionState: NaruHelperPermissionState(
                accessibility: "missing",
                inputMonitoring: "notRequired",
                pasteboardFallback: "available",
                activeUserSession: "available"
            ),
            supportedStrategies: [.pasteboardPasteWithRestore]
        )

        let decoded = try JSONDecoder().decode(
            NaruHelperCapabilityResponse.self,
            from: try JSONEncoder().encode(response)
        )

        XCTAssertEqual(decoded.schemaVersion, naruHelperTextBridgeSchemaVersion)
        XCTAssertEqual(decoded.availability, .permissionMissing)
        XCTAssertEqual(decoded.permissionState.accessibility, "missing")
        XCTAssertEqual(decoded.supportedStrategies, [.pasteboardPasteWithRestore])
    }
}
