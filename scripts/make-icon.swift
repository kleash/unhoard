// Draws Tidyroll's app icon: a deep violet-to-magenta backdrop with soft colour glows, two frosted glass cards fanned
// like the swipe stack, and a bold four-point sparkle on the front card. 1024 × 1024, opaque (iOS rounds the corners).
// Usage: swift scripts/make-icon.swift Tidyroll/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else { fputs("usage: swift scripts/make-icon.swift <out.png>\n", stderr); exit(2) }
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let size = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Backdrop: deep indigo (bottom left) to magenta (top right), y up, then soft glows like the app's mesh gradient.
let base = CGGradient(colorsSpace: sRGB, colors: [color(18, 14, 60), color(70, 30, 140), color(196, 50, 140)] as CFArray,
                      locations: [0, 0.55, 1])!
cg.drawLinearGradient(base, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
for (x, y, r, c) in [(180.0, 860.0, 520.0, color(40, 200, 255, 0.55)), (900.0, 160.0, 480.0, color(255, 140, 60, 0.45)),
                     (520.0, 520.0, 420.0, color(150, 90, 255, 0.35))] {
    let glow = CGGradient(colorsSpace: sRGB, colors: [c, color(0, 0, 0, 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}

// Two glass cards, back to front: a translucent white fill, a bright top-left rim and a soft shadow.
let card = CGRect(x: -230, y: -290, width: 460, height: 580)
for (angle, dx, fill) in [(-13.0, -40.0, 0.16), (7.0, 30.0, 0.26)] {
    cg.saveGState()
    cg.translateBy(x: 512 + dx, y: 500)
    cg.rotate(by: angle * .pi / 180)
    let path = CGPath(roundedRect: card, cornerWidth: 80, cornerHeight: 80, transform: nil)
    cg.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: color(10, 0, 40, 0.5))
    cg.addPath(path)
    cg.setFillColor(color(255, 255, 255, fill))
    cg.fillPath()
    cg.setShadow(offset: .zero, blur: 0, color: nil)
    // The glass sheen: a highlight fading from the top left.
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let sheen = CGGradient(colorsSpace: sRGB, colors: [color(255, 255, 255, 0.35), color(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: -230, y: 290), end: CGPoint(x: 120, y: -100), options: [])
    cg.restoreGState()
    cg.addPath(path)
    cg.setStrokeColor(color(255, 255, 255, 0.55))
    cg.setLineWidth(6)
    cg.strokePath()
    cg.restoreGState()
}

// The sparkle: a four-point star with concave sides, white to warm yellow, and a small companion star.
func sparkle(at c: CGPoint, radius r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let pinch = r * 0.16
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
    return p
}
let star = CGGradient(colorsSpace: sRGB, colors: [color(255, 255, 255), color(255, 220, 120)] as CFArray, locations: [0, 1])!
for (center, radius) in [(CGPoint(x: 545, y: 505), 215.0), (CGPoint(x: 700, y: 690), 70.0)] {
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 50, color: color(255, 230, 160, 0.8))
    cg.addPath(sparkle(at: center, radius: radius))
    cg.setFillColor(color(255, 255, 255))
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(sparkle(at: center, radius: radius))
    cg.clip()
    cg.drawLinearGradient(star, start: CGPoint(x: center.x, y: center.y + radius), end: CGPoint(x: center.x, y: center.y - radius), options: [])
    cg.restoreGState()
}

let image = cg.makeImage()!
guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fputs("couldn't write \(output.path)\n", stderr); exit(1) }
