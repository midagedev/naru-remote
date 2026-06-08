import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperTextBridgeCapabilityProbeTests: XCTestCase {
    func testTextPermissionRequestGrantedWhenEitherNativePermissionIsGranted() throws {
        let requester = NaruHelperTextPermissionRequester(
            accessibilityPermissionProvider: { false },
            postEventPermissionProvider: { true },
            accessibilityPermissionRequest: { false },
            postEventPermissionRequest: { true },
            permissionIdentityProvider: {
                NaruHelperVideoPermissionIdentityContext(
                    processKind: .appBundle,
                    grantHint: .grantAppBundle
                )
            }
        )

        let response = requester.request()

        XCTAssertEqual(response.schemaVersion, naruHelperTextPermissionRequestSchemaVersion)
        XCTAssertEqual(response.availability, .reachable)
        XCTAssertEqual(response.accessibilityValueInsert, .missing)
        XCTAssertEqual(response.unicodeKeyboardEvent, .granted)
        XCTAssertEqual(response.pasteboardFallback, .available)
        XCTAssertEqual(response.requestResult, .granted)
        XCTAssertEqual(response.permissionIdentity.processKind, .appBundle)
        XCTAssertEqual(response.permissionIdentity.grantHint, .grantAppBundle)
        XCTAssertNil(response.safeFailureCode)
    }

    func testTextPermissionRequestMissingReportsSafeCatalogFailure() throws {
        let requester = NaruHelperTextPermissionRequester(
            accessibilityPermissionProvider: { false },
            postEventPermissionProvider: { false },
            accessibilityPermissionRequest: { false },
            postEventPermissionRequest: { false }
        )

        let response = requester.request()

        XCTAssertEqual(response.availability, .permissionMissing)
        XCTAssertEqual(response.accessibilityValueInsert, .missing)
        XCTAssertEqual(response.unicodeKeyboardEvent, .missing)
        XCTAssertEqual(response.pasteboardFallback, .missing)
        XCTAssertEqual(response.requestResult, .notGranted)
        XCTAssertEqual(response.safeFailureCode, .permissionMissing)
    }

    func testUnsupportedTextPermissionRequestUsesCatalogOnly() throws {
        let requester = NaruHelperTextPermissionRequester(
            platformSupported: false,
            accessibilityPermissionProvider: { true },
            postEventPermissionProvider: { true },
            accessibilityPermissionRequest: { true },
            postEventPermissionRequest: { true },
            permissionIdentityProvider: {
                .unsupported
            }
        )

        let response = requester.request()

        XCTAssertEqual(response.availability, .versionUnsupported)
        XCTAssertEqual(response.accessibilityValueInsert, .unsupported)
        XCTAssertEqual(response.unicodeKeyboardEvent, .unsupported)
        XCTAssertEqual(response.pasteboardFallback, .unsupported)
        XCTAssertEqual(response.requestResult, .unsupported)
        XCTAssertEqual(response.permissionIdentity, .unsupported)
        XCTAssertEqual(response.safeFailureCode, .versionUnsupported)
    }

    func testTextPermissionRequestJSONOmitsUnsafeDetails() throws {
        let response = NaruHelperTextPermissionRequestResponse(
            availability: .permissionMissing,
            accessibilityValueInsert: .missing,
            unicodeKeyboardEvent: .missing,
            pasteboardFallback: .missing,
            requestResult: .notGranted,
            permissionIdentity: NaruHelperVideoPermissionIdentityContext(
                processKind: .swiftPMBuildArtifact,
                grantHint: .useStableHelperExecutable
            ),
            safeFailureCode: .permissionMissing
        )

        let json = String(data: try JSONEncoder().encode(response), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"availability\":\"permissionMissing\""))
        XCTAssertTrue(json.contains("\"accessibilityValueInsert\":\"missing\""))
        XCTAssertTrue(json.contains("\"unicodeKeyboardEvent\":\"missing\""))
        XCTAssertTrue(json.contains("\"pasteboardFallback\":\"missing\""))
        XCTAssertTrue(json.contains("\"requestResult\":\"notGranted\""))
        XCTAssertTrue(json.contains("\"processKind\":\"swiftPMBuildArtifact\""))
        XCTAssertTrue(json.contains("\"grantHint\":\"useStableHelperExecutable\""))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("host"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("raw"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("error"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("/Users"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains(".build/debug/NaruHelper"))
    }

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
