import SwiftUI

/// Background for app chrome that floats over the remote screen.
///
/// The dock, the status line and the immersive control bar all sit on pixels
/// **the remote machine owns**. They used to paint `.ultraThinMaterial`, which
/// means their background — and therefore their text contrast — was decided by
/// whatever the remote desktop happened to be showing. Over a dark desktop in
/// light appearance the material resolved to a mid-gray under dark secondary
/// text and measured near 2:1 (found 2026-08-19 while shooting the light store
/// captures; the dark set shipped only because the defect is appearance-bound).
///
/// A material's result cannot be gated, because it is not a value the app
/// holds. An opaque token can be, and is: `NaruColorContrastTests` measures
/// every text pairing on `NaruColors.dock` in both appearances. So this
/// modifier is the single place that decides what remote-facing chrome is
/// painted with, and using it — rather than a material — is what keeps that
/// gate meaningful.
struct RemoteChromeSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.background(NaruColors.dock, in: shape)
    }
}

extension View {
    /// Paints app-owned chrome that overlays the remote screen.
    ///
    /// - Parameter shape: the chrome's outline — `Rectangle()` for edge-to-edge
    ///   bars, `Capsule()` or a rounded rectangle for floating pills.
    func remoteChromeSurface<S: Shape>(_ shape: S) -> some View {
        modifier(RemoteChromeSurface(shape: shape))
    }

    /// Edge-to-edge variant.
    func remoteChromeSurface() -> some View {
        modifier(RemoteChromeSurface(shape: Rectangle()))
    }
}
