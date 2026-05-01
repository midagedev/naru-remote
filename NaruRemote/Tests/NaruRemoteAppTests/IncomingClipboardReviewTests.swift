import XCTest
import NaruRemoteCore
@testable import NaruRemoteApp

@MainActor
final class IncomingClipboardReviewTests: XCTestCase {
    func testRecordIncomingClipboardSetsPendingReview() throws {
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(localClipboardWriter: writer)

        XCTAssertNil(model.pendingIncomingClipboard)

        model.recordIncomingClipboard("hello from remote")

        let review = try XCTUnwrap(model.pendingIncomingClipboard)
        XCTAssertEqual(review.text, "hello from remote")
        XCTAssertEqual(review.previewText, "hello from remote")
        XCTAssertTrue(writer.writes.isEmpty)
    }

    func testRecordIncomingClipboardTruncatesPreviewToCharacterLimit() throws {
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(localClipboardWriter: writer)
        let longBody = String(repeating: "가", count: 200)

        model.recordIncomingClipboard(longBody)

        let review = try XCTUnwrap(model.pendingIncomingClipboard)
        XCTAssertEqual(review.text, longBody)
        XCTAssertEqual(review.previewText.count, IncomingClipboardReview.previewCharacterLimit + 1)
        XCTAssertTrue(review.previewText.hasSuffix("\u{2026}"))
    }

    func testRecordIncomingClipboardIgnoresEmptyPayload() {
        let model = NaruRemoteAppModel(localClipboardWriter: RecordingClipboardWriter())

        model.recordIncomingClipboard("")

        XCTAssertNil(model.pendingIncomingClipboard)
    }

    func testAcceptIncomingClipboardWritesFullTextAndClearsPending() {
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(localClipboardWriter: writer)
        let longBody = String(repeating: "Z", count: 500)

        model.recordIncomingClipboard(longBody)
        model.acceptIncomingClipboard()

        XCTAssertEqual(writer.writes, [longBody])
        XCTAssertNil(model.pendingIncomingClipboard)
    }

    func testAcceptIncomingClipboardIsNoopWhenNoPendingReview() {
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(localClipboardWriter: writer)

        model.acceptIncomingClipboard()

        XCTAssertTrue(writer.writes.isEmpty)
        XCTAssertNil(model.pendingIncomingClipboard)
    }

    func testDismissIncomingClipboardClearsPendingWithoutWriting() {
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(localClipboardWriter: writer)

        model.recordIncomingClipboard("review me")
        model.dismissIncomingClipboard()

        XCTAssertNil(model.pendingIncomingClipboard)
        XCTAssertTrue(writer.writes.isEmpty)
    }

