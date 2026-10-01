import NotcherCore
import SwiftUI

// MARK: - Pong

struct PongView: View {
    let engine: PongEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: PongEngine.width, height: PongEngine.height), in: size)
            PongRenderer.draw(engine, in: ctx)
        }
    }
}

enum PongRenderer {
    static let you = [Color(hex: 0x8BE0FF), Color(hex: 0x3478F6)]
    static let cpu = [Color(hex: 0xFF9BC4), Color(hex: 0xE5245F)]

    static func draw(_ e: PongEngine, in ctx: GraphicsContext) {
        let w = PongEngine.width, h = PongEngine.height

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x0E1424), Color(hex: 0x06070C)]), center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: w * 0.6))

        // Halves tinted by player
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w / 2, height: h)), with: .color(you[1].opacity(0.03)))
        ctx.fill(Path(CGRect(x: w / 2, y: 0, width: w / 2, height: h)), with: .color(cpu[1].opacity(0.03)))

        // Center line
        var dashes = Path()
        var y = 6.0
        while y < h {
            dashes.addRoundedRect(in: CGRect(x: w / 2 - 1, y: y, width: 2, height: 9), cornerSize: CGSize(width: 1, height: 1))
            y += 17
        }
        ctx.fill(dashes, with: .color(.white.opacity(0.12)))

        // Big score digits
        let score = { (n: Int, color: Color) in
            Text("\(n)").font(.system(size: 72, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(color.opacity(0.13))
        }
        ctx.draw(score(e.playerPoints, you[0]), at: CGPoint(x: w / 2 - 58, y: h / 2), anchor: .center)
        ctx.draw(score(e.aiPoints, cpu[0]), at: CGPoint(x: w / 2 + 58, y: h / 2), anchor: .center)

        let level = Text("LEVEL \(e.level)").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.3))
        ctx.draw(level, at: CGPoint(x: w / 2, y: 10), anchor: .top)

        // Paddles
        drawPaddle(ctx, x: PongEngine.playerX, y: e.player.y, colors: you, flash: e.player.flash)
        drawPaddle(ctx, x: PongEngine.aiX, y: e.ai.y, colors: cpu, flash: e.ai.flash)

        // Ball trail + ball
        let r = PongEngine.ballRadius
        for (i, p) in e.trail.enumerated() {
            let f = Double(i + 1) / Double(max(1, e.trail.count))
            ctx.fillCircle(p.point, radius: r * (0.3 + 0.6 * f), with: .color(.white.opacity(0.18 * f)))
        }
        let serving = e.serveTimer > 0 && e.phase == .playing
        let pulse = serving ? 0.6 + 0.4 * sin(e.clock * 12) : 1
        ctx.glow(.white.opacity(0.9), radius: 10) { layer in
            layer.fillCircle(e.ball.point, radius: r, with: .color(.white.opacity(pulse)))
        }

        drawParticles(e.particles.particles, in: ctx, palette: [you[0], cpu[0]])

        if let banner = e.banner {
            let text = Text(banner.uppercased()).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Color.white)
            ctx.glow(you[0], radius: 14) { layer in
                layer.draw(text, at: CGPoint(x: w / 2, y: h / 2), anchor: .center)
            }
        }
    }

    static func drawPaddle(_ ctx: GraphicsContext, x: Double, y: Double, colors: [Color], flash: Double) {
        let rect = CGRect(x: x, y: y - PongEngine.paddleHeight / 2, width: PongEngine.paddleWidth, height: PongEngine.paddleHeight)
        ctx.glow(colors[1].opacity(0.6 + 0.4 * flash), radius: 8 + 10 * flash) { layer in
            layer.fill(Path(roundedRect: rect, cornerRadius: 4.5), with: layer.linear(colors, from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY)))
        }
        if flash > 0 {
            ctx.fill(Path(roundedRect: rect, cornerRadius: 4.5), with: .color(.white.opacity(flash * 0.6)))
        }
    }
}

// MARK: - Breakout

struct BreakoutView: View {
    let engine: BreakoutEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: BreakoutEngine.width, height: BreakoutEngine.height), in: size)
            BreakoutRenderer.draw(engine, in: ctx)
        }
    }
}

enum BreakoutRenderer {
    static let rows: [[Color]] = [
        [Color(hex: 0xFF8AC2), Color(hex: 0xE5367F)],
        [Color(hex: 0xFFA27A), Color(hex: 0xF05A3A)],
        [Color(hex: 0xFFD66B), Color(hex: 0xF0A020)],
        [Color(hex: 0xA8F07A), Color(hex: 0x3FBF5A)],
        [Color(hex: 0x8BE0FF), Color(hex: 0x2F8FE8)],
        [Color(hex: 0xC6A8FF), Color(hex: 0x7A4CF0)],
    ]

