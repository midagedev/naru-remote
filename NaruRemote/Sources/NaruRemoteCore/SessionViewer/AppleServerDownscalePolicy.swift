import CoreGraphics
import Foundation

/// Decides when to send Apple Screen Sharing's proprietary ScaleFactor
/// message (type 0x08). `nil` means "send nothing this incremental tick".
///
/// v1 ladder is {1.0, 0.5}. Downscale is visually lossless-only and
/// Apple-gated: sending 0x08 to a non-Apple server desyncs the RFB
/// stream (no client-message length negotiation). Coordinates, framebuffer
/// dimensions, and scale factors tied to dimensions stay out of logs and
/// diagnostic exports (constitution IV). This policy is pure so the app
/// model and `swift test` share one decision table.
public struct AppleServerDownscalePolicy {
    public static let downscaledRung: Double = 0.5
    public static let fullRung: Double = 1.0

    /// Consecutive eligible incremental ticks required before requesting
    /// 0.5. Same constant family as the spec 017 region heartbeat.
    public let eligibleTickThreshold: Int
    /// Used when the view has not yet published `displayPixelsPerPoint`.
    /// iPhone @3x is the conservative default — it errs toward NOT
    /// downscaling on unknown screens.
    public let assumedDisplayPixelsPerPoint: CGFloat

    private var eligibleTickCount = 0

    public init(
        eligibleTickThreshold: Int = 10,
        assumedDisplayPixelsPerPoint: CGFloat = 3
    ) {
        self.eligibleTickThreshold = max(eligibleTickThreshold, 1)
        self.assumedDisplayPixelsPerPoint = max(assumedDisplayPixelsPerPoint, 1)
    }

    /// Called once per incremental update-request tick. Returns the rung
    /// to REQUEST now, or nil when no message should be sent this tick.
    public mutating func requestedRung(
        transform: ViewportTransform?,
        liveFramebufferWidth: Int,
        liveFramebufferHeight: Int,
        displayPixelsPerPoint: CGFloat?,
        serverAdvertisedAppleSecurity: Bool,
        currentAppliedRung: Double
    ) -> Double? {
        guard serverAdvertisedAppleSecurity else {
            return nil
        }
        guard let transform else {
            return nil
        }

        let transformWidth = Int(transform.framebufferSize.width.rounded(.down))
        let transformHeight = Int(transform.framebufferSize.height.rounded(.down))
        if transformWidth != liveFramebufferWidth
            || transformHeight != liveFramebufferHeight
        {
            eligibleTickCount = 0
            return nil
        }

        if transform.isZoomed {
            eligibleTickCount = 0
            if currentAppliedRung != Self.fullRung {
                return Self.fullRung
            }
            return nil
        }

        let pixelsPerPoint = displayPixelsPerPoint ?? assumedDisplayPixelsPerPoint
        // Normalize to the UNSCALED framebuffer (2026-08-20 spec-defect
        // fix, FAIL-first in testStaysDownscaledAfterServerResizeApplies-
        // TheHalfFramebuffer): once 0.5 is applied, DesktopSize halves the
        // framebuffer and `displayScale` doubles — the raw condition would
        // read "not lossless" and flap the ladder 0.5↔1.0 forever. The
        // stable invariant is `displayScale(full fb) × ppp ≤ 0.5`, and
        // `displayScale(full fb) = displayScale(current fb) × appliedRung`.
        let unscaledDisplayScale = transform.displayScale * currentAppliedRung
        let isLossless = unscaledDisplayScale * pixelsPerPoint <= Self.downscaledRung

        if isLossless {
            eligibleTickCount += 1
            if eligibleTickCount >= eligibleTickThreshold,
               currentAppliedRung != Self.downscaledRung
            {
                return Self.downscaledRung
            }
            return nil
        }

        eligibleTickCount = 0
        if currentAppliedRung != Self.fullRung {
            return Self.fullRung
        }
        return nil
    }

    public mutating func reset() {
        eligibleTickCount = 0
    }

    /// Outbound pointer-coordinate mapping while the downscale is applied.
    ///
    /// Live-measured 2026-08-20 (`LiveMacPointerHoverTests/
    /// testScaledSessionPointerInputSpaceStaysUnscaled`): screensharingd's
    /// pointer input space stays the **unscaled** framebuffer while
    /// ScaleFactor 0.5 is applied — a scaled-coordinate PointerEvent lands
    /// at half the intended point, and full-framebuffer coordinates keep
    /// landing exactly. The view computes pointer coordinates in the
    /// framebuffer it renders (the scaled one, once the DesktopSize resize
    /// lands), so the app model multiplies outbound pointer coordinates by
    /// `unscaledWidth / currentWidth` at its single pointer choke point.
    ///
    /// Shape detection instead of rung bookkeeping: a current width that is
    /// exactly the half-shape of the known unscaled width (±2 px rounding)
    /// is our downscale; **any other size is adopted as the new unscaled
    /// truth** (initial connect, restore-to-1.0 landing, a genuine Mac
    /// resolution change while un-scaled). Residual: a resolution change
    /// that happens *while scaled* mis-adopts the scaled size until the
    /// next restore round-trip (documented in spec 018).
    public static func pointerCoordinateMapping(
        knownUnscaledWidth: Int?,
        currentWidth: Int?
    ) -> (multiplier: Double, unscaledWidthToStore: Int?) {
        guard let currentWidth, currentWidth > 0 else {
            return (1, knownUnscaledWidth)
        }
        if let knownUnscaledWidth,
           knownUnscaledWidth > currentWidth,
           abs(currentWidth * 2 - knownUnscaledWidth) <= 2
        {
            return (
                Double(knownUnscaledWidth) / Double(currentWidth),
                knownUnscaledWidth
            )
        }
        return (1, currentWidth)
    }

    /// Applies `pointerCoordinateMapping`'s multiplier to one command.
    public static func mappedPointerCommand(
        _ command: RFBPointerCommand,
        multiplier: Double
    ) -> RFBPointerCommand {
        guard multiplier != 1 else {
            return command
        }
        return RFBPointerCommand(
            buttonMask: command.buttonMask,
            x: RFBPointerCommand.clamp(CGFloat(Double(command.x) * multiplier)),
            y: RFBPointerCommand.clamp(CGFloat(Double(command.y) * multiplier))
        )
    }
}
