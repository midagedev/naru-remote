import NaruRemoteCore
import SwiftUI

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
#endif

public typealias SessionFramebufferTapHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias SessionFramebufferRightClickHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias SessionFramebufferScrollHandler = @MainActor @Sendable (
    _ point: CGPoint,
    _ viewSize: CGSize,
    _ delta: CGSize
) -> Void
public typealias SessionFramebufferPointerDownHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias SessionFramebufferPointerMoveHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias SessionFramebufferPointerUpHandler = @MainActor @Sendable (CGPoint, CGSize) -> Void
public typealias SessionRendererUploadTimingHandler = @MainActor @Sendable (_ milliseconds: Int) -> Void
public typealias SessionViewportSizeChangeHandler = @MainActor @Sendable (_ size: CGSize) -> Void
public typealias SessionViewportRedrawDiagnosticsHandler = @MainActor @Sendable (
    ViewportRedrawDiagnostics
) -> Void

public struct SessionViewportView: View {
    private let title: String
    private let subtitle: String
    private let session: RemoteSession?
    private let framebuffer: RFBRawFramebuffer?
    private let inputCoordinateSpace: RemoteFramebufferCoordinateSpace?
    private let frameStore: SessionFrameStore?
    private let frameDirtyRectangles: [RFBFrameDamageRect]?
    private let frameChangedPixelCount: Int?
    private let serverCursor: RFBServerCursor?
    private let isPiPWatchAvailable: Bool
    private let pipWatchStatusText: String
    private let isPiPWatching: Bool
    private let usesHelperVideoPrimaryPreview: Bool
    private let onRunChecks: (() -> Void)?
    private let onConnect: (() -> Void)?
    private let onDisconnect: (() -> Void)?
    private let onStartPiPWatch: (() -> Void)?
    private let onFramebufferTap: SessionFramebufferTapHandler?
    private let onFramebufferRightClick: SessionFramebufferRightClickHandler?
    private let onFramebufferScroll: SessionFramebufferScrollHandler?
    private let onFramebufferPointerDown: SessionFramebufferPointerDownHandler?
    private let onFramebufferPointerMove: SessionFramebufferPointerMoveHandler?
    private let onFramebufferPointerUp: SessionFramebufferPointerUpHandler?
    /// How a one-finger gesture is interpreted (spec 003 US3 / T015).
    /// `.directTouch` keeps the tap-where-you-touch wire path; `.trackpad`
    /// draws the trackpad cursor and routes gestures through
    /// `onTrackpadGesture`. Constitution §I: viewport auto-pan is LOCAL;
    /// cursor moves reach the remote OS as buttonless pointer moves.
    private let pointerControlMode: PointerControlMode
    /// Trackpad cursor (framebuffer pixels) drawn over the preview while
    /// in trackpad mode. Constitution §IV: the position is rendered but
    /// never logged or persisted.
    private let trackpadCursor: TrackpadCursor
    /// Routes a trackpad-mode gesture (resolved view point + per-event
    /// translation) to the model with the live zoom/pan transform.  The
    /// returned result carries local-only auto-pan state plus the
    /// immediate cursor that keeps the Metal hot path visually in sync
    /// while zoomed (spec 003 FR-011).
    private let onTrackpadGesture: ((
        PointerGesture,
        ViewportTransform,
        TrackpadCursor
    ) -> SessionViewportTrackpadGestureResult?)?
    /// Publishes the local viewport transform to the app model so the
    /// stream request loop can make memory-only region decisions.
    private let onViewportTransformChange: ((ViewportTransform) -> Void)?
    /// Publishes only the local viewport container size. The model can combine
    /// this with `ServerInit` after handshake to make an opt-in first-frame
    /// visible-focus request before framebuffer pixels exist.
    private let onViewportSizeChange: SessionViewportSizeChangeHandler?
    /// Reports local viewport manipulation lifecycle to the app model
    /// so it can coalesce incoming streaming frames while the Metal
    /// view redraws the current texture locally.
    private let onViewportInteractionChange: ((
        Bool,
        ViewportInteractionFrameStrategy
    ) -> Void)?
    private let onViewportRedrawDiagnostics: SessionViewportRedrawDiagnosticsHandler?
    /// Reports actual Metal texture upload timing back to the app
    /// model. Raw milliseconds stay memory-only; diagnostics export
    /// only coarse timing buckets.
    private let onRendererUploadTiming: SessionRendererUploadTimingHandler?
    /// Flips `pointerControlMode` direct ↔ trackpad via the control-bar
    /// toggle.
    private let onTogglePointerMode: (() -> Void)?
    /// User-selected sustained-session stream pacing mode.  This is a
    /// local viewer preference only; it changes request cadence but does
    /// not reveal power/thermal state to diagnostics.
    private let streamPowerMode: StreamPowerMode
    /// Persists the next `streamPowerMode` through the app model.
    private let onToggleStreamPowerMode: (() -> Void)?
    private let streamEncodingMode: StreamEncodingMode
    private let onToggleStreamEncodingMode: (() -> Void)?
    private let startupPreflightMode: StreamStartupPreflightMode
    private let onToggleStartupPreflightMode: (() -> Void)?
    private let startupGlanceScaleMode: StreamStartupGlanceScaleMode
    private let onToggleStartupGlanceScaleMode: (() -> Void)?
    private let canUseStartupGlanceScaleMode: Bool
    /// Latency-derived connection quality, shown as a compact chip while
    /// the session is streaming (spec 003 US4).  Constitution §IV: this
    /// is a coarse bucket only — no raw latency value is displayed or
    /// exported.
    private let connectionQuality: ConnectionQuality
    /// When `true` the remote-screen container becomes the dominant
    /// full-height "hero" (GRD parity, spec 003 FR-001) instead of a
    /// width-driven aspect-fit box.  Live frames start at a local
    /// zoom-fill baseline so phone portrait avoids wasting most of the
    /// stream area on letterbox space while preserving true-aspect
    /// mapping through `ViewportTransform`.
    /// The Shell sets
    /// this only during a live session so the screen fills the space above
    /// the dock and the soft keyboard merely shrinks it rather than
    /// crushing it.  Pure local layout — constitution §I.
    private let fillsAvailableHeight: Bool
    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    private let pipLayerHost: PiPLayerHost?
    private let helperVideoLayerHost: HelperVideoLayerHost?
    #endif

    /// Local view-only zoom scale driven by pinch.  Constitution §I:
    /// pinch is a LOCAL composition step — it never produces an RFB
    /// message.  Clamped to `[minZoomScale, maxZoomScale]` on every
    /// update.
    @State private var zoomScale: CGFloat = 1.0

    /// Live-session crop-to-fill baseline.  In immersive mode the
    /// framebuffer starts at the smallest local zoom that fills the
    /// viewport height, then user pinch can zoom further.  Keeping this
    /// as state lets keyboard-driven viewport height changes preserve
    /// explicit user zoom while still re-centering when the user was at
    /// the baseline.
    @State private var immersiveBaselineZoomScale: CGFloat = 1.0

    /// Local pan offset in view points while zoomed. Constitution I:
    /// pan is a local viewport transform and never emits an RFB message.
    @State private var panOffset: CGSize = .zero

    /// Auto-hidden live controls.  The bar appears on entry / reveal,
    /// then collapses to a tiny top handle so the remote screen is the
    /// default visual state.
    @State private var showsImmersiveControlBar: Bool = true
    /// Local mirror of the UIKit/Metal viewport gesture lifecycle.  The
    /// app model also receives this signal for frame coalescing; keeping
    /// a view-local copy lets the immersive chrome avoid animating itself
    /// away while a pinch or pan is in flight.
    @State private var isViewportInteractionActive: Bool = false

    /// Gesture baselines used only by the PiP display-layer path. The
    /// regular Metal path owns UIKit recognizers and reports absolute
    /// values back through callbacks.
    @State private var pipPinchStartZoomScale: CGFloat?
    @State private var pipPanStartOffset: CGSize?

    /// Previous cumulative `DragGesture` translation for the active
    /// trackpad drag, used to derive the per-event delta `TrackpadCursor`
    /// expects.  `nil` between drags.
    @State private var trackpadDragPrevious: CGSize?
    @State private var directTouchDragStarted: Bool = false
    @State private var directTouchDragMovedFar: Bool = false

