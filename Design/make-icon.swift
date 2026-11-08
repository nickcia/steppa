// Draws the app icon: a running track (a stadium-shaped ring with six lanes and a finish line) as a glossy,
// dark glass object on black, with a bright highlight and an iridescent sheen sliding round its lower edge.
// Original artwork, shaded pixel by pixel as a rounded 3D ring lit from the top left.
// Regenerate with:  swift Design/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import Foundation

let size = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

// MARK: Geometry (image coordinates: y grows downwards)

let cx = 512.0, cy = 512.0
/// Half the length of the straights, measured along the centre line of the track.
let straight = 170.0
/// Distance from the straights' axis to the middle of the track, and the track's width.
let centreRadius = 188.0
let width = 168.0
let half = width / 2
let lanes = 6

/// Closest point on the straights' axis, so distance from it is distance from the track's centre line.
func axisPoint(_ x: Double) -> Double { min(max(x, cx - straight), cx + straight) }

// MARK: Shading helpers

func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(v, lo), hi) }
func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
func mix(_ a: [Double], _ b: [Double], _ t: Double) -> [Double] { zip(a, b).map { $0 + ($1 - $0) * t } }
func add(_ a: [Double], _ b: [Double], _ k: Double) -> [Double] { zip(a, b).map { $0 + $1 * k } }

/// Smooth iridescent colours, cycling cyan → violet → pink → amber → cyan.
func iridescent(_ phase: Double) -> [Double] {
    let stops: [[Double]] = [[0.35, 0.85, 1.0], [0.55, 0.45, 1.0], [1.0, 0.42, 0.75], [1.0, 0.72, 0.38], [0.35, 0.85, 1.0]]
    let p = (phase - floor(phase)) * Double(stops.count - 1)
    let i = Int(p)
    return mix(stops[i], stops[i + 1], smoothstep(0, 1, p - Double(i)))
}

// Light from the top left, slightly in front; the viewer looks straight down.
let light: (Double, Double, Double) = {
    let (x, y, z) = (-0.55, -0.65, 0.55)
    let n = (x * x + y * y + z * z).squareRoot()
    return (x / n, y / n, z / n)
}()
let halfVector: (Double, Double, Double) = {
    let (x, y, z) = (light.0, light.1, light.2 + 1)
    let n = (x * x + y * y + z * z).squareRoot()
    return (x / n, y / n, z / n)
}()

// MARK: Render (2×2 supersampling for smooth edges)

var pixels = [UInt8](repeating: 0, count: size * size * 4)

func shade(_ x: Double, _ y: Double) -> [Double] {
    let ax = axisPoint(x)
    let dx = x - ax, dy = y - cy
    let d = (dx * dx + dy * dy).squareRoot()
    let ox = d > 0 ? dx / d : 0, oy = d > 0 ? dy / d : -1   // outward direction in the plane
    let t = (d - centreRadius) / half                          // -1 inner edge … +1 outer edge

    // Background: black, with a soft glow of the sheen thrown onto it just outside the track.
    let gap = abs(t) - 1
    var background: [Double] = [0, 0, 0]
    if gap > 0 {
        let falloff = exp(-gap * half / 26)
        let lower = smoothstep(-0.2, 0.9, oy)                  // brighter under the track
        let glow = iridescent(atan2(dy, dx) / (2 * .pi) + 0.2 + 1)
        background = add(background, glow, falloff * (0.05 + 0.24 * lower))
        background = add(background, [1, 1, 1], falloff * 0.05)
    }
    guard abs(t) <= 1 else { return background }

    // The ring's surface: a flattened tube, nearly flat across the lanes, rounding off steeply at the edges.
    let u = t
    let height = pow(max(1 - pow(abs(u), 3), 0), 1.0 / 3)       // superellipse cross-section
    let slope = height > 0.0001 ? pow(abs(u), 2) / pow(height, 2) * (u < 0 ? -1 : 1) : (u < 0 ? -40 : 40)
    var nx = ox * slope * 0.9, ny = oy * slope * 0.9, nz = 1.0
    let nl = (nx * nx + ny * ny + nz * nz).squareRoot()
    nx /= nl; ny /= nl; nz /= nl

    let diffuse = max(0, nx * light.0 + ny * light.1 + nz * light.2)
    let spec = pow(max(0, nx * halfVector.0 + ny * halfVector.1 + nz * halfVector.2), 60)
    let broadSpec = pow(max(0, nx * halfVector.0 + ny * halfVector.1 + nz * halfVector.2), 8)
    let fresnel = pow(1 - nz, 2.2)

    // Dark smoky glass: deep grey body, lighter towards the top of the image.
    let vertical = clamp((y - (cy - centreRadius - half)) / ((centreRadius + half) * 2))
    var color = mix([0.075, 0.075, 0.085], [0.012, 0.012, 0.016], vertical)
    color = add(color, [1, 1, 1], diffuse * 0.035)
    // A soft cloudy reflection across the upper surfaces, like the sky in a polished sphere.
    let upward = smoothstep(-0.1, -0.75, ny)
    color = add(color, [0.82, 0.84, 0.9], upward * 0.22 + pow(max(0, -ny), 3) * 0.18)

    // Iridescent sheen on the edges facing down and right, sliding round the track like light inside glass.
    let angle = atan2(dy, dx) / (2 * .pi)
    let facingAway = smoothstep(-0.35, 0.7, nx * 0.45 + ny * 0.9)
    let sheen = iridescent(angle + u * 0.3 + 0.2)
    let sheenStrength = facingAway * (pow(1 - nz, 1.2) * 1.25 + 0.05)
    color = add(color, sheen, sheenStrength)

    // Cool grey rim on the lit side, then the highlights.
    color = add(color, [0.85, 0.88, 0.95], fresnel * (1 - facingAway) * 0.55)
    color = add(color, [1, 1, 1], broadSpec * 0.10 + spec * 0.95)

    // Lanes and the finish line, etched on the top surface; they fade as the surface rounds away.
    let flatness = smoothstep(0.55, 0.95, nz)
    let laneWidth = 2.0 / Double(lanes)
    var mark = 0.0
    for lane in 1..<lanes {
        let lineT = -1 + laneWidth * Double(lane)
        let distance = abs(u - lineT) * half                     // in pixels
        mark = max(mark, 1 - smoothstep(0.6, 1.6, distance))
    }
    let finishX = cx + 95
    if y > cy, abs(x - finishX) < 4.5 { mark = max(mark, 1 - smoothstep(3.0, 4.5, abs(x - finishX))) }
    let lineBrightness = 0.22 + 0.30 * (1 - vertical)
    color = mix(color, [1, 1, 1], mark * flatness * lineBrightness)

    // Soft edge where the ring meets the background.
    let edge = smoothstep(1.0, 1.0 - 1.2 / half, abs(t))
    return mix(background, color, edge)
}

for py in 0..<size {
    for px in 0..<size {
        var sum: [Double] = [0, 0, 0]
        for (sx, sy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
            sum = add(sum, shade(Double(px) + sx, Double(py) + sy), 0.25)
        }
        let i = (py * size + px) * 4
        for c in 0..<3 {
            // Gentle tone curve so highlights roll off instead of clipping.
            let v = 1 - exp(-sum[c] * 1.35)
            pixels[i + c] = UInt8(clamp(v / (1 - exp(-1.35))) * 255)
        }
        pixels[i + 3] = 255
    }
}

// MARK: Write (opaque, as the App Store requires)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: size * 4, bitsPerPixel: 32)!
pixels.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, size * size * 4) }
let cg = rep.cgImage!.copy(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
