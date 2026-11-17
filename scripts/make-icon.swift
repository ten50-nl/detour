import AppKit

let args = CommandLine.arguments
let out = args[1]
let dark = !(args.count > 2 && args[2] == "light")
let size: CGFloat = 1024

func squircle(in rect: CGRect, exponent n: CGFloat = 4.2) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(in: body)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(dark ? 0.45 : 0.28).cgColor)
(dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white).setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
let bg = dark
    ? NSGradient(starting: NSColor(white: 0.26, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!
    : NSGradient(starting: NSColor(white: 1.0, alpha: 1), ending: NSColor(white: 0.86, alpha: 1))!
bg.draw(in: body, angle: -90)
let sheen = NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.10 : 0.0), ending: NSColor.white.withAlphaComponent(0))!
sheen.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

let edge = squircle(in: body.insetBy(dx: 1.5, dy: 1.5))
edge.lineWidth = 3
(dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)).setStroke()
edge.stroke()

let ink = dark ? NSColor(white: 0.97, alpha: 1) : NSColor(white: 0.10, alpha: 1)
let width: CGFloat = 50
let fork = NSPoint(x: 452, y: 470)
let start = NSPoint(x: 452, y: 262)

struct Branch { let end: NSPoint; let c1: NSPoint; let c2: NSPoint }
let branches = [
    Branch(end: NSPoint(x: 452, y: 768), c1: fork, c2: NSPoint(x: 452, y: 700)),
    Branch(end: NSPoint(x: 660, y: 716), c1: NSPoint(x: 452, y: 590), c2: NSPoint(x: 560, y: 616)),
]

func stroke(_ path: NSBezierPath) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    ink.setStroke()
    path.stroke()
}

let stem = NSBezierPath()
stem.move(to: start)
stem.line(to: fork)
stroke(stem)

for b in branches {
    let p = NSBezierPath()
    p.move(to: fork)
    p.curve(to: b.end, controlPoint1: b.c1, controlPoint2: b.c2)
    stroke(p)
    let dx = b.end.x - b.c2.x, dy = b.end.y - b.c2.y
    let len = max(hypot(dx, dy), 0.001)
    let ux = dx / len, uy = dy / len
    let head: CGFloat = 70
    let spread: CGFloat = 0.72
    let left = NSPoint(x: b.end.x - head * (ux * cos(spread) - uy * sin(spread)), y: b.end.y - head * (uy * cos(spread) + ux * sin(spread)))
    let right = NSPoint(x: b.end.x - head * (ux * cos(spread) + uy * sin(spread)), y: b.end.y - head * (uy * cos(spread) - ux * sin(spread)))
    let arrow = NSBezierPath()
    arrow.move(to: left)
    arrow.line(to: b.end)
    arrow.line(to: right)
    stroke(arrow)
}

let r: CGFloat = 40
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
