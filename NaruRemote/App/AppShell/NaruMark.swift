import SwiftUI

/// The Naru identity mark, drawn from the same motif as the app icon
/// (BRANDING.md §6.2/§6.3): remote nodes joined by thin lines, a horizontal
/// input slot, and a Signal-Blue pulse crossing from the slot into the
/// active node — "local input crossing into private remote nodes". Using
/// this instead of a stock SF Symbol ties the in-app surfaces to the icon's
/// identity.
///
/// `pulse` (0…1) advances the travelling packet from the dock up to the
/// node, so the same mark can stand still in an empty state or animate the
/// Compose & Send "crossing" moment.
struct NaruMark: View {
    /// Travelling-packet position, 0 (at the dock) … 1 (arrived at node).
    var pulse: Double = 1
    /// Whether the active node reads as "lit" (Signal Blue) vs idle.
    var isActive: Bool = true

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            // Geometry mirrors the app icon's proportions.
            let nodeSide = w * 0.30
            let activeSide = w * 0.345
            let nA = CGPoint(x: w * 0.235, y: h * 0.235)
            let nB = CGPoint(x: w * 0.765, y: h * 0.200)
            let nActive = CGPoint(x: w * 0.500, y: h * 0.470)

            let laneEdge = Color(NaruColors.hairline)
            let blue = Color(NaruColors.signalBlue)
            let nodeFill = Color(NaruColors.surfaceMuted)
            let core = Color(NaruColors.mutedInk)

            func chip(_ center: CGPoint, _ side: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: center.x - side / 2, y: center.y - side / 2,
                                         width: side, height: side),
                     cornerRadius: side * 0.28)
            }

            // Links between nodes.
            var links = Path()
            links.move(to: nA); links.addLine(to: nB)
            links.move(to: nA); links.addLine(to: nActive)
            links.move(to: nB); links.addLine(to: nActive)
            context.stroke(links, with: .color(laneEdge), lineWidth: w * 0.014)

            // Input slot / dock.
            let laneRect = CGRect(x: w * 0.250, y: h * 0.760, width: w * 0.500, height: h * 0.085)
            let lanePath = Path(roundedRect: laneRect, cornerRadius: laneRect.height / 2)
            context.fill(lanePath, with: .color(nodeFill))
            context.stroke(lanePath, with: .color(laneEdge), lineWidth: w * 0.008)

            // Pulse beam from the dock up to the active node.
            let beamTop = nActive.y + activeSide * 0.5
            let beamBottom = laneRect.minY
            var beam = Path()
            beam.move(to: CGPoint(x: nActive.x, y: beamBottom))
            beam.addLine(to: CGPoint(x: nActive.x, y: beamTop))
            context.stroke(beam, with: .color(blue.opacity(0.30)),
                           style: StrokeStyle(lineWidth: w * 0.026, lineCap: .round))

            // Idle (muted) side nodes.
            context.fill(chip(nA, nodeSide), with: .color(nodeFill))
            context.stroke(chip(nA, nodeSide), with: .color(laneEdge), lineWidth: w * 0.010)
            context.fill(chip(nB, nodeSide), with: .color(nodeFill))
            context.stroke(chip(nB, nodeSide), with: .color(laneEdge), lineWidth: w * 0.010)
            let coreSide = nodeSide * 0.30
            context.fill(chip(nA, coreSide), with: .color(core))
            context.fill(chip(nB, coreSide), with: .color(core))

            // Travelling packet along the beam.
            let packetY = beamBottom + (beamTop - beamBottom) * CGFloat(min(max(pulse, 0), 1))
            let packetR = w * 0.030
            context.fill(
                Path(ellipseIn: CGRect(x: nActive.x - packetR, y: packetY - packetR,
                                       width: packetR * 2, height: packetR * 2)),
                with: .color(blue)
            )

            // Active node.
            let activePath = chip(nActive, activeSide)
            context.fill(activePath, with: .color(isActive ? blue : nodeFill))
            if !isActive {
                context.stroke(activePath, with: .color(laneEdge), lineWidth: w * 0.010)
            }
            let activeCoreSide = activeSide * 0.34
            context.fill(chip(nActive, activeCoreSide),
                         with: .color(isActive ? Color.white.opacity(0.92) : core))
        }
        .accessibilityHidden(true)
    }
}
