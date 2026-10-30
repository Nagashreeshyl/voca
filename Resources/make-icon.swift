// Renders the Voca app icon. Usage: swift Resources/make-icon.swift <out.png> (1024×1024)
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Standard macOS icon grid: 824pt squircle centered on a 1024 canvas.
let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

// Background: deep indigo → violet with a cyan glow.
shape.addClip()
NSGradient(colors: [
    NSColor(srgbRed: 0.07, green: 0.06, blue: 0.22, alpha: 1),
    NSColor(srgbRed: 0.29, green: 0.20, blue: 0.85, alpha: 1),
    NSColor(srgbRed: 0.62, green: 0.28, blue: 0.95, alpha: 1),
])!.draw(in: rect, angle: -55)
NSGradient(colors: [NSColor(srgbRed: 0.20, green: 0.85, blue: 1, alpha: 0.55), .clear])!
    .draw(fromCenter: CGPoint(x: 300, y: 300), radius: 0, toCenter: CGPoint(x: 300, y: 300), radius: 520, options: [])

// Waveform bars.
let heights: [CGFloat] = [0.26, 0.5, 0.78, 1.0, 0.7, 0.44, 0.24]
let barW: CGFloat = 58, gap: CGFloat = 30, maxH: CGFloat = 470
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor(srgbRed: 0.1, green: 0.05, blue: 0.4, alpha: 0.6).cgColor)
for (i, h) in heights.enumerated() {
    let x = (size - totalW) / 2 + CGFloat(i) * (barW + gap)
    let bh = maxH * h
    let bar = NSBezierPath(roundedRect: CGRect(x: x, y: size / 2 - bh / 2, width: barW, height: bh), xRadius: barW / 2, yRadius: barW / 2)
    NSGradient(colors: [.white, NSColor(srgbRed: 0.85, green: 0.92, blue: 1, alpha: 1)])!.draw(in: bar, angle: -90)
}
ctx.restoreGState()

// Glass sheen on the top half and a thin rim light.
NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0.26), 0), (NSColor.white.withAlphaComponent(0), 0.55))!
    .draw(in: shape, angle: -90)
NSColor.white.withAlphaComponent(0.35).setStroke()
let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
rim.lineWidth = 4
rim.stroke()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
