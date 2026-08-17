import Foundation
import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// Spec 012 US2 — strip hold-repeat envelope, one-tap ⌃C path, and
/// IME/pending-insert flush barrier at the app-model boundary.
@MainActor
final class StripCompletionsModelTests: XCTestCase {

    // MARK: - Armed consume on repeat (US2-1)

    func testRepeatEmissionsConsumeArmedStickyOnlyOnFirstFire() async throws {
        let connector = StripCompletionsConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(connector: connector, helper: nil, helperReachable: false)

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)

        await model.sendAccessoryKey(.arrowUp)
        try await waitFor {
            connector.recordedKeyEvents.contains { $0.keysym == KeysymMapping.keysym(for: .up) }
        }
        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .idle,
            "First repeatable emission consumes armed Control."
        )

        let controlCountAfterFirst = connector.recordedKeyEvents.filter {
            $0.keysym == KeysymMapping.keysym(for: .controlLeft)
        }.count

        await model.sendAccessoryKey(.arrowUp)
        try await waitFor {
            connector.recordedKeyEvents.filter { $0.keysym == KeysymMapping.keysym(for: .up) }.count >= 4
        }

        let controlCountAfterSecond = connector.recordedKeyEvents.filter {
            $0.keysym == KeysymMapping.keysym(for: .controlLeft)
        }.count
        XCTAssertEqual(
            controlCountAfterFirst,
            2,
            "First fire wraps Ctrl down/up."
        )
        XCTAssertEqual(
            controlCountAfterSecond,
            controlCountAfterFirst,
            "Repeat 2+ must not re-wrap the already-consumed armed modifier."
        )
    }

    // MARK: - ⌃C envelope stays ComposeQuickKey.controlC (US2-2)

    func testComposeQuickKeyControlCEmitsFixedChordIndependentOfSticky() async throws {
        let connector = StripCompletionsConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(connector: connector, helper: nil, helperReachable: false)

        await model.tapDirectKey(.modifier(.shift))
        XCTAssertEqual(model.stickyModifierState.slot(for: .shift), .armed)

        await model.sendComposeQuickKey(.controlC)
        try await waitFor {
            connector.recordedKeyEvents.contains { $0.keysym == 0x63 }
        }

        let downs = connector.recordedKeyEvents.filter(\.isDown).map(\.keysym)
        XCTAssertTrue(downs.contains(KeysymMapping.keysym(for: .controlLeft)))
        XCTAssertTrue(downs.contains(0x63))
        XCTAssertFalse(
            downs.contains(KeysymMapping.keysym(for: .shiftLeft)),
            "⌃C must not read sticky modifiers."
        )
        XCTAssertEqual(
            model.stickyModifierState.slot(for: .shift),
            .armed,
            "⌃C must not consume sticky state."
        )
    }

    // MARK: - Flush barrier (US2-3)

    func testKeyLaneInsertIsEnqueuedBeforeStripKeysym() async throws {
        let connector = StripCompletionsConnector(
            width: 80,
            height: 60,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let model = try await makeConnectedModel(connector: connector, helper: nil, helperReachable: false)
        model.setRemoteInputDockMode(.live)

        model.liveCommit(committedText: "가", hasMarkedText: false)
        await model.sendAccessoryKey(.escape)

        try await waitFor {
            connector.recordedKeyEvents.contains { $0.keysym == 0xFF1B }
                && connector.recordedKeyEvents.contains { $0.keysym == 0x0100_AC00 }
        }

        let downKeysyms = connector.recordedKeyEvents.filter(\.isDown).map(\.keysym)
        let hangulIndex = downKeysyms.firstIndex(of: 0x0100_AC00) ?? .max
        let escapeIndex = downKeysyms.firstIndex(of: 0xFF1B) ?? .min
        XCTAssertLessThan(hangulIndex, escapeIndex, "Committed insert must precede the strip keysym")
        XCTAssertNotEqual(hangulIndex, .max)
        XCTAssertNotEqual(escapeIndex, .min)
    }

    func testPendingHelperInsertSucceedsThenStripKeyEmits() async throws {
        let helper = StripCompletionsHelper(delayNanoseconds: 80_000_000)
        let connector = StripCompletionsConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )
        model.setRemoteInputDockMode(.live)

        let escapeWhenInsertFired = OSAllocatedUnfairLock(initialState: 0)
        helper.onInsert.withLock { hook in
            hook = { _ in
                let count = connector.recordedKeyEvents.filter { $0.keysym == 0xFF1B }.count
                escapeWhenInsertFired.withLock { $0 = count }
            }
        }

        model.liveCommit(committedText: "안녕", hasMarkedText: false)
        await model.sendAccessoryKey(.escape)
        try await waitFor { connector.recordedKeyEvents.contains { $0.keysym == 0xFF1B } }

        XCTAssertEqual(helper.insertedTexts, ["안녕"])
        XCTAssertEqual(
            escapeWhenInsertFired.withLock { $0 },
            0,
            "Strip keysym must not leave the wire before the pending insert starts"
        )
        XCTAssertTrue(connector.recordedKeyEvents.contains { $0.keysym == 0xFF1B })
    }

    func testFlushFailureDropsStripKeyAndLeavesStickyArmed() async throws {
        let helper = StripCompletionsHelper(
            result: HelperTextInsertResult(
                requestID: UUID(),
                strategyUsed: .nativeInsert,
                status: .failed,
                safeFailureCode: .focusUnavailable
            ),
            delayNanoseconds: 80_000_000
        )
        let connector = StripCompletionsConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )
        model.setRemoteInputDockMode(.live)

        await model.tapDirectKey(.modifier(.control))
        XCTAssertEqual(model.stickyModifierState.slot(for: .control), .armed)

        model.liveCommit(committedText: "안녕", hasMarkedText: false)
        await model.sendAccessoryKey(.escape)
        try await waitFor { model.liveTypeThroughMode.lastStatus == .retainedFailure }

        XCTAssertFalse(
            connector.recordedKeyEvents.contains { $0.keysym == 0xFF1B },
            "Failed flush must not emit the strip keysym"
        )
        XCTAssertEqual(
            model.stickyModifierState.slot(for: .control),
            .armed,
            "Drop keeps existing sticky state."
        )
    }

    func testFlushFailureDropsComposeQuickKey() async throws {
        let helper = StripCompletionsHelper(
            result: HelperTextInsertResult(
                requestID: UUID(),
                strategyUsed: .nativeInsert,
                status: .failed,
                safeFailureCode: .focusUnavailable
            ),
            delayNanoseconds: 80_000_000
        )
        let connector = StripCompletionsConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )
        model.setRemoteInputDockMode(.live)

        model.liveCommit(committedText: "안녕", hasMarkedText: false)
        await model.sendComposeQuickKey(.controlC)
        try await waitFor { model.liveTypeThroughMode.lastStatus == .retainedFailure }

        XCTAssertFalse(
            connector.recordedKeyEvents.contains { $0.keysym == 0x63 },
            "Failed flush must not emit ⌃C"
        )
        XCTAssertTrue(helper.insertedTexts.contains("안녕"))
    }

    // MARK: - Helpers

    private func makeConnectedModel(
        connector: StripCompletionsConnector,
        helper: StripCompletionsHelper?,
        helperReachable: Bool
    ) async throws -> NaruRemoteAppModel {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        var helperState: [ConnectionProfile.ID: HelperTextBridgeProfileState] = [:]
        if helperReachable {
            helperState[profile.id] = HelperTextBridgeProfileState(
                isEnabled: true,
                pairingFingerprint: "sha256:helper-pairing",
                availability: .reachable,
                lastFailureCode: nil,
                lastCheckedBucket: .recent
            )
        }
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(
                profiles: [profile],
                selectedProfileID: profile.id,
                helperTextBridgeState: helperState
            ),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            helperTextInsertClient: helper
        )
        await model.connectSelectedProfile()
        try await waitFor { model.snapshot.session?.state == .active }
        return model
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }
}

