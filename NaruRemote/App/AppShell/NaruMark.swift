import SwiftUI

/// Naru's “Between Worlds” identity mark.
///
/// Two otherwise separate planes briefly become adjacent along a Signal-Blue
/// seam. The small light tile is a completed thought crossing that boundary:
/// local composition becoming remote action. The metaphor is intentionally
/// abstract — no monitor, cursor, network topology, or upload arrow — so the
/// same mark can represent text, voice, images, and files.
struct NaruMark: View {
    /// Position of the travelling thought along the seam, 0 (local) … 1
    /// (remote). The resting identity state holds it at the threshold.
    var pulse: Double = 0.5
    var isActive: Bool = true

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let center = CGPoint(x: width / 2, y: height / 2)
            let planeWidth = width * 0.49
            let planeHeight = height * 0.41
            let cornerRadius = min(planeWidth, planeHeight) * 0.19
            let angle = -CGFloat.pi * 0.22

            func plane(center planeCenter: CGPoint) -> Path {
                let rect = CGRect(
                    x: planeCenter.x - planeWidth / 2,
                    y: planeCenter.y - planeHeight / 2,
                    width: planeWidth,
                    height: planeHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                let transform = CGAffineTransform(
                    translationX: planeCenter.x,
                    y: planeCenter.y
                )
                .rotated(by: angle)
                .translatedBy(x: -planeCenter.x, y: -planeCenter.y)
                return path.applying(transform)
            }

            let localCenter = CGPoint(x: width * 0.37, y: height * 0.35)
            let remoteCenter = CGPoint(x: width * 0.63, y: height * 0.65)
            let localPlane = plane(center: localCenter)
            let remotePlane = plane(center: remoteCenter)

            let graphiteNear = Color(
                red: 0x3A / 255.0,
                green: 0x42 / 255.0,
                blue: 0x4F / 255.0
            )
            let graphiteFar = Color(
                red: 0x26 / 255.0,
                green: 0x2C / 255.0,
                blue: 0x36 / 255.0
            )
            let edge = Color.white.opacity(0.17)
            let signal = Color(NaruColors.signalBlue)

            // The farther plane sits first. A restrained highlight keeps the
            // impossible overlap legible on both light and dark canvases.
            context.fill(remotePlane, with: .color(graphiteFar))
            context.stroke(remotePlane, with: .color(edge), lineWidth: max(0.8, width * 0.010))
            context.fill(localPlane, with: .color(graphiteNear))
            context.stroke(localPlane, with: .color(edge), lineWidth: max(0.8, width * 0.010))

            // The seam runs bottom-left → top-right: a single quiet boundary,
            // not an arrow. Its width is deliberately bold enough to survive
            // the 60-point home-screen icon reduction.
            let seamStart = CGPoint(x: width * 0.24, y: height * 0.73)
            let seamEnd = CGPoint(x: width * 0.76, y: height * 0.27)
            var seam = Path()
            seam.move(to: seamStart)
            seam.addLine(to: seamEnd)
            context.stroke(
                seam,
                with: .linearGradient(
                    Gradient(colors: [signal.opacity(0.82), signal]),
                    startPoint: seamStart,
                    endPoint: seamEnd
                ),
                style: StrokeStyle(
                    lineWidth: width * 0.075,
                    lineCap: .round
                )
            )

            // The thought travels on the same seam. Drawing it before the
            // narrow blue crest lets the boundary visibly bisect the tile.
            let clampedPulse = CGFloat(min(max(pulse, 0), 1))
            let thoughtCenter = CGPoint(
                x: seamStart.x + (seamEnd.x - seamStart.x) * clampedPulse,
                y: seamStart.y + (seamEnd.y - seamStart.y) * clampedPulse
            )
            let thoughtSide = width * 0.20
            let thought = Path(
                roundedRect: CGRect(
                    x: thoughtCenter.x - thoughtSide / 2,
                    y: thoughtCenter.y - thoughtSide / 2,
                    width: thoughtSide,
                    height: thoughtSide
                ),
                cornerRadius: thoughtSide * 0.25
            )
            let thoughtColor = isActive
                ? Color(red: 0xF3 / 255.0, green: 0xF5 / 255.0, blue: 0xF7 / 255.0)
                : Color(NaruColors.mutedInk)
            context.fill(
                thought,
                with: .color(thoughtColor)
            )

            var crest = Path()
            crest.move(to: seamStart)
            crest.addLine(to: seamEnd)
            context.stroke(
                crest,
                with: .color(signal),
                style: StrokeStyle(lineWidth: width * 0.022, lineCap: .round)
            )

            // A tiny crossing highlight is enough to suggest depth without
            // turning the mark into glossy 3D artwork.
            let highlightLength = width * 0.13
            let direction = CGVector(dx: seamEnd.x - seamStart.x, dy: seamEnd.y - seamStart.y)
            let magnitude = max(1, hypot(direction.dx, direction.dy))
            let unit = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
            var highlight = Path()
            highlight.move(to: CGPoint(
                x: center.x - unit.dx * highlightLength / 2,
                y: center.y - unit.dy * highlightLength / 2
            ))
            highlight.addLine(to: CGPoint(
                x: center.x + unit.dx * highlightLength / 2,
                y: center.y + unit.dy * highlightLength / 2
            ))
            context.stroke(
                highlight,
                with: .color(Color.white.opacity(0.38)),
                style: StrokeStyle(lineWidth: width * 0.010, lineCap: .round)
            )
        }
        .accessibilityHidden(true)
    }
}
