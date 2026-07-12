#!/usr/bin/env swift
//
// Reproducible Naru Remote app-icon normalizer.
//
// The 2026-07-12 “Between Worlds” artwork was created with the Codex
// image-generation skill and archived in-repo with its prompt. This script
// turns that retained source into the exact App Store asset shape: 1024×1024,
// opaque, and tagged sRGB. Keeping normalization deterministic avoids silently
// falling back to the retired node-topology icon.
//
// Usage:
//   swift scripts/generate-app-icon.swift [source.png] [output.png]
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sourcePath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "artifacts/branding/2026-07-12/between-worlds-imagegen-source.png"
let outputPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "NaruRemote/iOSApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

guard sourcePath != outputPath else {
    fatalError("Source and output paths must be different")
}

let sourceURL = URL(fileURLWithPath: sourcePath)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Unable to read source artwork at \(sourcePath)")
}

let outputSize = 1024
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: outputSize,
        height: outputSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      ) else {
    fatalError("Unable to create opaque sRGB bitmap context")
}

// Fill first even though the retained source is opaque. This keeps the output
// valid if a future source contains transparency around the artwork.
context.setFillColor(
    CGColor(
        colorSpace: colorSpace,
        components: [17.0 / 255.0, 19.0 / 255.0, 24.0 / 255.0, 1.0]
    )!
)
context.fill(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))

let sourceWidth = CGFloat(sourceImage.width)
let sourceHeight = CGFloat(sourceImage.height)
let scale = max(CGFloat(outputSize) / sourceWidth, CGFloat(outputSize) / sourceHeight)
let drawWidth = sourceWidth * scale
let drawHeight = sourceHeight * scale
let drawRect = CGRect(
    x: (CGFloat(outputSize) - drawWidth) / 2,
    y: (CGFloat(outputSize) - drawHeight) / 2,
    width: drawWidth,
    height: drawHeight
)

context.interpolationQuality = .high
context.draw(sourceImage, in: drawRect)

guard let outputImage = context.makeImage() else {
    fatalError("Unable to create normalized icon image")
}

let outputURL = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Unable to create PNG destination at \(outputPath)")
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Unable to write PNG at \(outputPath)")
}

print("Wrote opaque 1024×1024 sRGB icon to \(outputPath)")