    /// Drives the title vs. action-row split.  iPhone (`.compact`)
    /// drops the action pills onto their own row below the title so
    /// each Label keeps a horizontal icon+text silhouette and the
    /// status badge has room to render without mid-word wrap (UX
    /// punch-list #005 / #104).  iPad (`.regular`) prefers the inline
    /// layout when there's room, but falls back to the compact stack
    /// when the available width can't fit it (iPad portrait with the
    /// sidebar visible — UX punch-list #303).  The `ViewThatFits`
    /// branch in `body` handles that fallback at draw time.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let minZoomScale: CGFloat = 1.0
    private static let maxZoomScale: CGFloat = 4.0

    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    public init(
        title: String,
        subtitle: String,
        session: RemoteSession?,
        framebuffer: RFBRawFramebuffer? = nil,
        inputCoordinateSpace: RemoteFramebufferCoordinateSpace? = nil,
        frameStore: SessionFrameStore? = nil,
        frameDirtyRectangles: [RFBFrameDamageRect]? = nil,
        frameChangedPixelCount: Int? = nil,
        serverCursor: RFBServerCursor? = nil,
        isPiPWatchAvailable: Bool = false,
        pipWatchStatusText: String = "PiP after first frame",
        isPiPWatching: Bool = false,
        usesHelperVideoPrimaryPreview: Bool = false,
        pointerControlMode: PointerControlMode = .directTouch,
        trackpadCursor: TrackpadCursor = TrackpadCursor(),
        pipLayerHost: PiPLayerHost? = nil,
        helperVideoLayerHost: HelperVideoLayerHost? = nil,
        onRunChecks: (() -> Void)? = nil,
        onConnect: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil,
        onStartPiPWatch: (() -> Void)? = nil,
        onFramebufferTap: SessionFramebufferTapHandler? = nil,
        onFramebufferRightClick: SessionFramebufferRightClickHandler? = nil,
        onFramebufferScroll: SessionFramebufferScrollHandler? = nil,
        onFramebufferPointerDown: SessionFramebufferPointerDownHandler? = nil,
        onFramebufferPointerMove: SessionFramebufferPointerMoveHandler? = nil,
        onFramebufferPointerUp: SessionFramebufferPointerUpHandler? = nil,
        onTrackpadGesture: ((
            PointerGesture,
            ViewportTransform,
            TrackpadCursor
        ) -> SessionViewportTrackpadGestureResult?)? = nil,
        onViewportTransformChange: ((ViewportTransform) -> Void)? = nil,
        onViewportSizeChange: SessionViewportSizeChangeHandler? = nil,
        onViewportInteractionChange: ((
            Bool,
            ViewportInteractionFrameStrategy
        ) -> Void)? = nil,
        onViewportRedrawDiagnostics: SessionViewportRedrawDiagnosticsHandler? = nil,
        onRendererUploadTiming: SessionRendererUploadTimingHandler? = nil,
        onTogglePointerMode: (() -> Void)? = nil,
        streamPowerMode: StreamPowerMode = .balanced,
        onToggleStreamPowerMode: (() -> Void)? = nil,
        streamEncodingMode: StreamEncodingMode = .standard,
        onToggleStreamEncodingMode: (() -> Void)? = nil,
        startupPreflightMode: StreamStartupPreflightMode = .disabled,
        onToggleStartupPreflightMode: (() -> Void)? = nil,
        startupGlanceScaleMode: StreamStartupGlanceScaleMode = .standard045,
        onToggleStartupGlanceScaleMode: (() -> Void)? = nil,
        canUseStartupGlanceScaleMode: Bool = false,
        connectionQuality: ConnectionQuality = .unknown,
        fillsAvailableHeight: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.session = session
        self.framebuffer = framebuffer
        self.inputCoordinateSpace = inputCoordinateSpace
        self.frameStore = frameStore
        self.frameDirtyRectangles = frameDirtyRectangles
        self.frameChangedPixelCount = frameChangedPixelCount.map { max($0, 0) }
        self.serverCursor = serverCursor
        self.isPiPWatchAvailable = isPiPWatchAvailable
        self.pipWatchStatusText = pipWatchStatusText
        self.isPiPWatching = isPiPWatching
        self.usesHelperVideoPrimaryPreview = usesHelperVideoPrimaryPreview
        self.pointerControlMode = pointerControlMode
        self.trackpadCursor = trackpadCursor
        self.pipLayerHost = pipLayerHost
        self.helperVideoLayerHost = helperVideoLayerHost
        self.onRunChecks = onRunChecks
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onStartPiPWatch = onStartPiPWatch
        self.onFramebufferTap = onFramebufferTap
        self.onFramebufferRightClick = onFramebufferRightClick
        self.onFramebufferScroll = onFramebufferScroll
        self.onFramebufferPointerDown = onFramebufferPointerDown
        self.onFramebufferPointerMove = onFramebufferPointerMove
        self.onFramebufferPointerUp = onFramebufferPointerUp
        self.onTrackpadGesture = onTrackpadGesture
        self.onViewportTransformChange = onViewportTransformChange
        self.onViewportSizeChange = onViewportSizeChange
        self.onViewportInteractionChange = onViewportInteractionChange
        self.onViewportRedrawDiagnostics = onViewportRedrawDiagnostics
        self.onRendererUploadTiming = onRendererUploadTiming
        self.onTogglePointerMode = onTogglePointerMode
        self.streamPowerMode = streamPowerMode
        self.onToggleStreamPowerMode = onToggleStreamPowerMode
        self.streamEncodingMode = streamEncodingMode
        self.onToggleStreamEncodingMode = onToggleStreamEncodingMode
        self.startupPreflightMode = startupPreflightMode
        self.onToggleStartupPreflightMode = onToggleStartupPreflightMode
        self.startupGlanceScaleMode = startupGlanceScaleMode
        self.onToggleStartupGlanceScaleMode = onToggleStartupGlanceScaleMode
        self.canUseStartupGlanceScaleMode = canUseStartupGlanceScaleMode
        self.connectionQuality = connectionQuality
        self.fillsAvailableHeight = fillsAvailableHeight
    }
    #else
    public init(
        title: String,
        subtitle: String,
        session: RemoteSession?,
        framebuffer: RFBRawFramebuffer? = nil,
        inputCoordinateSpace: RemoteFramebufferCoordinateSpace? = nil,
        frameStore: SessionFrameStore? = nil,
        frameDirtyRectangles: [RFBFrameDamageRect]? = nil,
        frameChangedPixelCount: Int? = nil,
        serverCursor: RFBServerCursor? = nil,
        isPiPWatchAvailable: Bool = false,
        pipWatchStatusText: String = "PiP after first frame",
        isPiPWatching: Bool = false,
        usesHelperVideoPrimaryPreview: Bool = false,
        pointerControlMode: PointerControlMode = .directTouch,
        trackpadCursor: TrackpadCursor = TrackpadCursor(),
        onRunChecks: (() -> Void)? = nil,
        onConnect: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil,
        onStartPiPWatch: (() -> Void)? = nil,
        onFramebufferTap: SessionFramebufferTapHandler? = nil,
        onFramebufferRightClick: SessionFramebufferRightClickHandler? = nil,
        onFramebufferScroll: SessionFramebufferScrollHandler? = nil,
        onFramebufferPointerDown: SessionFramebufferPointerDownHandler? = nil,
        onFramebufferPointerMove: SessionFramebufferPointerMoveHandler? = nil,
        onFramebufferPointerUp: SessionFramebufferPointerUpHandler? = nil,
        onTrackpadGesture: ((
            PointerGesture,
            ViewportTransform,
            TrackpadCursor
        ) -> SessionViewportTrackpadGestureResult?)? = nil,
        onViewportTransformChange: ((ViewportTransform) -> Void)? = nil,
        onViewportSizeChange: SessionViewportSizeChangeHandler? = nil,
        onViewportInteractionChange: ((
            Bool,
            ViewportInteractionFrameStrategy
        ) -> Void)? = nil,
        onViewportRedrawDiagnostics: SessionViewportRedrawDiagnosticsHandler? = nil,
        onRendererUploadTiming: SessionRendererUploadTimingHandler? = nil,
        onTogglePointerMode: (() -> Void)? = nil,
        streamPowerMode: StreamPowerMode = .balanced,
        onToggleStreamPowerMode: (() -> Void)? = nil,
        streamEncodingMode: StreamEncodingMode = .standard,
        onToggleStreamEncodingMode: (() -> Void)? = nil,
        startupPreflightMode: StreamStartupPreflightMode = .disabled,
        onToggleStartupPreflightMode: (() -> Void)? = nil,
        startupGlanceScaleMode: StreamStartupGlanceScaleMode = .standard045,
        onToggleStartupGlanceScaleMode: (() -> Void)? = nil,
        canUseStartupGlanceScaleMode: Bool = false,
        connectionQuality: ConnectionQuality = .unknown,
        fillsAvailableHeight: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.session = session
        self.framebuffer = framebuffer
        self.inputCoordinateSpace = inputCoordinateSpace
        self.frameStore = frameStore
        self.frameDirtyRectangles = frameDirtyRectangles
        self.frameChangedPixelCount = frameChangedPixelCount.map { max($0, 0) }
        self.serverCursor = serverCursor
        self.isPiPWatchAvailable = isPiPWatchAvailable
        self.pipWatchStatusText = pipWatchStatusText
        self.isPiPWatching = isPiPWatching
        self.usesHelperVideoPrimaryPreview = usesHelperVideoPrimaryPreview
        self.pointerControlMode = pointerControlMode
        self.trackpadCursor = trackpadCursor
        self.onRunChecks = onRunChecks
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        self.onStartPiPWatch = onStartPiPWatch
        self.onFramebufferTap = onFramebufferTap
        self.onFramebufferRightClick = onFramebufferRightClick
        self.onFramebufferScroll = onFramebufferScroll
        self.onFramebufferPointerDown = onFramebufferPointerDown
        self.onFramebufferPointerMove = onFramebufferPointerMove
        self.onFramebufferPointerUp = onFramebufferPointerUp
        self.onTrackpadGesture = onTrackpadGesture
        self.onViewportTransformChange = onViewportTransformChange
        self.onViewportSizeChange = onViewportSizeChange
        self.onViewportInteractionChange = onViewportInteractionChange
        self.onViewportRedrawDiagnostics = onViewportRedrawDiagnostics
        self.onRendererUploadTiming = onRendererUploadTiming
        self.onTogglePointerMode = onTogglePointerMode
        self.streamPowerMode = streamPowerMode
        self.onToggleStreamPowerMode = onToggleStreamPowerMode
        self.streamEncodingMode = streamEncodingMode
        self.onToggleStreamEncodingMode = onToggleStreamEncodingMode
        self.startupPreflightMode = startupPreflightMode
        self.onToggleStartupPreflightMode = onToggleStartupPreflightMode
        self.startupGlanceScaleMode = startupGlanceScaleMode
        self.onToggleStartupGlanceScaleMode = onToggleStartupGlanceScaleMode
        self.canUseStartupGlanceScaleMode = canUseStartupGlanceScaleMode
        self.connectionQuality = connectionQuality
        self.fillsAvailableHeight = fillsAvailableHeight
    }
    #endif

