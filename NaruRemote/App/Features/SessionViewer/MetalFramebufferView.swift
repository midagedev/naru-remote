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

/// Closures invoked across the lifecycle of a single-finger drag
/// (button-1 hold) on the rendered framebuffer.  Same coordinate
/// contract as `MetalFramebufferTapHandler` — the model maps each
/// event to a `PointerEvent` with mask `0x01` (down/move) or `0x00`
/// (up).  The recognizer defers `down` until the gesture actually
/// moves so a fast tap is unaffected by drag wiring.
public typealias MetalFramebufferPointerDownHandler = @MainActor (CGPoint, CGSize) -> Void
public typealias MetalFramebufferPointerMoveHandler = @MainActor (CGPoint, CGSize) -> Void
public typealias MetalFramebufferPointerUpHandler = @MainActor (CGPoint, CGSize) -> Void

/// Closure invoked while the user pans a *zoomed* framebuffer with one
/// finger.  `offset` is the new (clamped) local pan translation in view
/// points — a LOCAL view transform per constitution §I, never an RFB
/// message.  Only fires when `zoomScale > 1`; at fit scale the
/// one-finger drag remains the remote button-1 drag path.
public typealias MetalFramebufferPanHandler = @MainActor (_ offset: CGSize) -> Void

/// Closure invoked on a double-tap.  The model toggles between fit
/// scale and a comfortable zoom centered on the tapped point — a LOCAL
/// view transform per constitution §I, never an RFB message.
public typealias MetalFramebufferZoomToggleHandler = @MainActor (_ point: CGPoint, _ viewSize: CGSize) -> Void

public struct MetalFramebufferView: UIViewRepresentable {
    private let framebuffer: RFBRawFramebuffer
    private let dirtyRectangles: [RFBFrameDamageRect]?
    private let device: MTLDevice?
    private let accessibilityIdentifier: String
    private let onTap: MetalFramebufferTapHandler?
    private let onRightClick: MetalFramebufferRightClickHandler?
    private let onScroll: MetalFramebufferScrollHandler?
    private let onPinch: MetalFramebufferPinchHandler?
    private let onPointerDown: MetalFramebufferPointerDownHandler?
    private let onPointerMove: MetalFramebufferPointerMoveHandler?
    private let onPointerUp: MetalFramebufferPointerUpHandler?
    private let onPan: MetalFramebufferPanHandler?
    private let onZoomToggle: MetalFramebufferZoomToggleHandler?
    /// Current local zoom scale, owned by the SwiftUI parent and pushed
    /// down so the host's gesture handlers know whether a one-finger
    /// drag is a pan (zoomed) or a remote drag (fit), and so the pan
    /// clamp uses the live scale.
    private let zoomScale: CGFloat
    /// Current local pan offset, pushed down so the host stays in sync
    /// when the parent resets zoom/pan (e.g. the 1× button).
    private let panOffset: CGSize

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        accessibilityIdentifier: String = "naru.session.metalFramebuffer",
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        onTap: MetalFramebufferTapHandler? = nil,
        onRightClick: MetalFramebufferRightClickHandler? = nil,
        onScroll: MetalFramebufferScrollHandler? = nil,
        onPinch: MetalFramebufferPinchHandler? = nil,
        onPointerDown: MetalFramebufferPointerDownHandler? = nil,
        onPointerMove: MetalFramebufferPointerMoveHandler? = nil,
        onPointerUp: MetalFramebufferPointerUpHandler? = nil,
        onPan: MetalFramebufferPanHandler? = nil,
        onZoomToggle: MetalFramebufferZoomToggleHandler? = nil
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.device = device
        self.accessibilityIdentifier = accessibilityIdentifier
        self.zoomScale = zoomScale
        self.panOffset = panOffset
        self.onTap = onTap
        self.onRightClick = onRightClick
        self.onScroll = onScroll
        self.onPinch = onPinch
        self.onPointerDown = onPointerDown
        self.onPointerMove = onPointerMove
        self.onPointerUp = onPointerUp
        self.onPan = onPan
        self.onZoomToggle = onZoomToggle
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
        host.pointerDownHandler = onPointerDown
        host.pointerMoveHandler = onPointerMove
        host.pointerUpHandler = onPointerUp
        host.panHandler = onPan
        host.zoomToggleHandler = onZoomToggle
        host.syncZoomPan(scale: zoomScale, offset: panOffset)
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
        uiView.pointerDownHandler = onPointerDown
        uiView.pointerMoveHandler = onPointerMove
        uiView.pointerUpHandler = onPointerUp
        uiView.panHandler = onPan
        uiView.zoomToggleHandler = onZoomToggle
        uiView.syncZoomPan(scale: zoomScale, offset: panOffset)
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

