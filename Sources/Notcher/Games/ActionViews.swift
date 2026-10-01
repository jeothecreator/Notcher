import NotcherCore
import SwiftUI

// MARK: - Invaders

struct InvadersView: View {
    let engine: InvadersEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: InvadersEngine.width, height: InvadersEngine.height), in: size)
            InvadersRenderer.draw(engine, in: ctx)
        }
    }
}

enum InvadersRenderer {
    static let rowColors: [Color] = [
        Color(hex: 0xFF8AC2), Color(hex: 0xC9A7FF), Color(hex: 0x9BB8FF), Color(hex: 0x7CFFCB), Color(hex: 0xB4F05A),
    ]
    static let saucerColor = Color(hex: 0xFF5F6D)
    static let bunkerColor = Color(hex: 0x5EF2A0)
    static let player = [Color(hex: 0xC8FFF0), Color(hex: 0x14B8A6)]

    // Two animation frames per alien type, as pixel rows.
    static let squid = [
        ["...XX...", "..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", "..X..X..", ".X.XX.X.", "X.X..X.X"],
        ["...XX...", "..XXXX..", ".XXXXXX.", "XX.XX.XX", "XXXXXXXX", ".X.XX.X.", "X......X", ".X....X."],
    ]
    static let crab = [
        ["..X.....X..", "...X...X...", "..XXXXXXX..", ".XX.XXX.XX.", "XXXXXXXXXXX", "X.XXXXXXX.X", "X.X.....X.X", "...XX.XX..."],
        ["..X.....X..", "X..X...X..X", "X.XXXXXXX.X", "XXX.XXX.XXX", "XXXXXXXXXXX", ".XXXXXXXXX.", "..X.....X..", ".X.......X."],
    ]
    static let octopus = [
        ["....XXXX....", ".XXXXXXXXXX.", "XXXXXXXXXXXX", "XXX..XX..XXX", "XXXXXXXXXXXX", "...XX..XX...", "..XX.XX.XX..", "XX........XX"],
        ["....XXXX....", ".XXXXXXXXXX.", "XXXXXXXXXXXX", "XXX..XX..XXX", "XXXXXXXXXXXX", "..XXX..XXX..", ".XX..XX..XX.", "..XX....XX.."],
    ]

    /// Unit-pixel paths, built once.
    static let sprites: [[Path]] = [InvadersRenderer.squid, InvadersRenderer.crab, InvadersRenderer.octopus].map { frames in
        frames.map { InvadersRenderer.pixelPath($0) }
    }

