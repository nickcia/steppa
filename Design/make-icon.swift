// Draws the app icon: a three-step staircase (a plan that builds) with the goal resting on the top step.
// Original artwork; regenerate with:  swift Design/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size = 1024.0
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Background: deep teal diagonal gradient (opaque, as App Store icons must be).
let gradient = CGGradient(colorsSpace: space, colors: [color(0x16A99E), color(0x0B4F63)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// A staircase of three steps (a plan that builds week by week), softened with round joins.
let stepWidth = 200.0, rise = 150.0, base = 230.0, left = 162.0, first = 170.0
let path = CGMutablePath()
path.move(to: CGPoint(x: left, y: base))
path.addLine(to: CGPoint(x: left, y: base + first))
for step in 0..<3 {
    let x = left + Double(step) * stepWidth
    let y = base + first + Double(step) * rise
    path.addLine(to: CGPoint(x: x + stepWidth, y: y))
    if step < 2 { path.addLine(to: CGPoint(x: x + stepWidth, y: y + rise)) }
}
path.addLine(to: CGPoint(x: left + 3 * stepWidth, y: base))
path.closeSubpath()
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.setLineWidth(56)
ctx.setLineJoin(.round)
ctx.addPath(path)
ctx.drawPath(using: .fillStroke)

// The goal, resting on the top step, in the app's warm accent.
let dotSize = 150.0
let topY = base + first + 2 * rise + 28
ctx.setFillColor(color(0xFF7A59))
ctx.fillEllipse(in: CGRect(x: left + 2 * stepWidth + (stepWidth - dotSize) / 2, y: topY + 34, width: dotSize, height: dotSize))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
