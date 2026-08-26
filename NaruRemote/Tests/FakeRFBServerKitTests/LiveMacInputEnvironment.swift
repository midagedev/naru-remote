import CoreGraphics
import Foundation
import XCTest

/// Preconditions for the live probes that put synthetic input into *this* Mac.
///
/// Those probes ask a real question — does an RFB pointer or wheel event reach
/// macOS — and they answer it by watching this machine. That only works when
/// the machine is available to be watched, and it is not always: on
/// 2026-08-26 the same scroll probe measured ten notches to ten scroll events
/// in the morning and zero in the evening, with the display awake and the
/// session unlocked, while this Mac held an outbound Screen Sharing session to
/// another machine and its sibling probe reported the pointer oracle busy.
///
/// A red gate for that is worse than useless: it is a gate that cries wolf,
/// and the next person spends an hour looking for a defect in the pointer lane
/// that is not there. `LiveMacPointerHoverTests` already had one test that
/// skipped on this — the reference-move guard — and the two that did not are
/// exactly the two that went red.
///
/// So these are the states a probe checks before believing its own zero. Each
/// one is observable without any permission the test runner does not have:
/// `CGDisplayIsAsleep`, the session dictionary, and the cursor position.
enum LiveMacInputEnvironment {

    static func currentPointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Skips unless this Mac is in a state where synthetic input can be
    /// observed: display awake, session unlocked and on console, and nobody
    /// else moving the pointer.
    ///
    /// Call this *before* connecting, so a skipped run costs nothing.
    static func requireAQuietMac(
        settleFor seconds: TimeInterval = 0.35,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let display = CGMainDisplayID()
        if CGDisplayIsAsleep(display) != 0 {
            throw XCTSkip("this Mac's display is asleep; synthetic input cannot be observed")
        }

        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if let locked = session?["CGSSessionScreenIsLocked"] as? Bool, locked {
            throw XCTSkip("this Mac's session is locked; synthetic input goes to the login window")
        }
        if let onConsole = session?["kCGSSessionOnConsoleKey"] as? Bool, !onConsole {
            throw XCTSkip("this Mac's session is not on the console")
        }

        // A pointer that moves while we are not touching it means a person is
        // using this Mac, or something else is driving it. Either way our own
        // moves will be fought and the reading is not ours to trust.
        guard let first = currentPointerLocation() else {
            throw XCTSkip("this Mac's pointer position is unreadable")
        }
        Thread.sleep(forTimeInterval: seconds)
        guard let second = currentPointerLocation() else {
            throw XCTSkip("this Mac's pointer position is unreadable")
        }
        if abs(first.x - second.x) > 1 || abs(first.y - second.y) > 1 {
            throw XCTSkip("this Mac's pointer is moving on its own — somebody is using it")
        }
    }

    /// Waits for the pointer to reach `target`, and **skips** rather than
    /// failing when it never does.
    ///
    /// Use this for the reference move a probe makes on its way to measuring
    /// something else. A probe whose subject *is* the pointer move must assert
    /// instead — that is the difference between "the machine would not let us
    /// look" and "the thing we came to measure is broken".
    @discardableResult
    static func requirePointerToReach(
        _ target: CGPoint,
        tolerance: CGFloat,
        timeout: TimeInterval,
        because reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGPoint {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGPoint?
        while Date() < deadline {
            guard let location = currentPointerLocation() else {
                break
            }
            last = location
            if abs(location.x - target.x) <= tolerance, abs(location.y - target.y) <= tolerance {
                return location
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let observed = last.map { "(\(Int($0.x)), \(Int($0.y)))" } ?? "unreadable"
        throw XCTSkip(
            """
            \(reason): a reference pointer move did not land (pointer is at \(observed)). \
            The pointer oracle is busy — another Screen Sharing client, a person at the \
            keyboard, or an app warping the cursor. Re-run on a quiet machine.
            """
        )
    }
}
