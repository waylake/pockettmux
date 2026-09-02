#!/usr/bin/env swift
// make-icon.swift — renders the PocketTmux app icon (1024×1024 PNG).
// Design: sumi-ink background, vermilion "❯" terminal prompt + washi block
// cursor. Run: swift scripts/make-icon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background: vertical gradient 墨 → 藍墨
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.043, green: 0.051, blue: 0.067, alpha: 1),   // #0B0D11
    CGColor(srgbRed: 0.078, green: 0.102, blue: 0.149, alpha: 1),   // #141A26
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])

// Vermilion ">" chevron (two strokes, round caps)
let vermilion = CGColor(srgbRed: 0.878, green: 0.345, blue: 0.298, alpha: 1)  // #E0584C
ctx.setStrokeColor(vermilion)
ctx.setLineWidth(92)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.beginPath()
ctx.move(to: CGPoint(x: 330, y: 300))
ctx.addLine(to: CGPoint(x: 500, y: 512))
ctx.addLine(to: CGPoint(x: 330, y: 724))
ctx.strokePath()

// Washi block cursor (terminal caret)
let washi = CGColor(srgbRed: 0.894, green: 0.878, blue: 0.831, alpha: 1)  // #E4E0D4
let cursor = CGRect(x: 600, y: 392, width: 236, height: 240)
ctx.setFillColor(washi)
ctx.addPath(CGPath(roundedRect: cursor, cornerWidth: 64, cornerHeight: 64, transform: nil))
ctx.fillPath()

// Subtle baseline tick in 藍 ai (keeps the glyph grounded, ink-on-ink)
let indigo = CGColor(srgbRed: 0.29, green: 0.435, blue: 0.647, alpha: 0.35)  // #4A6FA5
ctx.setFillColor(indigo)
ctx.fill(CGRect(x: 330, y: 150, width: 506, height: 26))

let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")