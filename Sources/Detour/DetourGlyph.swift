import AppKit

enum DetourGlyph {
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect, lineWidth: 1.8)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Detour"
        return image
    }

    static func draw(in rect: NSRect, lineWidth: CGFloat) {
        let box = NSRect(x: 395, y: 215, width: 320, height: 590)
        let scale = min(rect.width / box.width, rect.height / box.height) * 0.92
        let dx = rect.midX - box.midX * scale
        let dy = rect.midY - box.midY * scale
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale + dx, y: y * scale + dy) }

        NSColor.black.setStroke()
        NSColor.black.setFill()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: p(452, 262))
        path.line(to: p(452, 768))
        path.move(to: p(452, 470))
        path.curve(to: p(660, 716), controlPoint1: p(452, 590), controlPoint2: p(560, 616))
        arrowHead(path, tip: p(452, 768), from: p(452, 700), length: 70 * scale)
        arrowHead(path, tip: p(660, 716), from: p(560, 616), length: 70 * scale)
        path.stroke()
        let r = max(40 * scale, lineWidth * 1.1)
        let start = p(452, 262)
        NSBezierPath(ovalIn: NSRect(x: start.x - r, y: start.y - r, width: r * 2, height: r * 2)).fill()
    }

    private static func arrowHead(_ path: NSBezierPath, tip: NSPoint, from: NSPoint, length: CGFloat) {
        let dx = tip.x - from.x, dy = tip.y - from.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len
        let spread: CGFloat = 0.72
        let left = NSPoint(x: tip.x - length * (ux * cos(spread) - uy * sin(spread)), y: tip.y - length * (uy * cos(spread) + ux * sin(spread)))
        let right = NSPoint(x: tip.x - length * (ux * cos(spread) + uy * sin(spread)), y: tip.y - length * (uy * cos(spread) - ux * sin(spread)))
        path.move(to: left)
        path.line(to: tip)
        path.line(to: right)
    }
}