    static func powerColor(_ kind: BreakoutEngine.PowerKind) -> [Color] {
        switch kind {
        case .wide: return [Color(hex: 0x8BE0FF), Color(hex: 0x2F8FE8)]
        case .multi: return [Color(hex: 0xFF8AC2), Color(hex: 0xA35BFF)]
        case .slow: return [Color(hex: 0xA8F07A), Color(hex: 0x2FBF8A)]
        case .life: return [Color(hex: 0xFFD66B), Color(hex: 0xFF5E3A)]
        }
    }

    static func draw(_ e: BreakoutEngine, in ctx: GraphicsContext) {
        let w = BreakoutEngine.width, h = BreakoutEngine.height
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x120A1E), Color(hex: 0x07060C)], from: .zero, to: CGPoint(x: 0, y: h)))
        drawDotGrid(ctx, size: CGSize(width: w, height: h), spacing: 16, color: .white.opacity(0.035))

        // Bricks
        for brick in e.bricks {
            let colors = rows[brick.row % rows.count]
            let rect = brick.box.rect
            let damaged = brick.hp < brick.maxHP
            let tough = brick.maxHP > 1
            ctx.glow(colors[1].opacity(0.45), radius: 5) { layer in
                layer.fill(Path(roundedRect: rect, cornerRadius: 3),
                           with: layer.linear(damaged ? colors.map { $0.opacity(0.55) } : colors, from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY)))
            }
            ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + 1.5, width: rect.width - 4, height: 2), cornerRadius: 1), with: .color(.white.opacity(0.4)))
            if tough && !damaged {
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 2), with: .color(.white.opacity(0.55)), lineWidth: 1)
            }
            if damaged {
                var crack = Path()
                crack.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY))
                crack.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.midY))
                crack.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
                ctx.stroke(crack, with: .color(.black.opacity(0.5)), lineWidth: 1)
            }
            if brick.flash > 0 {
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.white.opacity(brick.flash * 0.8)))
            }
        }

        // Power-ups
        for p in e.powerUps {
            let rect = CGRect(x: p.position.x - 12, y: p.position.y - 6.5, width: 24, height: 13)
            let colors = powerColor(p.kind)
            ctx.glow(colors[0], radius: 8) { layer in
                layer.fill(Path(roundedRect: rect, cornerRadius: 6.5), with: layer.linear(colors, from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.maxX, y: 0)))
            }
            let letter = Text(p.kind.letter).font(.system(size: 9, weight: .black, design: .rounded)).foregroundStyle(Color.black.opacity(0.75))
            ctx.draw(letter, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }

        // Paddle
        let pw = e.paddleWidth
        let paddle = CGRect(x: e.paddleX - pw / 2, y: BreakoutEngine.paddleY, width: pw, height: BreakoutEngine.paddleHeight)
        let paddleColors = e.wideTime > 0 ? [Color(hex: 0x8BE0FF), Color(hex: 0x2F8FE8)] : [Color(hex: 0xFF8AD0), Color(hex: 0xA35BFF)]
        ctx.glow(paddleColors[1], radius: 10) { layer in
            layer.fill(Path(roundedRect: paddle, cornerRadius: 4), with: layer.linear(paddleColors, from: CGPoint(x: paddle.minX, y: 0), to: CGPoint(x: paddle.maxX, y: 0)))
        }

        // Balls
        let r = BreakoutEngine.ballRadius
        for ball in e.balls {
            for (i, p) in ball.trail.enumerated() {
                let f = Double(i + 1) / Double(max(1, ball.trail.count))
                ctx.fillCircle(p.point, radius: r * (0.3 + 0.6 * f), with: .color(Color(hex: 0xFFD1F0).opacity(0.16 * f)))
            }
            ctx.glow(.white, radius: 8) { layer in
                layer.fillCircle(ball.position.point, radius: r, with: .color(e.slowTime > 0 ? Color(hex: 0xC8FFD8) : .white))
            }
        }

        let palette = rows.map { $0[0] }
        drawParticles(e.particles.particles, in: ctx, palette: palette)

        // Lives and combo
        var hearts = Path()
        for i in 0..<max(0, e.lives) {
            hearts.addEllipse(in: CGRect(x: w - 14 - Double(i) * 11, y: h - 13, width: 6, height: 6))
        }
        ctx.fill(hearts, with: .color(Color(hex: 0xFF8AC2).opacity(0.8)))

        if e.multiplier > 1 {
            let combo = Text("×\(e.multiplier)").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Color(hex: 0xFFD66B))
            ctx.draw(combo, at: CGPoint(x: e.paddleX, y: BreakoutEngine.paddleY - 14), anchor: .center)
        }
        let level = Text("LEVEL \(e.level)").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.3))
        ctx.draw(level, at: CGPoint(x: 12, y: h - 8), anchor: .bottomLeading)

        if let banner = e.banner {
            let text = Text(banner.uppercased()).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Color.white)
            ctx.glow(Color(hex: 0xFF8AC2), radius: 14) { layer in
                layer.draw(text, at: CGPoint(x: w / 2, y: h * 0.62), anchor: .center)
            }
        }
    }
}