    static func pixelPath(_ rows: [String]) -> Path {
        var p = Path()
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() where c == "X" {
                p.addRect(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1.04, height: 1.04))
            }
        }
        return p
    }

    static func sprite(forRow row: Int) -> (paths: [Path], width: CGFloat) {
        switch row {
        case 0: return (sprites[0], 8)
        case 1, 2: return (sprites[1], 11)
        default: return (sprites[2], 12)
        }
    }

    static func draw(_ e: InvadersEngine, in ctx: GraphicsContext) {
        let w = InvadersEngine.width, h = InvadersEngine.height
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x070914), Color(hex: 0x0C1026), Color(hex: 0x0A1A1A)], from: .zero, to: CGPoint(x: 0, y: h)))
        // Stars
        for i in 0..<70 {
            let x = hash01(i, 1) * w, y = hash01(i, 2) * h * 0.85
            let twinkle = 0.25 + 0.35 * (0.5 + 0.5 * sin(t * (1 + hash01(i, 3) * 2) + Double(i)))
            ctx.fill(Path(CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white.opacity(twinkle * 0.6)))
        }

        // Ground
        ctx.glow(bunkerColor.opacity(0.6), radius: 4) { layer in
            layer.fill(Path(CGRect(x: 0, y: 228, width: w, height: 1)), with: .color(bunkerColor.opacity(0.55)))
        }

        // Bunkers
        let cell = InvadersEngine.bunkerCell
        var bunkerPath = Path()
        for b in e.bunkers {
            for r in 0..<InvadersEngine.bunkerRows {
                for c in 0..<InvadersEngine.bunkerColumns where b.isSolid(c, r) {
                    bunkerPath.addRect(CGRect(x: b.x + Double(c) * cell, y: InvadersEngine.bunkerY + Double(r) * cell, width: cell + 0.1, height: cell + 0.1))
                }
            }
        }
        ctx.glow(bunkerColor.opacity(0.35), radius: 5) { layer in
            layer.fill(bunkerPath, with: layer.linear([bunkerColor, Color(hex: 0x1FB58F)], from: CGPoint(x: 0, y: InvadersEngine.bunkerY), to: CGPoint(x: 0, y: InvadersEngine.bunkerY + 28)))
        }

        // Aliens, one glow layer per row
        for row in 0..<InvadersEngine.rows {
            let (paths, spriteWidth) = sprite(forRow: row)
            let unit = paths[e.frame % 2]
            var combined = Path()
            for a in e.aliens where a.alive && a.row == row {
                let box = e.alienBox(a)
                let px = min(box.w / Double(spriteWidth), box.h / 8)
                let ox = box.x + (box.w - Double(spriteWidth) * px) / 2
                let oy = box.y + (box.h - 8 * px) / 2
                combined.addPath(unit, transform: CGAffineTransform(a: px, b: 0, c: 0, d: px, tx: ox, ty: oy))
            }
            let color = rowColors[row % rowColors.count]
            ctx.glow(color.opacity(0.75), radius: 6) { layer in
                layer.fill(combined, with: .color(color))
            }
        }

        // Saucer
        if let s = e.saucer {
            let blink = sin(t * 18) > 0
            ctx.glow(saucerColor, radius: 10) { layer in
                layer.fill(Path(ellipseIn: CGRect(x: s.x - 16, y: 10, width: 32, height: 10)),
                           with: layer.linear([Color(hex: 0xFF9AA2), saucerColor], from: CGPoint(x: 0, y: 10), to: CGPoint(x: 0, y: 20)))
                layer.fill(Path(ellipseIn: CGRect(x: s.x - 7, y: 5, width: 14, height: 9)), with: .color(Color(hex: 0xFFD0D4)))
            }
            for i in 0..<4 {
                let lx = s.x - 10 + Double(i) * 6.6
                ctx.fillCircle(CGPoint(x: lx, y: 15), radius: 1.2, with: .color(.white.opacity((i % 2 == 0) == blink ? 0.95 : 0.3)))
            }
        }

        // Shots
        ctx.glow(.white, radius: 5) { layer in
            for shot in e.playerShots {
                layer.fill(Path(roundedRect: CGRect(x: shot.position.x - 1, y: shot.position.y - 6, width: 2, height: 12), cornerRadius: 1), with: .color(Color(hex: 0xE6FFFA)))
            }
        }
        ctx.glow(Color(hex: 0xFF8A80), radius: 4) { layer in
            for shot in e.alienShots {
                var zig = Path()
                let x = shot.position.x, y = shot.position.y
                for k in 0...4 {
                    let yy = y - 6 + Double(k) * 3
                    let xx = x + ((k + Int(shot.phase * 8)) % 2 == 0 ? -2 : 2)
                    if k == 0 { zig.move(to: CGPoint(x: xx, y: yy)) } else { zig.addLine(to: CGPoint(x: xx, y: yy)) }
                }
                layer.stroke(zig, with: .color(Color(hex: 0xFFB4AC)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }

        // Player cannon
        let visible = e.respawn <= 0 && (e.invulnerable <= 0 || sin(t * 30) > -0.2) && e.phase != .over
        if visible {
            let x = e.playerX, y = InvadersEngine.playerY
            var cannon = Path()
            cannon.addRoundedRect(in: CGRect(x: x - 13, y: y - 2, width: 26, height: 8), cornerSize: CGSize(width: 2, height: 2))
            cannon.addRoundedRect(in: CGRect(x: x - 9, y: y - 5, width: 18, height: 4), cornerSize: CGSize(width: 1.5, height: 1.5))
            cannon.addRoundedRect(in: CGRect(x: x - 2, y: y - 9, width: 4, height: 5), cornerSize: CGSize(width: 1, height: 1))
            ctx.glow(player[1], radius: 8) { layer in
                layer.fill(cannon, with: layer.linear(player, from: CGPoint(x: x, y: y - 9), to: CGPoint(x: x, y: y + 6)))
            }
        }

        drawParticles(e.particles.particles, in: ctx, palette: rowColors + [saucerColor, bunkerColor.opacity(0.8), Color(hex: 0xC8FFF0)])

        // Score popups
        for p in e.popups {
            let alpha = max(0, 1 - p.age / 0.9)
            let text = Text(p.text).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(saucerColor.opacity(alpha))
            ctx.draw(text, at: CGPoint(x: p.position.x, y: p.position.y - p.age * 18), anchor: .center)
        }

        // HUD
        for i in 0..<max(0, e.lives - 1) {
            let x = 14 + Double(i) * 20
            var mini = Path()
            mini.addRoundedRect(in: CGRect(x: x, y: 233, width: 14, height: 3), cornerSize: CGSize(width: 1, height: 1))
            ctx.fill(mini, with: .color(player[0].opacity(0.55)))
        }
        let wave = Text("WAVE \(e.wave)").font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.3))
        ctx.draw(wave, at: CGPoint(x: w - 10, y: 234.5), anchor: .trailing)

        if let banner = e.waveBanner, e.phase == .playing, t - banner < 1.6 {
            let a = min(1, (1.6 - (t - banner)) * 2)
            let text = Text("WAVE \(e.wave)").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(0.85 * a))
            ctx.draw(text, at: CGPoint(x: w / 2, y: 132), anchor: .center)
        }
    }
}

