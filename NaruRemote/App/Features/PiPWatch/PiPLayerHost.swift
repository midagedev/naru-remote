import Foundation
import NaruRemoteCore

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
import CoreMedia
import CoreVideo

/// Owns the live `AVSampleBufferDisplayLayer` shared between the in-app
/// session surface and the system Picture-in-Picture controller.
///
/// The host is created and owned by `NaruRemoteAppModel` so the layer
/// outlives any SwiftUI view rebuilds.  The hosted view embeds
/// `layer` as a sublayer; the `PiPWatchPictureInPictureController` uses
/// the same layer instance to back its content source.  A single sink
/// avoids double-rendering streamed frames.
@MainActor
public final class PiPLayerHost {
    public let layer: AVSampleBufferDisplayLayer
    private let renderer: PiPWatchSampleBufferRenderer

    public init(
        renderer: PiPWatchSampleBufferRenderer = PiPWatchSampleBufferRenderer()
    ) {
        self.renderer = renderer
        self.layer = renderer.displayLayer
    }

    /// Forwards a freshly received remote framebuffer to the hosted
    /// display layer.  Called by `NaruRemoteAppModel` for every frame
    /// it stores in `latestFramebuffer`, regardless of whether system
    /// PiP is currently active — the same layer is reused so attaching
    /// the controller later does not require a separate render path.
    @discardableResult
    public func enqueue(_ framebuffer: RFBRawFramebuffer) throws -> CMSampleBuffer {
        try renderer.enqueue(framebuffer)
    }

    /// Drops any queued samples and resets the renderer's frame index.
    public func flush() {
        renderer.flush()
    }
}
#endif