// MARK: - Test doubles
// Copied from LiveTypeThroughRoutingTests (latest sibling), including
// the insert-hook and UTF-8 clipboard flags. The doubles there are
// file-private; a second surface needs its own copy.

private final class StripCompletionsHelper: HelperTextInsertClient {
    private struct Recording {
        var requests: [HelperTextInsertRequestMetadata] = []
        var insertedTexts: [String] = []
    }

    private let recording = OSAllocatedUnfairLock(initialState: Recording())
    let availability: HelperTextBridgeAvailability
    private let result: HelperTextInsertResult?
    private let delayNanoseconds: UInt64
    let onInsert: OSAllocatedUnfairLock<(@Sendable (String) -> Void)?> = .init(initialState: nil)

    init(
        availability: HelperTextBridgeAvailability = .reachable,
        result: HelperTextInsertResult? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.availability = availability
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    var insertedTexts: [String] {
        recording.withLock { $0.insertedTexts }
    }

    func insertText(
        _ text: String,
        metadata: HelperTextInsertRequestMetadata
    ) async throws -> HelperTextInsertResult {
        onInsert.withLock { $0 }?(text)
        recording.withLock { state in
            state.requests.append(metadata)
            state.insertedTexts.append(text)
        }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let result {
            return result
        }
        return HelperTextInsertResult(
            requestID: metadata.id,
            strategyUsed: .nativeInsert,
            status: .sent,
            safeFailureCode: .none
        )
    }
}

private final class StripCompletionsConnector: RFBStreamingClient, @unchecked Sendable {
    private struct Recording {
        var framebuffers: [RFBRawFramebuffer]
        var keyEvents: [(keysym: UInt32, isDown: Bool)] = []
        var clipboardPayloads: [String] = []
        var pasteCommands: [PasteCommand] = []
        var requestedFrameCount = 0
    }

