import NotcherCore
import SwiftUI

struct SnakeView: View {
    let engine: SnakeEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            let cell = 20.0
            ctx.fit(CGSize(width: Double(SnakeEngine.columns) * cell, height: Double(SnakeEngine.rows) * cell), in: size)
            SnakeRenderer.draw(engine, in: ctx, cell: cell)
        }
    }
}

enum SnakeRenderer {
    static let head = Color(hex: 0xC6F76B)
    static let tail = Color(hex: 0x1FB58F)

    static func draw(_ e: SnakeEngine, in ctx: GraphicsContext, cell: Double) {
        let cols = SnakeEngine.columns, rows = SnakeEngine.rows
        let w = Double(cols) * cell, h = Double(rows) * cell
        let t = e.clock

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x08120E), Color(hex: 0x050807)], from: .zero, to: CGPoint(x: 0, y: h)))
        drawDotGrid(ctx, size: CGSize(width: w, height: h), spacing: cell, color: Color.white.opacity(0.05))

        // Closed-off border rings.
        let a = e.arena
        let arenaRect = CGRect(x: Double(a.minX) * cell, y: Double(a.minY) * cell,
                               width: Double(a.maxX - a.minX + 1) * cell, height: Double(a.maxY - a.minY + 1) * cell)
        if e.inset > 0 {
            var outside = Path(CGRect(x: 0, y: 0, width: w, height: h))
            outside.addRect(arenaRect)
            ctx.fill(outside, with: .color(Color.black.opacity(0.55)), style: FillStyle(eoFill: true))
            var hatch = Path()
            var x = -h
            while x < w {
                hatch.move(to: CGPoint(x: x, y: h))
                hatch.addLine(to: CGPoint(x: x + h, y: 0))
                x += 10
            }
            var clipped = ctx
            clipped.clip(to: outside, style: FillStyle(eoFill: true))
            clipped.stroke(hatch, with: .color(Color.white.opacity(0.04)), lineWidth: 1)
        }
        let warn = e.shrinkPending && sin(t * 14) > 0
        ctx.glow((warn ? Color(hex: 0xFF453A) : head).opacity(0.5), radius: 6) { layer in
            layer.stroke(Path(roundedRect: arenaRect.insetBy(dx: 1, dy: 1), cornerRadius: 6),
                         with: .color((warn ? Color(hex: 0xFF453A) : head).opacity(warn ? 0.9 : 0.25)), lineWidth: 1.5)
        }

        // Apple
        let pulse = 1 + 0.08 * sin(t * 6)
        let ap = CGPoint(x: (Double(e.apple.x) + 0.5) * cell, y: (Double(e.apple.y) + 0.5) * cell)
        ctx.glow(Color(hex: 0xFF453A).opacity(0.8), radius: 10) { layer in
            layer.fillCircle(ap, radius: cell * 0.34 * pulse, with: layer.linear([Color(hex: 0xFF8A80), Color(hex: 0xE5243B)], from: CGPoint(x: ap.x - 6, y: ap.y - 6), to: CGPoint(x: ap.x + 6, y: ap.y + 6)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: ap.x + 0.5, y: ap.y - cell * 0.48, width: 6, height: 3.2)), with: .color(Color(hex: 0x7BE07B)))

        // Gem
        if let g = e.gem {
            let c = CGPoint(x: (Double(g.x) + 0.5) * cell, y: (Double(g.y) + 0.5) * cell)
            let r = cell * 0.36
            var diamond = Path()
            diamond.move(to: CGPoint(x: c.x, y: c.y - r))
            diamond.addLine(to: CGPoint(x: c.x + r * 0.8, y: c.y))
            diamond.addLine(to: CGPoint(x: c.x, y: c.y + r))
            diamond.addLine(to: CGPoint(x: c.x - r * 0.8, y: c.y))
            diamond.closeSubpath()
            ctx.glow(Color(hex: 0x6AD4FF), radius: 10) { layer in
                layer.fill(diamond, with: layer.linear([Color(hex: 0xD4F6FF), Color(hex: 0x3BA7FF)], from: CGPoint(x: c.x, y: c.y - r), to: CGPoint(x: c.x, y: c.y + r)))
            }
            // Countdown ring
            var ring = Path()
            ring.addArc(center: c, radius: r + 4, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * max(0, e.gemTimeLeft / 5)), clockwise: false)
            ctx.stroke(ring, with: .color(Color(hex: 0x6AD4FF).opacity(0.6)), lineWidth: 1.5)
        }

        // Snake (interpolated between grid steps)
        let progress = e.phase == .playing ? e.stepProgress : 1
        let body = e.body
        let previous = e.previousBody
        var points: [CGPoint] = []
        points.reserveCapacity(body.count)
        for (i, p) in body.enumerated() {
            let from = i < previous.count ? previous[i] : p
            let x = Double(from.x) + (Double(p.x) - Double(from.x)) * progress
            let y = Double(from.y) + (Double(p.y) - Double(from.y)) * progress
            points.append(CGPoint(x: (x + 0.5) * cell, y: (y + 0.5) * cell))
        }
        let dead = e.phase == .over
        let flash = dead && sin(t * 20) > 0
        let n = max(1, points.count - 1)

        ctx.glow(head.opacity(dead ? 0.2 : 0.55), radius: 10) { layer in
            for i in stride(from: points.count - 1, to: 0, by: -1) {
                var seg = Path()
                seg.move(to: points[i])
                seg.addLine(to: points[i - 1])
                let f = Double(i) / Double(n)
                let color = flash ? Color(hex: 0xFF453A) : mix(head, tail, f)
                let width = cell * (0.72 - 0.22 * f)
                layer.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            if points.count == 1 {
                layer.fillCircle(points[0], radius: cell * 0.36, with: .color(head))
            }
        }

        // Head & eyes
        if let headPoint = points.first {
            ctx.fillCircle(headPoint, radius: cell * 0.38, with: .color(flash ? Color(hex: 0xFF453A) : head))
            let d = e.direction.delta
            let forward = CGPoint(x: Double(d.x), y: Double(d.y))
            let side = CGPoint(x: -forward.y, y: forward.x)
            for s in [-1.0, 1.0] {
                let eye = CGPoint(x: headPoint.x + forward.x * 3 + side.x * 4 * s, y: headPoint.y + forward.y * 3 + side.y * 4 * s)
                ctx.fillCircle(eye, radius: 2.6, with: .color(.white))
                ctx.fillCircle(CGPoint(x: eye.x + forward.x * 1, y: eye.y + forward.y * 1), radius: dead ? 0.6 : 1.4, with: .color(Color(hex: 0x0B1A12)))
            }
        }

        drawParticles(e.particles.particles, in: ctx, palette: [head, Color(hex: 0xFF6B6B), Color(hex: 0x8FE3FF), Color(hex: 0xFF453A)], scale: cell)

        // Length badge
        let label = Text("LENGTH \(body.count)").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.28))
        ctx.draw(label, at: CGPoint(x: w - 10, y: h - 8), anchor: .bottomTrailing)
    }
}
