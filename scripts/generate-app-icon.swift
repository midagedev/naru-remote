#!/usr/bin/env swift
//
// Reproducible Naru Remote app-icon generator.
//
// Renders the 1024×1024 marketing icon as an opaque PNG (App Store
// icons must have no alpha channel) using CoreGraphics, so the brand
// mark is regenerable from source instead of being an opaque binary
// blob.  The motif is a "나루"/ferry-crossing glyph — a rounded ferry
// prow (upward chevron) gliding over two water lines — in white on the
// brand teal gradient (BRANDING.md §7 focus/preview teal family).
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

// MARK: Background — vertical brand-teal gradient.
let top = color(48, 167, 156)
let bottom = color(16, 74, 70)
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [top, bottom] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: 0, y: size),
    options: []
)

// Soft top-center glow for depth.
let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(255, 255, 255, 0.16), color(255, 255, 255, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: size * 0.5, y: size * 0.30),
    startRadius: 0,
    endCenter: CGPoint(x: size * 0.5, y: size * 0.30),
    endRadius: size * 0.62,
    options: []
)

// MARK: Ferry prow — an upward rounded chevron.
let cx = size * 0.5
let apexY = size * 0.345
let armDX = size * 0.205
let armDY = size * 0.150
let stroke = size * 0.090

ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setStrokeColor(color(255, 255, 255))
ctx.setLineWidth(stroke)
ctx.beginPath()
ctx.move(to: CGPoint(x: cx - armDX, y: apexY + armDY))
ctx.addLine(to: CGPoint(x: cx, y: apexY))
ctx.addLine(to: CGPoint(x: cx + armDX, y: apexY + armDY))
ctx.strokePath()

// MARK: Water lines — two rounded capsules, the lower shorter/fainter.
func waterLine(centerY: Double, halfWidth: Double, alpha: Double) {
    let thickness = size * 0.058
    ctx.setStrokeColor(color(255, 255, 255, alpha))
    ctx.setLineWidth(thickness)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx - halfWidth, y: centerY))
    ctx.addLine(to: CGPoint(x: cx + halfWidth, y: centerY))
    ctx.strokePath()
}
waterLine(centerY: size * 0.620, halfWidth: size * 0.230, alpha: 1.0)
waterLine(centerY: size * 0.715, halfWidth: size * 0.150, alpha: 0.72)

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
