#!/usr/bin/swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Dark install window: app on the left, Applications on the right, a chevron between.

guard CommandLine.arguments.count == 4,
      let width = Int(CommandLine.arguments[2]),
      let height = Int(CommandLine.arguments[3]),
      width > 0, height > 0
else {
    fputs("usage: render-dmg-background.swift <out.png> <width> <height>\n", stderr)
    exit(1)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create graphics context")
}

ctx.translateBy(x: 0, y: CGFloat(height))
ctx.scaleBy(x: 1, y: -1)

ctx.setFillColor(CGColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

let cx = CGFloat(width) * 0.5
let cy = CGFloat(height) * 0.47
let arm: CGFloat = 18
let ctxLine: CGFloat = 5

ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28))
ctx.setLineWidth(ctxLine)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.beginPath()
ctx.move(to: CGPoint(x: cx - 6, y: cy - arm))
ctx.addLine(to: CGPoint(x: cx + 14, y: cy))
ctx.addLine(to: CGPoint(x: cx - 6, y: cy + arm))
ctx.strokePath()

guard let image = ctx.makeImage() else {
    fatalError("Could not create background image")
}
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not write \(outURL.path)")
}
CGImageDestinationAddImage(dest, image, [
    kCGImagePropertyDPIWidth: 72,
    kCGImagePropertyDPIHeight: 72,
] as CFDictionary)
guard CGImageDestinationFinalize(dest) else {
    fatalError("Could not finalize \(outURL.path)")
}