    public var body: some View {
        Group {
            if fillsAvailableHeight {
                immersiveBody
            } else {
                standardBody
            }
        }
        .accessibilityIdentifier("naru.session.viewport")
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if horizontalSizeClass == .compact {
                compactHeader
            } else {
                // UX punch-list #303: iPad reports `.regular` even in
                // portrait, but with the sidebar visible the detail
                // column is narrow enough that the historical inline
                // header layout cramped the action pills into ~50pt
                // buckets, wrapping each label into vertical glyph
                // strips ("Ch / ec / ks").  `ViewThatFits` lets the
                // system pick the inline layout when it fits and
                // gracefully fall back to the stacked `compactHeader`
                // when it doesn't — no width thresholds to maintain.
                ViewThatFits(in: .horizontal) {
                    regularHeader
                    compactHeader
                }
            }

            viewportSurface
            // Screen-first (spec 003 FR-001): the session container adopts
            // the server's TRUE aspect ratio once a frame exists, so a
            // 16:9 / 16:10 desktop fills the width instead of being
            // double-letterboxed inside a hardcoded 4:3 box.  The
            // empty-state placeholder keeps 4:3 until the first frame
            // defines the real ratio (see `containerAspectRatio`).  In
            // hero mode (`fillsAvailableHeight`) the container greedily
            // fills the available height and the visible framebuffer may
            // crop via a local zoom-fill baseline rather than shrink.
            .modifier(
                ViewportSizing(
                    fill: fillsAvailableHeight,
                    aspectRatio: containerAspectRatio
                )
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var immersiveBody: some View {
        viewportSurface
            .modifier(ViewportSizing(fill: true, aspectRatio: containerAspectRatio))
            .overlay(alignment: .top) {
                Group {
                    if showsImmersiveControlBar {
                        immersiveControlBar
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        controlRevealHandle
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showsImmersiveControlBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .task(id: immersiveControlAutoHideToken) {
                guard Self.allowsImmersiveControlAutoHide(
                    showsControlBar: showsImmersiveControlBar,
                    isViewportInteractionActive: isViewportInteractionActive
                ) else { return }
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                guard !Task.isCancelled,
                      Self.allowsImmersiveControlAutoHide(
                        showsControlBar: showsImmersiveControlBar,
                        isViewportInteractionActive: isViewportInteractionActive
                      )
                else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsImmersiveControlBar = false
                }
            }
    }

    private var immersiveControlAutoHideToken: Int {
        (showsImmersiveControlBar ? 1 : 0)
            | (isViewportInteractionActive ? 2 : 0)
    }

    private var viewportSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: viewportCornerRadius)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: viewportCornerRadius)
                        .stroke(Color.black.opacity(fillsAvailableHeight ? 0 : 0.12), lineWidth: 1)
                )

            if let framebuffer {
                framebufferLayer(framebuffer)
            } else if usesHelperVideoPrimaryPreview {
                helperVideoLayerPreviewWithoutFramebuffer()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(viewportText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        onViewportSizeChange?(proxy.size)
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        onViewportSizeChange?(newSize)
                    }
            }
        )
        .overlay(alignment: .topTrailing) {
            // UX punch-list #103: the "PiP after first frame"
            // affordance is only meaningful once a session has been
            // attempted — rendering it on the empty-state home
            // screen reads as a dead UI chip.  In immersive mode the
            // PiP affordance moves into the top control strip so the
            // remote screen keeps every possible point.
            if !fillsAvailableHeight, showsPiPHudChip {
                Label(pipWatchStatusText, systemImage: "rectangle.on.rectangle")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.32))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(10)
            }
        }
        .overlay(alignment: .topLeading) {
            if !fillsAvailableHeight, let badge = reconnectBadgeText {
                Label(badge, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(10)
                    .accessibilityIdentifier("naru.session.reconnectBadge")
            }
        }
    }

    private var viewportCornerRadius: CGFloat {
        fillsAvailableHeight ? 0 : 8
    }

    private var previewCornerRadius: CGFloat {
        fillsAvailableHeight ? 0 : 8
    }

    private var framebufferAlignment: Alignment {
        fillsAvailableHeight ? .top : .center
    }

    // MARK: - Header layouts

    private var immersiveControlBar: some View {
        HStack(spacing: 8) {
            statusBadge
                .padding(.vertical, 7)
                .padding(.horizontal, 9)
                .background(Color.black.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            qualityChip

            Spacer(minLength: 8)

            checksButton(iconOnly: true)
            if showsConnectButton {
                connectButton
            }
            if showsDisconnectButton {
                disconnectButton
            }
            streamPowerModeButton
            if showsStreamEncodingModeButton {
                streamEncodingModeButton
            }
            if showsStartupPreflightModeButton {
                startupPreflightModeButton
            }
            if showsStartupGlanceScaleModeButton {
                startupGlanceScaleModeButton
            }
            pointerModeButton
            pipWatchButton(iconOnly: true)
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
        .accessibilityIdentifier("naru.session.controlBar")
    }

    private var controlRevealHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsImmersiveControlBar = true
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.86))
                .frame(width: 52, height: 24)
                .background(Color.black.opacity(0.42))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Show session controls")
        .accessibilityIdentifier("naru.session.controls.reveal")
    }

    /// iPad / regular-width path.  Mirrors the historical inline
    /// layout: title on the left, action pills + status badge on the
    /// right.  The only divergence from the pre-cleanup version is
    /// the `.fixedSize` on the status `Label` so even the iPad row
    /// won't wrap mid-word if the status string ever grows past the
    /// trailing column width.
    @ViewBuilder
    private var regularHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            titleStack
            Spacer()

            HStack(spacing: 10) {
                checksButton(iconOnly: false)
                if showsConnectButton {
                    connectButton
                }
                if showsDisconnectButton {
                    disconnectButton
                }
                streamPowerModeButton
                if showsStreamEncodingModeButton {
                    streamEncodingModeButton
                }
                if showsStartupPreflightModeButton {
                    startupPreflightModeButton
                }
                if showsStartupGlanceScaleModeButton {
                    startupGlanceScaleModeButton
                }
                pointerModeButton
                pipWatchButton(iconOnly: false)
                qualityChip
                statusBadge
            }
        }
    }

    /// iPhone / compact-width path.  The action pills move to a
    /// dedicated row below the title so each Label keeps a horizontal
    /// icon+text silhouette and the status badge has room to render
    /// without mid-word wrap (UX punch-list #005 / #104).  Checks +
    /// PiP Watch render `.iconOnly` to keep the row from spilling off
    /// the right edge on the smallest iPhone widths.
    @ViewBuilder
    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleStack

            HStack(spacing: 8) {
                checksButton(iconOnly: true)
                if showsConnectButton {
                    connectButton
                }
                if showsDisconnectButton {
                    disconnectButton
                }
                streamPowerModeButton
                if showsStreamEncodingModeButton {
                    streamEncodingModeButton
                }
                if showsStartupPreflightModeButton {
                    startupPreflightModeButton
                }
                if showsStartupGlanceScaleModeButton {
                    startupGlanceScaleModeButton
                }
                pointerModeButton
                pipWatchButton(iconOnly: true)
                Spacer(minLength: 4)
                qualityChip
                statusBadge
            }
        }
    }

    private var titleStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func checksButton(iconOnly: Bool) -> some View {
        Button {
            onRunChecks?()
        } label: {
            if iconOnly {
                Label("Checks", systemImage: "checklist")
                    .labelStyle(.iconOnly)
            } else {
                Label("Checks", systemImage: "checklist")
            }
        }
        .buttonStyle(.bordered)
        .disabled(onRunChecks == nil)
        .help("Run connection checks")
        .accessibilityLabel("Checks")
        .accessibilityIdentifier("naru.session.checks")
    }

    private var connectButton: some View {
        Button {
            onConnect?()
        } label: {
            Label("Connect", systemImage: "bolt.horizontal.circle")
                // Keep the label on one line so a tight action row never
                // wraps it into a vertical glyph strip ("Co / nne / ct")
                // once the trackpad / PiP controls share the row on the
                // pre-connect screen (UX punch-list #005).
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
        .disabled(onConnect == nil)
        .help("Connect to selected profile")
        .accessibilityIdentifier("naru.session.connect")
    }

    @ViewBuilder
    private var disconnectButton: some View {
        Button {
            onDisconnect?()
        } label: {
            if horizontalSizeClass == .compact {
                Label("Disconnect", systemImage: "bolt.horizontal.circle.fill")
                    .labelStyle(.iconOnly)
            } else {
                Label("Disconnect", systemImage: "bolt.horizontal.circle.fill")
            }
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(onDisconnect == nil)
        .help("End the active session and stop auto-reconnect")
        .accessibilityLabel("Disconnect")
        .accessibilityIdentifier("naru.session.disconnect")
    }

    @ViewBuilder
    private func pipWatchButton(iconOnly: Bool) -> some View {
        Button {
            onStartPiPWatch?()
        } label: {
            if iconOnly {
                Label("PiP Watch", systemImage: "rectangle.on.rectangle")
                    .labelStyle(.iconOnly)
            } else {
                Label("PiP Watch", systemImage: "rectangle.on.rectangle")
            }
        }
        .buttonStyle(.bordered)
        .disabled(!canStartPiPWatch)
        .help(pipWatchButtonHelp)
        .accessibilityLabel("PiP Watch")
        .accessibilityIdentifier("naru.session.pipWatch")
    }

    /// Control-bar toggle between direct-touch and trackpad pointer
    /// modes (spec 003 US3 / T015).  Only meaningful while a session is
    /// active — disabled otherwise so it never reads as a live control on
    /// the empty-state home screen.  The SF Symbol mirrors the *current*
    /// mode (a trackpad-cursor glyph in trackpad mode, a tapping hand in
    /// direct mode) and the accessibility label states it outright.
    @ViewBuilder
    private var pointerModeButton: some View {
        Button {
            onTogglePointerMode?()
        } label: {
            Label(
                pointerModeLabelText,
                systemImage: pointerControlMode.isTrackpad ? "cursorarrow.rays" : "hand.tap"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .disabled(onTogglePointerMode == nil || session?.state != .active)
        .help(pointerModeLabelText)
        .accessibilityLabel(pointerModeLabelText)
        .accessibilityIdentifier("naru.session.pointerMode")
    }

    private var pointerModeLabelText: String {
        pointerControlMode.isTrackpad
            ? "Trackpad mode — tap to switch to direct touch"
            : "Direct touch — tap to switch to trackpad"
    }

    @ViewBuilder
    private var streamPowerModeButton: some View {
        Button {
            onToggleStreamPowerMode?()
        } label: {
            Label(
                streamPowerModeLabelText,
                systemImage: streamPowerMode == .powerSaver ? "leaf.fill" : "leaf"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .tint(streamPowerMode == .powerSaver ? .green : .accentColor)
        .disabled(onToggleStreamPowerMode == nil)
        .help(streamPowerModeLabelText)
        .accessibilityLabel(streamPowerModeLabelText)
        .accessibilityIdentifier("naru.session.streamPowerMode")
    }

    private var streamPowerModeLabelText: String {
        streamPowerMode == .powerSaver
            ? "Power saver stream — tap to use balanced pacing"
            : "Balanced stream — tap to reduce heat"
    }

    private var showsStreamEncodingModeButton: Bool {
        session?.state != .active
    }

    @ViewBuilder
    private var streamEncodingModeButton: some View {
        Button {
            onToggleStreamEncodingMode?()
        } label: {
            Label(
                streamEncodingModeLabelText,
                systemImage: "slider.horizontal.3"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .tint(streamEncodingMode == .standard ? .accentColor : .cyan)
        .disabled(onToggleStreamEncodingMode == nil)
        .help(streamEncodingModeLabelText)
        .accessibilityLabel(streamEncodingModeLabelText)
        .accessibilityIdentifier("naru.session.streamEncodingMode")
    }

    private var streamEncodingModeLabelText: String {
        switch streamEncodingMode {
        case .standard:
            return "Standard stream profile — tap to try Tight cursor"
        case .tightFirstCursor:
            return "Tight cursor stream profile — tap to try RGB565 low latency"
        case .localLowLatencyRGB565:
            return "RGB565 low-latency stream profile — tap to try ZRLE compression 0"
        case .zrleCompressionZero:
            return "ZRLE compression 0 stream profile — tap to try ZRLE RGB565 low traffic"
        case .zrleCompressionZeroRGB565:
            return "ZRLE RGB565 low-traffic stream profile — tap to try adaptive full"
        case .adaptiveGoodFull:
            return "Adaptive full stream profile — tap to use standard"
        }
    }

    private var showsStartupPreflightModeButton: Bool {
        // Startup warm-up only affects the next frame stream, so active-session
        // chrome stays focused on controls that can change the current stream.
        session?.state != .active
    }

    @ViewBuilder
    private var startupPreflightModeButton: some View {
        Button {
            onToggleStartupPreflightMode?()
        } label: {
            Label(
                startupPreflightModeLabelText,
                systemImage: "speedometer"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .tint(startupPreflightMode == .oneHiddenFrame ? .orange : .accentColor)
        .disabled(onToggleStartupPreflightMode == nil)
        .help(startupPreflightModeLabelText)
        .accessibilityLabel(startupPreflightModeLabelText)
        .accessibilityIdentifier("naru.session.startupPreflightMode")
    }

    private var startupPreflightModeLabelText: String {
        startupPreflightMode == .oneHiddenFrame
            ? "Startup warm-up enabled — tap to disable"
            : "Startup warm-up disabled — tap to enable"
    }

    private var showsStartupGlanceScaleModeButton: Bool {
        session?.state != .active && canUseStartupGlanceScaleMode
    }

    @ViewBuilder
    private var startupGlanceScaleModeButton: some View {
        Button {
            onToggleStartupGlanceScaleMode?()
        } label: {
            Label(
                startupGlanceScaleModeLabelText,
                systemImage: "viewfinder"
            )
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .tint(startupGlanceScaleMode == .standard045 ? .accentColor : .orange)
        .disabled(onToggleStartupGlanceScaleMode == nil)
        .help(startupGlanceScaleModeLabelText)
        .accessibilityLabel(startupGlanceScaleModeLabelText)
        .accessibilityIdentifier("naru.session.startupGlanceScaleMode")
    }

    private var startupGlanceScaleModeLabelText: String {
        switch startupGlanceScaleMode {
        case .standard045:
            return "Startup glance 0.45 — tap to try 0.35"
        case .minimal035:
            return "Startup glance 0.35 — tap to try 0.25"
        case .glance025:
            return "Startup glance 0.25 — tap to use 0.45"
        }
    }

    /// Compact latency-derived connection-quality indicator (spec 003
    /// US4).  Shown only while the session is streaming (`.active`) and a
    /// bucket has been established (`!= .unknown`) so it never reads as a
    /// dead chip during connect or after disconnect.  Mirrors the GRD
    /// signal-strength affordance the latency estimator was wired for.
    @ViewBuilder
    private var qualityChip: some View {
        if session?.state == .active, connectionQuality != .unknown {
            Label(qualityText, systemImage: "wifi")
                .font(.caption.weight(.medium))
                .foregroundStyle(qualityColor)
                .labelStyle(.titleAndIcon)
                .fixedSize(horizontal: true, vertical: false)
                .help("Connection quality")
                .accessibilityLabel("Connection quality: \(qualityText)")
                .accessibilityIdentifier("naru.session.quality")
        }
    }

    private var qualityText: String {
        switch connectionQuality {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return ""
        }
    }

    private var qualityColor: Color {
        switch connectionQuality {
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        case .unknown: return .secondary
        }
    }

    /// Transparent, full-bleed gesture layer used only in trackpad mode.
    /// A one-finger drag emits `dragChanged`/`dragEnded` (relative remote
    /// pointer motion with no button pressed) and a near-stationary press
    /// emits `tap` (click at the cursor). The `GeometryReader` captures
    /// the framebuffer container's size so this view can pass the live
    /// fit × zoom × pan `ViewportTransform` to the model.
    /// `translation` is the per-event delta in view points (`DragGesture`
    /// reports cumulative translation, so we diff against the previous
    /// value).
    private func trackpadGestureSurface(framebuffer: RFBRawFramebuffer) -> some View {
        trackpadGestureSurface(
            coordinateSpace: coordinateSpace(for: framebuffer),
            framebuffer: framebuffer
        )
    }

    private func trackpadGestureSurface(
        coordinateSpace: RemoteFramebufferCoordinateSpace,
        framebuffer: RFBRawFramebuffer?
    ) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let previous = trackpadDragPrevious ?? .zero
                            let delta = CGSize(
                                width: value.translation.width - previous.width,
                                height: value.translation.height - previous.height
                            )
                            trackpadDragPrevious = value.translation
                            dispatchTrackpadGesture(
                                .dragChanged(viewPoint: value.location, translation: delta),
                                coordinateSpace: coordinateSpace,
                                framebuffer: framebuffer,
                                viewSize: size
                            )
                        }
                        .onEnded { value in
                            let movedFar = abs(value.translation.width) > 6
                                || abs(value.translation.height) > 6
                            trackpadDragPrevious = nil
                            if movedFar {
                                dispatchTrackpadGesture(
                                    .dragEnded(viewPoint: value.location),
                                    coordinateSpace: coordinateSpace,
                                    framebuffer: framebuffer,
                                    viewSize: size
                                )
                            } else {
                                // A near-stationary press-release reads as
                                // a tap → click at the cursor (003 FR-008).
                                dispatchTrackpadGesture(
                                    .tap(viewPoint: value.location),
                                    coordinateSpace: coordinateSpace,
                                    framebuffer: framebuffer,
                                    viewSize: size
                                )
                            }
                        }
                )
        }
        .accessibilityIdentifier("naru.session.trackpadSurface")
    }

    private func directTouchGestureSurface() -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let movedFar = abs(value.translation.width) > 6
                                || abs(value.translation.height) > 6
                            guard movedFar || directTouchDragStarted else {
                                return
                            }
                            directTouchDragMovedFar = true
                            if directTouchDragStarted {
                                onFramebufferPointerMove?(value.location, size)
                            } else {
                                directTouchDragStarted = true
                                onFramebufferPointerDown?(value.location, size)
                            }
                        }
                        .onEnded { value in
                            defer {
                                directTouchDragStarted = false
                                directTouchDragMovedFar = false
                            }
                            guard directTouchDragMovedFar else {
                                onFramebufferTap?(value.location, size)
                                return
                            }
                            onFramebufferPointerUp?(value.location, size)
                        }
                )
        }
        .accessibilityIdentifier("naru.session.directTouchSurface")
    }

    private func dispatchTrackpadGesture(
        _ gesture: PointerGesture,
        coordinateSpace: RemoteFramebufferCoordinateSpace,
        framebuffer: RFBRawFramebuffer?,
        viewSize: CGSize
    ) {
        let transform = currentViewportTransform(coordinateSpace: coordinateSpace, viewSize: viewSize)
        let updatedTransform = onTrackpadGesture?(gesture, transform, trackpadCursor)?.transform ?? transform
        applyViewportTransform(
            updatedTransform,
            coordinateSpace: coordinateSpace,
            framebuffer: framebuffer,
            viewSize: viewSize
        )
    }

    private func applyViewportTransform(
        _ transform: ViewportTransform,
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) {
        applyViewportTransform(
            transform,
            coordinateSpace: coordinateSpace(for: framebuffer),
            framebuffer: framebuffer,
            viewSize: viewSize
        )
    }

    private func applyViewportTransform(
        _ transform: ViewportTransform,
        coordinateSpace: RemoteFramebufferCoordinateSpace,
        framebuffer: RFBRawFramebuffer?,
        viewSize: CGSize
    ) {
        zoomScale = transform.zoomScale
        panOffset = transform.panOffset
        if let framebuffer {
            syncPiPViewport(framebuffer: framebuffer, viewSize: viewSize)
        }
        onViewportTransformChange?(transform)
    }

    /// Maps the trackpad cursor's framebuffer position into the
    /// container's view space with the same transform the preview uses,
    /// then draws the server cursor shape or a local fallback glyph.
    /// `.allowsHitTesting(false)` keeps it from eating the gesture
    /// surface.
    @ViewBuilder
    private func cursorOverlay(framebuffer: RFBRawFramebuffer) -> some View {
        if Self.cursorOverlayKind(serverCursor: serverCursor) == .serverShape, let serverCursor {
            serverCursorOverlay(cursor: serverCursor, framebuffer: framebuffer)
        } else {
            syntheticCursorOverlay(framebuffer: framebuffer)
        }
    }

    @ViewBuilder
    private func syntheticCursorOverlay(framebuffer: RFBRawFramebuffer) -> some View {
        syntheticCursorOverlay(coordinateSpace: coordinateSpace(for: framebuffer))
    }

    @ViewBuilder
    private func syntheticCursorOverlay(coordinateSpace: RemoteFramebufferCoordinateSpace) -> some View {
        GeometryReader { proxy in
            let point = Self.cursorViewPoint(
                framebufferPosition: trackpadCursor.position,
                framebufferWidth: coordinateSpace.width,
                framebufferHeight: coordinateSpace.height,
                containerSize: proxy.size,
                zoomScale: zoomScale,
                panOffset: panOffset,
                maxZoomScale: Self.maxZoomScale
            )
            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
                .position(point)
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("naru.session.cursor")
    }

    @ViewBuilder
    private func serverCursorOverlay(cursor: RFBServerCursor, framebuffer: RFBRawFramebuffer) -> some View {
        GeometryReader { proxy in
            let transform = currentViewportTransform(framebuffer: framebuffer, viewSize: proxy.size)
            let scale = transform.displayScale
            let anchor = transform.viewPoint(fromFramebufferPoint: trackpadCursor.position)
            let origin = CGPoint(
                x: anchor.x - CGFloat(cursor.hotSpotX) * scale,
                y: anchor.y - CGFloat(cursor.hotSpotY) * scale
            )

            Canvas { context, _ in
                for y in 0..<cursor.height {
                    for x in 0..<cursor.width {
                        guard let color = cursor[x, y], color.alpha > 0 else {
                            continue
                        }
                        let rect = CGRect(
                            x: origin.x + CGFloat(x) * scale,
                            y: origin.y + CGFloat(y) * scale,
                            width: max(1, scale.rounded(.up)),
                            height: max(1, scale.rounded(.up))
                        )
                        context.fill(Path(rect), with: .color(color.previewColor))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("naru.session.serverCursor")
    }

    private var statusBadge: some View {
        Label(statusText, systemImage: statusSymbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(statusColor)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: true, vertical: false)
            .help("Connection state")
    }

    @ViewBuilder
    private func framebufferLayer(_ framebuffer: RFBRawFramebuffer) -> some View {
        let aspectRatio = CGFloat(max(framebuffer.width, 1)) / CGFloat(max(framebuffer.height, 1))

        GeometryReader { proxy in
            let displaySize = fillsAvailableHeight
                ? proxy.size
                : Self.aspectFitSize(aspectRatio: aspectRatio, containerSize: proxy.size)
            let minimumZoomScale = fillsAvailableHeight
                ? Self.aspectFillZoomScale(aspectRatio: aspectRatio, containerSize: proxy.size)
                : Self.minZoomScale
            let framebufferSizeToken = "\(framebuffer.width)x\(framebuffer.height)"

            framebufferContent(
                framebuffer,
                aspectRatio: aspectRatio,
                usesViewportFrame: fillsAvailableHeight,
                minimumZoomScale: minimumZoomScale
            )
                .frame(width: displaySize.width, height: displaySize.height)
                .overlay {
                    if Self.usesSwiftUIDirectTouchInputOverlay(
                        isPiPWatching: isPiPWatching,
                        usesHelperVideoPrimaryPreview: usesHelperVideoPrimaryPreview,
                        pointerControlMode: pointerControlMode,
                        metalFramebufferInputSupported: Self.metalFramebufferInputSupported
                    ) {
                        directTouchGestureSurface()
                    }
                }
                // Trackpad gesture surface — a transparent layer that
                // intercepts one-finger drag + tap ONLY in trackpad mode
                // and forwards them as `PointerGesture`s.  Keeping this
                // overlay on the fitted framebuffer layer (not the full
                // hero background) preserves the same geometry for hit
                // testing, cursor drawing, and zoom/pan math.
                .overlay {
                    if Self.usesSwiftUITrackpadInputOverlay(
                        isPiPWatching: isPiPWatching,
                        usesHelperVideoPrimaryPreview: usesHelperVideoPrimaryPreview,
                        pointerControlMode: pointerControlMode,
                        metalFramebufferInputSupported: Self.metalFramebufferInputSupported
                    ) {
                        trackpadGestureSurface(framebuffer: framebuffer)
                    }
                }
                // Soft cursor overlay (trackpad mode only).  Drawn on
                // top of the preview and never hit-testing so it cannot
                // eat the gesture surface below it.
                .overlay {
                    if Self.showsTrackpadCursor(
                        isPiPWatching: isPiPWatching,
                        pointerControlMode: pointerControlMode,
                        cursor: trackpadCursor
                    ),
                       !Self.usesMetalHotTrackpadCursor(
                        isPiPWatching: isPiPWatching,
                        usesHelperVideoPrimaryPreview: usesHelperVideoPrimaryPreview,
                        pointerControlMode: pointerControlMode,
                        metalFramebufferInputSupported: Self.metalFramebufferInputSupported
                    ) {
                        cursorOverlay(framebuffer: framebuffer)
                    }
                }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: framebufferAlignment)
                .onAppear {
                    syncImmersiveBaselineZoom(
                        minimumZoomScale,
                        framebuffer: framebuffer,
                        viewSize: proxy.size
                    )
                }
                .onChange(of: proxy.size) { _, newSize in
                    syncImmersiveBaselineZoom(
                        fillsAvailableHeight
                            ? Self.aspectFillZoomScale(aspectRatio: aspectRatio, containerSize: newSize)
                            : Self.minZoomScale,
                        framebuffer: framebuffer,
                        viewSize: newSize
                    )
                }
                .onChange(of: framebufferSizeToken) { _, _ in
                    syncImmersiveBaselineZoom(
                        minimumZoomScale,
                        framebuffer: framebuffer,
                        viewSize: proxy.size
                    )
                }
        }
    }

    @ViewBuilder
    private func framebufferContent(
        _ framebuffer: RFBRawFramebuffer,
        aspectRatio: CGFloat,
        usesViewportFrame: Bool,
        minimumZoomScale: CGFloat
    ) -> some View {
        #if os(iOS) && canImport(UIKit) && canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        if usesHelperVideoPrimaryPreview, let helperVideoLayerHost {
            sampleBufferLayerPreview(
                framebuffer: framebuffer,
                aspectRatio: aspectRatio,
                layer: helperVideoLayerHost.layer,
                accessibilityIdentifier: "naru.session.helperVideoDisplayLayer",
                accessibilityLabel: "Remote helper video"
            )
        } else if isPiPWatching, let pipLayerHost {
            // Active system PiP — render through the shared
            // AVSampleBufferDisplayLayer so the in-app preview and the
            // PiP content source share one renderer (PR #5).
            sampleBufferLayerPreview(
                framebuffer: framebuffer,
                aspectRatio: aspectRatio,
                layer: pipLayerHost.layer,
                accessibilityIdentifier: "naru.session.pipDisplayLayer",
                accessibilityLabel: "Remote framebuffer in Picture-in-Picture display layer"
            )
        } else {
            metalOrSampledPreview(
                framebuffer: framebuffer,
                aspectRatio: aspectRatio,
                usesViewportFrame: usesViewportFrame,
                minimumZoomScale: minimumZoomScale
            )
        }
        #else
        RemoteFramebufferPreview(framebuffer: framebuffer)
            .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
            .accessibilityIdentifier("naru.session.framebufferPreview")
        #endif
    }

    #if os(iOS) && canImport(UIKit) && canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    private func sampleBufferLayerPreview(
        framebuffer: RFBRawFramebuffer,
        aspectRatio: CGFloat,
        layer: AVSampleBufferDisplayLayer,
        accessibilityIdentifier: String,
        accessibilityLabel: String
    ) -> some View {
        GeometryReader { proxy in
            PiPSampleBufferDisplayLayerView(
                layer: layer,
                accessibilityIdentifier: accessibilityIdentifier,
                accessibilityLabel: accessibilityLabel
            )
                .contentShape(Rectangle())
                .simultaneousGesture(pipMagnificationGesture(framebuffer: framebuffer, viewSize: proxy.size))
                .simultaneousGesture(pipPanGesture(framebuffer: framebuffer, viewSize: proxy.size))
                .simultaneousGesture(pipDoubleTapGesture(framebuffer: framebuffer, viewSize: proxy.size))
                .onAppear {
                    syncPiPViewport(framebuffer: framebuffer, viewSize: proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    syncPiPViewport(framebuffer: framebuffer, viewSize: newSize)
                }
                .onChange(of: zoomScale) { _, _ in
                    syncPiPViewport(framebuffer: framebuffer, viewSize: proxy.size)
                }
                .onChange(of: panOffset) { _, _ in
                    syncPiPViewport(framebuffer: framebuffer, viewSize: proxy.size)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityIdentifier("naru.session.framebufferPreview")
    }

    @ViewBuilder
    private func helperVideoLayerPreviewWithoutFramebuffer() -> some View {
        if let helperVideoLayerHost {
            PiPSampleBufferDisplayLayerView(
                layer: helperVideoLayerHost.layer,
                accessibilityIdentifier: "naru.session.helperVideoDisplayLayer",
                accessibilityLabel: "Remote helper video"
            )
            .overlay {
                if let inputCoordinateSpace {
                    helperVideoInputOverlay(coordinateSpace: inputCoordinateSpace)
                }
            }
            .overlay(alignment: .bottom) {
                Text("Preparing control channel")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.38))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(viewportText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private func helperVideoInputOverlay(coordinateSpace: RemoteFramebufferCoordinateSpace) -> some View {
        if Self.usesSwiftUITrackpadInputOverlay(
            isPiPWatching: isPiPWatching,
            usesHelperVideoPrimaryPreview: usesHelperVideoPrimaryPreview,
            pointerControlMode: pointerControlMode,
            metalFramebufferInputSupported: Self.metalFramebufferInputSupported
        ) {
            trackpadGestureSurface(coordinateSpace: coordinateSpace, framebuffer: nil)
                .overlay {
                    syntheticCursorOverlay(coordinateSpace: coordinateSpace)
                }
        } else if Self.usesSwiftUIDirectTouchInputOverlay(
            isPiPWatching: isPiPWatching,
            usesHelperVideoPrimaryPreview: usesHelperVideoPrimaryPreview,
            pointerControlMode: pointerControlMode,
            metalFramebufferInputSupported: Self.metalFramebufferInputSupported
        ) {
            directTouchGestureSurface()
        }
    }
    #else
    private func helperVideoLayerPreviewWithoutFramebuffer() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "display")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(viewportText)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
    #endif

    @ViewBuilder
    private func metalOrSampledPreview(
        framebuffer: RFBRawFramebuffer,
        aspectRatio: CGFloat,
        usesViewportFrame: Bool,
        minimumZoomScale: CGFloat
    ) -> some View {
        #if os(iOS) && canImport(UIKit) && canImport(Metal) && canImport(MetalKit)
        if MetalFramebufferView.isSupported() {
            let preview = MetalFramebufferView(
                framebuffer: framebuffer,
                frameStore: frameStore,
                dirtyRectangles: frameDirtyRectangles,
                changedPixelCount: frameChangedPixelCount,
                sessionID: session?.id,
                zoomScale: zoomScale,
                panOffset: panOffset,
                minimumZoomScale: minimumZoomScale,
                onTap: onFramebufferTap,
                onRightClick: onFramebufferRightClick,
                onScroll: onFramebufferScroll,
                onPinch: { newScale, anchor, viewSize in
                    // Constitution §I: pinch is a LOCAL view
                    // transform, never an RFB message.
                    applyZoomScale(
                        newScale,
                        anchor: anchor,
                        framebuffer: framebuffer,
                        viewSize: viewSize
                    )
                },
                onPointerDown: onFramebufferPointerDown,
                onPointerMove: onFramebufferPointerMove,
                onPointerUp: onFramebufferPointerUp,
                onPan: { newOffset, viewSize in
                    applyPanOffset(newOffset, framebuffer: framebuffer, viewSize: viewSize)
                },
                onZoomToggle: { point, viewSize in
                    toggleZoom(at: point, in: viewSize, framebuffer: framebuffer)
                },
                onViewportTransform: { transform in
                    applyViewportTransform(
                        transform,
                        framebuffer: framebuffer,
                        viewSize: transform.viewSize
                    )
                },
                pointerControlMode: pointerControlMode,
                trackpadCursor: trackpadCursor,
                serverCursor: serverCursor,
                onTrackpadGesture: { gesture, transform, cursor in
                    // The Metal host applies returned auto-pan immediately and
                    // mirrors viewport state after the gesture settles.
                    // Updating SwiftUI state on every pointer sample makes
                    // physical iPhone drags fight the fast UIKit path.
                    onTrackpadGesture?(gesture, transform, cursor)
                },
                onViewportInteractionChange: handleViewportInteractionChange(_:frameStrategy:),
                onViewportRedrawDiagnostics: onViewportRedrawDiagnostics,
                onUploadTiming: onRendererUploadTiming
            )
                // The Metal path applies zoom/pan directly inside
                // `MetalFramebufferHostingView` so UIKit recognizers
                // can move the pixels immediately during a gesture.
                // SwiftUI state still drives overlays, hit mapping,
                // and PiP focus, but not the hot visual transform.
                .transaction { transaction in
                    transaction.animation = nil
                }
                .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))

            if usesViewportFrame {
                preview
                    .accessibilityIdentifier("naru.session.framebufferPreview")
            } else {
                preview
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .accessibilityIdentifier("naru.session.framebufferPreview")
            }
        } else {
            RemoteFramebufferPreview(framebuffer: framebuffer)
                .scaleEffect(zoomScale)
                .offset(panOffset)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
                .accessibilityIdentifier("naru.session.framebufferPreview")
        }
        #else
        RemoteFramebufferPreview(framebuffer: framebuffer)
            .scaleEffect(zoomScale)
            .offset(panOffset)
            .transaction { transaction in
                transaction.animation = nil
            }
            .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
            .accessibilityIdentifier("naru.session.framebufferPreview")
        #endif
    }

    /// Aspect ratio for the session container.  Uses the live
    /// framebuffer's real ratio (screen-first, spec 003 FR-001), clamped
    /// to `[0.5, 2.5]` so a degenerate server size can't make the
    /// container a sliver or a wall.  Falls back to 4:3 — a neutral
    /// monitor shape — for the pre-first-frame placeholder.
    private var containerAspectRatio: CGFloat {
        if let framebuffer, framebuffer.width > 0, framebuffer.height > 0 {
            let ratio = CGFloat(framebuffer.width) / CGFloat(framebuffer.height)
            return min(max(ratio, 0.5), 2.5)
        }
        if let inputCoordinateSpace {
            let ratio = inputCoordinateSpace.aspectRatio
            return min(max(ratio, 0.5), 2.5)
        }
        return 4.0 / 3.0
    }

    static func aspectFitSize(aspectRatio: CGFloat, containerSize: CGSize) -> CGSize {
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return .zero
        }

        let containerRatio = containerSize.width / containerSize.height
        if containerRatio > aspectRatio {
            let height = containerSize.height
            return CGSize(width: height * aspectRatio, height: height)
        }

        let width = containerSize.width
        return CGSize(width: width, height: width / aspectRatio)
    }

    static func aspectFillZoomScale(aspectRatio: CGFloat, containerSize: CGSize) -> CGFloat {
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return 1
        }

        let containerRatio = containerSize.width / containerSize.height
        guard containerRatio > 0 else { return 1 }
        return max(1, max(containerRatio / aspectRatio, aspectRatio / containerRatio))
    }

    private func minimumZoomScale(for viewSize: CGSize, framebuffer: RFBRawFramebuffer) -> CGFloat {
        guard fillsAvailableHeight else {
            return Self.minZoomScale
        }

        let aspectRatio = CGFloat(max(framebuffer.width, 1)) / CGFloat(max(framebuffer.height, 1))
        let fillScale = Self.aspectFillZoomScale(aspectRatio: aspectRatio, containerSize: viewSize)
        return min(max(fillScale, Self.minZoomScale), Self.maxZoomScale)
    }

    private func syncImmersiveBaselineZoom(
        _ minimumZoomScale: CGFloat,
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) {
        guard fillsAvailableHeight,
              viewSize.width > 0,
              viewSize.height > 0
        else {
            return
        }

        let baseline = min(max(minimumZoomScale, Self.minZoomScale), Self.maxZoomScale)
        let wasAtBaseline = abs(zoomScale - immersiveBaselineZoomScale) < 0.02
        let shouldSnapToBaseline = wasAtBaseline || zoomScale < baseline
        immersiveBaselineZoomScale = baseline

        let targetZoom = shouldSnapToBaseline ? baseline : zoomScale
        let targetPan = shouldSnapToBaseline ? CGSize.zero : panOffset
        let transform = ViewportTransform(
            framebufferSize: CGSize(width: framebuffer.width, height: framebuffer.height),
            viewSize: viewSize,
            zoomScale: targetZoom,
            panOffset: targetPan,
            maxZoomScale: Self.maxZoomScale
        )
        zoomScale = transform.zoomScale
        panOffset = transform.panOffset
    }

    private func toggleZoom(
        at point: CGPoint,
        in viewSize: CGSize,
        framebuffer: RFBRawFramebuffer
    ) {
        let updated = Self.zoomToggleTransform(
            framebufferSize: CGSize(width: framebuffer.width, height: framebuffer.height),
            viewSize: viewSize,
            zoomScale: zoomScale,
            panOffset: panOffset,
            anchor: point,
            baselineZoomScale: minimumZoomScale(for: viewSize, framebuffer: framebuffer)
        )
        applyViewportTransform(updated, framebuffer: framebuffer, viewSize: viewSize)
    }

    #if os(iOS) && canImport(UIKit) && canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    private func pipMagnificationGesture(
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let startScale = pipPinchStartZoomScale ?? zoomScale
                pipPinchStartZoomScale = startScale
                applyZoomScale(
                    startScale * value,
                    anchor: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2),
                    framebuffer: framebuffer,
                    viewSize: viewSize
                )
            }
            .onEnded { _ in
                pipPinchStartZoomScale = nil
                syncPiPViewport(framebuffer: framebuffer, viewSize: viewSize)
            }
    }

    private func pipPanGesture(
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard zoomScale > 1.0001 else {
                    return
                }
                let startOffset = pipPanStartOffset ?? panOffset
                pipPanStartOffset = startOffset
                let proposed = CGSize(
                    width: startOffset.width + value.translation.width,
                    height: startOffset.height + value.translation.height
                )
                applyPanOffset(proposed, framebuffer: framebuffer, viewSize: viewSize)
            }
            .onEnded { _ in
                pipPanStartOffset = nil
                syncPiPViewport(framebuffer: framebuffer, viewSize: viewSize)
            }
    }

    private func pipDoubleTapGesture(
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                toggleZoom(at: value.location, in: viewSize, framebuffer: framebuffer)
            }
    }
    #endif

    private func syncPiPViewport(framebuffer: RFBRawFramebuffer, viewSize: CGSize) {
        #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        guard viewSize.width > 0,
              viewSize.height > 0,
              let pipLayerHost
        else {
            return
        }

        let transform = currentViewportTransform(framebuffer: framebuffer, viewSize: viewSize)
        let replayFrame = isPiPWatching ? framebuffer : nil
        _ = try? pipLayerHost.updateViewport(PiPWatchViewport(transform: transform), replaying: replayFrame)
        #endif
    }

    private func currentViewportTransform(
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) -> ViewportTransform {
        currentViewportTransform(coordinateSpace: coordinateSpace(for: framebuffer), viewSize: viewSize)
    }

    private func currentViewportTransform(
        coordinateSpace: RemoteFramebufferCoordinateSpace,
        viewSize: CGSize
    ) -> ViewportTransform {
        ViewportTransform(
            framebufferSize: coordinateSpace.size,
            viewSize: viewSize,
            zoomScale: zoomScale,
            panOffset: panOffset,
            maxZoomScale: Self.maxZoomScale
        )
    }

    private func coordinateSpace(for framebuffer: RFBRawFramebuffer) -> RemoteFramebufferCoordinateSpace {
        RemoteFramebufferCoordinateSpace(width: framebuffer.width, height: framebuffer.height)
            ?? RemoteFramebufferCoordinateSpace(width: 1, height: 1)!
    }

    private func applyZoomScale(
        _ scale: CGFloat,
        anchor: CGPoint,
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) {
        let minimum = minimumZoomScale(for: viewSize, framebuffer: framebuffer)
        let clamped = min(max(scale, minimum), Self.maxZoomScale)
        let current = currentViewportTransform(framebuffer: framebuffer, viewSize: viewSize)
        let updated: ViewportTransform
        if clamped <= minimum + 0.0001 {
            updated = ViewportTransform(
                framebufferSize: current.framebufferSize,
                viewSize: current.viewSize,
                zoomScale: minimum,
                panOffset: .zero,
                maxZoomScale: current.maxZoomScale
            )
        } else {
            updated = current.zoomed(to: clamped, about: anchor)
        }
        applyViewportTransform(updated, framebuffer: framebuffer, viewSize: viewSize)
    }

    private func applyPanOffset(
        _ proposed: CGSize,
        framebuffer: RFBRawFramebuffer,
        viewSize: CGSize
    ) {
        let updated = ViewportTransform(
            framebufferSize: CGSize(width: framebuffer.width, height: framebuffer.height),
            viewSize: viewSize,
            zoomScale: zoomScale,
            panOffset: proposed,
            maxZoomScale: Self.maxZoomScale
        )
        applyViewportTransform(updated, framebuffer: framebuffer, viewSize: viewSize)
    }

    private func handleViewportInteractionChange(
        _ isActive: Bool,
        frameStrategy: ViewportInteractionFrameStrategy
    ) {
        if isViewportInteractionActive != isActive {
            isViewportInteractionActive = isActive
        }
        onViewportInteractionChange?(isActive, frameStrategy)
    }

    private var statusText: String {
        // "Not connected" reads clearer than the terse "None" the badge
        // used to show, while still staying short enough that it doesn't
        // wrap mid-glyph on compact width (UX punch-list #005).  The icon
        // next to it already carries the "this is the session-state slot"
        // semantics.
        guard let state = session?.state else {
            return "Not connected"
        }
        if case let .reconnecting(attempt, total) = state {
            return "Reconnecting (\(attempt)/\(total))…"
        }
        return state.identifier.capitalized
    }

    /// PiP HUD chip is gated on session presence so the dead-UI chip
    /// never renders on the empty-state home screen (UX punch-list
    /// #103).  `latestFramebuffer != nil` would also work but `session
    /// != nil` is strictly broader — the chip can appear during the
    /// connect handshake's "PiP after first frame" wait — and matches
    /// the action-row's own gating (Connect button enabled iff a
    /// profile is selected, which implies a session can exist).
    private var showsPiPHudChip: Bool {
        session != nil || framebuffer != nil
    }

    /// HUD badge text for `RemoteSessionState.reconnecting`.  Nil
    /// when the session is not in the reconnect window so the
    /// overlay collapses entirely.  No retry button is exposed
    /// while reconnecting — the system is already trying.
    private var reconnectBadgeText: String? {
        guard let state = session?.state,
              case let .reconnecting(attempt, total) = state
        else {
            return nil
        }
        return "Reconnecting (\(attempt)/\(total))…"
    }

    private var canStartPiPWatch: Bool {
        isPiPWatchAvailable && onStartPiPWatch != nil
    }

    /// Disconnect is only meaningful while a session is actively
    /// streaming or in the bounded auto-reconnect window.  In every
    /// other state (no session, connecting, authenticating, degraded,
    /// closed, failed) showing it would be either redundant — the
    /// system is already not running — or actively misleading, e.g.
    /// while the user is still completing a connect handshake.
    /// Hiding the button entirely (vs. disabling it) keeps the
    /// action row compact on iPhone (constitution §VI).
    private var showsDisconnectButton: Bool {
        guard let state = session?.state else { return false }
        switch state {
        case .active, .reconnecting:
            return true
        case .connecting, .authenticating, .degraded, .failed, .closed:
            return false
        }
    }

    /// Connect is hidden once the session is streaming or in the bounded
    /// auto-reconnect window — you don't "Connect" while already
    /// connected, and Disconnect is the relevant action there.  Hiding
    /// it (vs. disabling) frees width so the action row doesn't overflow
    /// and wrap the Connect label into a vertical glyph strip on compact
    /// iPhone widths once the trackpad / PiP / quality controls are all
    /// present (constitution §VI).  Inverse of `showsDisconnectButton`.
    private var showsConnectButton: Bool {
        guard let state = session?.state else { return true }
        switch state {
        case .active, .reconnecting:
            return false
        case .connecting, .authenticating, .degraded, .failed, .closed:
            return true
        }
    }

    private var pipWatchButtonHelp: String {
        if isPiPWatchAvailable, onStartPiPWatch == nil {
            return "PiP renderer pending"
        }

        return pipWatchStatusText
    }

    private var viewportText: String {
        guard let session else {
            return "No remote frame yet"
        }

        if let lastFrameAt = session.lastFrameAt {
            return "Last frame \(lastFrameAt.formatted(date: .omitted, time: .shortened))"
        }

        return session.hudMessage ?? "Waiting for first frame"
    }

    private var statusSymbolName: String {
        switch session?.state {
        case .active:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .reconnecting, .connecting, .authenticating:
            return "arrow.triangle.2.circlepath"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .closed, nil:
            return "circle"
        }
    }

    private var statusColor: Color {
        switch session?.state {
        case .active:
            return .green
        case .failed:
            return .red
        case .degraded:
            return .orange
        case .connecting, .authenticating, .reconnecting:
            return .blue
        case .closed, nil:
            return .secondary
        }
    }

    /// Trackpad-mode input is a remote-control surface, so it stays out
    /// of the active PiP watch path.  While PiP is fronting the preview,
    /// one-finger drag / pinch / double-tap are reserved for local
    /// focus changes that crop the floating watch frame.
    static func allowsTrackpadInputOverlay(
        isPiPWatching: Bool,
        pointerControlMode: PointerControlMode
    ) -> Bool {
        !isPiPWatching && pointerControlMode.isTrackpad
    }

    static func usesSwiftUITrackpadInputOverlay(
        isPiPWatching: Bool,
        usesHelperVideoPrimaryPreview: Bool = false,
        pointerControlMode: PointerControlMode,
        metalFramebufferInputSupported: Bool
    ) -> Bool {
        allowsTrackpadInputOverlay(
            isPiPWatching: isPiPWatching,
            pointerControlMode: pointerControlMode
        ) && (usesHelperVideoPrimaryPreview || !metalFramebufferInputSupported)
    }

    static func usesSwiftUIDirectTouchInputOverlay(
        isPiPWatching: Bool,
        usesHelperVideoPrimaryPreview: Bool,
        pointerControlMode: PointerControlMode,
        metalFramebufferInputSupported: Bool
    ) -> Bool {
        !isPiPWatching
            && pointerControlMode == .directTouch
            && (usesHelperVideoPrimaryPreview || !metalFramebufferInputSupported)
    }

    static func usesMetalHotTrackpadCursor(
        isPiPWatching: Bool,
        usesHelperVideoPrimaryPreview: Bool = false,
        pointerControlMode: PointerControlMode,
        metalFramebufferInputSupported: Bool
    ) -> Bool {
        allowsTrackpadInputOverlay(
            isPiPWatching: isPiPWatching,
            pointerControlMode: pointerControlMode
        ) && metalFramebufferInputSupported && !usesHelperVideoPrimaryPreview
    }

    private static var metalFramebufferInputSupported: Bool {
        #if os(iOS) && canImport(UIKit) && canImport(Metal) && canImport(MetalKit)
        MetalFramebufferView.isSupported()
        #else
        false
        #endif
    }

    static func showsTrackpadCursor(
        isPiPWatching: Bool,
        pointerControlMode: PointerControlMode,
        cursor: TrackpadCursor
    ) -> Bool {
        allowsTrackpadInputOverlay(
            isPiPWatching: isPiPWatching,
            pointerControlMode: pointerControlMode
        ) && cursor.isVisible
    }

    enum CursorOverlayKind: Equatable {
        case serverShape
        case syntheticFallback
    }

    static func cursorOverlayKind(serverCursor: RFBServerCursor?) -> CursorOverlayKind {
        guard let serverCursor, serverCursor.width > 0, serverCursor.height > 0 else {
            return .syntheticFallback
        }
        return .serverShape
    }

    /// Double-tap zoom uses the same transform math as pointer mapping
    /// so a tapped terminal line remains under the user's finger even
    /// when the server aspect ratio leaves letterbox bands in the
    /// session container.
    static func zoomToggleTransform(
        framebufferSize: CGSize,
        viewSize: CGSize,
        zoomScale: CGFloat,
        panOffset: CGSize,
        anchor: CGPoint,
        baselineZoomScale: CGFloat = Self.minZoomScale,
        maxZoomScale: CGFloat = Self.maxZoomScale
    ) -> ViewportTransform {
        let baseline = min(max(baselineZoomScale, Self.minZoomScale), maxZoomScale)
        let current = ViewportTransform(
            framebufferSize: framebufferSize,
            viewSize: viewSize,
            zoomScale: max(zoomScale, baseline),
            panOffset: panOffset,
            maxZoomScale: maxZoomScale
        )
        guard current.zoomScale <= baseline + 0.02 else {
            return ViewportTransform(
                framebufferSize: framebufferSize,
                viewSize: viewSize,
                zoomScale: baseline,
                panOffset: .zero,
                maxZoomScale: maxZoomScale
            )
        }
        let targetZoomScale = min(max(baseline * 1.35, CGFloat(2.5)), maxZoomScale)
        guard targetZoomScale > baseline + 0.02 else {
            return current
        }
        return current.zoomed(to: targetZoomScale, about: anchor)
    }

    nonisolated static func allowsImmersiveControlAutoHide(
        showsControlBar: Bool,
        isViewportInteractionActive: Bool
    ) -> Bool {
        showsControlBar && !isViewportInteractionActive
    }

    nonisolated static func trackpadDragOwnsViewportInteraction(
        transform: ViewportTransform
    ) -> Bool {
        transform.isPannable
    }

    enum ViewportStatePublishPolicy: Equatable {
        case gestureEnd
        case liveDisplayLink
    }

    nonisolated static func viewportStatePublishPolicy(
        for frameStrategy: ViewportInteractionFrameStrategy
    ) -> ViewportStatePublishPolicy {
        switch frameStrategy {
        case .deferUntilSettled, .liveRemoteFrames:
            return .liveDisplayLink
        }
    }

    /// Maps a framebuffer-pixel cursor position into the container's
    /// view-space point using the same fit × zoom × pan transform as the
    /// framebuffer preview.  This keeps the soft/server cursor aligned
    /// while the user zooms and pans locally (spec 003 FR-014/FR-015).
    static func cursorViewPoint(
        framebufferPosition: CGPoint,
        framebufferWidth: Int,
        framebufferHeight: Int,
        containerSize: CGSize,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        maxZoomScale: CGFloat = Self.maxZoomScale
    ) -> CGPoint {
        guard framebufferWidth > 0,
              framebufferHeight > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        }

        let transform = ViewportTransform(
            framebufferSize: CGSize(width: framebufferWidth, height: framebufferHeight),
            viewSize: containerSize,
            zoomScale: zoomScale,
            panOffset: panOffset,
            maxZoomScale: maxZoomScale
        )
        return transform.viewPoint(fromFramebufferPoint: framebufferPosition)
    }
}

