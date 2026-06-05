import NaruRemoteCore
import SwiftUI

#if os(iOS) && canImport(UIKit) && canImport(Metal) && canImport(MetalKit)
import UIKit
import Metal
import MetalKit
import QuartzCore

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
public typealias MetalFramebufferViewportTransformHandler = @MainActor @Sendable (
    _ transform: ViewportTransform
) -> Void

/// Closure invoked for trackpad-mode gestures hosted directly by the
/// UIKit/Metal surface.  Returning the updated transform lets the host
/// apply auto-pan immediately, before SwiftUI's published-state round
/// trip catches up.
public typealias MetalFramebufferTrackpadGestureHandler = @MainActor @Sendable (
    _ gesture: PointerGesture,
    _ transform: ViewportTransform
) -> SessionViewportTrackpadGestureResult?

/// Closure invoked when the user starts or finishes a local viewport
/// manipulation (pinch, zoomed pan, or a trackpad cursor drag that
/// actually pans the local viewport). The app model uses this signal
/// to defer SwiftUI framebuffer publication while the Metal surface
/// stays on the compositor transform path.
public typealias MetalFramebufferViewportInteractionHandler = @MainActor @Sendable (Bool) -> Void

/// Closure invoked with safe aggregate local viewport redraw counters.
/// The host batches these counters locally and reports them at gesture
/// boundaries so diagnostics do not make the touch hot path publish
/// SwiftUI state at frame cadence.
public typealias MetalFramebufferViewportRedrawDiagnosticsHandler = @MainActor @Sendable (
    ViewportRedrawDiagnostics
) -> Void

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
    private let onViewportTransform: MetalFramebufferViewportTransformHandler?
    private let pointerControlMode: PointerControlMode
    private let trackpadCursor: TrackpadCursor
    private let serverCursor: RFBServerCursor?
    private let onTrackpadGesture: MetalFramebufferTrackpadGestureHandler?
    private let onViewportInteractionChange: MetalFramebufferViewportInteractionHandler?
    private let onViewportRedrawDiagnostics: MetalFramebufferViewportRedrawDiagnosticsHandler?
    private let onUploadTiming: MetalFramebufferUploadTimingHandler?
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
        onViewportTransform: MetalFramebufferViewportTransformHandler? = nil,
        pointerControlMode: PointerControlMode = .directTouch,
        trackpadCursor: TrackpadCursor = TrackpadCursor(),
        serverCursor: RFBServerCursor? = nil,
        onTrackpadGesture: MetalFramebufferTrackpadGestureHandler? = nil,
        onViewportInteractionChange: MetalFramebufferViewportInteractionHandler? = nil,
        onViewportRedrawDiagnostics: MetalFramebufferViewportRedrawDiagnosticsHandler? = nil,
        onUploadTiming: MetalFramebufferUploadTimingHandler? = nil
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
        self.onViewportTransform = onViewportTransform
        self.pointerControlMode = pointerControlMode
        self.trackpadCursor = trackpadCursor
        self.serverCursor = serverCursor
        self.onTrackpadGesture = onTrackpadGesture
        self.onViewportInteractionChange = onViewportInteractionChange
        self.onViewportRedrawDiagnostics = onViewportRedrawDiagnostics
        self.onUploadTiming = onUploadTiming
    }

    public static func isSupported() -> Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(device: device)
    }

    public func makeUIView(context: Context) -> MetalFramebufferHostingView {
        let host = MetalFramebufferHostingView(coordinator: context.coordinator)
        context.coordinator.updateUploadTimingHandler(onUploadTiming)
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
        host.viewportTransformHandler = onViewportTransform
        host.trackpadGestureHandler = onTrackpadGesture
        host.viewportInteractionHandler = onViewportInteractionChange
        host.viewportRedrawDiagnosticsHandler = onViewportRedrawDiagnostics
        host.syncInputState(
            pointerControlMode: pointerControlMode,
            trackpadCursor: trackpadCursor,
            serverCursor: serverCursor,
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
        host.requestRedrawForIncomingFrame()
        return host
    }

    public func updateUIView(_ uiView: MetalFramebufferHostingView, context: Context) {
        context.coordinator.prepareForSession(sessionID)
        context.coordinator.updateUploadTimingHandler(onUploadTiming)
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
        uiView.viewportTransformHandler = onViewportTransform
        uiView.trackpadGestureHandler = onTrackpadGesture
        uiView.viewportInteractionHandler = onViewportInteractionChange
        uiView.viewportRedrawDiagnosticsHandler = onViewportRedrawDiagnostics
        uiView.syncInputState(
            pointerControlMode: pointerControlMode,
            trackpadCursor: trackpadCursor,
            serverCursor: serverCursor,
            framebufferSize: CGSize(width: framebuffer.width, height: framebuffer.height)
        )
        uiView.syncZoomPan(scale: zoomScale, offset: panOffset, minimumScale: minimumZoomScale)
        if didEnqueueFramebuffer {
            uiView.requestRedrawForIncomingFrame()
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

        func updateUploadTimingHandler(_ handler: MetalFramebufferUploadTimingHandler?) {
            renderer?.uploadTimingHandler = handler
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
    private let hotCursorView = UIImageView()

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
    public var viewportTransformHandler: MetalFramebufferViewportTransformHandler?

    /// Closure invoked for trackpad-mode gestures.  The model resolves
    /// cursor movement + remote pointer commands and returns any local
    /// auto-pan transform, which this host applies through the Metal
    /// renderer immediately.
    public var trackpadGestureHandler: MetalFramebufferTrackpadGestureHandler?

    /// Signals when the host is locally manipulating the viewport.
    /// This lets the model merge incoming frames to the newest pending
    /// frame instead of making SwiftUI republish during every touch
    /// sample.
    public var viewportInteractionHandler: MetalFramebufferViewportInteractionHandler?

    /// Reports batched, safe redraw diagnostics at viewport gesture
    /// boundaries. This stays off the per-touch publish path.
    public var viewportRedrawDiagnosticsHandler: MetalFramebufferViewportRedrawDiagnosticsHandler?

    /// Current one-finger input mode.  Direct-touch keeps the existing
    /// tap/drag behavior; trackpad mode turns tap/drag into cursor
    /// gestures without routing through a SwiftUI overlay.
    private var pointerControlMode: PointerControlMode = .directTouch

    /// Latest trackpad cursor fed from SwiftUI or returned immediately
    /// by the model while the UIKit recognizer is in the hot path.
    private var currentTrackpadCursor = TrackpadCursor()

    /// Latest server-provided cursor shape.  Rendered here when
    /// available so the actual remote pointer shape follows the
    /// immediate trackpad cursor, not SwiftUI's published-state cadence.
    private var currentServerCursor: RFBServerCursor?
    private var currentServerCursorImage: UIImage?

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
    private var isTrackpadDragActive = false
    private var trackpadDragMoved: Bool = false
    private var trackpadDragOwnsViewportInteraction: Bool = false

    /// Current local zoom scale, owned by the host view so the
    /// recognizer can clamp incrementally between callbacks.  The
    /// SwiftUI parent mirrors the value through `pinchHandler`, while
    /// the host applies the visible transform directly to the embedded
    /// `MTKView` layer so streaming-driven SwiftUI diffs do not sit in
    /// the gesture's critical path.
    private var currentZoomScale: CGFloat = 1.0

    /// Dynamic lower bound for pinch zoom.  Standard aspect-fit sessions use
    /// 1×, while immersive aspect-fill sessions may start above 1×.
    private var currentMinimumZoomScale: CGFloat = 1.0

    /// While a UIKit pinch or zoomed-pan gesture is active, SwiftUI may
    /// still rebuild this representable for incoming VNC frames.  Do
    /// not let those frame-driven updates overwrite the recognizer's
    /// in-flight accumulator with a one-frame-old parent value.
    private var isViewportTransformGestureActive = false

    /// A two-finger pinch can be recognized simultaneously with the
    /// two-finger pan recognizer. While pinch is active, the pan
    /// recognizer's translation is local gesture drift, not remote
    /// scroll intent.
    private var isPinchGestureActive = false
    private var pinchLastAnchor: CGPoint?

    /// Local clamp range applied to the zoom scale.  Mirrors the
    /// range applied by `SessionViewportView` so the host view's
    /// internal accumulator never drifts past the visible clamp.
    private static let minZoomScale: CGFloat = 1.0
    private static let maxZoomScale: CGFloat = 4.0

    /// Coalesces or defers SwiftUI/PiP state mirroring while the Metal
    /// renderer applies the visible viewport transform immediately.
    /// This keeps frame-driven SwiftUI work out of the per-touch
    /// critical path.
    private var pendingViewportState: PendingViewportState?
    private var viewportStateDisplayLink: CADisplayLink?
    private var deferredViewportStateRequiresFlush = false
    private var viewportDecelerationDisplayLink: CADisplayLink?
    private var viewportDecelerationVelocity: CGPoint = .zero
    private var viewportDecelerationLastTimestamp: CFTimeInterval?
    private var viewportGestureLastSampleTimestamp: CFTimeInterval?
    private var pendingViewportRedrawDiagnostics = ViewportRedrawDiagnostics()
    private var viewportGestureRedrawThrottle = ViewportGestureRedrawThrottle(
        minimumInterval: MetalFramebufferHostingView.viewportGestureRedrawMinimumInterval,
        allowsFirstRedrawDuringGesture: true
    )
    private var deferredFramebufferRedrawDuringViewportGesture = false
    private static let minimumDecelerationVelocity: CGFloat = 18
    private static let decelerationVelocityDecayPerSecond: CGFloat = 0.12
    // The local transform stays on the compositor path, but real-device
    // feedback showed that deferring every streamed frame until gesture end
    // makes remote cursor/desktop changes appear frozen. Allow localized
    // dirty-rect refresh slots while pinching/panning; request pacing keeps
    // full uploads conservative and only promotes partial cursor/text echo.
    private static let viewportGestureRedrawMinimumInterval: TimeInterval =
        StreamPressurePacingDefaults.viewportInteractionPartialContentFrameIntervalSeconds
    private static let viewportGestureLongFrameInterval: TimeInterval = 0.024

    private enum ViewportStatePublishCadence {
        case nextDisplayLink
        case gestureEnd
    }

    private static let interactiveViewportStatePublishCadence: ViewportStatePublishCadence =
        .gestureEnd

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

        hotCursorView.isHidden = true
        hotCursorView.isUserInteractionEnabled = false
        hotCursorView.contentMode = .scaleToFill
        hotCursorView.tintColor = .white
        hotCursorView.layer.shadowColor = UIColor.black.cgColor
        hotCursorView.layer.shadowOpacity = 0.55
        hotCursorView.layer.shadowRadius = 2
        hotCursorView.layer.shadowOffset = CGSize(width: 0, height: 1)
        hotCursorView.layer.magnificationFilter = .nearest
        hotCursorView.layer.minificationFilter = .nearest
        addSubview(hotCursorView)

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

        // Single-finger pan is the drag-to-move recognizer. It coexists
        // with long-press and tap so zoomed panning can begin as soon as
        // UIKit has classified movement, instead of waiting for the
        // long-press timeout before the viewport follows the finger. Tap
        // and long-press precedence is preserved by the
        // `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`
        // delegate hook and by deferring
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

        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(doubleTapRecognizer)
        addGestureRecognizer(secondaryTapRecognizer)
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(dragRecognizer)
        isUserInteractionEnabled = true
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
        let nextZoomScale = min(max(scale, currentMinimumZoomScale), Self.maxZoomScale)
        let nextPanOffset = viewportTransform(
            zoomScale: nextZoomScale,
            panOffset: offset
        ).panOffset
        let didChange = abs(nextZoomScale - currentZoomScale) > 0.0001
            || nextPanOffset != currentPanOffset
        currentZoomScale = nextZoomScale
        currentPanOffset = nextPanOffset
        if didChange {
            applyViewportTransformToMetalView()
        }
    }

    public func syncInputState(
        pointerControlMode: PointerControlMode,
        trackpadCursor: TrackpadCursor,
        serverCursor: RFBServerCursor?,
        framebufferSize: CGSize
    ) {
        let didChangePointerControlMode = self.pointerControlMode != pointerControlMode
        self.pointerControlMode = pointerControlMode
        if TrackpadCursorSnapshotPolicy.shouldAdoptPublishedCursor(
            pointerControlMode: pointerControlMode,
            didChangePointerControlMode: didChangePointerControlMode,
            isTrackpadDragActive: isTrackpadDragActive
        ) {
            currentTrackpadCursor = trackpadCursor
        }
        if currentServerCursor != serverCursor {
            currentServerCursor = serverCursor
            currentServerCursorImage = serverCursor.flatMap(Self.cursorImage(_:))
        }
        self.currentFramebufferSize = CGSize(
            width: max(framebufferSize.width, 0),
            height: max(framebufferSize.height, 0)
        )
        updateHotCursorOverlay()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyViewportTransformToMetalView()
    }

    private var isZoomed: Bool { currentZoomScale > 1.0001 }

    private var canPanViewport: Bool {
        viewportTransform(zoomScale: currentZoomScale, panOffset: currentPanOffset).isPannable
    }

    /// Clamp against the actual aspect-fit framebuffer content, not
    /// the MTKView rectangle. The remote frame is first aspect-fit by
    /// the renderer, then locally zoomed/panned by this host; wide
    /// desktops in portrait otherwise hit the wrong boundary and feel
    /// sticky near crop-to-fill edges.
    private func clampedPan(_ pan: CGSize) -> CGSize {
        viewportTransform(zoomScale: currentZoomScale, panOffset: pan).panOffset
    }

    private func viewportTransform(
        zoomScale: CGFloat,
        panOffset: CGSize
    ) -> ViewportTransform {
        ViewportTransform(
            framebufferSize: currentFramebufferSize,
            viewSize: bounds.size,
            zoomScale: zoomScale,
            panOffset: panOffset,
            maxZoomScale: Self.maxZoomScale
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

    /// Request a redraw for a newly arrived remote frame, giving touch
    /// tracking priority while the local viewport is being manipulated.
    public func requestRedrawForIncomingFrame(now: TimeInterval = CACurrentMediaTime()) {
        if isViewportTransformGestureActive {
            switch viewportGestureRedrawThrottle.recordIncomingFrame(
                isGestureActive: true,
                now: now
            ) {
            case .requestNow:
                coordinator?.renderer?.allowNextPendingFramebufferUploadWhileSuspended()
                pendingViewportRedrawDiagnostics.redrawRequestCount += 1
                requestRedraw()
            case .deferRedraw:
                deferredFramebufferRedrawDuringViewportGesture = true
                pendingViewportRedrawDiagnostics.incomingFrameDeferredCount += 1
            }
            return
        }

        switch viewportGestureRedrawThrottle.recordIncomingFrame(
            isGestureActive: false,
            now: now
        ) {
        case .requestNow:
            requestRedraw()
        case .deferRedraw:
            break
        }
    }

    @MainActor
    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard newWindow == nil else {
            return
        }
        viewportStateDisplayLink?.invalidate()
        viewportStateDisplayLink = nil
        viewportDecelerationDisplayLink?.invalidate()
        viewportDecelerationDisplayLink = nil
        viewportDecelerationVelocity = .zero
        viewportDecelerationLastTimestamp = nil
        viewportGestureRedrawThrottle.reset()
        deferredFramebufferRedrawDuringViewportGesture = false
        trackpadDragOwnsViewportInteraction = false
        finishViewportTransformGesture()
        flushViewportRedrawDiagnosticsIfNeeded()
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
        stopViewportDeceleration()
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
        guard !isPinchGestureActive else {
            recognizer.setTranslation(.zero, in: self)
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
            stopViewportDeceleration()
            beginViewportTransformGesture()
            isPinchGestureActive = true
            pinchLastAnchor = recognizer.location(in: self)
        case .changed:
            break
        case .ended, .cancelled, .failed:
            isPinchGestureActive = false
            pinchLastAnchor = nil
            finishViewportTransformGesture()
            return
        default:
            return
        }

        let previousZoomScale = currentZoomScale
        recordViewportGestureSample()
        let proposed = previousZoomScale * recognizer.scale
        let anchor = recognizer.location(in: self)
        let previousAnchor = pinchLastAnchor ?? anchor
        let anchorDelta = CGSize(
            width: anchor.x - previousAnchor.x,
            height: anchor.y - previousAnchor.y
        )
        pinchLastAnchor = anchor
        recognizer.scale = 1.0
        let nextTransform = viewportTransform(
            zoomScale: previousZoomScale,
            panOffset: currentPanOffset
        )
        .pinched(
            to: proposed,
            about: anchor,
            anchorDelta: anchorDelta,
            minimumZoomScale: currentMinimumZoomScale
        )
        currentZoomScale = nextTransform.zoomScale
        let nextPanOffset = nextTransform.panOffset
        let panDidChange = nextPanOffset != currentPanOffset
        currentPanOffset = nextPanOffset
        applyViewportTransformToMetalView()
        // Constitution §I: pinch is a LOCAL view transform.  We must
        // never translate this into a remote scroll/zoom event.  The layer
        // transform stays immediate so the content remains under the user's
        // fingers; SwiftUI overlays and PiP focus catch up at gesture end.
        queueViewportStatePublish(
            zoomScale: currentZoomScale,
            panOffset: nextPanOffset,
            anchor: anchor,
            viewSize: bounds.size,
            shouldPublishZoom: true,
            shouldPublishPan: panDidChange,
            cadence: Self.interactiveViewportStatePublishCadence
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
            stopViewportDeceleration()
            beginViewportTransformGesture()
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
            let initialTranslation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            applyZoomedPanTranslation(
                initialTranslation,
                anchor: recognizer.location(in: self)
            )
        case .changed:
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            applyZoomedPanTranslation(
                translation,
                anchor: recognizer.location(in: self)
            )
        case .ended:
            let velocity = recognizer.velocity(in: self)
            if startViewportDecelerationIfNeeded(velocity: velocity) {
                return
            }
            finishViewportTransformGesture()
        case .cancelled, .failed:
            finishViewportTransformGesture()
        default:
            break
        }
    }

    @MainActor
    private func applyZoomedPanTranslation(_ translation: CGPoint, anchor: CGPoint) {
        applyZoomedPanTranslation(
            CGSize(width: translation.x, height: translation.y),
            anchor: anchor
        )
    }

    @MainActor
    private func applyZoomedPanTranslation(_ translation: CGSize, anchor: CGPoint) {
        guard translation != .zero else {
            return
        }
        recordViewportGestureSample()
        let proposed = CGSize(
            width: currentPanOffset.width + translation.width,
            height: currentPanOffset.height + translation.height
        )
        let nextPanOffset = clampedPan(proposed)
        guard nextPanOffset != currentPanOffset else {
            return
        }
        currentPanOffset = nextPanOffset
        applyViewportTransformToMetalView()
        queueViewportStatePublish(
            zoomScale: currentZoomScale,
            panOffset: currentPanOffset,
            anchor: anchor,
            viewSize: bounds.size,
            shouldPublishZoom: false,
            shouldPublishPan: true,
            cadence: Self.interactiveViewportStatePublishCadence
        )
    }

    /// One-finger drag in trackpad mode: move the local cursor
    /// relatively and let the model send buttonless pointer moves.
    /// Auto-pan returned by the model is applied through the Metal
    /// renderer here, avoiding a SwiftUI overlay/state round trip in
    /// the hot path.
    @MainActor
    private func handleTrackpadDrag(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopViewportDeceleration()
            isTrackpadDragActive = true
            trackpadDragOwnsViewportInteraction = SessionViewportView
                .trackpadDragOwnsViewportInteraction(
                    transform: viewportTransform(
                        zoomScale: currentZoomScale,
                        panOffset: currentPanOffset
                    )
                )
            if trackpadDragOwnsViewportInteraction {
                beginViewportTransformGesture()
            }
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
            if trackpadDragOwnsViewportInteraction {
                recordViewportGestureSample()
            }
            dispatchTrackpadGesture(
                .dragChanged(viewPoint: recognizer.location(in: self), translation: delta)
            )
        case .ended, .cancelled, .failed:
            if trackpadDragMoved {
                dispatchTrackpadGesture(.dragEnded(viewPoint: recognizer.location(in: self)))
            }
            trackpadDragLastTranslation = .zero
            trackpadDragMoved = false
            if trackpadDragOwnsViewportInteraction {
                finishViewportTransformGesture()
            }
            trackpadDragOwnsViewportInteraction = false
            isTrackpadDragActive = false
        default:
            break
        }
    }

    private func applyViewportTransformToMetalView() {
        // Keep local viewport navigation on Core Animation's compositor
        // path. The renderer already draws the latest texture at its
        // stable aspect-fit baseline, so the hot path should not mutate
        // renderer state for every display tick.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            metalView?.transform = viewportLayerTransform()
        }
        CATransaction.commit()
        updateHotCursorOverlay()
    }

    private func viewportLayerTransform() -> CGAffineTransform {
        let clampedScale = min(max(currentZoomScale, currentMinimumZoomScale), Self.maxZoomScale)
        guard clampedScale > 0 else {
            return .identity
        }

        // `UIView.transform` already scales around the view's layer
        // anchor point (center by default). Keep the matrix simple:
        // translate the scaled surface by the clamped local pan.
        return CGAffineTransform(
            translationX: currentPanOffset.width,
            y: currentPanOffset.height
        )
            .scaledBy(x: clampedScale, y: clampedScale)
    }

    @MainActor
    private func startViewportDecelerationIfNeeded(velocity: CGPoint) -> Bool {
        let clampedStart = clampedPan(currentPanOffset)
        guard clampedStart == currentPanOffset else {
            currentPanOffset = clampedStart
            applyViewportTransformToMetalView()
            queueViewportStatePublish(
                zoomScale: currentZoomScale,
                panOffset: currentPanOffset,
                anchor: CGPoint(x: bounds.midX, y: bounds.midY),
                viewSize: bounds.size,
                shouldPublishZoom: false,
                shouldPublishPan: true,
                cadence: .gestureEnd
            )
            return false
        }

        let speed = hypot(velocity.x, velocity.y)
        guard isZoomed,
              speed >= Self.minimumDecelerationVelocity,
              bounds.width > 0,
              bounds.height > 0
        else {
            return false
        }

        viewportDecelerationVelocity = velocity
        viewportDecelerationLastTimestamp = CACurrentMediaTime()
        beginViewportTransformGesture()

        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(handleViewportDecelerationFrame(_:))
        )
        configureViewportDisplayLink(displayLink)
        displayLink.add(to: .main, forMode: .common)
        viewportDecelerationDisplayLink = displayLink
        return true
    }

    private func recordViewportDisplayRefreshRate() {
        let screenMaximum = window?.screen.maximumFramesPerSecond
            ?? UIScreen.main.maximumFramesPerSecond
        pendingViewportRedrawDiagnostics.observedMaximumFramesPerSecond = max(
            pendingViewportRedrawDiagnostics.observedMaximumFramesPerSecond,
            max(60, screenMaximum)
        )
    }

    private func configureViewportDisplayLink(_ displayLink: CADisplayLink) {
        let screenMaximum = window?.screen.maximumFramesPerSecond
            ?? UIScreen.main.maximumFramesPerSecond
        let maximum = Float(max(60, screenMaximum))
        recordViewportDisplayRefreshRate()
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(60, maximum),
            maximum: maximum,
            preferred: maximum
        )
    }

    @MainActor
    @objc
    private func handleViewportDecelerationFrame(_ displayLink: CADisplayLink) {
        pendingViewportRedrawDiagnostics.decelerationFrameCount += 1
        guard isZoomed else {
            finishViewportDeceleration()
            return
        }

        let timestamp = displayLink.timestamp
        let previousTimestamp = viewportDecelerationLastTimestamp ?? timestamp
        viewportDecelerationLastTimestamp = timestamp
        let deltaTime = min(max(timestamp - previousTimestamp, 1.0 / 120.0), 1.0 / 30.0)
        guard deltaTime.isFinite, deltaTime > 0 else {
            return
        }

        let proposed = CGSize(
            width: currentPanOffset.width + viewportDecelerationVelocity.x * deltaTime,
            height: currentPanOffset.height + viewportDecelerationVelocity.y * deltaTime
        )
        let nextPanOffset = clampedPan(proposed)
        let movedX = abs(nextPanOffset.width - currentPanOffset.width) > 0.01
        let movedY = abs(nextPanOffset.height - currentPanOffset.height) > 0.01

        currentPanOffset = nextPanOffset
        applyViewportTransformToMetalView()
        queueViewportStatePublish(
            zoomScale: currentZoomScale,
            panOffset: currentPanOffset,
            anchor: CGPoint(x: bounds.midX, y: bounds.midY),
            viewSize: bounds.size,
            shouldPublishZoom: false,
            shouldPublishPan: true,
            cadence: Self.interactiveViewportStatePublishCadence
        )

        if !movedX {
            viewportDecelerationVelocity.x = 0
        }
        if !movedY {
            viewportDecelerationVelocity.y = 0
        }

        let decay = pow(Self.decelerationVelocityDecayPerSecond, CGFloat(deltaTime))
        viewportDecelerationVelocity.x *= decay
        viewportDecelerationVelocity.y *= decay

        let speed = hypot(viewportDecelerationVelocity.x, viewportDecelerationVelocity.y)
        if speed < Self.minimumDecelerationVelocity || (!movedX && !movedY) {
            finishViewportDeceleration()
        }
    }

    @MainActor
    private func finishViewportDeceleration() {
        viewportDecelerationDisplayLink?.invalidate()
        viewportDecelerationDisplayLink = nil
        viewportDecelerationVelocity = .zero
        viewportDecelerationLastTimestamp = nil
        viewportGestureLastSampleTimestamp = nil
        finishViewportTransformGesture()
    }

    @MainActor
    private func stopViewportDeceleration() {
        guard viewportDecelerationDisplayLink != nil else {
            return
        }
        viewportDecelerationDisplayLink?.invalidate()
        viewportDecelerationDisplayLink = nil
        viewportDecelerationVelocity = .zero
        viewportDecelerationLastTimestamp = nil
        viewportGestureLastSampleTimestamp = nil
        finishViewportTransformGesture()
    }

    @MainActor
    private func finishViewportTransformGesture() {
        let wasActive = isViewportTransformGestureActive
        isViewportTransformGestureActive = false
        viewportGestureLastSampleTimestamp = nil
        coordinator?.renderer?.setPendingFramebufferUploadSuspended(false)
        let shouldFlushRedraw = viewportGestureRedrawThrottle.flushAfterGesture()
            || deferredFramebufferRedrawDuringViewportGesture
        deferredFramebufferRedrawDuringViewportGesture = false
        if deferredViewportStateRequiresFlush || pendingViewportState != nil {
            flushPendingViewportState()
        }
        if shouldFlushRedraw {
            pendingViewportRedrawDiagnostics.redrawFlushCount += 1
            requestRedraw()
        }
        if wasActive {
            viewportInteractionHandler?(false)
        }
        flushViewportRedrawDiagnosticsIfNeeded()
    }

    @MainActor
    private func beginViewportTransformGesture() {
        let wasInactive = !isViewportTransformGestureActive
        if wasInactive {
            deferredFramebufferRedrawDuringViewportGesture = false
        }
        isViewportTransformGestureActive = true
        coordinator?.renderer?.setPendingFramebufferUploadSuspended(true)
        if wasInactive {
            viewportGestureLastSampleTimestamp = nil
            pendingViewportRedrawDiagnostics.interactionCount += 1
            recordViewportDisplayRefreshRate()
            viewportInteractionHandler?(true)
        }
    }

    private func recordViewportGestureSample(now: CFTimeInterval = CACurrentMediaTime()) {
        pendingViewportRedrawDiagnostics.gestureSampleCount += 1
        if let previous = viewportGestureLastSampleTimestamp {
            let interval = max(0, now - previous)
            let milliseconds = Int((interval * 1_000).rounded())
            pendingViewportRedrawDiagnostics.gestureMaxIntervalMilliseconds = max(
                pendingViewportRedrawDiagnostics.gestureMaxIntervalMilliseconds,
                milliseconds
            )
            if interval > Self.viewportGestureLongFrameInterval {
                pendingViewportRedrawDiagnostics.gestureLongFrameCount += 1
            }
        }
        viewportGestureLastSampleTimestamp = now
    }

    @MainActor
    private func flushViewportRedrawDiagnosticsIfNeeded() {
        guard pendingViewportRedrawDiagnostics.hasSamples else {
            return
        }
        let diagnostics = pendingViewportRedrawDiagnostics
        pendingViewportRedrawDiagnostics = ViewportRedrawDiagnostics()
        viewportRedrawDiagnosticsHandler?(diagnostics)
    }

    @MainActor
    private func queueViewportStatePublish(
        zoomScale: CGFloat,
        panOffset: CGSize,
        anchor: CGPoint,
        viewSize: CGSize,
        shouldPublishZoom: Bool,
        shouldPublishPan: Bool,
        cadence: ViewportStatePublishCadence = .nextDisplayLink
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

        guard cadence == .nextDisplayLink else {
            deferredViewportStateRequiresFlush = true
            viewportStateDisplayLink?.invalidate()
            viewportStateDisplayLink = nil
            return
        }

        guard viewportStateDisplayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFlushPendingViewportState(_:)))
        configureViewportDisplayLink(displayLink)
        displayLink.add(to: .main, forMode: .common)
        viewportStateDisplayLink = displayLink
    }

    @MainActor
    @objc
    private func displayLinkFlushPendingViewportState(_ displayLink: CADisplayLink) {
        flushPendingViewportState()
    }

    @MainActor
    private func flushPendingViewportState() {
        viewportStateDisplayLink?.invalidate()
        viewportStateDisplayLink = nil
        deferredViewportStateRequiresFlush = false
        guard let pending = pendingViewportState else {
            return
        }
        pendingViewportState = nil

        if let viewportTransformHandler {
            // The Metal host owns the final gesture transform, so prefer
            // this atomic sync path over replaying legacy zoom and pan
            // callbacks separately at gesture end.
            viewportTransformHandler(
                ViewportTransform(
                    framebufferSize: currentFramebufferSize,
                    viewSize: pending.viewSize,
                    zoomScale: pending.zoomScale,
                    panOffset: pending.panOffset,
                    maxZoomScale: Self.maxZoomScale
                )
            )
            return
        }

        if pending.shouldPublishZoom {
            pinchHandler?(pending.zoomScale, pending.anchor, pending.viewSize)
        }
        if pending.shouldPublishPan {
            panHandler?(pending.panOffset, pending.viewSize)
        }
    }

    @discardableResult
    private func dispatchTrackpadGesture(_ gesture: PointerGesture) -> SessionViewportTrackpadGestureResult? {
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
        guard let result = trackpadGestureHandler(gesture, transform) else {
            return nil
        }

        let updated = result.transform
        let zoomDidChange = abs(updated.zoomScale - currentZoomScale) > 0.0001
        let panDidChange = updated.panOffset != currentPanOffset
        currentTrackpadCursor = result.cursor
        currentZoomScale = min(max(updated.zoomScale, currentMinimumZoomScale), Self.maxZoomScale)
        currentPanOffset = clampedPan(updated.panOffset)
        if zoomDidChange || panDidChange {
            applyViewportTransformToMetalView()
            queueViewportStatePublish(
                zoomScale: currentZoomScale,
                panOffset: currentPanOffset,
                anchor: viewportAnchor(for: gesture),
                viewSize: bounds.size,
                shouldPublishZoom: zoomDidChange,
                shouldPublishPan: panDidChange,
                cadence: Self.interactiveViewportStatePublishCadence
            )
        } else {
            updateHotCursorOverlay()
        }
        return result
    }

    private func updateHotCursorOverlay() {
        guard pointerControlMode.isTrackpad,
              currentTrackpadCursor.isVisible,
              currentFramebufferSize.width > 0,
              currentFramebufferSize.height > 0,
              bounds.width > 0,
              bounds.height > 0
        else {
            hotCursorView.isHidden = true
            return
        }

        let transform = ViewportTransform(
            framebufferSize: currentFramebufferSize,
            viewSize: bounds.size,
            zoomScale: currentZoomScale,
            panOffset: currentPanOffset,
            maxZoomScale: Self.maxZoomScale
        )
        let anchor = transform.viewPoint(fromFramebufferPoint: currentTrackpadCursor.position)

        if let cursor = currentServerCursor,
           cursor.width > 0,
           cursor.height > 0,
           let image = currentServerCursorImage {
            let visualScale = max(1, transform.displayScale)
            let size = CGSize(
                width: CGFloat(cursor.width) * visualScale,
                height: CGFloat(cursor.height) * visualScale
            )
            let origin = CGPoint(
                x: anchor.x - CGFloat(cursor.hotSpotX) * visualScale,
                y: anchor.y - CGFloat(cursor.hotSpotY) * visualScale
            )
            hotCursorView.image = image
            hotCursorView.bounds = CGRect(origin: .zero, size: size)
            hotCursorView.center = CGPoint(
                x: origin.x + size.width / 2,
                y: origin.y + size.height / 2
            )
        } else {
            hotCursorView.image = UIImage(systemName: "cursorarrow")
            hotCursorView.bounds = CGRect(origin: .zero, size: CGSize(width: 22, height: 22))
            hotCursorView.center = anchor
        }

        hotCursorView.isHidden = false
        bringSubviewToFront(hotCursorView)
    }

    private static func cursorImage(_ cursor: RFBServerCursor) -> UIImage? {
        guard cursor.width > 0, cursor.height > 0 else {
            return nil
        }

        let size = CGSize(width: CGFloat(cursor.width), height: CGFloat(cursor.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            for y in 0..<cursor.height {
                for x in 0..<cursor.width {
                    guard let color = cursor[x, y], color.alpha > 0 else {
                        continue
                    }
                    context.cgContext.setFillColor(
                        UIColor(
                            red: CGFloat(color.red) / 255.0,
                            green: CGFloat(color.green) / 255.0,
                            blue: CGFloat(color.blue) / 255.0,
                            alpha: CGFloat(color.alpha) / 255.0
                        ).cgColor
                    )
                    context.cgContext.fill(
                        CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1)
                    )
                }
            }
        }
    }

    private func viewportAnchor(for gesture: PointerGesture) -> CGPoint {
        switch gesture {
        case let .tap(viewPoint),
             let .secondaryTap(viewPoint),
             let .longPress(viewPoint),
             let .dragBegan(viewPoint),
             let .dragChanged(viewPoint, _),
             let .dragEnded(viewPoint):
            return viewPoint
        case .pressDragBegan,
             .pressDragChanged,
             .pressDragEnded:
            return CGPoint(x: bounds.midX, y: bounds.midY)
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
