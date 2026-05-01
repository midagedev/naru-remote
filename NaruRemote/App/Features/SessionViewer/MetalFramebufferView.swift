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

/// Closure invoked when the user performs a long-press on the
/// rendered framebuffer.  Same coordinate contract as
/// `MetalFramebufferTapHandler` — the model maps to a button-3
/// (right-click) PointerEvent pair.
public typealias MetalFramebufferRightClickHandler = @MainActor (CGPoint, CGSize) -> Void

/// Closure invoked while the user is two-finger panning.  `delta`
/// is the per-callback translation in points (NOT cumulative — the
/// recognizer resets translation to zero between callbacks).  The
/// model accumulates these into discrete RFB scroll-wheel ticks.
public typealias MetalFramebufferScrollHandler = @MainActor (_ point: CGPoint, _ viewSize: CGSize, _ delta: CGSize) -> Void

/// Closure invoked while the user is pinching the rendered
/// framebuffer.  `scale` is the new (clamped) local view scale —
/// pinch is a LOCAL view transform per constitution §I and never
/// produces an RFB message.
public typealias MetalFramebufferPinchHandler = @MainActor (_ scale: CGFloat) -> Void

public struct MetalFramebufferView: UIViewRepresentable {
    private let framebuffer: RFBRawFramebuffer
    private let dirtyRectangles: [RFBFrameDamageRect]?
    private let device: MTLDevice?
    private let accessibilityIdentifier: String
    private let onTap: MetalFramebufferTapHandler?
    private let onRightClick: MetalFramebufferRightClickHandler?
    private let onScroll: MetalFramebufferScrollHandler?
    private let onPinch: MetalFramebufferPinchHandler?

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        accessibilityIdentifier: String = "naru.session.metalFramebuffer",
        onTap: MetalFramebufferTapHandler? = nil,
        onRightClick: MetalFramebufferRightClickHandler? = nil,
        onScroll: MetalFramebufferScrollHandler? = nil,
        onPinch: MetalFramebufferPinchHandler? = nil
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.device = device
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onTap = onTap
        self.onRightClick = onRightClick
        self.onScroll = onScroll
        self.onPinch = onPinch
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
        host.rightClickHandler = onRightClick
        host.scrollHandler = onScroll
        host.pinchHandler = onPinch
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
        uiView.rightClickHandler = onRightClick
        uiView.scrollHandler = onScroll
        uiView.pinchHandler = onPinch
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
/// Hosts the input gestures for the non-PiP main preview:
///   - `UITapGestureRecognizer` → `tapHandler` (button-1 click)
///   - `UILongPressGestureRecognizer` → `rightClickHandler` (button-3)
///   - Two-finger `UIPanGestureRecognizer` → `scrollHandler` (wheel)
///   - `UIPinchGestureRecognizer` → `pinchHandler` (LOCAL view scale,
///     constitution §I — never translated to an RFB message)
///
/// The watch-only PiP path (`PiPSampleBufferDisplayLayerView`)
/// intentionally does NOT install any of these recognizers.
public final class MetalFramebufferHostingView: UIView, UIGestureRecognizerDelegate {
    private weak var metalView: MTKView?
    private weak var coordinator: MetalFramebufferView.Coordinator?

    /// Closure invoked on a tap inside the host view.  Reassigned by
    /// the SwiftUI representable on every `updateUIView` so the model
    /// reference stays current across re-renders.
    public var tapHandler: MetalFramebufferTapHandler?

    /// Closure invoked at the start of a long-press.  We fire once on
    /// `.began` so the user gets immediate feedback when the press
    /// passes the recognizer's `minimumPressDuration` threshold.
    public var rightClickHandler: MetalFramebufferRightClickHandler?

    /// Closure invoked while the user two-finger pans.  Receives the
    /// per-callback translation; the model accumulates ticks across
    /// calls.
    public var scrollHandler: MetalFramebufferScrollHandler?

    /// Closure invoked while the user pinches.  Receives the new
    /// (clamped) local view scale.  Pinch is LOCAL — no RFB message
    /// is generated by this path.
    public var pinchHandler: MetalFramebufferPinchHandler?

    /// Current local zoom scale, owned by the host view so the
    /// recognizer can clamp incrementally between callbacks.  The
    /// SwiftUI parent mirrors the value through `pinchHandler` and
    /// applies a `.scaleEffect` to the framebuffer presentation.
    private var currentZoomScale: CGFloat = 1.0

    /// Local clamp range applied to the zoom scale.  Mirrors the
    /// range applied by `SessionViewportView` so the host view's
    /// internal accumulator never drifts past the visible clamp.
    private static let minZoomScale: CGFloat = 0.5
    private static let maxZoomScale: CGFloat = 4.0

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

        let longPressRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPressGesture(_:))
        )
        longPressRecognizer.minimumPressDuration = 0.5
        longPressRecognizer.cancelsTouchesInView = false
        // A press long enough to be a right-click should NOT also be
        // dispatched as a single tap — the user's intent is button-3,
        // not button-1.
        tapRecognizer.require(toFail: longPressRecognizer)

        let panRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePanGesture(_:))
        )
        panRecognizer.minimumNumberOfTouches = 2
        panRecognizer.maximumNumberOfTouches = 2
        panRecognizer.cancelsTouchesInView = false
        panRecognizer.delegate = self

        let pinchRecognizer = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinchGesture(_:))
        )
        pinchRecognizer.cancelsTouchesInView = false
        pinchRecognizer.delegate = self

        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
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

    @MainActor
    @objc private func handleLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        // Fire on .began so the right-click feedback lands the moment
        // the press qualifies; later .changed/.ended states do not
        // re-trigger another button-3 dispatch.
        guard recognizer.state == .began,
              let handler = rightClickHandler
        else {
            return
        }
        let point = recognizer.location(in: self)
        handler(point, bounds.size)
    }

    @MainActor
    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        guard let handler = scrollHandler else {
            return
        }
        switch recognizer.state {
        case .changed, .ended:
            let translation = recognizer.translation(in: self)
            // Reset to zero so the next callback delivers an
            // incremental delta the model can accumulate against the
            // tick threshold.
            recognizer.setTranslation(.zero, in: self)
            guard translation != .zero else {
                return
            }
            let location = recognizer.location(in: self)
            handler(location, bounds.size, CGSize(width: translation.x, height: translation.y))
        default:
            break
        }
    }

    @MainActor
    @objc private func handlePinchGesture(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .changed || recognizer.state == .began else {
            return
        }
        let proposed = currentZoomScale * recognizer.scale
        recognizer.scale = 1.0
        let clamped = min(max(proposed, Self.minZoomScale), Self.maxZoomScale)
        currentZoomScale = clamped
        // Constitution §I: pinch is a LOCAL view transform.  We must
        // never translate this into a remote scroll/zoom event.  The
        // handler is wired only to the SwiftUI `.scaleEffect`.
        pinchHandler?(clamped)
    }

    // MARK: UIGestureRecognizerDelegate

    /// Allow the two-finger scroll pan and the pinch to coexist with
    /// the long-press / tap recognizers — a long-press should still
    /// fire even if a stray pan recognizer is also tracking.  The
    /// long-press → tap dependency is handled with an explicit
    /// `require(toFail:)` above.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
