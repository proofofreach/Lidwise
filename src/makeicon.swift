// Renders the Closed-Lid Awake app icon with Core Graphics.
// Apple-style superellipse body, warm amber glow, coffee cup on a closed laptop.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r/255), CGFloat(g/255), CGFloat(b/255), CGFloat(a)])!
}

// Apple's icon shape is a superellipse, not a rounded rect.
func superellipse(_ rect: CGRect, n: Double = 5.0) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * Double.pi
        let ct = cos(t), st = sin(t)
        let x = pow(abs(ct), 2.0/n) * (ct < 0 ? -1 : 1) * Double(a)
        let y = pow(abs(st), 2.0/n) * (st < 0 ? -1 : 1) * Double(b)
        let pt = CGPoint(x: cx + CGFloat(x), y: cy + CGFloat(y))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: cs,
               colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { CGFloat($0.0) })!
}

let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// ── icon body ────────────────────────────────────────────────────────────────
let inset: CGFloat = 76
let body = CGRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let shape = superellipse(body)

// drop shadow beneath the body
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 42, color: rgb(0, 0, 0, 0.55))
ctx.addPath(shape); ctx.setFillColor(rgb(18, 11, 7)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// base: deep espresso, lit from just above the cup
ctx.drawRadialGradient(gradient([(0.0, rgb(74, 42, 22)), (0.55, rgb(38, 22, 13)), (1.0, rgb(15, 9, 6))]),
                       startCenter: CGPoint(x: S/2, y: S*0.56), startRadius: 0,
                       endCenter: CGPoint(x: S/2, y: S*0.56), endRadius: S*0.62,
                       options: [.drawsAfterEndLocation])

// warm glow behind the cup
ctx.drawRadialGradient(gradient([(0.0, rgb(255, 157, 46, 0.55)), (0.45, rgb(255, 140, 40, 0.16)), (1.0, rgb(255, 140, 40, 0))]),
                       startCenter: CGPoint(x: S/2, y: S*0.53), startRadius: 0,
                       endCenter: CGPoint(x: S/2, y: S*0.53), endRadius: S*0.40,
                       options: [])

// ── steam ────────────────────────────────────────────────────────────────────
func steam(x: CGFloat, yTop: CGFloat, yBot: CGFloat, amp: CGFloat, width: CGFloat, alpha: Double) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x, y: yBot))
    let h = (yBot - yTop) / 2
    p.addCurve(to: CGPoint(x: x, y: yBot - h),
               control1: CGPoint(x: x - amp, y: yBot - h*0.35),
               control2: CGPoint(x: x + amp, y: yBot - h*0.65))
    p.addCurve(to: CGPoint(x: x, y: yTop),
               control1: CGPoint(x: x - amp, y: yBot - h*1.35),
               control2: CGPoint(x: x + amp, y: yBot - h*1.65))
    ctx.saveGState()
    ctx.addPath(p)
    ctx.setStrokeColor(rgb(255, 190, 120, alpha))
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
}
steam(x: 452, yTop: 800, yBot: 640, amp: 46, width: 26, alpha: 0.50)
steam(x: 566, yTop: 838, yBot: 640, amp: 52, width: 28, alpha: 0.72)
steam(x: 672, yTop: 792, yBot: 648, amp: 42, width: 24, alpha: 0.40)

// ── closed laptop slab ───────────────────────────────────────────────────────
let slab = CGRect(x: 214, y: 250, width: 596, height: 78)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0, 0, 0, 0.6))
ctx.addPath(CGPath(roundedRect: slab, cornerWidth: 24, cornerHeight: 24, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient([(0.0, rgb(58, 58, 64)), (0.5, rgb(96, 98, 106)), (1.0, rgb(38, 38, 43))]),
                       start: CGPoint(x: 0, y: slab.maxY), end: CGPoint(x: 0, y: slab.minY), options: [])
ctx.restoreGState()
// lid seam + front notch
ctx.setFillColor(rgb(150, 152, 160, 0.55))
ctx.fill(CGRect(x: slab.minX + 26, y: slab.maxY - 5, width: slab.width - 52, height: 4))
ctx.setFillColor(rgb(20, 20, 24, 0.85))
ctx.addPath(CGPath(roundedRect: CGRect(x: S/2 - 62, y: slab.minY + 6, width: 124, height: 14),
                   cornerWidth: 7, cornerHeight: 7, transform: nil))
ctx.fillPath()

// ── cup ──────────────────────────────────────────────────────────────────────
// handle first, so the body overlaps it cleanly
ctx.saveGState()
ctx.addArc(center: CGPoint(x: 686, y: 476), radius: 96, startAngle: -1.15, endAngle: 1.15, clockwise: false)
ctx.setStrokeColor(rgb(243, 152, 32))
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.strokePath()
ctx.restoreGState()

// tapered body
let cup = CGMutablePath()
cup.move(to: CGPoint(x: 306, y: 578))
cup.addLine(to: CGPoint(x: 682, y: 578))
cup.addCurve(to: CGPoint(x: 596, y: 336),
             control1: CGPoint(x: 678, y: 486), control2: CGPoint(x: 664, y: 372))
cup.addCurve(to: CGPoint(x: 392, y: 336),
             control1: CGPoint(x: 560, y: 318), control2: CGPoint(x: 428, y: 318))
cup.addCurve(to: CGPoint(x: 306, y: 578),
             control1: CGPoint(x: 324, y: 372), control2: CGPoint(x: 310, y: 486))
cup.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: rgb(90, 40, 0, 0.55))
ctx.addPath(cup); ctx.clip()
ctx.drawLinearGradient(gradient([(0.0, rgb(214, 118, 18)), (0.45, rgb(249, 168, 45)), (1.0, rgb(255, 214, 138))]),
                       start: CGPoint(x: 300, y: 336), end: CGPoint(x: 640, y: 590), options: [])
// soft sheen down the left face
ctx.drawLinearGradient(gradient([(0.0, rgb(255, 255, 255, 0.30)), (0.35, rgb(255, 255, 255, 0.0))]),
                       start: CGPoint(x: 330, y: 560), end: CGPoint(x: 520, y: 460), options: [])
ctx.restoreGState()

// rim
ctx.saveGState()
let rim = CGRect(x: 286, y: 546, width: 416, height: 74)
ctx.addPath(CGPath(ellipseIn: rim, transform: nil)); ctx.clip()
ctx.drawLinearGradient(gradient([(0.0, rgb(255, 196, 106)), (1.0, rgb(255, 236, 199))]),
                       start: CGPoint(x: 0, y: rim.minY), end: CGPoint(x: 0, y: rim.maxY), options: [])
ctx.restoreGState()
// coffee surface
ctx.setFillColor(rgb(74, 36, 12))
ctx.addPath(CGPath(ellipseIn: rim.insetBy(dx: 30, dy: 13), transform: nil))
ctx.fillPath()
ctx.setFillColor(rgb(120, 62, 22, 0.6))
ctx.addPath(CGPath(ellipseIn: CGRect(x: 340, y: 570, width: 150, height: 24), transform: nil))
ctx.fillPath()

// ── glass top highlight + inner border ───────────────────────────────────────
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
ctx.drawLinearGradient(gradient([(0.0, rgb(255, 255, 255, 0.13)), (0.28, rgb(255, 255, 255, 0.0))]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
ctx.restoreGState()

ctx.restoreGState() // end body clip

ctx.addPath(shape)
ctx.setStrokeColor(rgb(255, 205, 150, 0.16))
ctx.setLineWidth(3)
ctx.strokePath()

// ── write out ────────────────────────────────────────────────────────────────
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