    func testProfileChangeClearsPendingReviewWithoutWriting() throws {
        let first = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let second = try ConnectionProfile(displayName: "Laptop", host: "laptop.tailnet.ts.net")
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [first, second], selectedProfileID: first.id),
            localClipboardWriter: writer
        )

        model.recordIncomingClipboard("mid-review text")
        XCTAssertNotNil(model.pendingIncomingClipboard)

        model.selectProfile(id: second.id)

        XCTAssertNil(model.pendingIncomingClipboard)
        XCTAssertTrue(writer.writes.isEmpty)
    }

    func testNewIncomingClipboardReplacesEarlierPendingReview() throws {
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(localClipboardWriter: writer)

        model.recordIncomingClipboard("first")
        model.recordIncomingClipboard("second")

        let review = try XCTUnwrap(model.pendingIncomingClipboard)
        XCTAssertEqual(review.text, "second")
        XCTAssertTrue(writer.writes.isEmpty)
    }

    func testStreamingConnectorTriggersReceiveLoopAndRecordsPending() async throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let framebuffer = RFBRawFramebuffer(width: 1, height: 1, fill: RFBColor(red: 10, green: 0, blue: 0))
        let connector = ReceivingStreamingConnector(
            width: 1,
            height: 1,
            name: "Desk",
            framebuffers: [framebuffer],
            incomingPayloads: ["copied from remote"]
        )
        let writer = RecordingClipboardWriter()
        let model = NaruRemoteAppModel(
            snapshot: NaruRemoteAppSnapshot(profiles: [profile], selectedProfileID: profile.id),
            frameStreamConfiguration: RFBFramePumpConfiguration(maxFrames: 1, frameInterval: 0),
            connectorFactory: { connector },
            localClipboardWriter: writer
        )

        model.connectSelectedProfile()

        try await waitFor(model.pendingIncomingClipboard != nil, timeoutMillis: 500) {
            model.pendingIncomingClipboard != nil
        }

        let review = try XCTUnwrap(model.pendingIncomingClipboard)
        XCTAssertEqual(review.text, "copied from remote")
        XCTAssertTrue(writer.writes.isEmpty)
    }

    func testDiagnosticExportIsUnaffectedByIncomingClipboardEvent() throws {
        let profile = try ConnectionProfile(displayName: "Desk", host: "desk.tailnet.ts.net")
        let snapshot = NaruRemoteAppSnapshot(
            profiles: [profile],
            selectedProfileID: profile.id,
            diagnosticRun: ConnectionDiagnosticRun(
                profileID: profile.id,
                finishedAt: Date(timeIntervalSince1970: 1),
                stages: [
                    DiagnosticStageResult(
                        stage: .firstFrame,
                        status: .passed,
                        safeTitle: "First frame received",
                        safeDetail: "1x1 remote framebuffer is available."
                    )
                ]
            )
        )
        let model = NaruRemoteAppModel(
            snapshot: snapshot,
            localClipboardWriter: RecordingClipboardWriter()
        )

        let runBefore = try XCTUnwrap(model.snapshot.diagnosticRun)
        let summaryBefore = DiagnosticExport(run: runBefore, detailLevel: .stageSummary).summary

        // Run the entire OUT-direction lifecycle: receive, accept,
        // and a second-receive-and-dismiss.  None of this should
        // alter the diagnostic run summary, which is the only
        // export surface that ever leaves the device.
        model.recordIncomingClipboard("secret remote text")
        model.acceptIncomingClipboard()
        model.recordIncomingClipboard("another remote text")
        model.dismissIncomingClipboard()

        let runAfter = try XCTUnwrap(model.snapshot.diagnosticRun)
        let summaryAfter = DiagnosticExport(run: runAfter, detailLevel: .stageSummary).summary

        XCTAssertEqual(summaryBefore, summaryAfter)
        XCTAssertFalse(summaryAfter.contains("secret remote text"))
        XCTAssertFalse(summaryAfter.contains("another remote text"))
    }

    private func waitFor(
        _ initial: @autoclosure () -> Bool,
        timeoutMillis: Int,
        check: () -> Bool
    ) async throws {
        if initial() {
            return
        }
        let stepMillis = 10
        var elapsed = 0
        while elapsed < timeoutMillis {
            try await Task.sleep(for: .milliseconds(stepMillis))
            elapsed += stepMillis
            if check() {
                return
            }
        }
    }
}

private final class RecordingClipboardWriter: LocalClipboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedWrites: [String] = []

    init() {}

    var writes: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedWrites
    }

    func write(_ text: String) {
        lock.lock()
        recordedWrites.append(text)
        lock.unlock()
    }
}

private final class ReceivingStreamingConnector: RFBStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private let width: Int
    private let height: Int
    private let name: String
    private var framebuffers: [RFBRawFramebuffer]
    private var pendingIncomingPayloads: [String]

    init(
        width: Int,
        height: Int,
        name: String,
        framebuffers: [RFBRawFramebuffer],
        incomingPayloads: [String]
    ) {
        self.width = width
        self.height = height
        self.name = name
        self.framebuffers = framebuffers
        self.pendingIncomingPayloads = incomingPayloads
    }

    var state: RFBClientState { .receivingFrames }
    var lastFrame: RFBFrameMetadata? { RFBFrameMetadata(width: width, height: height) }

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
        lock.lock()
        let framebuffer = framebuffers.isEmpty ? nil : framebuffers.removeFirst()
        lock.unlock()

        guard let framebuffer else {
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return framebuffer
    }

    func setClipboardText(_ text: String) throws {}
    func sendPasteCommand(_ command: PasteCommand) throws {}

    func receiveServerCutText(timeout: TimeInterval) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if pendingIncomingPayloads.isEmpty {
            // Stay in the receive loop without producing more payloads.
            // A transient-style error keeps the loop alive but does
            // not advance the test.
            throw RFBNetworkClientError.incompleteTranscript(expected: 1, actual: 0)
        }
        return pendingIncomingPayloads.removeFirst()
    }
}
