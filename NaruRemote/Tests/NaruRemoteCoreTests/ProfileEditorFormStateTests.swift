import XCTest
@testable import NaruRemoteCore

final class ProfileEditorFormStateTests: XCTestCase {
    // MARK: - displayNameError

    func testDisplayNameErrorWhenEmpty() {
        let state = ProfileEditorFormState(displayName: "", host: "studio.tailnet.ts.net")
        XCTAssertEqual(state.displayNameError, "Profile name is required.")
    }

    func testDisplayNameErrorWhenWhitespaceOnly() {
        let state = ProfileEditorFormState(displayName: "   \t", host: "studio.tailnet.ts.net")
        XCTAssertEqual(state.displayNameError, "Profile name is required.")
    }

    func testDisplayNameErrorNilWhenFilled() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net")
        XCTAssertNil(state.displayNameError)
    }

    // MARK: - hostError

    func testHostErrorWhenEmpty() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "")
        XCTAssertEqual(state.hostError, "Host is required.")
    }

    func testHostErrorWhenWhitespaceOnly() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "  ")
        XCTAssertEqual(state.hostError, "Host is required.")
    }

    func testHostErrorNilWhenFilled() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net")
        XCTAssertNil(state.hostError)
    }

    // MARK: - portError

    func testPortErrorWhenEmpty() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "")
        XCTAssertEqual(state.portError, "Port is required.")
    }

    func testPortErrorWhenNonNumeric() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "abcd")
        XCTAssertEqual(state.portError, "Port must be a number.")
    }

    func testPortErrorWhenZero() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "0")
        XCTAssertEqual(state.portError, "Port must be between 1 and 65535.")
    }

    func testPortErrorWhenAboveRange() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "70000")
        XCTAssertEqual(state.portError, "Port must be between 1 and 65535.")
    }

    func testPortErrorWhenNegative() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "-1")
        XCTAssertEqual(state.portError, "Port must be between 1 and 65535.")
    }

    func testPortErrorNilWhenInRange() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "5900")
        XCTAssertNil(state.portError)
    }

    func testPortErrorNilAtUpperBoundary() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "65535")
        XCTAssertNil(state.portError)
    }

    func testPortErrorNilAtLowerBoundary() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "1")
        XCTAssertNil(state.portError)
    }

    // MARK: - helperPortError

    func testHelperPortErrorNilWhenHelperDisabled() {
        let state = ProfileEditorFormState(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            helperTextBridgeEnabled: false,
            helperPort: "not-a-port"
        )
        XCTAssertNil(state.helperPortError)
        XCTAssertTrue(state.isValid)
    }

    func testHelperPortErrorWhenEnabledAndNonNumeric() {
        let state = ProfileEditorFormState(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            helperTextBridgeEnabled: true,
            helperPort: "helper"
        )
        XCTAssertEqual(state.helperPortError, "Helper port must be a number.")
        XCTAssertFalse(state.isValid)
    }

    func testHelperPortParsesWhenEnabled() {
        let state = ProfileEditorFormState(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            helperTextBridgeEnabled: true,
            helperPort: "5974"
        )
        XCTAssertNil(state.helperPortError)
        XCTAssertEqual(state.parsedHelperPort, 5974)
    }

    // MARK: - isValid

    func testIsValidFalseWhenNameEmpty() {
        let state = ProfileEditorFormState(displayName: "", host: "studio.tailnet.ts.net", port: "5900")
        XCTAssertFalse(state.isValid)
    }

    func testIsValidFalseWhenHostEmpty() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "", port: "5900")
        XCTAssertFalse(state.isValid)
    }

    func testIsValidFalseWhenPortInvalid() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "0")
        XCTAssertFalse(state.isValid)
    }

    func testIsValidFalseOnFreshDefault() {
        // Default-init mirrors the "user just opened the editor" paint:
        // empty name + empty host with the canonical 5900 default port.
        // Save MUST stay disabled until the user fills in fields.
        let state = ProfileEditorFormState()
        XCTAssertFalse(state.isValid)
    }

    func testIsValidTrueWhenAllFieldsFilled() {
        let state = ProfileEditorFormState(
            displayName: "Studio",
            host: "studio.tailnet.ts.net",
            port: "5900"
        )
        XCTAssertTrue(state.isValid)
    }

    // MARK: - parsedPort

    func testParsedPortWhenValid() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "5901")
        XCTAssertEqual(state.parsedPort, 5901)
    }

    func testParsedPortNilWhenOutOfRange() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "0")
        XCTAssertNil(state.parsedPort)
    }

    func testParsedPortNilWhenNonNumeric() {
        let state = ProfileEditorFormState(displayName: "Studio", host: "studio.tailnet.ts.net", port: "vnc")
        XCTAssertNil(state.parsedPort)
    }
}
