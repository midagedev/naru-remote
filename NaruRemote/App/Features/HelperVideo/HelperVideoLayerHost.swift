import Foundation

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation

/// Owns the foreground helper-video display layer and H.264 access-unit
/// renderer for the active app model. Keeping this host at model lifetime
/// prevents SwiftUI view rebuilds from detaching the layer that receives
/// helper-video samples.
@MainActor
public final class HelperVideoLayerHost: @unchecked Sendable {
    public let renderer: HelperVideoH264SampleBufferRenderer

    public init(
        renderer: HelperVideoH264SampleBufferRenderer = HelperVideoH264SampleBufferRenderer()
    ) {
        self.renderer = renderer
    }

    public var layer: AVSampleBufferDisplayLayer {
        renderer.displayLayer
    }

    public func flush() async {
        await renderer.flush()
    }
}
#endif
