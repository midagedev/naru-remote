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
public typealias MetalFramebufferTapHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void

/// Closure invoked when the user performs a long-press on the
/// rendered framebuffer.  Same coordinate contract as
/// `MetalFramebufferTapHandler` — the model maps to a button-3
/// (right-click) PointerEvent pair.
public typealias MetalFramebufferRightClickHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void

/// Closure invoked while the user is two-finger panning.  `delta`
/// is the per-callback translation in points (NOT cumulative — the
/// recognizer resets translation to zero between callbacks).  The
/// model accumulates these into discrete RFB scroll-wheel ticks.
public typealias MetalFramebufferScrollHandler = @MainActor @Sendable (_ point: CGPoint, _ viewSize: CGSize, _ delta: CGSize) -> Void

/// Closure invoked while the user is pinching the rendered
/// framebuffer.  `scale` is the new (clamped) local view scale —
/// `anchor` is the pinch midpoint in host-view coordinates. Pinch is
/// a LOCAL view transform per constitution §I and never produces an
/// RFB message.
public typealias MetalFramebufferPinchHandler = @MainActor @Sendable (_ scale: CGFloat, _ anchor: CGPoint, _ viewSize: CGSize) -> Void

/// Closures invoked across the lifecycle of a single-finger drag
/// (button-1 hold) on the rendered framebuffer.  Same coordinate
/// contract as `MetalFramebufferTapHandler` — the model maps each
/// event to a `PointerEvent` with mask `0x01` (down/move) or `0x00`
/// (up).  The recognizer defers `down` until the gesture actually
/// moves so a fast tap is unaffected by drag wiring.
public typealias MetalFramebufferPointerDownHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias MetalFramebufferPointerMoveHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias MetalFramebufferPointerUpHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void

/// Closure invoked while the user pans a *zoomed* framebuffer with one
/// finger.  `offset` is the new (clamped) local pan translation in view
/// points — a LOCAL view transform per constitution §I, never an RFB
/// message.  Only fires when `zoomScale > 1`; at fit scale the
/// one-finger drag remains the remote button-1 drag path.
public typealias MetalFramebufferPanHandler = @MainActor @Sendable (_ offset: CGSize, _ viewSize: CGSize) -> Void

/// Closure invoked on a double-tap.  The model toggles between fit
/// scale and a comfortable zoom centered on the tapped point — a LOCAL
/// view transform per constitution §I, never an RFB message.
public typealias MetalFramebufferZoomToggleHandler = @MainActor @Sendable (_ point: CGPoint, _ viewSize: CGSize) -> Void

/// Closure invoked for trackpad-mode gestures hosted directly by the
/// UIKit/Metal surface.  Returning the updated transform lets the host
/// apply auto-pan immediately, before SwiftUI's published-state round
/// trip catches up.
public typealias MetalFramebufferTrackpadGestureHandler = @MainActor @Sendable (
    _ gesture: PointerGesture,
    _ transform: ViewportTransform
) -> ViewportTransform?

public struct MetalFramebufferView: UIViewRepresentable {
    private let framebuffer: RFBRawFramebuffer
    private let dirtyRectangles: [RFBFrameDamageRect]?
    private let sessionID: RemoteSession.ID?
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
    private let pointerControlMode: PointerControlMode
    private let onTrackpadGesture: MetalFramebufferTrackpadGestureHandler?
    /// Current local zoom scale, owned by the SwiftUI parent and pushed
    /// down so the host's gesture handlers know whether a one-finger
    /// drag is a pan (zoomed) or a remote drag (fit), and so the pan
    /// clamp uses the live scale.
    private let zoomScale: CGFloat
    /// Current local pan offset, pushed down so the host stays in sync
    /// when the parent resets zoom/pan (e.g. the 1× button).
    private let panOffset: CGSize
    /// Current local minimum zoom scale. In immersive crop-to-fill mode this
    /// is often > 1, so the UIKit recognizer must clamp against the same
    /// baseline the SwiftUI parent uses.
    private let minimumZoomScale: CGFloat

