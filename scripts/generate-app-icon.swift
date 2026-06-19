#!/usr/bin/env swift
//
// Reproducible Naru Remote app-icon generator.
//
// Renders the 1024×1024 marketing icon as an opaque PNG (App Store icons
// must have no alpha channel) using CoreGraphics, so the brand mark is
// regenerable from source instead of being an opaque binary blob.
//
// Motif (BRANDING.md §6.3 "App Icon 방향"): a graphite field holding three
// remote nodes joined by thin lines, a horizontal input slot (the dock /
// port) along the bottom, and a Signal-Blue pulse rising from the slot into
// the nearest node. It depicts "local input crossing into private remote
// nodes" (§6.2) — no monitor/cursor, no VNC lettering, no ferry, no cloud,
// no decorative gradient hero. Quiet Ops Console, not glossy SaaS.
//
// Usage:  swift scripts/generate-app-icon.swift <output.png>
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    // No alpha — opaque icon (noneSkipLast = ignore the alpha byte).
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Unable to create bitmap context")
}

// CoreGraphics origin is bottom-left; design coordinates below are
// expressed top-left, so flip once up front.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, a])!
}

// Brand palette (BRANDING.md §7).
let graphiteTop = color(0x1B, 0x1F, 0x26)   // slightly lifted graphite
let graphiteBottom = color(0x0E, 0x10, 0x15) // near-black floor
let signalBlue = color(0x2D, 0x7D, 0xFF)
let signalBlueSoft = color(0x5B, 0x9B, 0xFF)
let nodeFill = color(0x31, 0x39, 0x45)       // slate node chip
let nodeStroke = color(0x4A, 0x55, 0x64)     // muted hairline
let nodeCore = color(0xB4, 0xBC, 0xC8)       // muted device core
let lane = color(0x24, 0x2A, 0x33)           // surface-raised dock
let laneEdge = color(0x47, 0x51, 0x60)       // link / dock hairline

// MARK: Background — a quiet vertical graphite wash (not a hero gradient).
let bg = CGGradient(
    colorsSpace: colorSpace,
    colors: [graphiteTop, graphiteBottom] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bg,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: 0, y: size),
    options: []
)

// Helper: rounded-rect path.
func roundedRect(_ rect: CGRect, radius: Double) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Helper: a node chip centred at (x, y).
func node(x: Double, y: Double, side: Double, active: Bool) {
    let rect = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
    let path = roundedRect(rect, radius: side * 0.28)
    if active {
        // Subtle glow behind the active node.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: size * 0.045, color: signalBlue.copy(alpha: 0.55))
        ctx.addPath(path)
        ctx.setFillColor(signalBlue)
        ctx.fillPath()
        ctx.restoreGState()
        // Inner core dot.
        let coreSide = side * 0.34
        let core = CGRect(x: x - coreSide / 2, y: y - coreSide / 2, width: coreSide, height: coreSide)
        ctx.addPath(roundedRect(core, radius: coreSide * 0.3))
        ctx.setFillColor(color(255, 255, 255, 0.92))
        ctx.fillPath()
    } else {
        ctx.addPath(path)
        ctx.setFillColor(nodeFill)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(nodeStroke)
        ctx.setLineWidth(size * 0.010)
        ctx.strokePath()
        // Small muted core so the node reads as a device, not a blank tile.
        let coreSide = side * 0.30
        let core = CGRect(x: x - coreSide / 2, y: y - coreSide / 2, width: coreSide, height: coreSide)
        ctx.addPath(roundedRect(core, radius: coreSide * 0.3))
        ctx.setFillColor(nodeCore)
        ctx.fillPath()
    }
}

// Node positions — a small constellation, the lowest one "active".
let nA = CGPoint(x: size * 0.338, y: size * 0.352)
let nB = CGPoint(x: size * 0.692, y: size * 0.330)
let nActive = CGPoint(x: size * 0.515, y: size * 0.486)
let nodeSide = size * 0.162
let activeSide = size * 0.188

// MARK: Connection lines between nodes (hairlines).
ctx.setLineCap(.round)
ctx.setStrokeColor(laneEdge)
ctx.setLineWidth(size * 0.013)
func link(_ p: CGPoint, _ q: CGPoint) {
    ctx.beginPath()
    ctx.move(to: p)
    ctx.addLine(to: q)
    ctx.strokePath()
}
link(nA, nB)
link(nA, nActive)
link(nB, nActive)

// MARK: Input slot / dock — a rounded horizontal bar along the bottom.
let laneRect = CGRect(x: size * 0.250, y: size * 0.688, width: size * 0.500, height: size * 0.086)
ctx.addPath(roundedRect(laneRect, radius: laneRect.height / 2))
ctx.setFillColor(lane)
ctx.fillPath()
// Top hairline highlight so the slot reads as a raised surface.
ctx.addPath(roundedRect(laneRect, radius: laneRect.height / 2))
ctx.setStrokeColor(laneEdge)
ctx.setLineWidth(size * 0.007)
ctx.strokePath()
// A short Signal-Blue notch in the slot — where the pulse departs.
let notch = CGRect(x: nActive.x - size * 0.045, y: laneRect.midY - size * 0.011,
                   width: size * 0.090, height: size * 0.022)
ctx.addPath(roundedRect(notch, radius: notch.height / 2))
ctx.setFillColor(signalBlue)
ctx.fillPath()

// MARK: Signal pulse — a bold beam rising from the slot into the node.
let pulseX = nActive.x
let pulseStartY = laneRect.minY
let pulseEndY = nActive.y + activeSide * 0.5
ctx.setLineCap(.round)
let pulseGrad = CGGradient(
    colorsSpace: colorSpace,
    colors: [signalBlue.copy(alpha: 0.35)!, signalBlueSoft] as CFArray,
    locations: [0, 1]
)!
ctx.saveGState()
ctx.setLineWidth(size * 0.028)
ctx.beginPath()
ctx.move(to: CGPoint(x: pulseX, y: pulseStartY))
ctx.addLine(to: CGPoint(x: pulseX, y: pulseEndY))
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    pulseGrad,
    start: CGPoint(x: pulseX, y: pulseStartY),
    end: CGPoint(x: pulseX, y: pulseEndY),
    options: []
)
ctx.restoreGState()

// A single bright leading packet just below the active node.
ctx.saveGState()
let leadRadius = size * 0.026
ctx.setShadow(offset: .zero, blur: size * 0.03, color: signalBlue.copy(alpha: 0.75))
let lead = CGRect(x: pulseX - leadRadius, y: (pulseEndY + size * 0.020) - leadRadius,
                  width: leadRadius * 2, height: leadRadius * 2)
ctx.addPath(CGPath(ellipseIn: lead, transform: nil))
ctx.setFillColor(signalBlueSoft)
ctx.fillPath()
ctx.restoreGState()

// MARK: Draw nodes last so they sit above the lines/pulse.
node(x: nA.x, y: nA.y, side: nodeSide, active: false)
node(x: nB.x, y: nB.y, side: nodeSide, active: false)
node(x: nActive.x, y: nActive.y, side: activeSide, active: true)

// MARK: Encode PNG.
guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Unable to create image destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("PNG write failed") }
print("Wrote \(outputPath)")
