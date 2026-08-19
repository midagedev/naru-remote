import SwiftUI

/// How the diagnostics sheet is sized, in one place.
///
/// Both entry points — the host list's grid card and the in-session capsule —
/// used to declare `.presentationDetents([.medium, .large])` themselves, and on
/// a 13" iPad that medium box is shorter than the five-stage summary: the last
/// row and the Share Diagnostics button fell below the fold with nothing to
/// suggest they were there (found while shooting the store captures on
/// 2026-08-19, which is why the shipped iPad set is four shots, not five).
///
/// A detent is a fraction of the *screen*, so on a large screen it is unrelated
/// to how tall the content is — the same declaration that fits an iPhone cannot
/// be assumed to fit an iPad. Where the sheet is already a centred form sheet
/// with room to spare, take the full sheet instead of a half of it.
struct DiagnosticsSheetPresentation: ViewModifier {
    #if canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .diagnosticsSheetSizing(isRegularWidth: isRegularWidth)
    }

    private var isRegularWidth: Bool {
        #if canImport(UIKit)
        return horizontalSizeClass == .regular
        #else
        return false
        #endif
    }

    private var detents: Set<PresentationDetent> {
        #if canImport(UIKit)
        // Regular width is the iPad form sheet: it is already a modest box on a
        // large screen, and halving it is what clipped the summary.
        if horizontalSizeClass == .regular {
            return [.large]
        }
        #endif
        return [.medium, .large]
    }
}

extension View {
    /// Applies the shared diagnostics-sheet sizing.
    func diagnosticsSheetPresentation() -> some View {
        modifier(DiagnosticsSheetPresentation())
    }

    /// On a regular-width iPad the sheet is a form sheet whose height is fixed
    /// by the system, and the five-stage summary is taller than it — so the
    /// last row rendered half-cut against the bottom edge. Ask for the page
    /// size there, which is the larger of the two standard sheet sizes and is
    /// tall enough for the whole summary.
    ///
    /// `.fitted` would be the natural choice and does nothing here, measured:
    /// the sheet's root is a `ScrollView`, which has no intrinsic height to fit
    /// to. The cost of `.page` is a sheet roomier than its content; the benefit
    /// is that no row is ever cut.
    ///
    /// Unavailable before iOS 18; on 17 the sheet still scrolls, and the share
    /// action lives in the toolbar precisely so it does not depend on that.
    @ViewBuilder
    func diagnosticsSheetSizing(isRegularWidth: Bool) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), isRegularWidth {
            presentationSizing(.page)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