    private let recording: OSAllocatedUnfairLock<Recording>
    private let width: Int
    private let height: Int
    private let name: String
    let utf8ClipboardSupport: RemoteClipboardUTF8Support

    init(
        width: Int,
        height: Int,
        name: String,
        utf8ClipboardSupport: RemoteClipboardUTF8Support = .unknown
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.utf8ClipboardSupport = utf8ClipboardSupport
        let framebuffer = RFBRawFramebuffer(
            width: width,
            height: height,
            fill: RFBColor(red: 10, green: 20, blue: 30)
        )
        self.recording = OSAllocatedUnfairLock(
            initialState: Recording(framebuffers: [framebuffer, framebuffer, framebuffer])
        )
    }

    var recordedKeyEvents: [(keysym: UInt32, isDown: Bool)] {
        recording.withLock { $0.keyEvents }
    }

    var state: RFBClientState { .receivingFrames }

    var lastFrame: RFBFrameMetadata? {
        RFBFrameMetadata(width: width, height: height)
    }

    func connectNoAuthFirstFrame(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectFirstFrame(host: String, port: UInt16, credential: RFBConnectionCredential, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: credential, timeout: timeout)
    }

    func connectNoAuthSession(host: String, port: UInt16, timeout: TimeInterval) throws -> RFBServerInit {
        try connectSession(host: host, port: port, credential: .none, timeout: timeout)
    }

    func connectSession(host: String, port: UInt16, credential: RFBConnectionCredential, timeout: TimeInterval) throws -> RFBServerInit {
        RFBServerInit(
            width: width,
            height: height,
            pixelFormat: RFBPixelFormat(
                bitsPerPixel: 32,
                depth: 24,
                isBigEndian: false,
                isTrueColor: true,
                redMax: 255,
                greenMax: 255,
                blueMax: 255,
                redShift: 16,
                greenShift: 8,
                blueShift: 0
            ),
            name: name
        )
    }

    func requestRawFramebufferUpdate(incremental: Bool, timeout: TimeInterval) throws -> RFBRawFramebuffer {
        let framebuffer = recording.withLock { state -> RFBRawFramebuffer? in
            state.requestedFrameCount += 1
            return state.framebuffers.isEmpty ? nil : state.framebuffers.removeFirst()
        }
        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return framebuffer
    }

    func setClipboardText(_ text: String) throws {
        recording.withLock { $0.clipboardPayloads.append(text) }
    }

    func sendPasteCommand(_ command: PasteCommand) throws {
        recording.withLock { $0.pasteCommands.append(command) }
    }

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {}

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        recording.withLock { $0.keyEvents.append((keysym, isDown)) }
    }
}
