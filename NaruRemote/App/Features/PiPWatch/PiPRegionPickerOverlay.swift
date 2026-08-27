import NaruRemoteCore
import SwiftUI

/// Draws the region PiP will watch (spec 034 FR-005).
///
/// The box is **aspect-locked to the view it is drawn over**, which is the
/// framebuffer's displayed rect — and that is what the window will actually
/// show, because `PiPWatchViewport.sourceRect` crops width and height by the
/// same factor. A free-form rectangle would promise a framing the system
/// cannot deliver.
///
/// It reports the box in **its own view coordinates** and nothing else. The
/// host converts through the live `ViewportTransform`, because the remote
/// screen under the box may be zoomed and panned — treating a view rect as a
/// framebuffer rect would be right only at zoom 1 with no pan.
struct PiPRegionPickerOverlay: View {
    /// Normalised centre of the region, `[0, 1]` over the framebuffer.
    @State private var centerX: Double
    @State private var centerY: Double
    /// 1 is the whole framebuffer; the ceiling matches the app's own zoom.
    @State private var zoomScale: Double
    @State private var dragStart: CGPoint?
    @State private var pinchStart: Double?

    private let onCancel: () -> Void
    private let onUse: (CGRect) -> Void

    /// Aspect ratio of the remote framebuffer, width over height. The box is
    /// locked to it, so the shape drawn here is the shape the window shows.
    private let aspectRatio: Double

    /// `initialZoomScale` opens the box at a readable fraction of the view
    /// rather than at the whole thing, which would be a region that selects
    /// nothing.
    init(
        aspectRatio: Double,
        initialZoomScale: Double = 2,
        onCancel: @escaping () -> Void,
        onUse: @escaping (CGRect) -> Void
    ) {
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
        _centerX = State(initialValue: 0.5)
        _centerY = State(initialValue: 0.5)
        _zoomScale = State(initialValue: max(initialZoomScale, 1.2))
        self.onCancel = onCancel
        self.onUse = onUse
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let box = regionRect(in: size)

            ZStack(alignment: .top) {
                // Everything outside the region is dimmed, so the region reads
                // as the thing being chosen rather than as a floating frame.
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .mask(
                        ZStack {
                            Rectangle()
                            RoundedRectangle(cornerRadius: 6)
                                .frame(width: box.width, height: box.height)
                                .position(x: box.midX, y: box.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    )

                RoundedRectangle(cornerRadius: 6)
                    .stroke(NaruColors.signalBlue, lineWidth: 2)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .allowsHitTesting(false)

                instructions
                    .padding(.top, 62)

                controls(in: size)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: size))
            .simultaneousGesture(pinchGesture())
        }
        .ignoresSafeArea(edges: .bottom)
    }
    // No identifier on this root: SwiftUI applies the *outermost*
    // accessibility identifier to everything beneath it, so one here renamed
    // the picker's own buttons — measured twice while wiring
    // `PiPFramingUITests`, first inheriting `naru.session.viewport` and then
    // this view's own. The identifier lives on the instruction line instead,
    // which is a leaf.

    private var instructions: some View {
        Text("Drag to move, pinch to resize")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .accessibilityIdentifier("naru.session.pip.regionPicker")
    }

    /// Takes the laid-out size as a parameter rather than storing it: the
    /// confirmation has to report the box in the coordinates it was drawn in,
    /// and a `@State` copy written during layout is a side effect in a body.
    private func controls(in size: CGSize) -> some View {
        HStack(spacing: 10) {
            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("naru.session.pip.regionPicker.cancel")

            Button("Watch this region") {
                onUse(regionRect(in: size))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("naru.session.pip.regionPicker.use")
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(Capsule())
    }

    /// The region in view coordinates. The view is the framebuffer's displayed
    /// rect, so a normalised centre maps straight onto it.
    private func regionRect(in size: CGSize) -> CGRect {
        // Everything in Double: CGFloat and Double interconvert implicitly, and
        // a mixed expression here is ambiguous rather than convenient.
        let viewWidth = max(Double(size.width), 1)
        let viewHeight = max(Double(size.height), 1)
        // Locked to the framebuffer's aspect, not the screen's. The first
        // capture of this picker drew a portrait box over a landscape desktop,
        // which promised a shape `sourceRect` cannot produce: it divides width
        // and height by the same factor, so the crop always carries the
        // framebuffer's aspect.
        var width = viewWidth / zoomScale
        var height = width / aspectRatio
        if height > viewHeight {
            height = viewHeight
            width = height * aspectRatio
        }
        let center = CGPoint(
            x: clampCenter(centerX, span: width / viewWidth),
            y: clampCenter(centerY, span: height / viewHeight)
        )
        return CGRect(
            x: Double(center.x) * viewWidth - width / 2,
            y: Double(center.y) * viewHeight - height / 2,
            width: width,
            height: height
        )
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? CGPoint(x: centerX, y: centerY)
                dragStart = start
                guard size.width > 0, size.height > 0 else { return }
                let movedX = Double(value.translation.width) / Double(size.width)
                let movedY = Double(value.translation.height) / Double(size.height)
                centerX = clampCenter(Double(start.x) + movedX, span: 1 / zoomScale)
                centerY = clampCenter(Double(start.y) + movedY, span: 1 / zoomScale)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func pinchGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let start = pinchStart ?? zoomScale
                pinchStart = start
                // Pinching out shrinks the region — the gesture magnifies what
                // the window will show, which is the same direction as zooming
                // the viewport itself.
                zoomScale = min(max(start * Double(value), 1), PiPFramingTarget.maximumZoomScale)
                centerX = clampCenter(centerX, span: 1 / zoomScale)
                centerY = clampCenter(centerY, span: 1 / zoomScale)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private func clampCenter(_ value: Double, span: Double) -> Double {
        let half = min(span / 2, 0.5)
        return min(max(value, half), 1 - half)
    }
}
