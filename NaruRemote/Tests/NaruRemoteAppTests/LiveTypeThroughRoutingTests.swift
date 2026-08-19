import Foundation
import os
import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

/// App-model routing tests for Live type-through mode (spec 009, tasks T013).
///
/// These prove the app-model adapter-ladder wiring against fakes: the primary
/// helper `nativeInsert` path, the disclosed chunked-clipboard fallback, the
/// ASCII last resort / retain-honestly behaviour, delete-as-`BackSpace`, the
/// `Return` line boundary + seal, pointer-interaction sealing, and diagnostic
/// privacy. The pure window/diff/coalesce/seal logic is covered separately by
/// `LiveEditingWindowTests` in `NaruRemoteCoreTests`.
@MainActor
final class LiveTypeThroughRoutingTests: XCTestCase {

    // MARK: - (a) Helper primary — per-commit nativeInsert only

    func testHelperTierDeliversPerCommitNativeInsertAndNoVNCWrites() async throws {
        let helper = LiveRoutingHelper()
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)
        XCTAssertEqual(model.remoteInputDockMode, .live)

        // Marked (composing) text never crosses the boundary (FR-002).
        model.liveCommit(committedText: "", hasMarkedText: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(helper.insertedTexts.isEmpty, "Marked text must not be delivered")

        // Committed Korean unit flows through the helper as it commits.
        model.liveCommit(committedText: "안녕", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["안녕"] }

        // A second committed unit delivers only the new delta.
        model.liveCommit(committedText: "안녕하세요", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["안녕", "하세요"] }

        XCTAssertTrue(connector.clipboardPayloads.isEmpty, "Helper path must not touch the VNC clipboard")
        XCTAssertTrue(connector.pasteCommands.isEmpty)
        XCTAssertTrue(connector.recordedKeyEvents.isEmpty, "No Unicode KeyEvent on the helper path (FR-005)")
        XCTAssertEqual(model.liveTypeThroughMode.selectedTier, .helperNativeInsert)
        XCTAssertEqual(model.liveTypeThroughMode.lastStatus, .deliveredObserved)
    }

    // MARK: - (b) No helper + UTF-8 clipboard → disclosed chunked clipboard

    func testClipboardTierDeliversASCIIAndKoreanWithDisclosure() async throws {
        let connector = LiveRoutingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            utf8ClipboardSupport: .supported
        )
        let model = try await makeConnectedModel(
            connector: connector,
            helper: nil,
            helperReachable: false
        )

        model.setRemoteInputDockMode(.live)

        model.liveCommit(committedText: "hi 가", hasMarkedText: false)
        try await waitFor { connector.clipboardPayloads == ["hi 가"] }
        try await waitFor { connector.pasteCommands.count == 1 }
        try await waitFor { model.liveTypeThroughMode.lastStatus == .unconfirmedClipboard }

