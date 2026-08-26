import CoreGraphics
import Foundation
import XCTest
@testable import NaruRemoteCore

/// Does a VNC scroll-wheel event actually scroll the real Mac?
///
/// The founder reported (2026-08-26) that scrolling does not work and asked for
/// a gesture that does it — two-finger drag. Reading the code says the whole
/// path already exists: a two-touch `UIPanGestureRecognizer` in
/// `MetalFramebufferInputOverlayView` feeds `NaruRemoteAppModel.sendScrollAt`,
/// which turns accumulated motion into discrete RFB wheel clicks (RFC 6143
/// §7.5.5 bits 3..6). So "it doesn't scroll" has two possible halves, and code
/// reading cannot tell them apart:
///
/// 1. the **gesture** never reaches `sendScrollAt` (another recognizer — zoom,
///    local pan — claims the finger pair), or
/// 2. the **wheel event** reaches the server and the server does nothing with
///    it.
///
/// This probe answers (2) only, against a real macOS Screen Sharing server,
/// because that is the half that would make every client-side fix pointless.
/// It is deliberately a *permanent* probe rather than a scratch script: the
/// same question comes back every time a pointer-lane change lands.
///
/// ## Reading the result
///
/// The measurement is a **control against a treatment**, because an idle
/// desktop can repaint on its own (a clock, a notification) and a sleeping one
/// repaints for nothing:
///
/// - control high, treatment high → inconclusive, the desktop is busy
/// - control zero, treatment zero → this machine is not reporting pixels at
///   all (see `NEXT_STEPS.md` 00f, measured the same day), so the probe cannot
///   answer and the machine has to be woken
/// - control zero, treatment above zero → the wheel reaches the server and is
///   acted on: the defect is client-side, in the gesture
///
/// Counts and ratios only — never coordinates or pixels (constitution §IV).
/// Skipped unless `NARU_LIVE_MAC_HOST` / `NARU_LIVE_MAC_PASSWORD` are set. It
/// moves the host machine's real cursor and puts it back afterwards, and it
/// sends real scroll input to whatever is under that point.
final class LiveMacScrollWheelTests: XCTestCase {

