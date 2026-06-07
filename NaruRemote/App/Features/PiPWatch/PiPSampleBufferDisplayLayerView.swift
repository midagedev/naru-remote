import SwiftUI

#if os(iOS) && canImport(UIKit) && canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import UIKit
import AVFoundation

/// Hosts a shared `AVSampleBufferDisplayLayer` inside the SwiftUI view
/// tree.  System Picture-in-Picture cannot pick up a layer that is not
/// in the live view hierarchy, so the same layer instance owned by
/// `PiPLayerHost` is attached as a sublayer here while the
/// `AVPictureInPictureController` holds the layer through its content
/// source.
///
/// User interaction is disabled — PiP Watch is watch-only by
/// constitution principle I.  See `ROADMAP.md` Phase 6.
public struct PiPSampleBufferDisplayLayerView: UIViewRepresentable {
    private let sampleBufferLayer: AVSampleBufferDisplayLayer
    private let accessibilityIdentifier: String
    private let accessibilityLabel: String

    public init(
        layerHost: PiPLayerHost,
        accessibilityIdentifier: String = "naru.session.pipDisplayLayer"
    ) {
        self.init(
            layer: layerHost.layer,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: "Remote framebuffer in Picture-in-Picture display layer"
        )
    }

    public init(
        layer: AVSampleBufferDisplayLayer,
        accessibilityIdentifier: String = "naru.session.sampleBufferDisplayLayer",
        accessibilityLabel: String = "Remote video display layer"
    ) {
        self.sampleBufferLayer = layer
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
    }

    public func makeUIView(context: Context) -> PiPSampleBufferDisplayLayerHostingView {
        let view = PiPSampleBufferDisplayLayerHostingView(layer: sampleBufferLayer)
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = accessibilityIdentifier
        view.isAccessibilityElement = true
        view.accessibilityLabel = accessibilityLabel
        view.backgroundColor = .black
        return view
    }

    public func updateUIView(_ uiView: PiPSampleBufferDisplayLayerHostingView, context: Context) {
        uiView.attach(layer: sampleBufferLayer)
        uiView.setNeedsLayout()
    }
}

/// Plain `UIView` subclass that embeds the shared
/// `AVSampleBufferDisplayLayer` as a sublayer and keeps it sized to
/// match the view's bounds across rotations and Stage Manager resizes.
public final class PiPSampleBufferDisplayLayerHostingView: UIView {
    private weak var attachedLayer: AVSampleBufferDisplayLayer?

    public init(layer: AVSampleBufferDisplayLayer) {
        super.init(frame: .zero)
        attach(layer: layer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("PiPSampleBufferDisplayLayerHostingView does not support NSCoder.")
    }

    public func attach(layer newLayer: AVSampleBufferDisplayLayer) {
        if attachedLayer === newLayer {
            newLayer.frame = bounds
            return
        }

        attachedLayer?.removeFromSuperlayer()
        newLayer.frame = bounds
        self.layer.addSublayer(newLayer)
        attachedLayer = newLayer
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}
#endif
