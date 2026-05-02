import NaruRemoteCore
import SwiftUI

#if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
import AVFoundation
#endif

public struct SessionViewportView: View {
    private let title: String
    private let subtitle: String
    private let session: RemoteSession?
    private let framebuffer: RFBRawFramebuffer?
    private let frameDirtyRectangles: [RFBFrameDamageRect]?
    private let isPiPWatchAvailable: Bool
    private let pipWatchStatusText: String
    private let isPiPWatching: Bool
    private let onRunChecks: (() -> Void)?
    private let onConnect: (() -> Void)?
    private let onDisconnect: (() -> Void)?
    private let onStartPiPWatch: (() -> Void)?
    private let onFramebufferTap: ((CGPoint, CGSize) -> Void)?
    private let onFramebufferRightClick: ((CGPoint, CGSize) -> Void)?
    private let onFramebufferScroll: ((CGPoint, CGSize, CGSize) -> Void)?
    private let onFramebufferPointerDown: ((CGPoint, CGSize) -> Void)?
    private let onFramebufferPointerMove: ((CGPoint, CGSize) -> Void)?
    private let onFramebufferPointerUp: ((CGPoint, CGSize) -> Void)?
    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    private let pipLayerHost: PiPLayerHost?
    #endif

    /// Local view-only zoom scale driven by pinch.  Constitution §I:
    /// pinch is a LOCAL composition step — it never produces an RFB
    /// message.  Clamped to `[minZoomScale, maxZoomScale]` on every
    /// update.
    @State private var zoomScale: CGFloat = 1.0

    /// Drives the title vs. action-row split.  iPhone (`.compact`)
    /// drops the action pills onto their own row below the title so
    /// each Label keeps a horizontal icon+text silhouette and the
    /// status badge has room to render without mid-word wrap (UX
    /// punch-list #005 / #104).  iPad (`.regular`) keeps the inline
    /// layout — there is no horizontal pressure there.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let minZoomScale: CGFloat = 0.5
    private static let maxZoomScale: CGFloat = 4.0

