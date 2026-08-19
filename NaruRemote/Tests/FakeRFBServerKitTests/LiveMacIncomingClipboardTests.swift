import Foundation
import XCTest
@testable import NaruRemoteCore

/// Does a real macOS Screen Sharing server actually push its clipboard, and
/// does the frame loop keep it?
///
/// Fixtures prove the client handles a `ServerCutText` we wrote ourselves.
/// They cannot prove macOS sends one, or that it sends it in a shape we
/// decode — and "prove RFB/clipboard behavior against a real server before
/// claiming compatibility" is the repo rule for exactly this reason. So this
/// copies a unique string on the host, pumps frames, and asks the client what
/// it received.
///
/// Skipped unless `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` are set. It
/// writes to the host's pasteboard and restores the previous contents.
final class LiveMacIncomingClipboardTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    func testCopyingOnTheMacReachesTheClientThroughTheFrameLoop() throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live clipboard probe")
        }

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let timeout: TimeInterval = 5
        _ = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: timeout
        )
        _ = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

        // Drain anything the server volunteered on connect so the assertion
        // below is about the copy this test performs.
        _ = client.takeIncomingClipboardText()

        let previousPasteboard = Self.readPasteboard()
        defer {
            if let previousPasteboard {
                Self.writePasteboard(previousPasteboard)
            }
        }

        // A marker, not user content: nothing here is logged or exported.
        let marker = "naru-live-clipboard-\(UUID().uuidString.prefix(8))"
        Self.writePasteboard(marker)

        var received: String?
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, received == nil {
            _ = try? client.requestFramebufferUpdate(incremental: true, timeout: 1)
            received = client.takeIncomingClipboardText()
        }

        // Recorded, not required. Measured 2026-08-19 on macOS Screen Sharing:
        // the server sends **no** ServerCutText at all — not the text, not even
        // the extended-clipboard caps message — while the host's pasteboard
        // changes during a live session. So remote→local clipboard is a
        // server-capability question, and on the product's primary target the
        // answer is currently no. The client side is proven separately by
        // `testServerCutTextArrivingBetweenFramesIsKeptAndDoesNotDisturbTheFrame`,
        // which is what a server that does send one will hit.
        print(
            received == nil
                ? "Live clipboard probe: the server pushed no clipboard during the session"
                : "Live clipboard probe: received a server clipboard message"
        )
        if let received {
            XCTAssertEqual(
                received,
                marker,
                "A server that pushes its clipboard must deliver what was copied, intact"
            )
        }

        // Whatever the server chose to do, the session must still be healthy —
        // that is the part a regression here would break.
        let afterwards = try client.requestFramebufferUpdate(incremental: true, timeout: 2)
        XCTAssertGreaterThan(afterwards.framebuffer.width, 0)
    }

    // MARK: - Helpers

    private static func readPasteboard() -> String? {
        run("/usr/bin/pbpaste", arguments: [])
    }

    private static func writePasteboard(_ text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let input = Pipe()
        process.standardInput = input
        try? process.run()
        input.fileHandleForWriting.write(Data(text.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    @discardableResult
    private static func run(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
