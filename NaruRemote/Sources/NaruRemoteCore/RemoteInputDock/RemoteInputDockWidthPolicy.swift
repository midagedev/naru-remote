import Foundation

/// Pinned-dock content-column width (spec 012 US3-1).
///
/// Regular-width (iPad) pinned docks cap at 720 pt and center; compact
/// (iPhone) keeps the window width. The floating overlay is
/// intrinsically sized and must not receive the regular-width cap.
public enum RemoteInputDockWidthPolicy: Sendable {
    /// Origin: orca mobile `CONTENT_MAX_WIDTH`
    /// (`docs/research/orca-mobile-input-reference.md` §4.4).
    public static let regularPinnedContentMaxWidth: CGFloat = 720

    /// Max width for a pinned dock (standard / compact form).
    /// Compact size class: window width (unchanged iPhone path).
    /// Regular size class: `regularPinnedContentMaxWidth`.
    public static func pinnedColumnMaxWidth(
        isCompactSizeClass: Bool,
        windowWidth: CGFloat?
    ) -> CGFloat? {
        if isCompactSizeClass {
            return windowWidth.map { max(1, $0) }
        }
        return regularPinnedContentMaxWidth
    }

    /// Floating overlay width. Regular width stays `nil` (content-
    /// sized); compact still uses the window width.
    public static func floatingOverlayWidth(
        isCompactSizeClass: Bool,
        windowWidth: CGFloat?
    ) -> CGFloat? {
        if isCompactSizeClass {
            return windowWidth.map { max(1, $0) }
        }
        return nil
    }
}