    #if canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
    public init(
        title: String,
        subtitle: String,
        session: RemoteSession?,
        framebuffer: RFBRawFramebuffer? = nil,
        frameDirtyRectangles: [RFBFrameDamageRect]? = nil,
        isPiPWatchAvailable: Bool = false,
        pipWatchStatusText: String = "PiP after first frame",
        isPiPWatching: Bool = false,
        pipLayerHost: PiPLayerHost? = nil,
        onRunChecks: (() -> Void)? = nil,
        onConnect: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil,
        onStartPiPWatch: (() -> Void)? = nil,
        onFramebufferTap: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferRightClick: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferScroll: ((CGPoint, CGSize, CGSize) -> Void)? = nil,
        onFramebufferPointerDown: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferPointerMove: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferPointerUp: ((CGPoint, CGSize) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.session = session
        self.framebuffer = framebuffer
        self.frameDirtyRectangles = frameDirtyRectangles
        self.isPiPWatchAvailable = isPiPWatchAvailable
        self.pipWatchStatusText = pipWatchStatusText
        self.isPiPWatching = isPiPWatching
        self.pipLayerHost = pipLayerHost
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
    }
    #else
    public init(
        title: String,
        subtitle: String,
        session: RemoteSession?,
        framebuffer: RFBRawFramebuffer? = nil,
        frameDirtyRectangles: [RFBFrameDamageRect]? = nil,
        isPiPWatchAvailable: Bool = false,
        pipWatchStatusText: String = "PiP after first frame",
        isPiPWatching: Bool = false,
        onRunChecks: (() -> Void)? = nil,
        onConnect: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil,
        onStartPiPWatch: (() -> Void)? = nil,
        onFramebufferTap: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferRightClick: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferScroll: ((CGPoint, CGSize, CGSize) -> Void)? = nil,
        onFramebufferPointerDown: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferPointerMove: ((CGPoint, CGSize) -> Void)? = nil,
        onFramebufferPointerUp: ((CGPoint, CGSize) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.session = session
        self.framebuffer = framebuffer
        self.frameDirtyRectangles = frameDirtyRectangles
        self.isPiPWatchAvailable = isPiPWatchAvailable
        self.pipWatchStatusText = pipWatchStatusText
        self.isPiPWatching = isPiPWatching
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
    }
    #endif

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if horizontalSizeClass == .compact {
                compactHeader
            } else {
                regularHeader
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )

                if let framebuffer {
                    framebufferContent(framebuffer)
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
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                // UX punch-list #103: the "PiP after first frame"
                // affordance is only meaningful once a session has been
                // attempted — rendering it on the empty-state home
                // screen reads as a dead UI chip.  Gate on session
                // presence (any state, including .connecting) so the
                // chip appears as soon as the user starts a session
                // and disappears again on disconnect.
                if showsPiPHudChip {
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
                if let badge = reconnectBadgeText {
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
        .padding(16)
        .accessibilityIdentifier("naru.session.viewport")
    }

    // MARK: - Header layouts

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
                connectButton
                if showsDisconnectButton {
                    disconnectButton
                }
                pipWatchButton(iconOnly: false)
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
                connectButton
                if showsDisconnectButton {
                    disconnectButton
                }
                pipWatchButton(iconOnly: true)
                Spacer(minLength: 4)
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

    private var statusBadge: some View {
        Label(statusText, systemImage: statusSymbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(statusColor)
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: true, vertical: false)
            .help("Connection state")
    }

    @ViewBuilder
    private func framebufferContent(_ framebuffer: RFBRawFramebuffer) -> some View {
        let aspectRatio = CGFloat(max(framebuffer.width, 1)) / CGFloat(max(framebuffer.height, 1))

        #if os(iOS) && canImport(UIKit) && canImport(AVFoundation) && canImport(CoreMedia) && canImport(CoreVideo)
        if isPiPWatching, let pipLayerHost {
            // Active system PiP — render through the shared
            // AVSampleBufferDisplayLayer so the in-app preview and the
            // PiP content source share one renderer (PR #5).
            PiPSampleBufferDisplayLayerView(layerHost: pipLayerHost)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .aspectRatio(aspectRatio, contentMode: .fit)
                .accessibilityIdentifier("naru.session.framebufferPreview")
        } else {
            metalOrSampledPreview(framebuffer: framebuffer, aspectRatio: aspectRatio)
        }
        #else
        RemoteFramebufferPreview(framebuffer: framebuffer)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("naru.session.framebufferPreview")
        #endif
    }

    @ViewBuilder
    private func metalOrSampledPreview(
        framebuffer: RFBRawFramebuffer,
        aspectRatio: CGFloat
    ) -> some View {
        #if os(iOS) && canImport(UIKit) && canImport(Metal) && canImport(MetalKit)
        if MetalFramebufferView.isSupported() {
            MetalFramebufferView(
                framebuffer: framebuffer,
                dirtyRectangles: frameDirtyRectangles,
                onTap: onFramebufferTap,
                onRightClick: onFramebufferRightClick,
                onScroll: onFramebufferScroll,
                onPinch: { newScale in
                    // Constitution §I: pinch is a LOCAL view
                    // transform, never an RFB message.
                    zoomScale = min(max(newScale, Self.minZoomScale), Self.maxZoomScale)
                },
                onPointerDown: onFramebufferPointerDown,
                onPointerMove: onFramebufferPointerMove,
                onPointerUp: onFramebufferPointerUp
            )
                .scaleEffect(zoomScale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .aspectRatio(aspectRatio, contentMode: .fit)
                .accessibilityIdentifier("naru.session.framebufferPreview")
        } else {
            RemoteFramebufferPreview(framebuffer: framebuffer)
                .scaleEffect(zoomScale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("naru.session.framebufferPreview")
        }
        #else
        RemoteFramebufferPreview(framebuffer: framebuffer)
            .scaleEffect(zoomScale)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("naru.session.framebufferPreview")
        #endif
    }

    private var statusText: String {
        // "None" instead of "No Session" — terse copy keeps the badge
        // single-word so it never wraps mid-glyph on compact width
        // (UX punch-list #005).  The icon next to it already carries
        // the "this is the session-state slot" semantics.
        guard let state = session?.state else {
            return "None"
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
