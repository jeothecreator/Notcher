import NotcherCore
import SwiftUI

struct RunnerView: View {
    let engine: RunnerEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: RunnerEngine.width, height: RunnerEngine.height), in: size)
            RunnerRenderer.draw(engine, in: ctx)
        }
    }
}

enum RunnerRenderer {
    static let sunTop = Color(hex: 0xFFD66B)
    static let sunBottom = Color(hex: 0xFF3D7F)
    static let neon = Color(hex: 0xFF5E9A)
    static let player = [Color(hex: 0xFFE9A8), Color(hex: 0xFFA43A)]

    static func draw(_ e: RunnerEngine, in ctx: GraphicsContext) {
        let w = RunnerEngine.width, h = RunnerEngine.height, ground = RunnerEngine.groundY
        let t = e.clock
        let d = e.distance

        // Sky
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: ground)),
                 with: ctx.linear([Color(hex: 0x0B0820), Color(hex: 0x24102E), Color(hex: 0x3A1430)], from: .zero, to: CGPoint(x: 0, y: ground)))

        // Stars
        var stars = Path()
        for i in 0..<46 {
            let x = (hash01(i, 1) * (w + 40) - d * 0.02).truncatingRemainder(dividingBy: w + 40)
            let sx = x < 0 ? x + w + 40 : x
            let sy = hash01(i, 2) * (ground - 70)
            let twinkle = 0.6 + 0.4 * sin(t * (1 + hash01(i, 3) * 3) + Double(i))
            let r = (0.5 + hash01(i, 4) * 0.9) * twinkle
            stars.addEllipse(in: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
        }
        ctx.fill(stars, with: .color(.white.opacity(0.7)))

        // Striped synthwave sun
        let sunCenter = CGPoint(x: w * 0.72, y: ground - 46)
        let sunRadius = 46.0
        ctx.glow(sunBottom.opacity(0.7), radius: 24) { layer in
            layer.fillCircle(sunCenter, radius: sunRadius, with: layer.linear([sunTop, sunBottom], from: CGPoint(x: 0, y: sunCenter.y - sunRadius), to: CGPoint(x: 0, y: sunCenter.y + sunRadius)))
        }
        for i in 0..<5 {
            let y = sunCenter.y + 6 + Double(i) * 8
            let thickness = 1.2 + Double(i) * 0.9
            ctx.fill(Path(CGRect(x: sunCenter.x - sunRadius - 2, y: y, width: sunRadius * 2 + 4, height: thickness)), with: .color(Color(hex: 0x2E1230)))
        }

        // Far mountains and near hills with parallax
        drawRidge(ctx, offset: d * 0.12, base: ground, height: 46, period: 210, seed: 10, color: Color(hex: 0x2A1238))
        drawRidge(ctx, offset: d * 0.3, base: ground, height: 26, period: 140, seed: 20, color: Color(hex: 0x1B0C24))

        // Neon floor grid
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: h - ground)),
                 with: ctx.linear([Color(hex: 0x1A0A1E), Color(hex: 0x07050C)], from: CGPoint(x: 0, y: ground), to: CGPoint(x: 0, y: h)))
        var grid = Path()
        let vanishing = CGPoint(x: w / 2, y: ground - 30)
        let spacing = 46.0
        let shift = d.truncatingRemainder(dividingBy: spacing)
        var x = -spacing * 6 - shift
        while x < w + spacing * 6 {
            let bottom = CGPoint(x: x, y: h)
            let tParam = (ground - vanishing.y) / (h - vanishing.y)
            let top = CGPoint(x: vanishing.x + (bottom.x - vanishing.x) * tParam, y: ground)
            grid.move(to: top)
            grid.addLine(to: bottom)
            x += spacing
        }
        for i in 0..<5 {
            let p = Double(i) / 5
            let phase = (d / 60).truncatingRemainder(dividingBy: 1)
            let f = pow((p + phase / 5), 2)
            let y = ground + f * (h - ground)
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: w, y: y))
        }
        ctx.stroke(grid, with: .color(neon.opacity(0.22)), lineWidth: 1)
        ctx.glow(neon, radius: 6) { layer in
            layer.fill(Path(CGRect(x: 0, y: ground - 0.5, width: w, height: 1.6)), with: .color(neon.opacity(0.9)))
        }

        // Coins
        for coin in e.coins {
            let squeeze = abs(cos(coin.spin))
            let r = 6.5
            let rect = CGRect(x: coin.position.x - r * max(0.18, squeeze), y: coin.position.y - r, width: r * 2 * max(0.18, squeeze), height: r * 2)
            ctx.glow(Color(hex: 0xFFC94A).opacity(0.8), radius: 6) { layer in
                layer.fill(Path(ellipseIn: rect), with: layer.linear([Color(hex: 0xFFF1A8), Color(hex: 0xFFB000)], from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY)))
            }
        }

        // Obstacles
        for o in e.obstacles {
            switch o.kind {
            case .block:
                let rect = o.box.rect
                ctx.glow(Color(hex: 0xA35BFF).opacity(0.6), radius: 8) { layer in
                    layer.fill(Path(roundedRect: rect, cornerRadius: 4), with: layer.linear([Color(hex: 0xC48BFF), Color(hex: 0x5B2BC9)], from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.minX, y: rect.maxY)))
                }
                ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width - 4, height: 2), cornerRadius: 1), with: .color(.white.opacity(0.45)))
            case .spikes:
                let rect = o.box.rect
                let count = max(2, Int(rect.width / 11))
                let sw = rect.width / Double(count)
                var spikes = Path()
                for i in 0..<count {
                    let x0 = rect.minX + Double(i) * sw
                    spikes.move(to: CGPoint(x: x0, y: rect.maxY))
                    spikes.addLine(to: CGPoint(x: x0 + sw / 2, y: rect.minY))
                    spikes.addLine(to: CGPoint(x: x0 + sw, y: rect.maxY))
                    spikes.closeSubpath()
                }
                ctx.glow(Color(hex: 0xFF3D7F).opacity(0.7), radius: 7) { layer in
                    layer.fill(spikes, with: layer.linear([Color(hex: 0xFFA0C0), Color(hex: 0xE5245F)], from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY)))
                }
            case .drone:
                let rect = o.box.rect
                ctx.glow(Color(hex: 0x6AD4FF).opacity(0.7), radius: 8) { layer in
                    layer.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: 3), cornerRadius: 6), with: layer.linear([Color(hex: 0x9BE7FF), Color(hex: 0x2B7BE4)], from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY)))
                }
                // Rotors
                let blade = 10 * abs(sin(t * 40 + o.seed))
                var rotors = Path()
                rotors.move(to: CGPoint(x: rect.minX + 6 - blade, y: rect.minY + 1))
                rotors.addLine(to: CGPoint(x: rect.minX + 6 + blade, y: rect.minY + 1))
                rotors.move(to: CGPoint(x: rect.maxX - 6 - blade, y: rect.minY + 1))
                rotors.addLine(to: CGPoint(x: rect.maxX - 6 + blade, y: rect.minY + 1))
                ctx.stroke(rotors, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
                // Eye
                let blink = sin(t * 8 + o.seed) > 0 ? 1.0 : 0.4
                ctx.fillCircle(CGPoint(x: rect.minX + 7, y: rect.midY), radius: 2.4, with: .color(Color(hex: 0xFF3D5A).opacity(blink)))
            }
        }

        drawPlayer(e, in: ctx)

        drawParticles(e.particles.particles, in: ctx, palette: [Color.white.opacity(0.5), Color(hex: 0xFFB340), Color(hex: 0xFFE07A)])

        // Death flash
        if let death = e.deathTime {
            let a = max(0, 0.5 - (t - death) * 1.5)
            if a > 0 { ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.white.opacity(a))) }
        }

        // Speed meter
        if e.phase == .playing || e.phase == .over {
            let label = Text(String(format: "%.1f×", e.speed / 320)).font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Color.white.opacity(0.35))
            ctx.draw(label, at: CGPoint(x: 14, y: 12), anchor: .topLeading)
        }
    }

    static func drawRidge(_ ctx: GraphicsContext, offset: Double, base: Double, height: Double, period: Double, seed: Int, color: Color) {
        var path = Path()
        let w = RunnerEngine.width
        let shift = offset.truncatingRemainder(dividingBy: period)
        let startIndex = Int(offset / period)
        path.move(to: CGPoint(x: -period, y: base))
        var i = -1
        while Double(i) * period - shift < w + period {
            let x = Double(i) * period - shift
            let peak = height * (0.55 + 0.45 * hash01(startIndex + i, seed))
            let mid = height * (0.25 + 0.3 * hash01(startIndex + i, seed + 1))
            path.addLine(to: CGPoint(x: x + period * 0.35, y: base - peak))
            path.addLine(to: CGPoint(x: x + period * 0.6, y: base - mid))
            path.addLine(to: CGPoint(x: x + period * 0.8, y: base - mid * 1.3))
            path.addLine(to: CGPoint(x: x + period, y: base))
            i += 1
        }
        path.addLine(to: CGPoint(x: w + period, y: base))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    static func drawPlayer(_ e: RunnerEngine, in ctx: GraphicsContext) {
        let p = e.player
        let box = p.box.rect
        let t = e.clock
        var c = ctx
        // Squash & stretch around the feet.
        let squash = p.squash
        let stretch = p.onGround ? 0 : min(0.15, abs(p.vy) / 4000)
        let sx = 1 + 0.18 * squash - stretch * 0.6
        let sy = 1 - 0.18 * squash + stretch
        c.translateBy(x: box.midX, y: box.maxY)
        c.scaleBy(x: sx, y: sy)
        c.translateBy(x: -box.midX, y: -box.maxY)

        if e.phase == .over, let death = e.deathTime, t - death > 0.05 {
            // Gone in a burst of particles.
            return
        }

        // Speed streaks
        if e.phase == .playing {
            var streaks = Path()
            for i in 0..<3 {
                let y = box.minY + 5 + Double(i) * (box.height - 10) / 2
                let len = 8 + 14 * e.difficulty + 4 * sin(t * 30 + Double(i))
                streaks.move(to: CGPoint(x: box.minX - 4, y: y))
                streaks.addLine(to: CGPoint(x: box.minX - 4 - len, y: y))
            }
            c.stroke(streaks, with: .color(player[1].opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        // Legs
        if !p.sliding {
            let phase = p.runCycle
            let lift = p.onGround ? 1.0 : 0.0
            for k in 0..<2 {
                let a = sin(phase + Double(k) * .pi) * lift
                let legX = box.minX + 6 + Double(k) * 8 + a * 3
                let legH = p.onGround ? 6 - max(0, a) * 2 : 4
                c.fill(Path(roundedRect: CGRect(x: legX, y: box.maxY - legH, width: 4, height: legH), cornerRadius: 2), with: .color(Color(hex: 0xFF8A3D)))
            }
        }

        // Body
        let bodyRect = p.sliding ? box : CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height - 5)
        c.glow(player[1].opacity(0.75), radius: 10) { layer in
            layer.fill(Path(roundedRect: bodyRect, cornerRadius: p.sliding ? 7 : 8), with: layer.linear(player, from: CGPoint(x: bodyRect.minX, y: bodyRect.minY), to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY)))
        }
        // Visor
        let visor = CGRect(x: bodyRect.maxX - 12, y: bodyRect.minY + (p.sliding ? 3 : 6), width: 10, height: 5)
        c.fill(Path(roundedRect: visor, cornerRadius: 2.5), with: .color(Color(hex: 0x1B1030)))
        c.fill(Path(roundedRect: CGRect(x: visor.maxX - 4, y: visor.minY + 1, width: 2.5, height: 2), cornerRadius: 1), with: .color(Color(hex: 0x7CF4FF)))
        // Scarf trailing behind
        var scarf = Path()
        let sy0 = bodyRect.minY + (p.sliding ? 5 : 11)
        scarf.move(to: CGPoint(x: bodyRect.minX + 2, y: sy0))
        scarf.addQuadCurve(to: CGPoint(x: bodyRect.minX - 12, y: sy0 + 3 + sin(t * 18) * 2.5), control: CGPoint(x: bodyRect.minX - 6, y: sy0 - 3))
        c.stroke(scarf, with: .color(Color(hex: 0xFF3D7F)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}
