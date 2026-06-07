import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperTextBridgeCapabilityProbeTests: XCTestCase {
    func testNativeAndPasteboardCapabilityAdvertisesNativeFirst() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertWithAccessibility: true,
            canInsertWithUnicodeEvents: true,
            canFallbackToPasteboard: true
        )

        XCTAssertEqual(response.availability, .reachable)
        XCTAssertEqual(response.permissionState.accessibility, "granted")
        XCTAssertEqual(response.permissionState.accessibilityValueInsert, "granted")
        XCTAssertEqual(response.permissionState.unicodeKeyboardEvent, "granted")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "available")
        XCTAssertEqual(response.supportedStrategies, [.nativeInsert, .pasteboardPasteWithRestore])
    }

    func testUnicodeEventOnlyCapabilityAdvertisesNativeWithoutOverclaimingAX() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertWithAccessibility: false,
            canInsertWithUnicodeEvents: true,
            canFallbackToPasteboard: false
        )

        XCTAssertEqual(response.availability, .reachable)
        XCTAssertEqual(response.permissionState.accessibility, "missing")
        XCTAssertEqual(response.permissionState.accessibilityValueInsert, "missing")
        XCTAssertEqual(response.permissionState.unicodeKeyboardEvent, "granted")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "missing")
        XCTAssertEqual(response.supportedStrategies, [.nativeInsert])
    }

    func testPasteboardOnlyCapabilityDoesNotOverclaimNativeInsert() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertWithAccessibility: false,
            canInsertWithUnicodeEvents: false,
            canFallbackToPasteboard: true
        )

        XCTAssertEqual(response.availability, .reachable)
        XCTAssertEqual(response.permissionState.accessibility, "missing")
        XCTAssertEqual(response.permissionState.accessibilityValueInsert, "missing")
        XCTAssertEqual(response.permissionState.unicodeKeyboardEvent, "missing")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "available")
        XCTAssertEqual(response.supportedStrategies, [.pasteboardPasteWithRestore])
    }

    func testMissingInsertPermissionsReturnFixedPermissionState() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            canInsertWithAccessibility: false,
            canInsertWithUnicodeEvents: false,
            canFallbackToPasteboard: false
        )

        XCTAssertEqual(response.availability, .permissionMissing)
        XCTAssertEqual(response.permissionState.accessibility, "missing")
        XCTAssertEqual(response.permissionState.accessibilityValueInsert, "missing")
        XCTAssertEqual(response.permissionState.unicodeKeyboardEvent, "missing")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "missing")
        XCTAssertEqual(response.supportedStrategies, [])
    }

    func testUnsupportedPlatformDoesNotAdvertiseStrategies() throws {
        let response = NaruHelperTextBridgeCapabilityProbe.response(
            platformSupported: false,
            canInsertWithAccessibility: true,
            canInsertWithUnicodeEvents: true,
            canFallbackToPasteboard: true
        )

        XCTAssertEqual(response.availability, .versionUnsupported)
        XCTAssertEqual(response.permissionState.accessibility, "unsupported")
        XCTAssertEqual(response.permissionState.accessibilityValueInsert, "unsupported")
        XCTAssertEqual(response.permissionState.unicodeKeyboardEvent, "unsupported")
        XCTAssertEqual(response.permissionState.pasteboardFallback, "unsupported")
        XCTAssertEqual(response.permissionState.activeUserSession, "unsupported")
        XCTAssertEqual(response.supportedStrategies, [])
    }
}