/// Switches the session container between the historical width-driven
/// aspect-fit box and the immersive full-height "hero" (spec 003
/// FR-001).  Kept as a `ViewModifier` so the trailing `.clipShape` /
/// `.overlay` chain in `body` is applied once regardless of mode.
private struct ViewportSizing: ViewModifier {
    let fill: Bool
    let aspectRatio: CGFloat

    func body(content: Content) -> some View {
        if fill {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        }
    }
}

private struct RemoteFramebufferPreview: View {
    private let framebuffer: RFBRawFramebuffer
    private let xStep: Int
    private let yStep: Int

    init(framebuffer: RFBRawFramebuffer) {
        self.framebuffer = framebuffer
        self.xStep = max(1, framebuffer.width / 160)
        self.yStep = max(1, framebuffer.height / 90)
    }

    var body: some View {
        Canvas { context, size in
            let sampledColumns = max(1, (framebuffer.width + xStep - 1) / xStep)
            let sampledRows = max(1, (framebuffer.height + yStep - 1) / yStep)
            let cellWidth = size.width / CGFloat(sampledColumns)
            let cellHeight = size.height / CGFloat(sampledRows)

            for sampledY in 0..<sampledRows {
                for sampledX in 0..<sampledColumns {
                    let sourceX = min(sampledX * xStep, framebuffer.width - 1)
                    let sourceY = min(sampledY * yStep, framebuffer.height - 1)
                    guard let color = framebuffer[sourceX, sourceY] else {
                        continue
                    }

                    let rect = CGRect(
                        x: CGFloat(sampledX) * cellWidth,
                        y: CGFloat(sampledY) * cellHeight,
                        width: cellWidth.rounded(.up),
                        height: cellHeight.rounded(.up)
                    )
                    context.fill(
                        Path(rect),
                        with: .color(color.previewColor)
                    )
                }
            }
        }
        .aspectRatio(
            CGFloat(max(framebuffer.width, 1)) / CGFloat(max(framebuffer.height, 1)),
            contentMode: .fit
        )
        .accessibilityLabel("Remote framebuffer \(framebuffer.width) by \(framebuffer.height)")
    }
}

private extension RFBColor {
    var previewColor: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }
}
