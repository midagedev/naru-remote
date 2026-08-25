import Foundation

/// How PiP decides what to show (spec 034 FR-003).
///
/// Lives in Core because it is a persisted user preference (`AppSettings`) and
/// because the automatic mode's control loop is here too.
public enum PiPFramingMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Inherit the app's viewport at entry — centre and zoom of whatever the
    /// user was looking at. The default, and what a single tap does.
    case currentView
    /// Follow what is changing on the remote screen.
    case followActivity
    /// A region the user drew, for this session.
    case chosenRegion

    public var identifier: String { rawValue }
}

/// A framing, in normalised framebuffer terms. The app layer maps this onto
/// `PiPWatchViewport`; keeping the policy's output free of AVFoundation types
/// is what lets the control loop be tested under `swift test`.
public struct PiPFramingTarget: Equatable, Sendable {
    /// Centre of the crop, `[0, 1]` across the framebuffer.
    public let centerX: Double
    public let centerY: Double
    /// Crop magnification: 1 is the whole framebuffer.
    public let zoomScale: Double

    public init(centerX: Double, centerY: Double, zoomScale: Double) {
        self.centerX = min(max(centerX.isFinite ? centerX : 0.5, 0), 1)
        self.centerY = min(max(centerY.isFinite ? centerY : 0.5, 0), 1)
        self.zoomScale = min(
            max(zoomScale.isFinite ? zoomScale : 1, PiPAutoFramingPolicy.minimumZoomScale),
            PiPAutoFramingPolicy.maximumZoomScale
        )
    }

    public static let fullFrame = PiPFramingTarget(centerX: 0.5, centerY: 0.5, zoomScale: 1)
}

/// Frames the PiP window on whatever is actually changing (spec 034 FR-004).
///
/// The input is the damage rectangles the RFB layer already decodes for every
/// incremental frame — the same data the diagnostic export counts. Nothing new
/// is asked of the server, and nothing is sent to it: this is a local viewport
/// decision (constitution §I).
///
/// It is a control loop, so the interesting behaviour is not "does it centre
/// on the damage" but "does it hold still". A PiP window that re-frames on
/// every terminal line is worse than one that never moves, which is why the
/// dead zone and the cooldown are contract, not polish.
public struct PiPAutoFramingPolicy: Equatable, Sendable {
    /// The crop cannot be smaller than this fraction of the framebuffer.
    /// Matches the app's own zoom ceiling (`SessionViewportView.maxZoomScale`
    /// and `PiPWatchViewport.maximumZoomScale`, both 4.0), so automatic
    /// framing can never ask for a crop the manual path could not.
    public static let maximumZoomScale: Double = 4
    public static let minimumZoomScale: Double = 1

    /// Damage narrower than this is padded out to it. A cursor blink is a few
    /// pixels wide; framing PiP on a caret would be technically correct and
    /// useless.
    public let minimumCropWidthPixels: Double
    /// Damage wider than this is not zoomed out to fit — the policy centres on
    /// the busiest area instead (Non-Goals). Derived from legibility: on a
    /// 3024-wide desktop the app's 4x ceiling is a 756-pixel crop, which is
    /// about what 80 columns of terminal type needs.
    public let maximumCropWidthPixels: Double
    /// Margin added around the damage box, as a fraction of its width.
    public let cropMarginFraction: Double
    /// How far the target centre must move — as a fraction of the current crop
    /// — before the window is allowed to re-frame.
    public let recenterDeadZoneFraction: Double
    /// Minimum seconds between re-frames.
    public let recenterCooldownSeconds: TimeInterval
    /// Damage older than this stops contributing.
    public let damageWindowSeconds: TimeInterval

    public init(
        minimumCropWidthPixels: Double = 320,
        maximumCropWidthPixels: Double = 800,
        cropMarginFraction: Double = 0.35,
        recenterDeadZoneFraction: Double = 0.22,
        recenterCooldownSeconds: TimeInterval = 1.5,
        damageWindowSeconds: TimeInterval = 2.5
    ) {
        self.minimumCropWidthPixels = max(1, minimumCropWidthPixels)
        self.maximumCropWidthPixels = max(minimumCropWidthPixels, maximumCropWidthPixels)
        self.cropMarginFraction = max(0, cropMarginFraction)
        self.recenterDeadZoneFraction = max(0, recenterDeadZoneFraction)
        self.recenterCooldownSeconds = max(0, recenterCooldownSeconds)
        self.damageWindowSeconds = max(0, damageWindowSeconds)
    }
}

/// The mutable half: recent damage, the framing in force, and when it last
/// moved. Separated from the policy so the constants can be shared and the
/// state can be reset per session.
public struct PiPAutoFramingState: Equatable, Sendable {
    private struct Observation: Equatable, Sendable {
        let at: TimeInterval
        let centerX: Double
        let centerY: Double
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double
        let area: Double
    }

    public let policy: PiPAutoFramingPolicy
    public private(set) var current: PiPFramingTarget?
    public private(set) var lastReframeAt: TimeInterval?
    /// Re-frames applied, and re-frames suppressed by the dead zone or the
    /// cooldown. Counts only — the interesting question in a bug report is the
    /// ratio, not the coordinates (constitution §IV).
    public private(set) var reframeCount: Int = 0
    public private(set) var suppressedCount: Int = 0
    private var observations: [Observation] = []