    /// Closure invoked at the start of a single-finger drag (mask
    /// `0x01` button-down).  Deferred until the gesture actually
    /// moves; a stationary press that ends without movement does NOT
    /// invoke this handler so a fast tap stays a button-1 click.
    public var pointerDownHandler: MetalFramebufferPointerDownHandler?

    /// Closure invoked on each `.changed` update of a single-finger
    /// drag with the current view-coords (mask `0x01` button-hold).
    public var pointerMoveHandler: MetalFramebufferPointerMoveHandler?

    /// Closure invoked when the single-finger drag ends, is
    /// cancelled, or fails (mask `0x00` button-up).  Only invoked if
    /// `pointerDownHandler` was already called for this drag — a
    /// gesture that never moved past the tap-slop is a no-op here.
    public var pointerUpHandler: MetalFramebufferPointerUpHandler?

    /// Closure invoked while panning a zoomed framebuffer (one-finger
    /// drag with `currentZoomScale > 1`).  Receives the new clamped pan
    /// offset.  LOCAL transform — never an RFB message (constitution §I).
    public var panHandler: MetalFramebufferPanHandler?

    /// Closure invoked on a double-tap to toggle zoom.  LOCAL transform
    /// — never an RFB message (constitution §I).
    public var zoomToggleHandler: MetalFramebufferZoomToggleHandler?

    /// Current local pan offset (view points), kept in sync with the
    /// SwiftUI parent.  Accumulated during a zoomed one-finger drag and
    /// re-clamped against the live content/zoom each callback.
    private var currentPanOffset: CGSize = .zero

    /// Drag-recognizer state: the start view-coords (captured at
    /// `.began`) and a flag tracking whether `pointerDownHandler` has
    /// been emitted for this gesture so far.  The flag is the
    /// tap-vs-drag disambiguation primitive: the down event fires on
    /// the FIRST `.changed` callback, and the up event only fires on
    /// `.ended`/`.cancelled`/`.failed` if down was emitted.
    private var dragStartViewPoint: CGPoint?
    private var dragLastViewPoint: CGPoint?
    private var dragDownEmitted: Bool = false

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

