import Foundation

/// How PiP decides what to show (spec 034 FR-003, narrowed by spec 038 FR-006).
///
/// Lives in Core because it is a persisted user preference (`AppSettings`).
public enum PiPFramingMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Inherit the app's viewport at entry — centre and zoom of whatever the
    /// user was looking at. The default, and what a single tap does.
    case currentView
    /// A region the user drew, for this session.
    case chosenRegion

    public var identifier: String { rawValue }

    /// Spec 038 FR-006 removed `followActivity`, and a phone that ran build 12
    /// has it on disk. An unknown mode is not a corrupt settings file — it is a
    /// mode this build no longer has — so it decodes to the default instead of
    /// throwing and taking every other setting down with it.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PiPFramingMode(rawValue: raw) ?? .currentView
    }
}

/// A framing, in normalised framebuffer terms. The app layer maps this onto
/// `PiPWatchViewport`; keeping it free of AVFoundation types is what lets the
/// geometry be tested under `swift test`.
public struct PiPFramingTarget: Equatable, Sendable {
    /// The crop cannot be smaller than this fraction of the framebuffer.
    /// Matches the app's own zoom ceiling (`SessionViewportView.maxZoomScale`
    /// and `PiPWatchViewport.maximumZoomScale`, both 4.0), so a chosen region
    /// can never ask for a crop the manual path could not.
    public static let maximumZoomScale: Double = 4
    public static let minimumZoomScale: Double = 1

    /// Centre of the crop, `[0, 1]` across the framebuffer.
    public let centerX: Double
    public let centerY: Double
    /// Crop magnification: 1 is the whole framebuffer.
    public let zoomScale: Double

    public init(centerX: Double, centerY: Double, zoomScale: Double) {
        self.centerX = min(max(centerX.isFinite ? centerX : 0.5, 0), 1)
        self.centerY = min(max(centerY.isFinite ? centerY : 0.5, 0), 1)
        self.zoomScale = min(
            max(zoomScale.isFinite ? zoomScale : 1, Self.minimumZoomScale),
            Self.maximumZoomScale
        )
    }

    public static let fullFrame = PiPFramingTarget(centerX: 0.5, centerY: 0.5, zoomScale: 1)
}