    public init(
        framebuffer: RFBRawFramebuffer,
        dirtyRectangles: [RFBFrameDamageRect]? = nil,
        sessionID: RemoteSession.ID? = nil,
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        accessibilityIdentifier: String = "naru.session.metalFramebuffer",
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        minimumZoomScale: CGFloat = 1,
        onTap: MetalFramebufferTapHandler? = nil,
        onRightClick: MetalFramebufferRightClickHandler? = nil,
        onScroll: MetalFramebufferScrollHandler? = nil,
        onPinch: MetalFramebufferPinchHandler? = nil,
        onPointerDown: MetalFramebufferPointerDownHandler? = nil,
        onPointerMove: MetalFramebufferPointerMoveHandler? = nil,
        onPointerUp: MetalFramebufferPointerUpHandler? = nil,
        onPan: MetalFramebufferPanHandler? = nil,
        onZoomToggle: MetalFramebufferZoomToggleHandler? = nil,
        pointerControlMode: PointerControlMode = .directTouch,
        onTrackpadGesture: MetalFramebufferTrackpadGestureHandler? = nil
    ) {
        self.framebuffer = framebuffer
        self.dirtyRectangles = dirtyRectangles
        self.sessionID = sessionID
        self.device = device
        self.accessibilityIdentifier = accessibilityIdentifier
        self.zoomScale = zoomScale
        self.panOffset = panOffset
        self.minimumZoomScale = minimumZoomScale
        self.onTap = onTap
        self.onRightClick = onRightClick
        self.onScroll = onScroll
        self.onPinch = onPinch
        self.onPointerDown = onPointerDown
        self.onPointerMove = onPointerMove
        self.onPointerUp = onPointerUp
        self.onPan = onPan
        self.onZoomToggle = onZoomToggle
        self.pointerControlMode = pointerControlMode
        self.onTrackpadGesture = onTrackpadGesture
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
        host.trackpadGestureHandler = onTrackpadGesture
        host.syncInputState(
            pointerControlMode: pointerControlMode,
            framebufferSize: CGSize(width: framebuffer.width, height: framebuffer.height)
        )
        host.syncZoomPan(scale: zoomScale, offset: panOffset, minimumScale: minimumZoomScale)
        context.coordinator.prepareForSession(sessionID)
        // The very first frame after the view is constructed must
        // perform a full upload — the texture has just been created
        // and there is nothing prior on the GPU to combine with the
        // damage rects.  Pass nil here so the renderer takes the
        // full-frame path regardless of what the pump reported.
        context.coordinator.enqueue(framebuffer, dirtyRectangles: nil)
        return host
    }

    public func updateUIView(_ uiView: MetalFramebufferHostingView, context: Context) {
        context.coordinator.prepareForSession(sessionID)
        let didEnqueueFramebuffer = context.coordinator.enqueue(
            framebuffer,
            dirtyRectangles: dirtyRectangles
        )
        uiView.tapHandler = onTap
        uiView.rightClickHandler = onRightClick
        uiView.scrollHandler = onScroll
        uiView.pinchHandler = onPinch
        uiView.pointerDownHandler = onPointerDown
        uiView.pointerMoveHandler = onPointerMove
        uiView.pointerUpHandler = onPointerUp
        uiView.panHandler = onPan
        uiView.zoomToggleHandler = onZoomToggle
        uiView.trackpadGestureHandler = onTrackpadGesture
        uiView.syncInputState(
            pointerControlMode: pointerControlMode,
            framebufferSize: CGSize(width: framebuffer.width, height: framebuffer.height)
        )
        uiView.syncZoomPan(scale: zoomScale, offset: panOffset, minimumScale: minimumZoomScale)
        if didEnqueueFramebuffer {
            uiView.requestRedraw()
        }
    }

    /// Coordinator owns the long-lived `MetalFramebufferRenderer` and
    /// `MTKViewDelegate` so SwiftUI rebuilds of the representable do not
    /// thrash GPU resources.
    @MainActor
    public final class Coordinator {
        let renderer: MetalFramebufferRenderer?
        let delegate: MetalFramebufferViewDelegate?
        private var lastFramebufferDimensions: (width: Int, height: Int)?
        private var sessionID: RemoteSession.ID?
        private var uploadGate = FramebufferUploadGate()

        init(device: MTLDevice?) {
            if let device, let renderer = MetalFramebufferRenderer(device: device) {
                self.renderer = renderer
                self.delegate = MetalFramebufferViewDelegate(renderer: renderer)
            } else {
                self.renderer = nil
                self.delegate = nil
            }
        }