// MARK: - Astro

struct AstroView: View {
    let engine: AstroEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: AstroEngine.width, height: AstroEngine.height), in: size)
            AstroRenderer.draw(engine, in: ctx)
        }
    }
}

enum AstroRenderer {
    static let line = Color(hex: 0xE6E9FF)
    static let accent = Color(hex: 0x7C83FF)
    static let flame = [Color(hex: 0xFFF3C4), Color(hex: 0xFF8A3D)]

    static func draw(_ e: AstroEngine, in ctx: GraphicsContext) {
        let w = AstroEngine.width, h = AstroEngine.height
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: 0x05060C)))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(Gradient(colors: [accent.opacity(0.14), .clear]), center: CGPoint(x: w * 0.72, y: h * 0.3), startRadius: 0, endRadius: 260))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFF3DCB).opacity(0.06), .clear]), center: CGPoint(x: w * 0.18, y: h * 0.85), startRadius: 0, endRadius: 200))
        for i in 0..<90 {
            let x = hash01(i, 11) * w, y = hash01(i, 12) * h
            let s = hash01(i, 13) > 0.85 ? 1.6 : 1
            ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(0.15 + 0.35 * hash01(i, 14))))
        }

        // Rocks, drawn again across the edges they straddle.
        var rocks = Path()
        var craters = Path()
        for rock in e.rocks {
            for offset in wrapOffsets(rock.position, radius: rock.radius * 1.1, w: w, h: h) {
                let at = CGPoint(x: rock.position.x + offset.x, y: rock.position.y + offset.y)
                rocks.addPath(rockPath(rock, at: at))
                craters.addPath(craterPath(rock, at: at))
            }
        }
        ctx.fill(rocks, with: .color(Color(hex: 0x0B0D1A)))
        ctx.stroke(craters, with: .color(line.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        ctx.glow(accent.opacity(0.8), radius: 6) { layer in
            layer.stroke(rocks, with: .color(line.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }

        // Exhaust
        for (i, p) in e.exhaust.enumerated() {
            let f = Double(i + 1) / Double(max(1, e.exhaust.count))
            ctx.fillCircle(p.point, radius: 1 + 1.5 * f, with: .color(flame[1].opacity(0.35 * f)))
        }

        // Bullets
        ctx.glow(line, radius: 5) { layer in
            for b in e.bullets {
                let v = b.velocity
                let l = max(1, (v.x * v.x + v.y * v.y).squareRoot())
                var tail = Path()
                tail.move(to: b.position.point)
                tail.addLine(to: CGPoint(x: b.position.x - v.x / l * 6, y: b.position.y - v.y / l * 6))
                layer.stroke(tail, with: .color(line.opacity(0.5)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                layer.fillCircle(b.position.point, radius: 1.5, with: .color(.white))
            }
        }

        // Ship
        let ship = e.ship
        let visible = e.respawn <= 0 && e.phase != .over && (e.invulnerable <= 0 || sin(t * 28) > -0.3)
        if visible {
            for offset in wrapOffsets(ship.position, radius: 12, w: w, h: h) {
                drawShip(ship, at: CGPoint(x: ship.position.x + offset.x, y: ship.position.y + offset.y), t: t, in: ctx)
            }
        }

        drawParticles(e.particles.particles, in: ctx, palette: [line, Color(hex: 0xFFB340), flame[1], Color(hex: 0x8AF2FF)])

        // HUD
        for i in 0..<max(0, e.lives) {
            var c = ctx
            c.translateBy(x: 14 + Double(i) * 14, y: 14)
            c.rotate(by: .radians(-Double.pi / 2))
            c.stroke(shipOutline(scale: 0.75), with: .color(line.opacity(0.6)), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))
        }
        let wave = Text("WAVE \(e.wave)").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.3))
        ctx.draw(wave, at: CGPoint(x: w - 10, y: 8), anchor: .topTrailing)
        // Warp readiness
        let ready = e.warpCooldown <= 0
        let warpLabel = Text(ready ? "WARP READY" : "WARP").font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(ready ? 0.35 : 0.2))
        ctx.draw(warpLabel, at: CGPoint(x: 10, y: h - 8), anchor: .bottomLeading)
        if !ready {
            let frac = max(0, min(1, 1 - e.warpCooldown / 3))
            ctx.fill(Path(roundedRect: CGRect(x: 38, y: h - 13, width: 30, height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.08)))
            ctx.fill(Path(roundedRect: CGRect(x: 38, y: h - 13, width: 30 * frac, height: 3), cornerRadius: 1.5), with: .color(accent.opacity(0.7)))
        }

        if let banner = e.waveBanner, e.phase == .playing, t - banner < 1.6 {
            let a = min(1, (1.6 - (t - banner)) * 2)
            let text = Text("WAVE \(e.wave)").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(0.85 * a))
            ctx.draw(text, at: CGPoint(x: w / 2, y: h / 2 - 40), anchor: .center)
        }
    }

    static func wrapOffsets(_ p: Vec2, radius: Double, w: Double, h: Double) -> [CGPoint] {
        var xs: [Double] = [0], ys: [Double] = [0]
        if p.x < radius { xs.append(w) }
        if p.x > w - radius { xs.append(-w) }
        if p.y < radius { ys.append(h) }
        if p.y > h - radius { ys.append(-h) }
        var result: [CGPoint] = []
        for x in xs { for y in ys { result.append(CGPoint(x: x, y: y)) } }
        return result
    }

    static func rockPath(_ rock: AstroEngine.Rock, at c: CGPoint) -> Path {
        var p = Path()
        let n = rock.outline.count
        for (i, k) in rock.outline.enumerated() {
            let a = rock.angle + Double(i) / Double(n) * 2 * .pi
            let pt = CGPoint(x: c.x + cos(a) * rock.radius * k, y: c.y + sin(a) * rock.radius * k)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// A shallow crater on bigger rocks, drawn faintly for depth.
    static func craterPath(_ rock: AstroEngine.Rock, at c: CGPoint) -> Path {
        var p = Path()
        guard rock.size >= 2 else { return p }
        let r = rock.radius * 0.16
        let a = rock.angle * 0.7
        let cx = c.x + cos(a) * rock.radius * 0.38, cy = c.y + sin(a) * rock.radius * 0.38
        // Start with an explicit move so arcs from different rocks never join up.
        p.move(to: CGPoint(x: cx + cos(a + 0.6) * r, y: cy + sin(a + 0.6) * r))
        p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .radians(a + 0.6), endAngle: .radians(a + 3.6), clockwise: false)
        return p
    }

    /// Ship outline pointing right, centred on the origin.
    static func shipOutline(scale s: Double = 1) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 11 * s, y: 0))
        p.addLine(to: CGPoint(x: -7 * s, y: -7 * s))
        p.addLine(to: CGPoint(x: -4 * s, y: 0))
        p.addLine(to: CGPoint(x: -7 * s, y: 7 * s))
        p.closeSubpath()
        return p
    }

    static func drawShip(_ ship: AstroEngine.Ship, at c: CGPoint, t: Double, in ctx: GraphicsContext) {
        var s = ctx
        s.translateBy(x: c.x, y: c.y)
        s.rotate(by: .radians(ship.angle))
        if ship.thrusting {
            let len = 9 + 5 * (0.5 + 0.5 * sin(t * 60))
            var f = Path()
            f.move(to: CGPoint(x: -5, y: -3.5))
            f.addLine(to: CGPoint(x: -5 - len, y: 0))
            f.addLine(to: CGPoint(x: -5, y: 3.5))
            f.closeSubpath()
            s.glow(flame[1], radius: 8) { layer in
                layer.fill(f, with: layer.linear(flame, from: CGPoint(x: -5, y: 0), to: CGPoint(x: -5 - len, y: 0)))
            }
        }
        let outline = shipOutline()
        s.fill(outline, with: .color(Color(hex: 0x0B0D1A)))
        s.glow(Color(hex: 0x8AF2FF), radius: 7) { layer in
            layer.stroke(outline, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        s.fillCircle(CGPoint(x: 2, y: 0), radius: 1.6, with: .color(Color(hex: 0x8AF2FF)))
    }
}

// MARK: - Trails

struct TrailsView: View {
    let engine: TrailsEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            let c = TrailsEngine.cell
            ctx.fit(CGSize(width: Double(TrailsEngine.columns) * c, height: Double(TrailsEngine.rows) * c), in: size)
            TrailsRenderer.draw(engine, in: ctx)
        }
    }
}

