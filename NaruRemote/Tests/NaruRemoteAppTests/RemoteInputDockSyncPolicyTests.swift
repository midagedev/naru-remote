import XCTest
@testable import NaruRemoteApp

final class RemoteInputDockSyncPolicyTests: XCTestCase {
    func testAppliesIdenticalExternalText() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "hello",
                lastAppliedInitialText: "hello",
                currentText: "hello",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testDefersNonEmptyExternalTextWhileMarkedTextIsActive() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "old snapshot",
                lastAppliedInitialText: "prior",
                currentText: "한글 조합",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testDefersNonEmptyExternalTextWhileFocusedLocalDraftHasText() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "server echo",
                lastAppliedInitialText: "prior",
                currentText: "local edit",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: false
            )
        )
    }

    func testDefersExternalClearWhileMarkedTextIsActive() {
        XCTAssertFalse(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "",
                lastAppliedInitialText: "sent text",
                currentText: "한글",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }

    func testAppliesExternalClearWhenNoMarkedTextIsActive() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "",
                lastAppliedInitialText: "sent text",
                currentText: "sent text",
                isDirectModeActive: false,
                isComposeFieldFocused: true,
                hasMarkedText: false
            )
        )
    }

    func testAppliesExternalTextWhenEditorIsNotFocused() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "restored draft",
                lastAppliedInitialText: "prior",
                currentText: "prior",
                isDirectModeActive: false,
                isComposeFieldFocused: false,
                hasMarkedText: false
            )
        )
    }

    func testDirectModeAlwaysAllowsModelDrivenSync() {
        XCTAssertTrue(
            RemoteInputDockView.shouldApplyExternalComposeText(
                newValue: "model value",
                lastAppliedInitialText: "prior",
                currentText: "local edit",
                isDirectModeActive: true,
                isComposeFieldFocused: true,
                hasMarkedText: true
            )
        )
    }
}