        func prepareForSession(_ nextSessionID: RemoteSession.ID?) {
            guard nextSessionID != sessionID else {
                return
            }
            sessionID = nextSessionID
            lastFramebufferDimensions = nil
            uploadGate.reset()
        }

        @discardableResult
        func enqueue(
            _ framebuffer: RFBRawFramebuffer,
            dirtyRectangles: [RFBFrameDamageRect]? = nil
        ) -> Bool {
            guard uploadGate.shouldEnqueue(
                framebuffer: framebuffer,
                dirtyRectangles: dirtyRectangles
            ) else {
                return false
            }
            renderer?.enqueue(framebuffer, dirtyRectangles: dirtyRectangles)
            lastFramebufferDimensions = (framebuffer.width, framebuffer.height)
            return true
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
    private struct PendingViewportState {
        var zoomScale: CGFloat
        var panOffset: CGSize
        var anchor: CGPoint
        var viewSize: CGSize
        var shouldPublishZoom: Bool
        var shouldPublishPan: Bool
    }

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
    /// (clamped) local view scale and pinch midpoint.  Pinch is LOCAL
    /// — no RFB message is generated by this path.
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

    /// Closure invoked for trackpad-mode gestures.  The model resolves
    /// cursor movement + remote pointer commands and returns any local
    /// auto-pan transform, which this host applies immediately.
    public var trackpadGestureHandler: MetalFramebufferTrackpadGestureHandler?

    /// Current one-finger input mode.  Direct-touch keeps the existing
    /// tap/drag behavior; trackpad mode turns tap/drag into cursor
    /// gestures without routing through a SwiftUI overlay.
    private var pointerControlMode: PointerControlMode = .directTouch

    /// Live framebuffer dimensions used to build the same pure
    /// `ViewportTransform` the SwiftUI overlay used before the Metal
    /// path took over trackpad gesture hosting.
    private var currentFramebufferSize: CGSize = .zero

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

    /// Trackpad drag state for deriving per-callback deltas from
    /// UIKit's cumulative pan translation.
    private var trackpadDragLastTranslation: CGSize = .zero
    private var trackpadDragMoved: Bool = false

    /// Current local zoom scale, owned by the host view so the
    /// recognizer can clamp incrementally between callbacks.  The
    /// SwiftUI parent mirrors the value through `pinchHandler`, while
    /// the host applies the visible transform directly to the MTKView
    /// so streaming-driven SwiftUI diffs do not sit in the gesture's
    /// critical path.
    private var currentZoomScale: CGFloat = 1.0

    /// Dynamic lower bound for pinch zoom.  Standard aspect-fit sessions use
    /// 1×, while immersive aspect-fill sessions may start above 1×.
    private var currentMinimumZoomScale: CGFloat = 1.0

    /// While a UIKit pinch or zoomed-pan gesture is active, SwiftUI may
    /// still rebuild this representable for incoming VNC frames.  Do
    /// not let those frame-driven updates overwrite the recognizer's
    /// in-flight accumulator with a one-frame-old parent value.
    private var isViewportTransformGestureActive = false

    /// Local clamp range applied to the zoom scale.  Mirrors the
    /// range applied by `SessionViewportView` so the host view's
    /// internal accumulator never drifts past the visible clamp.
    private static let minZoomScale: CGFloat = 1.0
    private static let maxZoomScale: CGFloat = 4.0

    /// Coalesces SwiftUI/PiP state mirroring while UIKit applies the
    /// visible Metal transform immediately.  This keeps frame-driven
    /// SwiftUI work out of the per-touch critical path.
    private var pendingViewportState: PendingViewportState?
    private var viewportStatePublishTask: Task<Void, Never>?

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
        clipsToBounds = true
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

        // Trackpad-mode right click.  In direct-touch mode we leave
        // two-finger tap inert for now and keep long-press as the
        // established secondary-click path.
        let secondaryTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSecondaryTapGesture(_:))
        )
        secondaryTapRecognizer.numberOfTouchesRequired = 2
        secondaryTapRecognizer.cancelsTouchesInView = false
        tapRecognizer.require(toFail: secondaryTapRecognizer)

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
        addGestureRecognizer(secondaryTapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(dragRecognizer)
        isUserInteractionEnabled = true
    }

    deinit {
        viewportStatePublishTask?.cancel()
    }

