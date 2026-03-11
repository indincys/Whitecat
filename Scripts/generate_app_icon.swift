#!/usr/bin/env swift

import AppKit
import Foundation

enum IconGenerationError: Error {
    case bitmapCreationFailed
    case pngEncodingFailed
    case commandFailed(String)
}

let scriptURL = URL(fileURLWithPath: #filePath)
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let assetsURL = rootURL.appendingPathComponent("Assets/AppIcon", isDirectory: true)
let pngURL = assetsURL.appendingPathComponent("Whitecat-1024.png")
let iconsetURL = assetsURL.appendingPathComponent("Whitecat.iconset", isDirectory: true)
let icnsURL = assetsURL.appendingPathComponent("Whitecat.icns")

let canvasSize = CGFloat(1024)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize),
    pixelsHigh: Int(canvasSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)

guard let bitmap else {
    throw IconGenerationError.bitmapCreationFailed
}

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ path: NSBezierPath, gradient: NSGradient, angle: CGFloat) {
    gradient.draw(in: path, angle: angle)
}

func gradient(_ stops: [(NSColor, CGFloat)]) -> NSGradient {
    let colors = stops.map(\.0)
    var locations = stops.map(\.1)
    return locations.withUnsafeMutableBufferPointer { buffer in
        NSGradient(colors: colors, atLocations: buffer.baseAddress, colorSpace: .deviceRGB)!
    }
}

func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardError = pipe
    process.standardOutput = pipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw IconGenerationError.commandFailed(output.isEmpty ? "\(launchPath) failed" : output)
    }
}

try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetURL)
try? FileManager.default.removeItem(at: icnsURL)

let context = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context?.imageInterpolation = .high
context?.shouldAntialias = true

let canvasRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
NSColor.clear.setFill()
canvasRect.fill()

let tileRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let tilePath = roundedRect(tileRect, radius: 220)

let outerShadow = NSShadow()
outerShadow.shadowColor = color(0x062f1e, alpha: 0.22)
outerShadow.shadowBlurRadius = 64
outerShadow.shadowOffset = NSSize(width: 0, height: -26)
NSGraphicsContext.saveGraphicsState()
outerShadow.set()
color(0x0a5a39).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

let backgroundGradient = gradient([
    (color(0x7fe1a0), 0.0),
    (color(0x35a46e), 0.48),
    (color(0x0d5a39), 1.0)
])
fill(tilePath, gradient: backgroundGradient, angle: -48)

color(0xffffff, alpha: 0.12).setStroke()
tilePath.lineWidth = 2
tilePath.stroke()

NSGraphicsContext.saveGraphicsState()
tilePath.addClip()
let glowPath = NSBezierPath(ovalIn: NSRect(x: 118, y: 540, width: 680, height: 420))
let glowGradient = gradient([
    (color(0xffffff, alpha: 0.30), 0.0),
    (color(0xffffff, alpha: 0.10), 0.42),
    (color(0xffffff, alpha: 0.0), 1.0)
])
fill(glowPath, gradient: glowGradient, angle: 18)

let lowerShadePath = NSBezierPath(ovalIn: NSRect(x: 350, y: 80, width: 700, height: 360))
let lowerShadeGradient = gradient([
    (color(0x052416, alpha: 0.0), 0.0),
    (color(0x052416, alpha: 0.24), 1.0)
])
fill(lowerShadePath, gradient: lowerShadeGradient, angle: 0)
NSGraphicsContext.restoreGraphicsState()

let cardRect = NSRect(x: 284, y: 198, width: 456, height: 628)
let cardPath = roundedRect(cardRect, radius: 82)

let cardShadow = NSShadow()
cardShadow.shadowColor = color(0x083422, alpha: 0.20)
cardShadow.shadowBlurRadius = 34
cardShadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.saveGraphicsState()
cardShadow.set()
color(0xf8fff9).setFill()
cardPath.fill()
NSGraphicsContext.restoreGraphicsState()

let cardGradient = gradient([
    (color(0xffffff), 0.0),
    (color(0xf1fbf4), 1.0)
])
fill(cardPath, gradient: cardGradient, angle: -90)

color(0x0f6d46, alpha: 0.10).setStroke()
cardPath.lineWidth = 2
cardPath.stroke()

let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: cardRect.maxX - 128, y: cardRect.maxY))
foldPath.line(to: NSPoint(x: cardRect.maxX, y: cardRect.maxY))
foldPath.line(to: NSPoint(x: cardRect.maxX, y: cardRect.maxY - 128))
foldPath.close()

let foldGradient = gradient([
    (color(0xd7f8df), 0.0),
    (color(0x9dd9ae), 1.0)
])
fill(foldPath, gradient: foldGradient, angle: -45)

let foldEdge = NSBezierPath()
foldEdge.move(to: NSPoint(x: cardRect.maxX - 128, y: cardRect.maxY))
foldEdge.line(to: NSPoint(x: cardRect.maxX, y: cardRect.maxY - 128))
color(0x0d5a39, alpha: 0.14).setStroke()
foldEdge.lineWidth = 4
foldEdge.lineCapStyle = .round
foldEdge.stroke()

let railRect = NSRect(x: cardRect.minX + 54, y: cardRect.minY + 96, width: 72, height: cardRect.height - 192)
let railPath = roundedRect(railRect, radius: 36)
let railGradient = gradient([
    (color(0x63d28a), 0.0),
    (color(0x1f8c61), 1.0)
])
fill(railPath, gradient: railGradient, angle: -90)

let lineColor = color(0x15724b, alpha: 0.92)
let mutedLineColor = color(0x15724b, alpha: 0.52)

let line1 = roundedRect(NSRect(x: cardRect.minX + 164, y: cardRect.maxY - 176, width: 212, height: 36), radius: 18)
lineColor.setFill()
line1.fill()

let line2 = roundedRect(NSRect(x: cardRect.minX + 164, y: cardRect.maxY - 258, width: 258, height: 28), radius: 14)
mutedLineColor.setFill()
line2.fill()

let line3 = roundedRect(NSRect(x: cardRect.minX + 164, y: cardRect.maxY - 328, width: 214, height: 28), radius: 14)
mutedLineColor.setFill()
line3.fill()

let tagRect = NSRect(x: cardRect.minX + 164, y: cardRect.minY + 114, width: 176, height: 52)
let tagPath = roundedRect(tagRect, radius: 26)
let tagGradient = gradient([
    (color(0x4bc17c), 0.0),
    (color(0x188457), 1.0)
])
fill(tagPath, gradient: tagGradient, angle: 0)

let dotPath = NSBezierPath(ovalIn: NSRect(x: cardRect.maxX - 126, y: cardRect.minY + 108, width: 58, height: 58))
color(0xdaf7e2).setFill()
dotPath.fill()

let dotInner = NSBezierPath(ovalIn: NSRect(x: cardRect.maxX - 108, y: cardRect.minY + 126, width: 22, height: 22))
color(0x16774d).setFill()
dotInner.fill()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    throw IconGenerationError.pngEncodingFailed
}
try pngData.write(to: pngURL, options: .atomic)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconFiles {
    let targetURL = iconsetURL.appendingPathComponent(name)
    try run("/usr/bin/sips", ["-z", "\(size)", "\(size)", pngURL.path, "--out", targetURL.path])
}

try run("/usr/bin/iconutil", ["-c", "icns", iconsetURL.path, "-o", icnsURL.path])
try? FileManager.default.removeItem(at: iconsetURL)

print("Generated \(icnsURL.path)")