    private var host: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_HOST"]
    }

    private var port: UInt16 {
        UInt16(ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PORT"] ?? "5900") ?? 5900
    }

    private var password: String? {
        ProcessInfo.processInfo.environment["NARU_LIVE_MAC_PASSWORD"]
    }

    /// Wheel-down, the way `sendScrollAt` sends it: button-down with the mask,
    /// then button-up at the same point.
    private static let wheelDownMask: UInt8 = 0x10

    func testWheelEventsReachTheServerAndChangeTheScreen() async throws {
        guard let host, let password else {
            throw XCTSkip("Set NARU_LIVE_MAC_HOST + NARU_LIVE_MAC_PASSWORD to run the live scroll probe")
        }
        // Before believing a zero, check the machine can be watched at all
        // (2026-08-26: this probe read 10/10 in the morning and 0/10 in the
        // evening, unchanged, while somebody was using this Mac).
        try LiveMacInputEnvironment.requireAQuietMac()

        let client = RFBNetworkClient()
        defer { client.disconnect() }
        let timeout: TimeInterval = 5
        let serverInit = try client.connectSession(
            host: host,
            port: port,
            credential: .vncPassword(password),
            timeout: timeout
        )
        let firstFrame = try client.requestFramebufferUpdate(incremental: false, timeout: timeout)

        // Is the screen even awake? A first frame that is almost entirely one
        // colour is a sleeping or locked display, and every count below it
        // would read as "the wheel did nothing".
        let uniformity = Self.dominantColourRatio(of: firstFrame)
        print("[scroll-probe] first-frame dominant-colour ratio=\(String(format: "%.3f", uniformity))")

        let originalLocation = Self.currentPointerLocation()
        defer {
            if let originalLocation {
                CGWarpMouseCursorPosition(originalLocation)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }

        // Middle of the screen: whatever window is frontmost is under it, and
        // a wheel event there goes to that window rather than to the Dock or
        // the menu bar.
        let x = UInt16(Double(serverInit.width) * 0.5)
        let y = UInt16(Double(serverInit.height) * 0.5)
        try await client.sendPointerEvent(buttonMask: 0, x: x, y: y)

        // That move is also the oracle. If our own pointer event does not
        // land, nothing this probe sends afterwards is being observed either,
        // and a wheel count of zero would mean "we could not look" rather than
        // "Screen Sharing drops wheel buttons" — the conclusion this probe
        // exists to reach, and the expensive one to reach wrongly.
        let pointsPerPixel = CGFloat(CGDisplayBounds(CGMainDisplayID()).width)
            / CGFloat(max(serverInit.width, 1))
        try LiveMacInputEnvironment.requirePointerToReach(
            CGPoint(x: CGFloat(x) * pointsPerPixel, y: CGFloat(y) * pointsPerPixel),
            tolerance: 6,
            timeout: 3,
            because: "the scroll probe cannot measure this Mac"
        )

        // Drain first, or the measurement is meaningless.
        //
        // Screen Sharing answers one request at a time, and a pointer move
        // provokes a repaint that can arrive several requests later. The first
        // run of this probe read a *control* of 1.7M changed pixels and a
        // treatment of 0 purely from that lag — the control was the cursor
        // move's own repaint and the wheel's answer had not been asked for yet.
        // So: keep asking until the server says nothing changed, and only then
        // start measuring.
        let quietRounds = try await Self.drainUntilQuiet(client)
        print("[scroll-probe] drain rounds=\(quietRounds)")

        // Control: no input at all, same request shape, same wait.
        try await Task.sleep(for: .milliseconds(400))
        let control = try client.requestFramebufferUpdate(incremental: true, timeout: 3)
        print("[scroll-probe] control changedPixelCount=\(control.changedPixelCount)")

        // Treatment: ten wheel-down notches, the way a two-finger drag arrives
        // after crossing the tick threshold ten times.
        //
        // The decisive reading is **not** the pixels. Pixels only change if
        // something scrollable happens to be under that point, and the middle
        // of a desktop is often wallpaper — a wheel event there is delivered
        // and correctly does nothing. So the primary measurement is this
        // machine's own scroll-event counter, read through CoreGraphics: an
        // independent path that says whether the event reached the OS at all,
        // whatever the window under it decides to do about it.
        let scrollEventsBefore = Self.systemScrollEventCount()
        for _ in 0..<10 {
            try await client.sendPointerEvent(buttonMask: Self.wheelDownMask, x: x, y: y)
            try await client.sendPointerEvent(buttonMask: 0, x: x, y: y)
            try await Task.sleep(for: .milliseconds(30))
        }
        let treatment = try client.requestFramebufferUpdate(incremental: true, timeout: 3)
        let scrollEventsAfter = Self.systemScrollEventCount()
        let deliveredScrollEvents = scrollEventsAfter >= scrollEventsBefore
            ? scrollEventsAfter - scrollEventsBefore
            : 0
        print("[scroll-probe] wheel-down changedPixelCount=\(treatment.changedPixelCount)")
        print("[scroll-probe] OS scroll events observed=\(deliveredScrollEvents)")
        print(
            "[scroll-probe] pixels changed more than control: "
                + "\(treatment.changedPixelCount > control.changedPixelCount)"
        )

        XCTAssertGreaterThan(
            deliveredScrollEvents,
            0,
            """
            Ten RFB wheel notches produced no scroll events on this machine \
            (pixels: control=\(control.changedPixelCount), \
            wheel=\(treatment.changedPixelCount); first-frame uniformity=\
            \(String(format: "%.3f", uniformity))). If this holds, macOS Screen \
            Sharing drops RFB wheel buttons and **no client-side gesture can \
            make scrolling work** — the remote needs the helper, and that is a \
            product decision rather than a bug fix.
            """
        )
    }

    /// Scroll-wheel events this login session has seen, from CoreGraphics.
    ///
    /// Deliberately not a pixel measurement and not an event tap: no
    /// permission prompt, no dependence on what is under the cursor, and it
    /// answers the only question that decides where the defect lives — did the
    /// event arrive.
    private static func systemScrollEventCount() -> UInt32 {
        CGEventSource.counterForEventType(.combinedSessionState, eventType: .scrollWheel)
    }

    private static func currentPointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Requests incrementals until the server reports no change, so a later
    /// measurement is answering the input it just sent rather than a repaint
    /// still in the pipe. Returns how many rounds that took — a number worth
    /// printing, because a desktop that never goes quiet makes this whole probe
    /// inconclusive and that has to be visible in the log rather than inferred.
    private static func drainUntilQuiet(
        _ client: RFBNetworkClient,
        maximumRounds: Int = 12
    ) async throws -> Int {
        for round in 1...maximumRounds {
            let update = try client.requestFramebufferUpdate(incremental: true, timeout: 2)
            if update.changedPixelCount == 0 {
                return round
            }
            try await Task.sleep(for: .milliseconds(120))
        }
        return maximumRounds
    }

    /// Ratio of the single most common pixel colour, as a proxy for "is
    /// anything on this screen". A ratio near 1 is a blank/asleep display.
    /// Sampled on a grid so a 3024-wide framebuffer costs a few thousand
    /// comparisons instead of six million.
    private static func dominantColourRatio(of frame: RFBFramebufferUpdateResult) -> Double {
        let framebuffer = frame.framebuffer
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            return 1
        }
        let steps = 48
        var histogram: [UInt32: Int] = [:]
        var sampled = 0
        for row in 0..<steps {
            let y = framebuffer.height * row / steps
            for column in 0..<steps {
                let x = framebuffer.width * column / steps
                let pixel = framebuffer.pixels[y * framebuffer.width + x]
                let key = UInt32(pixel.red) << 16 | UInt32(pixel.green) << 8 | UInt32(pixel.blue)
                histogram[key, default: 0] += 1
                sampled += 1
            }
        }
        let dominant = histogram.values.max() ?? 0
        return sampled == 0 ? 1 : Double(dominant) / Double(sampled)
    }
}
