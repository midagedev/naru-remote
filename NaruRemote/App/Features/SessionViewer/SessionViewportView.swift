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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        onRunChecks?()
                    } label: {
                        Label("Checks", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .disabled(onRunChecks == nil)
                    .help("Run connection checks")
                    .accessibilityIdentifier("naru.session.checks")

                    Button {
                        onConnect?()
                    } label: {
                        Label("Connect", systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(onConnect == nil)
                    .help("Connect to selected profile")
                    .accessibilityIdentifier("naru.session.connect")

                    Button {
                        onStartPiPWatch?()
                    } label: {
                        Label("PiP Watch", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canStartPiPWatch)
                    .help(pipWatchButtonHelp)
                    .accessibilityIdentifier("naru.session.pipWatch")

                    Label(statusText, systemImage: statusSymbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                        .labelStyle(.titleAndIcon)
                        .help("Connection state")
                }
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
                Label(pipWatchStatusText, systemImage: "rectangle.on.rectangle")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.black.opacity(0.32))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(10)
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
        guard let state = session?.state else {
            return "No Session"
        }
        if case let .reconnecting(attempt, total) = state {
            return "Reconnecting (\(attempt)/\(total))…"
        }
        return state.identifier.capitalized
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
