#!/usr/bin/env swift

import AppKit
import Foundation

private let canvasSize: CGFloat = 1024

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func fill(_ path: CGPath, color: NSColor, in context: CGContext) {
    context.addPath(path)
    context.setFillColor(color.cgColor)
    context.fillPath()
}

private func stroke(_ path: CGPath, color: NSColor, width: CGFloat, in context: CGContext) {
    context.addPath(path)
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.strokePath()
}

private func gradient(
    _ path: CGPath,
    colors: [NSColor],
    locations: [CGFloat],
    start: CGPoint,
    end: CGPoint,
    in context: CGContext
) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors.map(\.cgColor) as CFArray,
        locations: locations
    ) else {
        return
    }
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

private func drawDocument(
    rect: CGRect,
    flipped: Bool,
    accent: NSColor,
    in context: CGContext
) {
    let path = roundedPath(rect, radius: 70)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -16),
        blur: 28,
        color: NSColor(hex: 0x003979, alpha: 0.28).cgColor
    )
    gradient(
        path,
        colors: [
            NSColor.white.withAlphaComponent(0.82),
            NSColor(hex: 0xc7eaff, alpha: 0.56),
        ],
        locations: [0, 1],
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        in: context
    )
    context.restoreGState()
    stroke(path, color: NSColor.white.withAlphaComponent(0.76), width: 8, in: context)

    let insetX: CGFloat = 46
    let lineWidth = rect.width - insetX * 2
    let lineHeight: CGFloat = 18
    let lines: [(CGFloat, CGFloat)] = [
        (rect.maxY - 110, 0.76),
        (rect.maxY - 164, 0.58),
        (rect.maxY - 218, 0.82),
        (rect.maxY - 362, 0.68),
        (rect.maxY - 416, 0.78),
    ]
    for (y, length) in lines {
        let originX = flipped ? rect.maxX - insetX - lineWidth * length : rect.minX + insetX
        fill(
            roundedPath(
                CGRect(x: originX, y: y, width: lineWidth * length, height: lineHeight),
                radius: lineHeight / 2
            ),
            color: NSColor(hex: 0x1677d2, alpha: 0.48),
            in: context
        )
    }

    let changeRect = CGRect(
        x: rect.minX + 34,
        y: rect.minY + 166,
        width: rect.width - 68,
        height: 82
    )
    fill(roundedPath(changeRect, radius: 28), color: accent.withAlphaComponent(0.45), in: context)
    fill(
        roundedPath(
            CGRect(x: changeRect.minX + 22, y: changeRect.midY - 8, width: changeRect.width * 0.62, height: 16),
            radius: 8
        ),
        color: NSColor.white.withAlphaComponent(0.7),
        in: context
    )

    let gloss = CGMutablePath()
    gloss.move(to: CGPoint(x: rect.minX + 28, y: rect.maxY - 88))
    gloss.addCurve(
        to: CGPoint(x: rect.maxX - 38, y: rect.maxY - 32),
        control1: CGPoint(x: rect.midX - 70, y: rect.maxY - 24),
        control2: CGPoint(x: rect.midX + 90, y: rect.maxY - 80)
    )
    stroke(gloss, color: NSColor.white.withAlphaComponent(0.46), width: 12, in: context)
}

private func drawTransferArrow(in context: CGContext) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 397, y: 470))
    path.addLine(to: CGPoint(x: 552, y: 470))
    path.addLine(to: CGPoint(x: 552, y: 420))
    path.addLine(to: CGPoint(x: 670, y: 512))
    path.addLine(to: CGPoint(x: 552, y: 604))
    path.addLine(to: CGPoint(x: 552, y: 554))
    path.addLine(to: CGPoint(x: 397, y: 554))
    path.closeSubpath()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -13),
        blur: 24,
        color: NSColor(hex: 0x8e2b00, alpha: 0.42).cgColor
    )
    gradient(
        path,
        colors: [NSColor(hex: 0xffc642), NSColor(hex: 0xff6b1a)],
        locations: [0, 1],
        start: CGPoint(x: 430, y: 580),
        end: CGPoint(x: 640, y: 435),
        in: context
    )
    context.restoreGState()
    stroke(path, color: NSColor.white.withAlphaComponent(0.56), width: 7, in: context)

    let shine = roundedPath(CGRect(x: 426, y: 524, width: 142, height: 12), radius: 6)
    fill(shine, color: NSColor.white.withAlphaComponent(0.42), in: context)
}

private func renderIcon(size: Int, destination: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    let scale = CGFloat(size) / canvasSize
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tileRect = CGRect(x: 72, y: 82, width: 880, height: 880)
    let tile = roundedPath(tileRect, radius: 210)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -34),
        blur: 52,
        color: NSColor.black.withAlphaComponent(0.28).cgColor
    )
    gradient(
        tile,
        colors: [
            NSColor(hex: 0x8edcff),
            NSColor(hex: 0x1688e8),
            NSColor(hex: 0x1643a6),
        ],
        locations: [0, 0.48, 1],
        start: CGPoint(x: tileRect.midX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.midX, y: tileRect.minY),
        in: context
    )
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let bloom = CGPath(ellipseIn: CGRect(x: 118, y: 540, width: 790, height: 500), transform: nil)
    gradient(
        bloom,
        colors: [NSColor.white.withAlphaComponent(0.32), NSColor.white.withAlphaComponent(0)],
        locations: [0, 1],
        start: CGPoint(x: 510, y: 970),
        end: CGPoint(x: 510, y: 560),
        in: context
    )
    context.restoreGState()
    stroke(tile, color: NSColor.white.withAlphaComponent(0.52), width: 10, in: context)

    drawDocument(
        rect: CGRect(x: 174, y: 230, width: 310, height: 584),
        flipped: false,
        accent: NSColor(hex: 0xffa21a),
        in: context
    )
    drawDocument(
        rect: CGRect(x: 540, y: 262, width: 310, height: 584),
        flipped: true,
        accent: NSColor(hex: 0x23d5c2),
        in: context
    )
    drawTransferArrow(in: context)

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: destination, options: .atomic)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <iconset-directory>\n".utf8))
    exit(2)
}

let iconset = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in outputs {
    try renderIcon(size: size, destination: iconset.appending(path: name))
}
