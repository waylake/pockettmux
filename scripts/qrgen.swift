#!/usr/bin/env swift
// qrgen.swift — renders a QR PNG for a given payload string.
// Run: swift scripts/qrgen.swift "pockettmux://pair?host=…&port=7682&token=…" out.png
import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else {
    print("usage: qrgen.swift <payload> <out.png>"); exit(1)
}
let payload = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(payload.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
guard let ci = filter.outputImage else { print("qr failed"); exit(1) }

// Scale up with crisp pixels, pad to a quiet zone, embed in sumi/paper colors.
let scale: CGFloat = 24
let transformed = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let qrRect = transformed.extent
let pad: CGFloat = 160
let canvas = CGRect(x: 0, y: 0,
                    width: qrRect.width + pad * 2,
                    height: qrRect.height + pad * 2)

let ciContext = CIContext()
guard let cg = ciContext.createCGImage(transformed, from: qrRect) else {
    print("cgImage render failed"); exit(1)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// 和紙 background, 墨 modules (invert for a dark-on-light code to print well)
ctx.setFillColor(CGColor(srgbRed: 0.894, green: 0.878, blue: 0.831, alpha: 1))  // washi
ctx.fill(canvas)
ctx.setFillColor(CGColor(srgbRed: 0.043, green: 0.051, blue: 0.067, alpha: 1))  // sumi
ctx.translateBy(x: pad, y: pad)
ctx.draw(cg, in: qrRect)

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")