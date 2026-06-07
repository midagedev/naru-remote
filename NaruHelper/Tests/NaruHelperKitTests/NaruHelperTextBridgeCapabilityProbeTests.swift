import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperTextBridgeCapabilityProbeTests: XCTestCase {
    func testNativeAndPasteboardCapabilityAdvertisesNativeFirst() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertNatively: true,
            canFallbackToPasteboard: true
        )

        XCTAssertEqual(response.availability, .reachable)
        XCTAssertEqual(response.permissionState.accessibility, "granted")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "available")
        XCTAssertEqual(response.supportedStrategies, [.nativeInsert, .pasteboardPasteWithRestore])
    }

    func testPasteboardOnlyCapabilityDoesNotOverclaimNativeInsert() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertNatively: false,
            canFallbackToPasteboard: true
        )

        XCTAssertEqual(response.availability, .reachable)
        XCTAssertEqual(response.permissionState.accessibility, "missing")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "available")
        XCTAssertEqual(response.supportedStrategies, [.pasteboardPasteWithRestore])
    }

    func testMissingInsertPermissionsReturnFixedPermissionState() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertNatively: false,
            canFallbackToPasteboard: false
        )

        XCTAssertEqual(response.availability, .permissionMissing)
        XCTAssertEqual(response.permissionState.accessibility, "missing")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "missing")
        XCTAssertEqual(response.supportedStrategies, [])
    }

    func testUnsupportedPlatformDoesNotAdvertiseStrategies() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            platformSupported: false,
            canInsertNatively: true,
            canFallbackToPasteboard: true
        )

        XCTAssertEqual(response.availability, .versionUnsupported)
        XCTAssertEqual(response.permissionState.accessibility, "unsupported")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "unsupported")
        XCTAssertEqual(response.permissionState.activeUserSession, "unsupported")
        XCTAssertEqual(response.supportedStrategies, [])
    }
}