enum TrailsRenderer {
    static let colors: [Color] = [Color(hex: 0x3DF5FF), Color(hex: 0xFF3DCB), Color(hex: 0xFFB340), Color(hex: 0xB4F05A)]

    static func draw(_ e: TrailsEngine, in ctx: GraphicsContext) {
        let cell = TrailsEngine.cell
        let w = Double(TrailsEngine.columns) * cell, h = Double(TrailsEngine.rows) * cell
        let t = e.clock

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x05060F), Color(hex: 0x0A0820)], from: .zero, to: CGPoint(x: 0, y: h)))
        // Grid
        var grid = Path()
        var x = 0.0
        while x <= w {
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: h))
            x += cell * 4
        }
        var y = 0.0
        while y <= h {
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: w, y: y))
            y += cell * 4
        }
        ctx.stroke(grid, with: .color(colors[0].opacity(0.06)), lineWidth: 0.6)
        ctx.glow(colors[0].opacity(0.5), radius: 5) { layer in
            layer.stroke(Path(roundedRect: CGRect(x: 1, y: 1, width: w - 2, height: h - 2), cornerRadius: 4), with: .color(colors[0].opacity(0.35)), lineWidth: 1.2)
        }

        let moving = e.phase == .playing && e.countdown <= 0 && e.roundResult == nil
        for bike in e.bikes {
            let color = colors[bike.index % colors.count]
            var fade = 1.0
            if let crashed = bike.crashedAt { fade = max(0.18, 1 - (t - crashed) * 1.4) }
            var trail = Path()
            for (i, p) in bike.path.enumerated() {
                let pt = CGPoint(x: (Double(p.x) + 0.5) * cell, y: (Double(p.y) + 0.5) * cell)
                if i == 0 { trail.move(to: pt) } else { trail.addLine(to: pt) }
            }
            var head = CGPoint(x: (Double(bike.head.x) + 0.5) * cell, y: (Double(bike.head.y) + 0.5) * cell)
            if bike.alive && moving {
                let d = bike.direction.delta
                head = CGPoint(x: head.x + Double(d.x) * cell * e.stepProgress, y: head.y + Double(d.y) * cell * e.stepProgress)
                trail.addLine(to: head)
            }
            ctx.glow(color.opacity(0.8 * fade), radius: 6) { layer in
                layer.stroke(trail, with: .color(color.opacity(0.85 * fade)), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(trail, with: .color(Color.white.opacity(0.55 * fade)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

            if bike.alive {
                let pulse = bike.isPlayer ? 1 + 0.15 * sin(t * 10) : 1
                ctx.glow(color, radius: 10) { layer in
                    layer.fillCircle(head, radius: 4.2 * pulse, with: .color(color))
                }
                ctx.fillCircle(head, radius: 2, with: .color(.white))
                if bike.isPlayer && e.countdown > 0 {
                    let label = Text("YOU").font(.system(size: 7.5, weight: .heavy, design: .rounded)).foregroundStyle(color)
                    ctx.draw(label, at: CGPoint(x: head.x, y: head.y - 10), anchor: .bottom)
                }
            }
        }

        drawParticles(e.particles.particles, in: ctx, palette: colors, scale: cell)

        // HUD
        for i in 0..<3 {
            let alive = i < e.lives
            ctx.fillCircle(CGPoint(x: 12 + Double(i) * 10, y: 11), radius: 3, with: .color(alive ? colors[0].opacity(0.8) : .white.opacity(0.12)))
        }
        let round = Text("ROUND \(e.round)").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.32))
        ctx.draw(round, at: CGPoint(x: w - 10, y: 6), anchor: .topTrailing)

        if e.phase == .playing && e.countdown > 0 && e.roundResult == nil {
            let n = max(1, Int((e.countdown / 0.4).rounded(.up)))
            let frac = e.countdown / 0.4 - Double(n - 1)
            let text = Text("\(n)").font(.system(size: 44, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(0.35 + 0.5 * frac))
            ctx.draw(text, at: CGPoint(x: w / 2, y: h / 2), anchor: .center)
        }
        if let result = e.roundResult {
            let a = min(1, (t - result.at) * 4)
            let title = result.won ? "ROUND \(e.round) CLEAR" : (e.lives > 0 ? "DEREZZED" : "GAME OVER")
            let text = Text(title).font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(result.won ? colors[0].opacity(a) : colors[1].opacity(a))
            ctx.draw(text, at: CGPoint(x: w / 2, y: h / 2 - 8), anchor: .center)
            if !result.won && e.lives > 0 {
                let sub = Text("\(e.lives) \(e.lives == 1 ? "life" : "lives") left").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.6 * a))
                ctx.draw(sub, at: CGPoint(x: w / 2, y: h / 2 + 16), anchor: .center)
            }
        }
    }
}
