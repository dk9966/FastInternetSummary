#!/usr/bin/swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downsamples docs/app-icon.png into every macOS AppIcon slot.

let sizes = [16, 32, 64, 128, 256, 512, 1024]

let root = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("docs/app-icon.png")
let outDir = root.appendingPathComponent("FastInternetSummary/Assets.xcassets/AppIcon.appiconset")

func loadPNG(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    else {
        fatalError("Could not load \(url.path)")
    }
    return image
}

func scaled(_ image: CGImage, size: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create graphics context")
    }
    ctx.interpolationQuality = size <= 32 ? .medium : .high
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let out = ctx.makeImage() else {
        fatalError("Could not scale icon to \(size)")
    }
    return out
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, [
        kCGImagePropertyDPIWidth: 72,
        kCGImagePropertyDPIHeight: 72,
    ] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Could not finalize \(url.path)")
    }
}

let source = loadPNG(sourceURL)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for size in sizes {
    writePNG(scaled(source, size: size), to: outDir.appendingPathComponent("icon_\(size).png"))
}

print("Wrote \(sizes.count) icons from \(sourceURL.lastPathComponent) to \(outDir.path)")