    public init(policy: PiPAutoFramingPolicy = PiPAutoFramingPolicy()) {
        self.policy = policy
    }

    /// Seeds the framing PiP entered with, so the first automatic decision is
    /// measured against what the user is already looking at rather than
    /// against nothing.
    public mutating func adopt(_ target: PiPFramingTarget, at now: TimeInterval) {
        current = target
        lastReframeAt = now
    }

    public mutating func reset() {
        current = nil
        lastReframeAt = nil
        observations.removeAll()
        reframeCount = 0
        suppressedCount = 0
    }

    /// Feeds one frame's damage in and returns a new framing when the window
    /// should move. `nil` means hold — which is the answer most of the time,
    /// and deliberately so.
    ///
    /// `now` is a monotonic seconds value supplied by the caller; the policy
    /// reads no clock of its own so a test can drive time exactly.
    public mutating func observe(
        damage: [RFBFrameDamageRect],
        framebufferWidth: Int,
        framebufferHeight: Int,
        now: TimeInterval
    ) -> PiPFramingTarget? {
        guard framebufferWidth > 0, framebufferHeight > 0 else {
            return nil
        }

        record(damage: damage, at: now)
        observations.removeAll { now - $0.at > policy.damageWindowSeconds }

        guard !observations.isEmpty else {
            // Idle: hold the last framing rather than drifting back to the
            // whole desktop (FR-004).
            return nil
        }

        let totalArea = observations.reduce(0) { $0 + $1.area }
        guard totalArea > 0 else {
            return nil
        }

        let weightedX = observations.reduce(0) { $0 + $1.centerX * $1.area } / totalArea
        let weightedY = observations.reduce(0) { $0 + $1.centerY * $1.area } / totalArea
        let boxWidth = (observations.map(\.maxX).max() ?? 0) - (observations.map(\.minX).min() ?? 0)
        let boxHeight = (observations.map(\.maxY).max() ?? 0) - (observations.map(\.minY).min() ?? 0)

        let width = Double(framebufferWidth)
        let height = Double(framebufferHeight)
        // The crop keeps the framebuffer's aspect ratio, because that is what
        // `PiPWatchViewport.sourceRect` produces — so the binding dimension is
        // whichever of the two needs more room.
        let aspect = width / height
        let neededWidth = max(boxWidth, boxHeight * aspect) * (1 + policy.cropMarginFraction)
        let cropWidth = min(
            max(neededWidth, policy.minimumCropWidthPixels),
            min(policy.maximumCropWidthPixels, width)
        )
        let zoom = min(
            max(width / max(cropWidth, 1), PiPAutoFramingPolicy.minimumZoomScale),
            PiPAutoFramingPolicy.maximumZoomScale
        )

        let candidate = PiPFramingTarget(
            centerX: weightedX / width,
            centerY: weightedY / height,
            zoomScale: zoom
        )

        guard let current else {
            current = candidate
            lastReframeAt = now
            reframeCount += 1
            return candidate
        }

        guard shouldReframe(from: current, to: candidate, framebufferWidth: width, now: now) else {
            suppressedCount += 1
            return nil
        }

        self.current = candidate
        lastReframeAt = now
        reframeCount += 1
        return candidate
    }

    private mutating func record(damage: [RFBFrameDamageRect], at now: TimeInterval) {
        for rect in damage where rect.width > 0 && rect.height > 0 {
            let minX = Double(rect.x)
            let minY = Double(rect.y)
            let maxX = Double(rect.x + rect.width)
            let maxY = Double(rect.y + rect.height)
            observations.append(
                Observation(
                    at: now,
                    centerX: (minX + maxX) / 2,
                    centerY: (minY + maxY) / 2,
                    minX: minX,
                    minY: minY,
                    maxX: maxX,
                    maxY: maxY,
                    area: Double(rect.width) * Double(rect.height)
                )
            )
        }
    }

    private func shouldReframe(
        from current: PiPFramingTarget,
        to candidate: PiPFramingTarget,
        framebufferWidth: Double,
        now: TimeInterval
    ) -> Bool {
        if let lastReframeAt, now - lastReframeAt < policy.recenterCooldownSeconds {
            return false
        }

        // The dead zone is measured in crop widths, not in pixels: moving half
        // a crop matters on any desktop, moving fifty pixels does not.
        let currentCropWidth = framebufferWidth / max(current.zoomScale, 1)
        let deadZone = (currentCropWidth / framebufferWidth) * policy.recenterDeadZoneFraction
        let movedX = abs(candidate.centerX - current.centerX)
        let movedY = abs(candidate.centerY - current.centerY)
        if movedX > deadZone || movedY > deadZone {
            return true
        }

        // A zoom change large enough to change legibility counts as a move
        // even when the centre held.
        let zoomRatio = candidate.zoomScale / max(current.zoomScale, 0.0001)
        return zoomRatio > 1.25 || zoomRatio < 0.8
    }
}