        // Double-tap toggles zoom (fit ↔ comfortable zoom about the
        // tapped point).  A single tap must lose to it so a quick
        // double-tap zoom does not also fire a button-1 click.
        let doubleTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTapGesture(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.cancelsTouchesInView = false
        tapRecognizer.require(toFail: doubleTapRecognizer)

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

        // Single-finger pan is the drag-to-move recognizer.  It must
        // lose to a long-press (so press-and-hold becomes a button-3
        // click instead of starting a drag) and is configured to
        // coexist with the tap recognizer through the
        // `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`
        // delegate hook.  Tap precedence is preserved by deferring
        // the actual `pointerDownHandler` invocation until the FIRST
        // `.changed` callback — a touch that never moves past the
        // recognizer's tap-slop never enters `.changed`, so the tap
        // recognizer fires the button-1 click and the drag handlers
        // are never invoked.
        let dragRecognizer = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleDragGesture(_:))
        )
        dragRecognizer.minimumNumberOfTouches = 1
        dragRecognizer.maximumNumberOfTouches = 1
        dragRecognizer.cancelsTouchesInView = false
        dragRecognizer.delegate = self
        dragRecognizer.require(toFail: longPressRecognizer)

        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(doubleTapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(dragRecognizer)
        isUserInteractionEnabled = true
    }

    /// Push the parent's current zoom/pan into the host so gesture
    /// handlers branch on the live scale and the pan accumulator does
    /// not drift after a parent-driven reset (the 1× button).
    public func syncZoomPan(scale: CGFloat, offset: CGSize) {
        currentZoomScale = min(max(scale, Self.minZoomScale), Self.maxZoomScale)
        currentPanOffset = offset
    }

    private var isZoomed: Bool { currentZoomScale > 1.0001 }

    /// Clamp a pan offset so the scaled content can never reveal
    /// background past its edges.  Mirrors
    /// `ViewportTransform.clampPan` (NaruRemoteCore) — the content size
    /// is the host bounds times the live zoom scale.
    private func clampedPan(_ pan: CGSize) -> CGSize {
        let maxX = max(0, (bounds.width * currentZoomScale - bounds.width) / 2)
        let maxY = max(0, (bounds.height * currentZoomScale - bounds.height) / 2)
        return CGSize(
            width: min(max(pan.width, -maxX), maxX),
            height: min(max(pan.height, -maxY), maxY)
        )
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
    @objc private func handleDoubleTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let handler = zoomToggleHandler
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
        // Re-clamp the pan against the new scale so zooming out pulls
        // the content back into frame (and a return to ~1× re-centers).
        let reclamped = clampedPan(currentPanOffset)
        if reclamped != currentPanOffset {
            currentPanOffset = reclamped
            panHandler?(reclamped)
        }
    }

    @MainActor
    @objc private func handleDragGesture(_ recognizer: UIPanGestureRecognizer) {
        // When the framebuffer is zoomed, a one-finger drag PANS the
        // local view (constitution §I — no RFB message) instead of
        // driving a remote button-1 drag.  At fit scale there is
        // nothing to pan, so the gesture remains the remote drag path.
        if isZoomed {
            handleZoomedPan(recognizer)
            return
        }

        switch recognizer.state {
        case .began:
            // Capture the start point but DO NOT emit the down event
            // yet — a touch that ends without entering `.changed` is
            // a tap, and the tap recognizer must own that path.
            let point = recognizer.location(in: self)
            dragStartViewPoint = point
            dragLastViewPoint = point
            dragDownEmitted = false
        case .changed:
            let location = recognizer.location(in: self)
            dragLastViewPoint = location
            let size = bounds.size
            // Emit the deferred down event on the FIRST .changed so
            // the remote sees a button-1 hold at the gesture's start
            // position before any move.  Anchor on the captured
            // `.began` point so the press location is preserved when
            // the slop threshold has carried the touch a few pixels
            // away.
            if !dragDownEmitted {
                dragDownEmitted = true
                if let startPoint = dragStartViewPoint, let downHandler = pointerDownHandler {
                    downHandler(startPoint, size)
                }
            }
            pointerMoveHandler?(location, size)
        case .ended, .cancelled, .failed:
            // Only emit a button-up if we actually emitted a button-
            // down for this gesture — a stationary press that ended
            // without movement (and therefore went straight to a tap)
            // must not fire a stray button-1 release on the wire.
            let endedWithDown = dragDownEmitted
            let endPoint = dragLastViewPoint ?? recognizer.location(in: self)
            let size = bounds.size
            dragStartViewPoint = nil
            dragLastViewPoint = nil
            dragDownEmitted = false
            if endedWithDown, let upHandler = pointerUpHandler {
                upHandler(endPoint, size)
            }
        default:
            break
        }
    }

    /// One-finger drag while zoomed: accumulate the per-callback
    /// translation into the pan offset, clamp it, and report the new
    /// offset to the parent.  Resets the recognizer translation each
    /// callback so the deltas accumulate against `currentPanOffset`.
    @MainActor
    private func handleZoomedPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            // If a remote button-1 drag had started before a pinch
            // zoomed the view mid-gesture, release it cleanly so no
            // stray button stays held on the wire.
            if dragDownEmitted {
                let size = bounds.size
                let endPoint = dragLastViewPoint ?? recognizer.location(in: self)
                dragDownEmitted = false
                dragStartViewPoint = nil
                dragLastViewPoint = nil
                pointerUpHandler?(endPoint, size)
            }
        case .changed:
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            let proposed = CGSize(
                width: currentPanOffset.width + translation.x,
                height: currentPanOffset.height + translation.y
            )
            currentPanOffset = clampedPan(proposed)
            panHandler?(currentPanOffset)
        default:
            break
        }
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
