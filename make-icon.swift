import AppKit
import CoreGraphics

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// Rounded square (squircle-ish)
let inset: CGFloat = 64
let rect = CGRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let radius: CGFloat = 190
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(60, 45, 25, 0.20))
ctx.addPath(path)
ctx.setFillColor(color(247, 245, 240))
ctx.fillPath()
ctx.restoreGState()

// Paper gradient inside
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(252, 250, 246), color(238, 232, 220)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
// Warm edge
ctx.addPath(path)
ctx.setStrokeColor(color(214, 204, 186))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// Content: three schedule lines
let left: CGFloat = 232
let widths: [CGFloat] = [368, 300, 240]
let ys: [CGFloat] = [618, 508, 398]
for (i, y) in ys.enumerated() {
    let line = CGRect(x: left, y: y, width: widths[i], height: 30)
    let lp = CGPath(roundedRect: line, cornerWidth: 15, cornerHeight: 15, transform: nil)
    ctx.addPath(lp)
    ctx.setFillColor(i == 1 ? color(160, 150, 134) : color(40, 40, 40))
    ctx.fillPath()
}

// Struck-through first line (warm brown)
ctx.saveGState()
ctx.setStrokeColor(color(138, 106, 58))
ctx.setLineWidth(12)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: left - 22, y: 618 + 34))
ctx.addLine(to: CGPoint(x: left + widths[0] + 22, y: 618 - 4))
ctx.strokePath()
ctx.restoreGState()

// Check mark, small, at the right end of the struck line
ctx.saveGState()
ctx.setStrokeColor(color(138, 106, 58))
ctx.setLineWidth(17)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 700, y: 620))
ctx.addLine(to: CGPoint(x: 730, y: 590))
ctx.addLine(to: CGPoint(x: 786, y: 668))
ctx.strokePath()
ctx.restoreGState()

// Time column ticks
for y in ys {
    let dot = CGRect(x: 150, y: y + 2, width: 26, height: 26)
    ctx.addEllipse(in: dot)
    ctx.setFillColor(color(138, 106, 58, 0.9))
    ctx.fillPath()
}

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
