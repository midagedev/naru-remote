import NaruRemoteCore
import SwiftUI

#if os(iOS) && canImport(UIKit) && canImport(Metal) && canImport(MetalKit)
import UIKit
import Metal
import MetalKit

/// SwiftUI representable that hosts a `MTKView` driven by
/// `MetalFramebufferRenderer`.  Uploads incoming `RFBRawFramebuffer`
/// pixels each frame and presents them with a fullscreen-quad shader.
///
/// This view is the **non-PiP main preview** path.  When system
/// Picture-in-Picture is active, the session viewport instead embeds
/// `PiPSampleBufferDisplayLayerView` (the shared
/// `AVSampleBufferDisplayLayer` host).  Picking the active presentation
/// at the SwiftUI level avoids double-rendering frames — the Metal
/// pipeline only runs when there is no PiP layer fronting the surface.
///
/// `makeUIView` returns a `UIView` host so a `nil` `MTLDevice` is
/// represented by a no-op black hosting view; SwiftUI callers that need
/// a fallback should test `MTLCreateSystemDefaultDevice() != nil` and
/// branch to the sampled `Canvas` preview when the device is missing.
/// Closure invoked when the user taps the rendered framebuffer.  The
/// `point` is in the host view's coordinate space (points, not
/// pixels); the `viewSize` is the host view's `bounds.size` at the
/// moment of the tap.  The model uses both to perform the
/// view→framebuffer aspect-fit mapping that mirrors
/// `MetalFramebufferRenderer.aspectFitViewport`.
public typealias MetalFramebufferTapHandler = @MainActor (CGPoint, CGSize) -> Void

public struct MetalFramebufferView: UIViewRepresentable {
    private let framebuffer: RFBRawFramebuffer
    private let dirtyRectangles: [RFBFrameDamageRect]?
    private let device: MTLDevice?
    private let accessibilityIdentifier: String
    private let onTap: MetalFramebufferTapHandler?

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        accessibilityIdentifier: String = "naru.session.metalFramebuffer",
        onTap: MetalFramebufferTapHandler? = nil
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.device = device
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
    }

    public static func isSupported() -> Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(device: device)
    }

    public func makeUIView(context: Context) -> MetalFramebufferHostingView {
        let host = MetalFramebufferHostingView(coordinator: context.coordinator)
        host.accessibilityIdentifier = accessibilityIdentifier
        host.isAccessibilityElement = true
        host.accessibilityLabel = "Remote framebuffer rendered with Metal"
        host.backgroundColor = .black
        host.tapHandler = onTap
        // The very first frame after the view is constructed must
        // perform a full upload — the texture has just been created
        // and there is nothing prior on the GPU to combine with the
        // damage rects.  Pass nil here so the renderer takes the
        // full-frame path regardless of what the pump reported.
        context.coordinator.enqueue(framebuffer, dirtyRectangles: nil)
        return host
    }

    public func updateUIView(_ uiView: MetalFramebufferHostingView, context: Context) {
        context.coordinator.enqueue(framebuffer, dirtyRectangles: dirtyRectangles)
        uiView.tapHandler = onTap
        uiView.requestRedraw()
    }

    /// Coordinator owns the long-lived `MetalFramebufferRenderer` and
    /// `MTKViewDelegate` so SwiftUI rebuilds of the representable do not
    /// thrash GPU resources.
    @MainActor
    public final class Coordinator {
        let renderer: MetalFramebufferRenderer?
        let delegate: MetalFramebufferViewDelegate?
        private var lastFramebufferDimensions: (width: Int, height: Int)?
        private var lastPixelHashSeed: Int = 0

        init(device: MTLDevice?) {
            if let device, let renderer = MetalFramebufferRenderer(device: device) {
                self.renderer = renderer
                self.delegate = MetalFramebufferViewDelegate(renderer: renderer)
            } else {
                self.renderer = nil
                self.delegate = nil
            }
        }

        func enqueue(
            _ framebuffer: RFBRawFramebuffer,
            dirtyRectangles: [RFBFrameDamageRect]? = nil
        ) {
            renderer?.enqueue(framebuffer, dirtyRectangles: dirtyRectangles)
            lastFramebufferDimensions = (framebuffer.width, framebuffer.height)
        }
    }
}

/// `UIView` host that owns the `MTKView`.  The Metal view is added as a
/// subview so the host can clip the layer to its own bounds and, when
/// Metal is unavailable, leave its background color visible.
///
/// Hosts a single `UITapGestureRecognizer` that forwards taps in the
/// host view's coordinate space to `tapHandler`.  This is the entry
/// point for the post-MVP Phase 3 pointer click — the watch-only PiP
/// path (`PiPSampleBufferDisplayLayerView`) intentionally does NOT
/// install a similar recognizer.
public final class MetalFramebufferHostingView: UIView {
    private weak var metalView: MTKView?
    private weak var coordinator: MetalFramebufferView.Coordinator?

    /// Closure invoked on a tap inside the host view.  Reassigned by
    /// the SwiftUI representable on every `updateUIView` so the model
    /// reference stays current across re-renders.
    public var tapHandler: MetalFramebufferTapHandler?

    init(coordinator: MetalFramebufferView.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)

        guard let renderer = coordinator.renderer,
              let delegate = coordinator.delegate
        else {
            return
        }

        let mtkView = MTKView(frame: .zero, device: renderer.device)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        mtkView.isOpaque = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        mtkView.delegate = delegate
        mtkView.backgroundColor = .black
        // The MTKView itself is non-interactive so the tap gesture
        // fires on the host view in its own coordinate space — that
        // matches the `(point, hostingView.bounds.size)` contract the
        // model expects for view→framebuffer mapping.
        mtkView.isUserInteractionEnabled = false

        addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.metalView = mtkView

        let tapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTapGesture(_:))
        )
        tapRecognizer.numberOfTapsRequired = 1
        tapRecognizer.cancelsTouchesInView = false
        addGestureRecognizer(tapRecognizer)
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("MetalFramebufferHostingView does not support NSCoder.")
    }

    /// Triggers a redraw of the embedded `MTKView`.  We pause the view
    /// and only request frames when SwiftUI hands us a new framebuffer
    /// — that keeps the GPU idle while the remote session is paused or
    /// while PiP fronting the surface.
    public func requestRedraw() {
        metalView?.setNeedsDisplay()
    }

    @MainActor
    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let handler = tapHandler
        else {
            return
        }
        let point = recognizer.location(in: self)
        handler(point, bounds.size)
    }
}
#endif