    /// Push the parent's current zoom/pan into the host so gesture
    /// handlers branch on the live scale and the pan accumulator does
    /// not drift after a parent-driven reset (the 1× button).
    public func syncZoomPan(scale: CGFloat, offset: CGSize, minimumScale: CGFloat = 1) {
        currentMinimumZoomScale = min(
            max(minimumScale, Self.minZoomScale),
            Self.maxZoomScale
        )
        guard !isViewportTransformGestureActive else {
            return
        }
        currentZoomScale = min(max(scale, currentMinimumZoomScale), Self.maxZoomScale)
        currentPanOffset = offset
        applyViewportTransformToMetalView()
    }

    public func syncInputState(pointerControlMode: PointerControlMode, framebufferSize: CGSize) {
        self.pointerControlMode = pointerControlMode
        self.currentFramebufferSize = CGSize(
            width: max(framebufferSize.width, 0),
            height: max(framebufferSize.height, 0)
        )
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
        guard recognizer.state == .ended else {
            return
        }
        let point = recognizer.location(in: self)
        if pointerControlMode.isTrackpad {
            dispatchTrackpadGesture(.tap(viewPoint: point))
        } else {
            tapHandler?(point, bounds.size)
        }
    }

    @MainActor
    @objc private func handleSecondaryTapGesture(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              pointerControlMode.isTrackpad
        else {
            return
        }
        dispatchTrackpadGesture(.secondaryTap(viewPoint: recognizer.location(in: self)))
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
        guard recognizer.state == .began else {
            return
        }
        let point = recognizer.location(in: self)
        if pointerControlMode.isTrackpad {
            dispatchTrackpadGesture(.secondaryTap(viewPoint: point))
        } else {
            rightClickHandler?(point, bounds.size)
        }
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
        switch recognizer.state {
        case .began:
            isViewportTransformGestureActive = true
        case .changed:
            break
        case .ended, .cancelled, .failed:
            isViewportTransformGestureActive = false
            flushPendingViewportState()
            return
        default:
            return
        }

        let previousZoomScale = currentZoomScale
        let proposed = previousZoomScale * recognizer.scale
        let anchor = recognizer.location(in: self)
        recognizer.scale = 1.0
        let clamped = min(max(proposed, currentMinimumZoomScale), Self.maxZoomScale)
        let proposedPan: CGSize
        if clamped <= currentMinimumZoomScale + 0.0001 {
            proposedPan = .zero
        } else {
            proposedPan = Self.anchoredPanOffset(
                currentPanOffset,
                previousZoomScale: previousZoomScale,
                newZoomScale: clamped,
                anchor: anchor,
                boundsSize: bounds.size
            )
        }
        currentZoomScale = clamped
        let nextPanOffset = clampedPan(proposedPan)
        let panDidChange = nextPanOffset != currentPanOffset
        currentPanOffset = nextPanOffset
        applyViewportTransformToMetalView()
        // Constitution §I: pinch is a LOCAL view transform.  We must
        // never translate this into a remote scroll/zoom event.  The
        // handler mirrors state into SwiftUI overlays and PiP focus;
        // the MTKView has already moved on this callback.
        queueViewportStatePublish(
            zoomScale: clamped,
            panOffset: nextPanOffset,
            anchor: anchor,
            viewSize: bounds.size,
            shouldPublishZoom: true,
            shouldPublishPan: panDidChange
        )
    }

