#!/usr/bin/env swift
// make-icon.swift — renders the PocketTmux app icon (1024×1024 PNG).
// Design: sumi-ink background, vermilion "❯" terminal prompt + washi block
// cursor.
//
//   swift scripts/make-icon.swift [--mac] <out.png>
//
//   default  iOS: artwork fills the full square (iOS masks the corners itself)
//   --mac    macOS: same artwork drawn at 824/1024 centred inside the standard
//            macOS icon margins, clipped to a rounded rect (radius ≈ 185 px at
//            1024) with transparent pixels outside — what Finder/Dock expect.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

var args = Array(CommandLine.arguments.dropFirst())
let mac = args.contains("--mac")
args.removeAll { $0 == "--mac" }
if args.count > 1 || args.first?.hasPrefix("-") == true {
    FileHandle.standardError.write(Data("usage: swift scripts/make-icon.swift [--mac] <out.png>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: args.first ?? (mac ? "AppIcon-mac-1024.png" : "AppIcon-1024.png"))

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Artwork is authored in a 1024-pt square. For --mac, shrink it to the
// 824-pt macOS "icon grid" square, centred, and clip to the rounded rect.
// Everything outside the clip stays transparent (the context starts cleared).
let artSize: CGFloat = mac ? 824 : 1024
let inset = (CGFloat(size) - artSize) / 2
let artRect = CGRect(x: inset, y: inset, width: artSize, height: artSize)
if mac {
    let radius: CGFloat = 185           // the macOS icon corner curve at 1024 px
    ctx.addPath(CGPath(roundedRect: artRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
}
ctx.translateBy(x: inset, y: inset)
ctx.scaleBy(x: artSize / 1024, y: artSize / 1024)

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
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)\(mac ? " (macOS margins + rounded mask)" : "")")
