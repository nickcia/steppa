// Draws the app icon: a running track (a stadium-shaped oval) in frosted glass on black. Original artwork;
// the glass look (translucent fill, bright rim, soft specular highlight, faint lanes and glow) is drawn here.
// Regenerate with:  swift Design/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreImage

let size = 1024.0
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: space])

func layer(_ draw: (CGContext) -> Void) -> CIImage {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return CIImage(cgImage: ctx.makeImage()!)
}

func blurred(_ image: CIImage, _ radius: Double) -> CIImage {
    image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: image.extent)
}

func white(_ alpha: Double) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }

// The track: an outer stadium and an inner one; the ring between them is the glass.
let center = CGPoint(x: size / 2, y: size / 2)
let outer = CGRect(x: center.x - 390, y: center.y - 245, width: 780, height: 490)
let thickness = 128.0
let inner = outer.insetBy(dx: thickness, dy: thickness)
func stadium(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
}
let ring: CGPath = {
    let path = CGMutablePath()
    path.addPath(stadium(outer))
    path.addPath(stadium(inner))
    return path
}()
func clipToRing(_ ctx: CGContext) {
    ctx.addPath(ring)
    ctx.clip(using: .evenOdd)
}

// 1. Background: black with the faintest lift in the middle, so the glass has something to sit in.
let background = layer { ctx in
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let lift = CGGradient(colorsSpace: space, colors: [white(0.07), white(0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(lift, startCenter: center, startRadius: 0, endCenter: center, endRadius: 560, options: [])
}

// 2. Glow: the ring's shape, blurred, very dim, as if light passes through the glass onto the surface.
let glow = blurred(layer { ctx in
    ctx.addPath(ring)
    ctx.setFillColor(CGColor(srgbRed: 0.62, green: 0.82, blue: 1, alpha: 0.35))
    ctx.fillPath(using: .evenOdd)
}, 38)

// 3. Glass body: translucent, lighter at the top, with a cool tint.
let body = layer { ctx in
    clipToRing(ctx)
    let fill = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.86, green: 0.93, blue: 1, alpha: 0.34),
        CGColor(srgbRed: 0.55, green: 0.70, blue: 0.88, alpha: 0.14),
        CGColor(srgbRed: 0.75, green: 0.86, blue: 1, alpha: 0.22),
    ] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: outer.maxY), end: CGPoint(x: 0, y: outer.minY), options: [])
    // Lanes: two faint lines following the track.
    ctx.setStrokeColor(white(0.16))
    ctx.setLineWidth(3)
    for inset in [thickness / 3, thickness * 2 / 3] {
        ctx.addPath(stadium(outer.insetBy(dx: inset, dy: inset)))
        ctx.strokePath()
    }
}

// 4. Inner shading: darker just inside both edges, which reads as thickness.
let shading = blurred(layer { ctx in
    clipToRing(ctx)
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.45))
    ctx.setLineWidth(22)
    ctx.addPath(stadium(outer))
    ctx.addPath(stadium(inner))
    ctx.strokePath()
}, 10)
let ringMask = layer { ctx in clipToRing(ctx); ctx.setFillColor(white(1)); ctx.fill(outer) }
let shadingClipped = shading.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: ringMask])

// 5. Rim: a bright edge on both sides, strongest at the top left where the light comes from.
let rim = layer { ctx in
    let light = CGGradient(colorsSpace: space, colors: [white(0.95), white(0.25), white(0.55)] as CFArray,
                           locations: [0, 0.55, 1])!
    for (path, width) in [(stadium(outer), 5.0), (stadium(inner), 3.5)] {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(width)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(light, start: CGPoint(x: outer.minX, y: outer.maxY),
                               end: CGPoint(x: outer.maxX, y: outer.minY), options: [])
        ctx.restoreGState()
    }
}

// 6. Specular highlights: soft elongated glints along the top-left curve and the bottom right, kept inside the glass.
func glint(_ ctx: CGContext, at point: CGPoint, width: Double, height: Double, alpha: Double) {
    ctx.saveGState()
    ctx.translateBy(x: point.x, y: point.y)
    ctx.scaleBy(x: width / height, y: 1)
    let gradient = CGGradient(colorsSpace: space, colors: [white(alpha), white(0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: height / 2,
                           options: [])
    ctx.restoreGState()
}
let specular = layer { ctx in
    clipToRing(ctx)
    glint(ctx, at: CGPoint(x: outer.minX + 210, y: outer.maxY - 62), width: 420, height: 120, alpha: 0.7)
    glint(ctx, at: CGPoint(x: outer.minX + 70, y: center.y + 60), width: 90, height: 260, alpha: 0.3)
    glint(ctx, at: CGPoint(x: outer.maxX - 180, y: outer.minY + 55), width: 260, height: 70, alpha: 0.3)
}

// Compose bottom to top.
var image = background
for top in [glow, body, shadingClipped, specular, rim] {
    image = top.composited(over: image)
}
let cg = ciContext.createCGImage(image, from: CGRect(x: 0, y: 0, width: size, height: size), format: .RGBA8,
                                 colorSpace: space)!
// App Store icons must be opaque: flatten onto black.
let flat = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                     space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.setFillColor(CGColor(gray: 0, alpha: 1))
flat.fill(CGRect(x: 0, y: 0, width: size, height: size))
flat.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
let rep = NSBitmapImageRep(cgImage: flat.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