    @MainActor
    @objc private func handleDragGesture(_ recognizer: UIPanGestureRecognizer) {
        if pointerControlMode.isTrackpad {
            handleTrackpadDrag(recognizer)
            return
        }

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
            isViewportTransformGestureActive = true
            recognizer.setTranslation(.zero, in: self)
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
            applyViewportTransformToMetalView()
            queueViewportStatePublish(
                zoomScale: currentZoomScale,
                panOffset: currentPanOffset,
                anchor: recognizer.location(in: self),
                viewSize: bounds.size,
                shouldPublishZoom: false,
                shouldPublishPan: true
            )
        case .ended, .cancelled, .failed:
            isViewportTransformGestureActive = false
            flushPendingViewportState()
        default:
            break
        }
    }

    /// One-finger drag in trackpad mode: move the local cursor
    /// relatively and let the model send buttonless pointer moves.
    /// Auto-pan returned by the model is applied to the MTKView here,
    /// avoiding a SwiftUI overlay/state round trip in the hot path.
    @MainActor
    private func handleTrackpadDrag(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isViewportTransformGestureActive = true
            trackpadDragLastTranslation = .zero
            trackpadDragMoved = false
            dispatchTrackpadGesture(.dragBegan(viewPoint: recognizer.location(in: self)))
        case .changed:
            let translation = recognizer.translation(in: self)
            let delta = CGSize(
                width: translation.x - trackpadDragLastTranslation.width,
                height: translation.y - trackpadDragLastTranslation.height
            )
            trackpadDragLastTranslation = CGSize(width: translation.x, height: translation.y)
            guard delta != .zero else {
                return
            }
            trackpadDragMoved = true
            dispatchTrackpadGesture(
                .dragChanged(viewPoint: recognizer.location(in: self), translation: delta)
            )
        case .ended, .cancelled, .failed:
            if trackpadDragMoved {
                dispatchTrackpadGesture(.dragEnded(viewPoint: recognizer.location(in: self)))
            }
            trackpadDragLastTranslation = .zero
            trackpadDragMoved = false
            isViewportTransformGestureActive = false
        default:
            break
        }
    }

    static func anchoredPanOffset(
        _ current: CGSize,
        previousZoomScale: CGFloat,
        newZoomScale: CGFloat,
        anchor: CGPoint,
        boundsSize: CGSize
    ) -> CGSize {
        guard previousZoomScale > 0,
              boundsSize.width > 0,
              boundsSize.height > 0
        else {
            return current
        }

        let zoomRatio = newZoomScale / previousZoomScale
        let center = CGPoint(x: boundsSize.width / 2, y: boundsSize.height / 2)
        return CGSize(
            width: anchor.x - center.x - zoomRatio * (anchor.x - center.x - current.width),
            height: anchor.y - center.y - zoomRatio * (anchor.y - center.y - current.height)
        )
    }

    private func applyViewportTransformToMetalView() {
        metalView?.transform = CGAffineTransform(
            a: currentZoomScale,
            b: 0,
            c: 0,
            d: currentZoomScale,
            tx: currentPanOffset.width,
            ty: currentPanOffset.height
        )
    }

    @MainActor
    private func queueViewportStatePublish(
        zoomScale: CGFloat,
        panOffset: CGSize,
        anchor: CGPoint,
        viewSize: CGSize,
        shouldPublishZoom: Bool,
        shouldPublishPan: Bool
    ) {
        let existing = pendingViewportState
        pendingViewportState = PendingViewportState(
            zoomScale: zoomScale,
            panOffset: panOffset,
            anchor: anchor,
            viewSize: viewSize,
            shouldPublishZoom: (existing?.shouldPublishZoom ?? false) || shouldPublishZoom,
            shouldPublishPan: (existing?.shouldPublishPan ?? false) || shouldPublishPan
        )

        guard viewportStatePublishTask == nil else {
            return
        }
        viewportStatePublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            self?.flushPendingViewportState()
        }
    }

    @MainActor
    private func flushPendingViewportState() {
        viewportStatePublishTask?.cancel()
        viewportStatePublishTask = nil
        guard let pending = pendingViewportState else {
            return
        }
        pendingViewportState = nil

        if pending.shouldPublishZoom {
            pinchHandler?(pending.zoomScale, pending.anchor, pending.viewSize)
        }
        if pending.shouldPublishPan {
            panHandler?(pending.panOffset, pending.viewSize)
        }
    }

    @discardableResult
    private func dispatchTrackpadGesture(_ gesture: PointerGesture) -> ViewportTransform? {
        guard let trackpadGestureHandler,
              currentFramebufferSize.width > 0,
              currentFramebufferSize.height > 0,
              bounds.width > 0,
              bounds.height > 0
        else {
            return nil
        }

        let transform = ViewportTransform(
            framebufferSize: currentFramebufferSize,
            viewSize: bounds.size,
            zoomScale: currentZoomScale,
            panOffset: currentPanOffset,
            maxZoomScale: Self.maxZoomScale
        )
        guard let updated = trackpadGestureHandler(gesture, transform) else {
            return nil
        }

        currentZoomScale = min(max(updated.zoomScale, currentMinimumZoomScale), Self.maxZoomScale)
        currentPanOffset = clampedPan(updated.panOffset)
        applyViewportTransformToMetalView()
        return updated
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