        XCTAssertEqual(model.liveTypeThroughMode.selectedTier, .clipboardChunk)
        XCTAssertTrue(connector.recordedKeyEvents.isEmpty, "Unicode must never ride the key lane (FR-005)")
        // Degraded transport is disclosed (D2 / FR-014 / IN-004).
        XCTAssertTrue(model.snapshot.liveTransportDisclosureText.contains("clipboard"))
        XCTAssertTrue(model.snapshot.liveTransportDisclosureText.contains("overwritten"))
    }

    // MARK: - (c) No helper + no confirmed clipboard → Unicode-keysym stream

    func testUnicodeWithNoConfirmedTransportIsRetainedNotGarbageKeysyms() async throws {
        let connector = LiveRoutingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let model = try await makeConnectedModel(
            connector: connector,
            helper: nil,
            helperReachable: false
        )

        model.setRemoteInputDockMode(.live)

        model.liveCommit(committedText: "가나다", hasMarkedText: false)
        try await waitFor {
            connector.recordedKeyEvents.count >= 6
        }

        // Spec 011 / constitution §I (2026-08-17): with neither a helper nor a
        // confirmed UTF-8 clipboard, Korean rides the X11 Unicode-keysym
        // stream — live-measured 2026-07-13 to render on macOS Screen Sharing.
        // Each syllable emits a down/up pair with keysym 0x01000000 | scalar.
        let expectedKeysyms: [UInt32] = ["가", "나", "다"].map {
            0x0100_0000 | UInt32($0.unicodeScalars.first!.value)
        }
        let downKeysyms = connector.recordedKeyEvents.filter(\.isDown).map(\.keysym)
        XCTAssertEqual(downKeysyms, expectedKeysyms, "Korean must ride the Unicode-keysym stream (down/up per syllable)")
        XCTAssertTrue(connector.clipboardPayloads.isEmpty, "The keysym stream must not touch the clipboard")
        XCTAssertEqual(model.liveTypeThroughMode.selectedTier, .keyEvent)
        XCTAssertEqual(model.liveTypeThroughMode.lastStatus, .asciiLastResort)
        XCTAssertEqual(model.liveFieldText, "가나다")
    }

    // MARK: - (d) Backspace → BackSpace key events; Return → Return + seal

    func testBackspaceEmitsBackSpaceKeyEventsAndReturnSealsWindow() async throws {
        let helper = LiveRoutingHelper()
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)

        // Type "hte" → helper insert; then backspace once (⌫ action button).
        model.liveCommit(committedText: "hte", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["hte"] }

        model.liveDeleteBackward()
        try await waitFor { connector.recordedKeyEvents.contains { $0.keysym == 0xFF08 } }

        // One BackSpace grapheme → down + up.
        let backspaceEvents = connector.recordedKeyEvents.filter { $0.keysym == 0xFF08 }
        XCTAssertEqual(backspaceEvents.map { $0.isDown }, [true, false])
        XCTAssertEqual(model.liveFieldText, "ht")

        // Retype and press Return (↵ action button) → Return key + seal.
        model.liveCommit(committedText: "hte", hasMarkedText: false)
        try await waitFor { helper.insertedTexts.contains("e") }

        model.liveNewline()
        try await waitFor { connector.recordedKeyEvents.contains { $0.keysym == 0xFF0D } }
        let returnEvents = connector.recordedKeyEvents.filter { $0.keysym == 0xFF0D }
        XCTAssertEqual(returnEvents.map { $0.isDown }, [true, false])
        // Fresh window: the line cleared for the next one (FR-010).
        XCTAssertEqual(model.liveFieldText, "")
        XCTAssertNil(model.liveTypeThroughMode.selectedTier)
    }

    // MARK: - (e) Pointer interaction seals; later backspace does not cross the seal

    func testPointerInteractionSealsWindowAndBackspaceDoesNotCrossSeal() async throws {
        let helper = LiveRoutingHelper()
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)
        model.liveCommit(committedText: "hello", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["hello"] }

        // A tap could move the remote cursor → seal (FR-011).
        model.sendTapAt(viewPoint: CGPoint(x: 40, y: 30), viewSize: CGSize(width: 80, height: 60))
        XCTAssertEqual(model.liveTypeThroughMode.lastSealReason, .pointerInteraction)

        let keyEventsBefore = connector.recordedKeyEvents.count
        // A backspace after the seal is clamped: no delete crosses into the
        // previously delivered "hello" (FR-011 / SC-004).
        model.liveDeleteBackward()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(connector.recordedKeyEvents.count, keyEventsBefore, "No BackSpace may cross the seal")
        XCTAssertTrue(model.liveReachedWindowStart)
    }

    // MARK: - (f) Diagnostics carry only fixed catalog values — no typed content

    func testDiagnosticExportContainsNoTypedLiveContent() async throws {
        let helper = LiveRoutingHelper()
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)
        model.liveCommit(committedText: "비밀문장", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["비밀문장"] }

        let json = model.makeDiagnosticExport().renderCollectionJSON(
            buildVersion: "test",
            now: Date(timeIntervalSince1970: 1_714_521_600)
        )
        XCTAssertFalse(json.contains("비밀문장"), "Diagnostics must never carry typed Live content (SP-005/SC-006)")
    }

    // MARK: - Mode switching preserves Compose draft and seals Live

    func testSwitchingModesPreservesComposeDraftAndSealsLive() async throws {
        let helper = LiveRoutingHelper()
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.updateComposeDraftText("작성 중인 초안")
        model.setRemoteInputDockMode(.live)
        XCTAssertEqual(model.remoteInputDockMode, .live)

        model.liveCommit(committedText: "라이브", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["라이브"] }

        model.setRemoteInputDockMode(.compose)
        XCTAssertEqual(model.remoteInputDockMode, .compose)
        XCTAssertFalse(model.liveTypeThroughMode.isActive)
        // Compose draft survived the round trip (FR-012).
        XCTAssertEqual(model.composeDraft?.text, "작성 중인 초안")
    }

    // MARK: - (g) Insert failure must retain the typed text (FR-015 regression)

    func testHelperInsertFailureRetainsTypedTextInsteadOfDroppingIt() async throws {
        let helper = LiveRoutingHelper(
            result: HelperTextInsertResult(
                requestID: UUID(),
                strategyUsed: .nativeInsert,
                status: .failed,
                safeFailureCode: .focusUnavailable
            )
        )
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)
        model.liveCommit(committedText: "안녕", hasMarkedText: false)
        try await waitFor { model.liveTypeThroughMode.lastStatus == .retainedFailure }

        // The failed chunk must come back into the retained tail — the
        // optimistic dispatch fold may not be trusted on failure (FR-015).
        XCTAssertEqual(model.liveFieldText, "안녕", "Failed insert must be retained, not dropped")
        XCTAssertEqual(model.liveTypeThroughMode.lastSealReason, .adapterFailure)
    }

    // MARK: - (h) Pointer seal racing an in-flight failed insert (FR-011 + FR-015)

    func testPointerSealDuringInFlightFailureStillRetainsAndSurfacesFailure() async throws {
        let helper = LiveRoutingHelper(
            result: HelperTextInsertResult(
                requestID: UUID(),
                strategyUsed: .nativeInsert,
                status: .failed,
                safeFailureCode: .focusUnavailable
            ),
            delayNanoseconds: 200_000_000
        )
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)
        model.liveCommit(committedText: "hello", hasMarkedText: false)
        try await waitFor { !helper.insertedTexts.isEmpty }

        // The user taps while the chunk is still in flight → pointer seal.
        model.sendTapAt(viewPoint: CGPoint(x: 40, y: 30), viewSize: CGSize(width: 80, height: 60))
        XCTAssertEqual(model.liveTypeThroughMode.lastSealReason, .pointerInteraction)

        // When the in-flight chunk then fails, the seal's fold-trusting
        // retention must be corrected and the failure surfaced.
        try await waitFor { model.liveTypeThroughMode.lastStatus == .retainedFailure }
        XCTAssertEqual(model.liveFieldText, "hello", "Chunk that failed mid-seal must be retained")
    }

    // MARK: - (i) Same-batch deletes flush before the async insert fires (FR-007)

    func testSameBatchDeletesFlushBeforeAsyncInsertFires() async throws {
        let helper = LiveRoutingHelper()
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: helper,
            helperReachable: true
        )

        model.setRemoteInputDockMode(.live)
        model.liveCommit(committedText: "abcd", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["abcd"] }

        // A middle edit produces one batch of [deleteBackward(2), insert("X")].
        // The insert must not overtake its deletes across lanes (FR-007).
        let backspaceEventsWhenInsertFired = OSAllocatedUnfairLock(initialState: -1)
        helper.onInsert.withLock { hook in
            hook = { text in
                guard text == "X" else { return }
                let count = connector.recordedKeyEvents.filter { $0.keysym == 0xFF08 }.count
                backspaceEventsWhenInsertFired.withLock { $0 = count }
            }
        }
        model.liveCommit(committedText: "abX", hasMarkedText: false)
        try await waitFor { helper.insertedTexts == ["abcd", "X"] }

        // 2 grapheme deletes → 4 key events (down+up each), all flushed
        // before the helper insert was invoked.
        XCTAssertEqual(
            backspaceEventsWhenInsertFired.withLock { $0 },
            4,
            "Same-batch BackSpaces must reach the wire before the async insert fires"
        )
    }

    // MARK: - Compose & Send default: Korean types through as Unicode keysyms

    func testComposeDefaultTypesKoreanAsUnicodeKeysymsWithoutClipboard() async throws {
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: nil,
            helperReachable: false
        )

        // The product default is keystroke type-through (no helper needed).
        XCTAssertEqual(model.appSettings.composeDelivery, .keystrokeStream)

        model.setRemoteInputDockMode(.compose)
        model.updateComposeDraftText("안녕")
        model.sendComposedTextUsingPreferredDelivery("안녕")

        // 안 = U+C548 → keysym 0x0100C548, 녕 = U+B155 → 0x0100B155
        // (X11 Unicode keysym convention), verified to render on macOS.
        try await waitFor {
            connector.recordedKeyEvents.contains { $0.keysym == 0x0100_C548 } &&
            connector.recordedKeyEvents.contains { $0.keysym == 0x0100_B155 }
        }
        XCTAssertTrue(connector.clipboardPayloads.isEmpty, "Keystroke default must not touch the clipboard")
        XCTAssertTrue(connector.pasteCommands.isEmpty)
    }

    // MARK: - Compose Send submits with Return (spec 015 v1.1 FR-010)

    func testComposeSendSubmittingWithReturnEndsWithAReturnKeypress() async throws {
        let connector = LiveRoutingConnector(width: 80, height: 60, name: "Desk")
        let model = try await makeConnectedModel(
            connector: connector,
            helper: nil,
            helperReachable: false
        )

        model.setRemoteInputDockMode(.compose)
        model.updateComposeDraftText("ls -la")
        model.sendComposedTextUsingPreferredDelivery("ls -la", submittingWithReturn: true)

        // The command types through, then one Return (0xFF0D) runs it — the
        // Send button is the submit, not a second tap on ↵.
        try await waitFor {
            connector.recordedKeyEvents.contains { $0.keysym == 0xFF0D }
        }
        // Each keysym rides as a down/up pair; exactly one Return press, last.
        let downKeysyms = connector.recordedKeyEvents.filter(\.isDown).map(\.keysym)
        XCTAssertEqual(downKeysyms.last, 0xFF0D)
        XCTAssertEqual(downKeysyms.filter { $0 == 0xFF0D }.count, 1)
    }

    func testComposeSubmitPayloadAppendsExactlyOneTrailingReturn() {
        XCTAssertEqual(NaruRemoteAppModel.composeSubmitPayload(for: "ls"), "ls\n")
        XCTAssertEqual(
            NaruRemoteAppModel.composeSubmitPayload(for: "ls\n"),
            "ls\n",
            "A draft the user already ended with a newline must not run twice"
        )
        XCTAssertEqual(
            NaruRemoteAppModel.composeSubmitPayload(for: ""),
            "",
            "An empty draft stays empty so the send paths keep rejecting it"
        )
    }

    // MARK: - Clipboard mode + Korean auto-routes to keystroke (no failure)

    func testClipboardModeKoreanAutoRoutesToKeystrokeInsteadOfFailing() async throws {
        // A server that never negotiated UTF-8 clipboard (macOS Screen
        // Sharing): the clipboard cannot carry Korean, so Compose & Send must
        // route to the keystroke path rather than surfacing a blocking error.
        let connector = LiveRoutingConnector(
            width: 80,
            height: 60,
            name: "Desk",
            utf8ClipboardSupport: .unsupported
        )
        let model = try await makeConnectedModel(
            connector: connector,
            helper: nil,
            helperReachable: false
        )

        model.setComposeDeliveryMode(.clipboardPaste)
        model.setRemoteInputDockMode(.compose)
        model.updateComposeDraftText("안녕")
        model.sendComposedTextUsingPreferredDelivery("안녕")

        try await waitFor {
            connector.recordedKeyEvents.contains { $0.keysym == 0x0100_C548 }
        }
        XCTAssertTrue(
            connector.clipboardPayloads.isEmpty,
            "Clipboard can't carry Korean to this server — must fall back to keystroke, not paste"
        )
        XCTAssertNotEqual(model.composeDraft?.sendState, .failed)
    }

    // MARK: - Helpers

    private func makeConnectedModel(
        connector: LiveRoutingConnector,
        helper: LiveRoutingHelper?,
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

private final class LiveRoutingHelper: HelperTextInsertClient {
    private struct Recording {
        var requests: [HelperTextInsertRequestMetadata] = []
        var insertedTexts: [String] = []
    }

    private let recording = OSAllocatedUnfairLock(initialState: Recording())
    let availability: HelperTextBridgeAvailability
    private let result: HelperTextInsertResult?
    private let delayNanoseconds: UInt64
    /// Invoked at the moment `insertText` is entered — lets ordering tests
    /// observe what already reached other lanes when the insert fired.
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

    var requests: [HelperTextInsertRequestMetadata] {
        recording.withLock { $0.requests }
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

private final class LiveRoutingConnector: RFBStreamingClient, @unchecked Sendable {
    private struct Recording {
        var framebuffers: [RFBRawFramebuffer]
        var keyEvents: [(keysym: UInt32, isDown: Bool)] = []
        var clipboardPayloads: [String] = []
        var pasteCommands: [PasteCommand] = []
        var pointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] = []
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

    var clipboardPayloads: [String] {
        recording.withLock { $0.clipboardPayloads }
    }

    var pasteCommands: [PasteCommand] {
        recording.withLock { $0.pasteCommands }
    }

    var pointerEvents: [(mask: UInt8, x: UInt16, y: UInt16)] {
        recording.withLock { $0.pointerEvents }
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

    func sendPointerEvent(buttonMask: UInt8, x: UInt16, y: UInt16) async throws {
        recording.withLock { $0.pointerEvents.append((buttonMask, x, y)) }
    }

    func sendKeyEvent(keysym: UInt32, isDown: Bool) async throws {
        recording.withLock { $0.keyEvents.append((keysym, isDown)) }
    }
}
