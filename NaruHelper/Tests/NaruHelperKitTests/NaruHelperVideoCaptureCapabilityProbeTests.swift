import XCTest
import NaruHelperKit
import NaruRemoteCore

final class NaruHelperVideoCaptureCapabilityProbeTests: XCTestCase {
    func testGrantedScreenRecordingAndAvailableContentReportsAvailable() async throws {
        let probe = NaruHelperVideoCaptureCapabilityProbe(
            permissionProvider: { .granted },
            captureSourceProvider: { .available }
        )

        let response = await probe.capability()

        XCTAssertEqual(response.schemaVersion, naruHelperVideoCapabilitySchemaVersion)
        XCTAssertEqual(response.availability, .available)
        XCTAssertEqual(response.screenRecordingPermission, .granted)
        XCTAssertEqual(response.captureSourceState, .available)
        XCTAssertEqual(response.captureAPI, .screenCaptureKit)
        XCTAssertNil(response.safeFailureCode)
    }

    func testMissingScreenRecordingPermissionDoesNotProbeShareableContent() async throws {
        let recorder = CaptureSourceProbeRecorder(result: .available)
        let probe = NaruHelperVideoCaptureCapabilityProbe(
            permissionProvider: { .missing },
            captureSourceProvider: {
                await recorder.captureSourceState()
            }
        )

        let response = await probe.capability()

        XCTAssertEqual(response.availability, .permissionMissing)
        XCTAssertEqual(response.screenRecordingPermission, .missing)
        XCTAssertEqual(response.captureSourceState, .notChecked)
        XCTAssertEqual(response.captureAPI, .screenCaptureKit)
        XCTAssertEqual(response.safeFailureCode, .permissionMissing)
        let callCount = await recorder.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testUnsupportedPlatformUsesUnsupportedCatalogWithoutCaptureAPI() async throws {
        let probe = NaruHelperVideoCaptureCapabilityProbe(
            captureAPI: nil,
            permissionProvider: { .unsupported },
            captureSourceProvider: { .unsupported }
        )

        let response = await probe.capability()

        XCTAssertEqual(response.availability, .failed)
        XCTAssertEqual(response.screenRecordingPermission, .unsupported)
        XCTAssertEqual(response.captureSourceState, .unsupported)
        XCTAssertNil(response.captureAPI)
        XCTAssertNil(response.safeFailureCode)
    }

    func testGrantedPermissionWithUnavailableContentReportsSafeFailure() async throws {
        let probe = NaruHelperVideoCaptureCapabilityProbe(
            permissionProvider: { .granted },
            captureSourceProvider: { .unavailable }
        )

        let response = await probe.capability()

        XCTAssertEqual(response.availability, .failed)
        XCTAssertEqual(response.screenRecordingPermission, .granted)
        XCTAssertEqual(response.captureSourceState, .unavailable)
        XCTAssertEqual(response.captureAPI, .screenCaptureKit)
        XCTAssertNil(response.safeFailureCode)
    }

    func testCapabilityJSONUsesOnlyFixedCatalogValues() async throws {
        let response = NaruHelperVideoCaptureCapabilityResponse(
            availability: .permissionMissing,
            screenRecordingPermission: .missing,
            captureSourceState: .notChecked,
            captureAPI: .screenCaptureKit,
            safeFailureCode: .permissionMissing
        )

        let json = String(data: try JSONEncoder().encode(response), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"availability\":\"permissionMissing\""))
        XCTAssertTrue(json.contains("\"screenRecordingPermission\":\"missing\""))
        XCTAssertTrue(json.contains("\"captureSourceState\":\"notChecked\""))
        XCTAssertTrue(json.contains("\"captureAPI\":\"screenCaptureKit\""))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("displayID"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("dimension"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("endpoint"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("host"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("byte"))
    }
}

private actor CaptureSourceProbeRecorder {
    private let result: NaruHelperVideoCaptureSourceState
    private var count = 0

    init(result: NaruHelperVideoCaptureSourceState) {
        self.result = result
    }

    var callCount: Int {
        count
    }

    func captureSourceState() -> NaruHelperVideoCaptureSourceState {
        count += 1
        return result
    }
}
