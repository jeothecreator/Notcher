import NotcherCore
import SwiftUI

struct ArcadeView: View {
    let session: GameSession
    let engine: ArcadeEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: 640, height: 240), in: size)
            switch engine.current {
            case let e as FlapEngine: FlapRenderer.draw(e, in: ctx)
            case let e as DodgeEngine: DodgeRenderer.draw(e, in: ctx)
            case let e as BullseyeEngine: BullseyeRenderer.draw(e, in: ctx)
            case let e as EchoEngine: EchoRenderer.draw(e, in: ctx)
            case let e as LanderEngine: LanderRenderer.draw(e, in: ctx)
            case let e as HopEngine: HopRenderer.draw(e, in: ctx)
            default: break
            }
        }
    }
}

/// Pills for the mini games; Tab cycles.
struct ArcadeMiniPicker: View {
    let session: GameSession
    let engine: ArcadeEngine

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(ArcadeMini.allCases.enumerated()), id: \.element) { index, mini in
                let selected = mini == engine.mini
                HStack(spacing: 4) {
                    Image(systemName: mini.symbol)
                        .font(.system(size: 9, weight: .bold))
                    Text(mini.title)
                        .font(Theme.rounded(10, .bold))
                    if mini == engine.featured {
                        Text("TODAY")
                            .font(Theme.rounded(7, .heavy))
                            .opacity(0.7)
                    }
                }
                .foregroundStyle(selected ? Color.black : Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? AnyShapeStyle(LinearGradient(colors: mini.colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.white.opacity(0.07))))
                .onTapGesture {
                    session.press(.number(index + 1), isRepeat: false)
                }
            }
            Keycap(label: "tab")
                .padding(.leading, 2)
        }
    }
}

// MARK: - Flap

enum FlapRenderer {
    static func draw(_ e: FlapEngine, in ctx: GraphicsContext) {
        let w = FlapEngine.width, h = FlapEngine.height
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x1A1440), Color(hex: 0x6B2A5E), Color(hex: 0xF08A4B)], from: .zero, to: CGPoint(x: 0, y: h)))
        // Clouds
        for i in 0..<6 {
            let speed = 0.08 + hash01(i, 7) * 0.1
            var x = (hash01(i, 8) * (w + 160) - e.distance * speed).truncatingRemainder(dividingBy: w + 160)
            if x < -80 { x += w + 160 }
            let y = 20 + hash01(i, 9) * 110
            let cw = 50 + hash01(i, 10) * 60
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: cw, height: 14), cornerRadius: 7), with: .color(.white.opacity(0.06)))
        }
        // Pipes
        for p in e.pipes {
            let top = CGRect(x: p.x, y: -10, width: FlapEngine.pipeWidth, height: p.gapY - p.gapHeight / 2 + 10)
            let bottom = CGRect(x: p.x, y: p.gapY + p.gapHeight / 2, width: FlapEngine.pipeWidth, height: h - (p.gapY + p.gapHeight / 2) + 10)
            for rect in [top, bottom] {
                ctx.glow(Color(hex: 0x30D5C8).opacity(0.5), radius: 8) { layer in
                    layer.fill(Path(roundedRect: rect, cornerRadius: 8),
                               with: layer.linear([Color(hex: 0x7CF2D8), Color(hex: 0x1FA49A)], from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.maxX, y: 0)))
                }
            }
            let capTop = CGRect(x: p.x - 4, y: top.maxY - 12, width: FlapEngine.pipeWidth + 8, height: 12)
            let capBottom = CGRect(x: p.x - 4, y: bottom.minY, width: FlapEngine.pipeWidth + 8, height: 12)
            for cap in [capTop, capBottom] {
                ctx.fill(Path(roundedRect: cap, cornerRadius: 5), with: .color(Color(hex: 0x9BF7E4)))
            }
        }
        // Bird
        var bird = ctx
        bird.translateBy(x: FlapEngine.birdX, y: e.birdY)
        bird.rotate(by: .radians(e.tilt))
        let r = FlapEngine.birdRadius
        bird.glow(Color(hex: 0xFFB340), radius: 10) { layer in
            layer.fill(Path(ellipseIn: CGRect(x: -r - 1, y: -r, width: (r + 1) * 2, height: r * 2)),
                       with: layer.linear([Color(hex: 0xFFE07A), Color(hex: 0xFF8A3D)], from: CGPoint(x: 0, y: -r), to: CGPoint(x: 0, y: r)))
        }
        let flap = sin(t * (e.phase == .playing ? 26 : 8)) * 4
        bird.fill(Path(ellipseIn: CGRect(x: -7, y: -1 + flap * 0.5, width: 9, height: 6)), with: .color(Color(hex: 0xFFF3C4)))
        bird.fillCircle(CGPoint(x: 4, y: -3), radius: 3, with: .color(.white))
        bird.fillCircle(CGPoint(x: 5, y: -3), radius: 1.5, with: .color(.black))
        var beak = Path()
        beak.move(to: CGPoint(x: r - 1, y: -1))
        beak.addLine(to: CGPoint(x: r + 6, y: 1))
        beak.addLine(to: CGPoint(x: r - 1, y: 3))
        beak.closeSubpath()
        bird.fill(beak, with: .color(Color(hex: 0xFF5E3A)))

        drawParticles(e.particles.particles, in: ctx, palette: [.white.opacity(0.6), Color(hex: 0xFFB340)])

        let score = Text("\(e.score)").font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Color.white.opacity(0.85))
        ctx.draw(score, at: CGPoint(x: w / 2, y: 14), anchor: .top)
    }
}

// MARK: - Dodge

enum DodgeRenderer {
    static func draw(_ e: DodgeEngine, in ctx: GraphicsContext) {
        let w = DodgeEngine.width, h = DodgeEngine.height
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x05061A), Color(hex: 0x0E0B2A)], from: .zero, to: CGPoint(x: 0, y: h)))
        // Streaking stars
        var stars = Path()
        for i in 0..<60 {
            let speed = 20 + hash01(i, 11) * 90
            let x = hash01(i, 12) * w
            let y = (hash01(i, 13) * h + t * speed).truncatingRemainder(dividingBy: h)
            let len = speed / 30
            stars.move(to: CGPoint(x: x, y: y))
            stars.addLine(to: CGPoint(x: x, y: y + len))
        }
        ctx.stroke(stars, with: .color(.white.opacity(0.35)), lineWidth: 1)

        for rock in e.rocks {
            if rock.isGem {
                var gem = Path()
                let c = rock.position.point, r = rock.radius
                gem.move(to: CGPoint(x: c.x, y: c.y - r))
                gem.addLine(to: CGPoint(x: c.x + r * 0.8, y: c.y))
                gem.addLine(to: CGPoint(x: c.x, y: c.y + r))
                gem.addLine(to: CGPoint(x: c.x - r * 0.8, y: c.y))
                gem.closeSubpath()
                ctx.glow(Color(hex: 0x6EE7A0), radius: 10) { layer in
                    layer.fill(gem, with: .color(Color(hex: 0x9BF7C4)))
                }
            } else {
                var poly = Path()
                let sides = 8
                for k in 0..<sides {
                    let a = Double(k) / Double(sides) * 2 * .pi + rock.spin
                    let jitter = 0.78 + 0.22 * hash01(k, Int(rock.radius * 10))
                    let p = CGPoint(x: rock.position.x + cos(a) * rock.radius * jitter, y: rock.position.y + sin(a) * rock.radius * jitter)
                    if k == 0 { poly.move(to: p) } else { poly.addLine(to: p) }
                }
                poly.closeSubpath()
                ctx.glow(Color(hex: 0x8B5CFF).opacity(0.6), radius: 8) { layer in
                    layer.fill(poly, with: layer.linear([Color(hex: 0x8C83B8), Color(hex: 0x3B3566)], from: CGPoint(x: rock.position.x, y: rock.position.y - rock.radius), to: CGPoint(x: rock.position.x, y: rock.position.y + rock.radius)))
                }
            }
        }

        // Ship
        if e.phase != .over {
            let x = e.playerX, y = DodgeEngine.playerY
            var ship = Path()
            ship.move(to: CGPoint(x: x, y: y - 6))
            ship.addLine(to: CGPoint(x: x + 14, y: y + 10))
            ship.addLine(to: CGPoint(x: x, y: y + 6))
            ship.addLine(to: CGPoint(x: x - 14, y: y + 10))
            ship.closeSubpath()
            let flame = 6 + 4 * sin(t * 40)
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y + 7, width: 6, height: flame)), with: .color(Color(hex: 0xFFB340).opacity(0.8)))
            ctx.glow(Color(hex: 0x8AF2FF), radius: 10) { layer in
                layer.fill(ship, with: layer.linear([Color(hex: 0xC8F7FF), Color(hex: 0x5865F2)], from: CGPoint(x: x, y: y - 6), to: CGPoint(x: x, y: y + 10)))
            }
        }

        drawParticles(e.particles.particles, in: ctx, palette: [.white, Color(hex: 0x8AF2FF), Color(hex: 0x9BF7C4)])

        let time = Text(String(format: "%.1fs", e.survived)).font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Color.white.opacity(0.4))
        ctx.draw(time, at: CGPoint(x: w - 12, y: 12), anchor: .topTrailing)
    }
}

// MARK: - Bullseye

enum BullseyeRenderer {
    static func draw(_ e: BullseyeEngine, in ctx: GraphicsContext) {
        let w = 640.0, h = 240.0
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x2A0E1E), Color(hex: 0x0B0609)]), center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: 360))

        let track = CGRect(x: 60, y: 108, width: 520, height: 24)
        ctx.fill(Path(roundedRect: track, cornerRadius: 12), with: .color(.white.opacity(0.06)))
        ctx.stroke(Path(roundedRect: track, cornerRadius: 12), with: .color(.white.opacity(0.1)), lineWidth: 1)

        let zoneX = track.minX + track.width * (e.zoneCenter - e.zoneWidth / 2)
        let zone = CGRect(x: zoneX, y: track.minY, width: track.width * e.zoneWidth, height: track.height)
        ctx.glow(Color(hex: 0xFF2D78), radius: 12) { layer in
            layer.fill(Path(roundedRect: zone, cornerRadius: 8), with: layer.linear([Color(hex: 0xFF8A80), Color(hex: 0xFF2D78)], from: CGPoint(x: zone.minX, y: 0), to: CGPoint(x: zone.maxX, y: 0)))
        }
        let centerX = zone.midX
        let perfect = CGRect(x: centerX - zone.width * 0.14, y: track.minY + 3, width: zone.width * 0.28, height: track.height - 6)
        ctx.fill(Path(roundedRect: perfect, cornerRadius: 4), with: .color(.white.opacity(0.35)))

        // Needle
        let nx = track.minX + track.width * e.needle
        var needle = Path()
        needle.move(to: CGPoint(x: nx, y: track.minY - 16))
        needle.addLine(to: CGPoint(x: nx, y: track.maxY + 16))
        ctx.glow(.white, radius: 8) { layer in
            layer.stroke(needle, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        var tip = Path()
        tip.move(to: CGPoint(x: nx - 6, y: track.minY - 22))
        tip.addLine(to: CGPoint(x: nx + 6, y: track.minY - 22))
        tip.addLine(to: CGPoint(x: nx, y: track.minY - 14))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(.white))

        // Lives & streak
        for i in 0..<3 {
            let alive = i < e.lives
            ctx.fillCircle(CGPoint(x: 70 + Double(i) * 14, y: 40), radius: 4.5, with: .color(alive ? Color(hex: 0xFF8A80) : .white.opacity(0.12)))
        }
        if e.streak > 1 {
            let streak = Text("STREAK \(e.streak)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Color(hex: 0xFFB340))
            ctx.draw(streak, at: CGPoint(x: w - 70, y: 40), anchor: .trailing)
        }

        if let hit = e.lastHit, t - hit.at < 0.7 {
            let a = 1 - (t - hit.at) / 0.7
            let label = Text(hit.perfect ? "PERFECT" : "NICE").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle((hit.perfect ? Color(hex: 0xFFE07A) : Color.white).opacity(a))
            ctx.draw(label, at: CGPoint(x: w / 2, y: 70 - (1 - a) * 12), anchor: .center)
        }
        if let miss = e.lastMiss, t - miss < 0.5 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: 0xFF2D55).opacity(0.25 * (1 - (t - miss) / 0.5))))
        }
        let hits = Text("\(e.hits) HITS").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.35))
        ctx.draw(hits, at: CGPoint(x: w / 2, y: 190), anchor: .center)
    }
}

// MARK: - Echo

enum EchoRenderer {
    static let pads: [(offset: CGPoint, colors: [Color], symbol: String)] = [
        (CGPoint(x: 0, y: -62), [Color(hex: 0x8CF2B0), Color(hex: 0x2FBF6A)], "arrow.up"),
        (CGPoint(x: 92, y: 0), [Color(hex: 0x8BE0FF), Color(hex: 0x2F8FE8)], "arrow.right"),
        (CGPoint(x: 0, y: 62), [Color(hex: 0xFFE07A), Color(hex: 0xF0A020)], "arrow.down"),
        (CGPoint(x: -92, y: 0), [Color(hex: 0xFF9BB0), Color(hex: 0xE5245F)], "arrow.left"),
    ]

    static func draw(_ e: EchoEngine, in ctx: GraphicsContext) {
        let w = 640.0, h = 240.0
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x1A1430), Color(hex: 0x08070F)]), center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: 360))
        let center = CGPoint(x: w / 2, y: h / 2)

        for (i, pad) in pads.enumerated() {
            let lit = e.lit.map { $0.pad == i } ?? false
            let wrong = e.wrongPad == i && e.phase == .over
            let c = CGPoint(x: center.x + pad.offset.x, y: center.y + pad.offset.y)
            let size = lit ? 52.0 : 48.0
            let rect = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
            let colors = wrong ? [Color(hex: 0xFF453A), Color(hex: 0xB0141E)] : pad.colors
            if lit || wrong {
                ctx.glow(colors[0], radius: 18) { layer in
                    layer.fill(Path(roundedRect: rect, cornerRadius: 14), with: layer.linear(colors, from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY)))
                }
            } else {
                ctx.fill(Path(roundedRect: rect, cornerRadius: 14), with: .color(colors[1].opacity(0.22)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 14), with: .color(colors[0].opacity(0.35)), lineWidth: 1)
            }
            var arrow = ctx.resolve(Image(systemName: pad.symbol))
            arrow.shading = .color(lit || wrong ? .black.opacity(0.7) : colors[0].opacity(0.8))
            ctx.draw(arrow, in: rect.insetBy(dx: 15, dy: 15))
        }

        let status: String
        switch e.phase {
        case .ready: status = "Watch, then repeat"
        case .over: status = "Round \(e.sequence.count)"
        default:
            switch e.stage {
            case .showing: status = "Watch…"
            case .input: status = "Your turn · \(e.inputIndex)/\(e.sequence.count)"
            case .success: status = "Nice!"
            }
        }
        let label = Text(status.uppercased()).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.5))
        ctx.draw(label, at: CGPoint(x: 90, y: h / 2), anchor: .center)
        let round = Text("\(e.score)").font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Color.white.opacity(0.85))
        ctx.draw(round, at: CGPoint(x: w - 90, y: h / 2 - 6), anchor: .center)
        let caption = Text("ROUNDS").font(.system(size: 8.5, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.35))
        ctx.draw(caption, at: CGPoint(x: w - 90, y: h / 2 + 22), anchor: .center)
        _ = t
    }
}

// MARK: - Lander

enum LanderRenderer {
    static let padColors: [Int: Color] = [2: Color(hex: 0x7CF08A), 3: Color(hex: 0x6AD4FF), 5: Color(hex: 0xFFD93D)]
    static let hull = [Color(hex: 0xF4F6FF), Color(hex: 0xA9B4D6)]

    static func draw(_ e: LanderEngine, in ctx: GraphicsContext) {
        let w = LanderEngine.width, h = LanderEngine.height
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x04050C), Color(hex: 0x0D1026), Color(hex: 0x161433)], from: .zero, to: CGPoint(x: 0, y: h)))
        for (i, s) in e.stars.enumerated() {
            let a = 0.2 + 0.5 * hash01(i, 31)
            ctx.fill(Path(CGRect(x: s.x, y: s.y, width: 1.2, height: 1.2)), with: .color(.white.opacity(a)))
        }
        // A planet on the horizon
        let planet = CGRect(x: w - 150, y: 18, width: 70, height: 70)
        ctx.fill(Path(ellipseIn: planet), with: ctx.linear([Color(hex: 0x6AD4FF).opacity(0.5), Color(hex: 0x3478F6).opacity(0.15)], from: CGPoint(x: planet.minX, y: planet.minY), to: CGPoint(x: planet.maxX, y: planet.maxY)))
        ctx.fill(Path(ellipseIn: planet.offsetBy(dx: 12, dy: -6)), with: .color(Color(hex: 0x0D1026).opacity(0.85)))

        // Terrain
        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: h))
        for p in e.terrain { ground.addLine(to: p.point) }
        ground.addLine(to: CGPoint(x: w, y: h))
        ground.closeSubpath()
        ctx.fill(ground, with: ctx.linear([Color(hex: 0x2C3150), Color(hex: 0x10121D)], from: CGPoint(x: 0, y: 120), to: CGPoint(x: 0, y: h)))
        var ridge = Path()
        for (i, p) in e.terrain.enumerated() {
            if i == 0 { ridge.move(to: p.point) } else { ridge.addLine(to: p.point) }
        }
        ctx.glow(Color(hex: 0x9BB8FF).opacity(0.5), radius: 4) { layer in
            layer.stroke(ridge, with: .color(Color(hex: 0xC9D2FF).opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        }

        // Pads
        for pad in e.pads {
            let color = padColors[pad.multiplier] ?? .white
            ctx.glow(color, radius: 6) { layer in
                layer.fill(Path(roundedRect: CGRect(x: pad.x0, y: pad.y - 1.5, width: pad.x1 - pad.x0, height: 3), cornerRadius: 1.5), with: .color(color))
            }
            let blink = sin(t * 6) > 0
            for x in [pad.x0 + 2, pad.x1 - 2] {
                ctx.fillCircle(CGPoint(x: x, y: pad.y - 4), radius: 1.4, with: .color(color.opacity(blink ? 1 : 0.3)))
            }
            let label = Text("×\(pad.multiplier)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(color)
            ctx.draw(label, at: CGPoint(x: (pad.x0 + pad.x1) / 2, y: pad.y + 4), anchor: .top)
        }

        drawParticles(e.particles.particles, in: ctx, palette: [Color(hex: 0xFFB340), Color(hex: 0xFF6B3D)])

        // Lander
        if e.crashedAt == nil {
            var l = ctx
            l.translateBy(x: e.position.x, y: e.position.y)
            l.rotate(by: .radians(e.angle))
            if e.thrusting {
                let len = 9 + 5 * (0.5 + 0.5 * sin(t * 55))
                var f = Path()
                f.move(to: CGPoint(x: -3.5, y: 5))
                f.addLine(to: CGPoint(x: 0, y: 5 + len))
                f.addLine(to: CGPoint(x: 3.5, y: 5))
                f.closeSubpath()
                l.glow(Color(hex: 0xFF8A3D), radius: 8) { layer in
                    layer.fill(f, with: layer.linear([Color(hex: 0xFFF3C4), Color(hex: 0xFF8A3D)], from: CGPoint(x: 0, y: 5), to: CGPoint(x: 0, y: 5 + len)))
                }
            }
            var legs = Path()
            legs.move(to: CGPoint(x: -5, y: 3)); legs.addLine(to: CGPoint(x: -8, y: 8))
            legs.move(to: CGPoint(x: 5, y: 3)); legs.addLine(to: CGPoint(x: 8, y: 8))
            legs.move(to: CGPoint(x: -10, y: 8)); legs.addLine(to: CGPoint(x: -6, y: 8))
            legs.move(to: CGPoint(x: 6, y: 8)); legs.addLine(to: CGPoint(x: 10, y: 8))
            l.stroke(legs, with: .color(hull[1]), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            l.glow(.white.opacity(0.5), radius: 6) { layer in
                layer.fill(Path(roundedRect: CGRect(x: -7, y: -6, width: 14, height: 10), cornerRadius: 4), with: layer.linear(hull, from: CGPoint(x: 0, y: -6), to: CGPoint(x: 0, y: 4)))
            }
            l.fillCircle(CGPoint(x: 0, y: -1.5), radius: 2.6, with: .color(Color(hex: 0x3478F6)))
            l.fillCircle(CGPoint(x: -0.8, y: -2.3), radius: 0.9, with: .color(.white.opacity(0.8)))
        }

        // HUD
        panelLabel("Fuel", in: ctx, at: CGPoint(x: 12, y: 10))
        let fuel = e.fuel / 100
        ctx.fill(Path(roundedRect: CGRect(x: 40, y: 12, width: 80, height: 5), cornerRadius: 2.5), with: .color(.white.opacity(0.1)))
        ctx.fill(Path(roundedRect: CGRect(x: 40, y: 12, width: 80 * fuel, height: 5), cornerRadius: 2.5),
                 with: .color(fuel < 0.2 ? Color(hex: 0xFF6B6B) : Color(hex: 0xFFB340)))
        let vSafe = e.velocity.y < 26, hSafe = abs(e.velocity.x) < 16, aSafe = abs(e.angle) < 0.22
        let readouts: [(String, String, Bool)] = [
            ("V", "\(Int(e.velocity.y.rounded()))", vSafe), ("H", "\(Int(abs(e.velocity.x).rounded()))", hSafe), ("A", "\(Int((e.angle * 180 / .pi).rounded()))°", aSafe),
        ]
        for (i, r) in readouts.enumerated() {
            let x = 12 + Double(i) * 46
            let text = Text("\(r.0) \(r.1)").font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(r.2 ? Color(hex: 0x7CF08A) : Color(hex: 0xFF8A80))
            ctx.draw(text, at: CGPoint(x: x, y: 24), anchor: .topLeading)
        }
        let score = Text("\(e.score)").font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(Color.white.opacity(0.85))
        ctx.draw(score, at: CGPoint(x: w / 2, y: 10), anchor: .top)
        if let landed = e.landedAt {
            let a = min(1, (t - landed) * 4)
            let text = Text("TOUCHDOWN").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(Color(hex: 0x7CF08A).opacity(a))
            ctx.draw(text, at: CGPoint(x: w / 2, y: 80), anchor: .center)
        }
    }
}

// MARK: - Hop

enum HopRenderer {
    static let cars: [Color] = [Color(hex: 0xFF6B7A), Color(hex: 0xFFD93D), Color(hex: 0x5B9CFF), Color(hex: 0xC77DFF)]
    static let frog = [Color(hex: 0xC6FF8A), Color(hex: 0x34C759)]

    static func draw(_ e: HopEngine, in ctx: GraphicsContext) {
        let w = HopEngine.width
        let lane = HopEngine.lane
        let t = e.clock

        for row in 0..<HopEngine.rows {
            let y = Double(row) * lane
            let rect = CGRect(x: 0, y: y, width: w, height: lane)
            switch HopEngine.kind(of: row) {
            case .goal:
                ctx.fill(Path(rect), with: ctx.linear([Color(hex: 0x123B22), Color(hex: 0x0B2416)], from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + lane)))
                for (i, bx) in HopEngine.bays.enumerated() {
                    let bay = CGRect(x: bx - 18, y: y + 3, width: 36, height: lane - 3)
                    ctx.fill(Path(roundedRect: bay, cornerRadius: 7), with: .color(Color(hex: 0x0A1E3A)))
                    if e.filled[i] { drawFrog(at: CGPoint(x: bx, y: y + lane / 2 + 1), in: ctx, t: t, happy: true) }
                }
            case .river:
                ctx.fill(Path(rect), with: ctx.linear([Color(hex: 0x0C2D5C), Color(hex: 0x0A2247)], from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + lane)))
                var waves = Path()
                for k in 0..<12 {
                    let wx = (Double(k) * 58 + t * 14 * (row % 2 == 0 ? 1 : -1)).truncatingRemainder(dividingBy: w + 40)
                    let x = wx < -20 ? wx + w + 40 : wx
                    waves.move(to: CGPoint(x: x, y: y + 8 + Double(k % 2) * 8))
                    waves.addQuadCurve(to: CGPoint(x: x + 14, y: y + 8 + Double(k % 2) * 8), control: CGPoint(x: x + 7, y: y + 5 + Double(k % 2) * 8))
                }
                ctx.stroke(waves, with: .color(.white.opacity(0.1)), lineWidth: 1)
            case .road:
                ctx.fill(Path(rect), with: .color(Color(hex: 0x15151C)))
                if row < 8 {
                    var dash = Path()
                    var x = 6.0
                    while x < w {
                        dash.addRect(CGRect(x: x, y: y + lane - 1, width: 14, height: 1.4))
                        x += 30
                    }
                    ctx.fill(dash, with: .color(.white.opacity(0.18)))
                }
            case .safe:
                ctx.fill(Path(rect), with: ctx.linear([Color(hex: 0x2A2240), Color(hex: 0x1E1930)], from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + lane)))
                for k in 0..<40 {
                    let x = hash01(k, row * 7) * w
                    ctx.fill(Path(CGRect(x: x, y: y + 4 + hash01(k, row * 7 + 1) * (lane - 8), width: 2, height: 2)), with: .color(Color(hex: 0xC77DFF).opacity(0.18)))
                }
            }

            for mover in e.lanes[row].movers {
                let speed = e.lanes[row].speed
                switch HopEngine.kind(of: row) {
                case .river:
                    let log = CGRect(x: mover.x, y: y + 3, width: mover.width, height: lane - 6)
                    ctx.fill(Path(roundedRect: log, cornerRadius: 8), with: ctx.linear([Color(hex: 0xA0703F), Color(hex: 0x6B4423)], from: CGPoint(x: 0, y: log.minY), to: CGPoint(x: 0, y: log.maxY)))
                    var bark = Path()
                    var bx = log.minX + 12
                    while bx < log.maxX - 8 {
                        bark.move(to: CGPoint(x: bx, y: log.minY + 5)); bark.addLine(to: CGPoint(x: bx + 10, y: log.minY + 5))
                        bark.move(to: CGPoint(x: bx + 6, y: log.maxY - 5)); bark.addLine(to: CGPoint(x: bx + 16, y: log.maxY - 5))
                        bx += 26
                    }
                    ctx.stroke(bark, with: .color(Color(hex: 0x4A2E17).opacity(0.7)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    ctx.fill(Path(ellipseIn: CGRect(x: log.maxX - 9, y: log.minY + 2, width: 7, height: log.height - 4)), with: .color(Color(hex: 0xC99A66)))
                case .road:
                    let car = CGRect(x: mover.x, y: y + 4, width: mover.width, height: lane - 8)
                    let color = cars[mover.style % cars.count]
                    ctx.glow(color.opacity(0.5), radius: 5) { layer in
                        layer.fill(Path(roundedRect: car, cornerRadius: 5), with: layer.linear([mix(color, .white, 0.25), color], from: CGPoint(x: 0, y: car.minY), to: CGPoint(x: 0, y: car.maxY)))
                    }
                    let front = speed > 0 ? car.maxX : car.minX
                    let windowX = speed > 0 ? car.maxX - 14 : car.minX + 6
                    ctx.fill(Path(roundedRect: CGRect(x: windowX, y: car.minY + 3, width: 8, height: car.height - 6), cornerRadius: 2), with: .color(Color(hex: 0x0E1830).opacity(0.8)))
                    for dy in [car.minY + 3, car.maxY - 3] {
                        ctx.glow(Color(hex: 0xFFF3C4), radius: 4) { layer in
                            layer.fillCircle(CGPoint(x: front, y: dy), radius: 1.6, with: .color(Color(hex: 0xFFF3C4)))
                        }
                    }
                default:
                    break
                }
            }
        }

        // Frog (with a little hop arc)
        var fx = e.frogX, fy = Double(e.frogRow) * lane + lane / 2
        var lift = 0.0
        if let hop = e.hopFrom, t - hop.at < 0.12 {
            let p = (t - hop.at) / 0.12
            fx = hop.x + (fx - hop.x) * p
            let fromY = Double(hop.row) * lane + lane / 2
            fy = fromY + (fy - fromY) * p
            lift = sin(p * .pi) * 4
        }
        if let death = e.deathAt {
            if sin((t - death) * 30) > 0 {
                drawFrog(at: CGPoint(x: fx, y: fy), in: ctx, t: t, tint: Color(hex: 0xFF6B6B))
            }
        } else if e.phase != .over {
            drawFrog(at: CGPoint(x: fx, y: fy - lift), in: ctx, t: t, scale: 1 + lift * 0.04)
        }

        drawParticles(e.particles.particles, in: ctx, palette: [frog[1], Color(hex: 0xFF6B6B), Color(hex: 0xFFE07A)])

        // HUD in the start row
        let y = Double(HopEngine.rows - 1) * lane
        for i in 0..<max(0, e.lives) {
            drawFrog(at: CGPoint(x: 16 + Double(i) * 18, y: y + lane / 2), in: ctx, t: 0, scale: 0.55)
        }
        let frac = max(0, e.timeLeft / 30)
        ctx.fill(Path(roundedRect: CGRect(x: w - 130, y: y + 10, width: 100, height: 4), cornerRadius: 2), with: .color(.white.opacity(0.1)))
        ctx.fill(Path(roundedRect: CGRect(x: w - 130, y: y + 10, width: 100 * frac, height: 4), cornerRadius: 2),
                 with: .color(frac < 0.25 ? Color(hex: 0xFF6B6B) : frog[0]))
        let level = Text("L\(e.level)").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.4))
        ctx.draw(level, at: CGPoint(x: w - 12, y: y + lane / 2), anchor: .trailing)
    }

    static func drawFrog(at c: CGPoint, in ctx: GraphicsContext, t: Double, scale: Double = 1, tint: Color? = nil, happy: Bool = false) {
        var f = ctx
        f.translateBy(x: c.x, y: c.y)
        f.scaleBy(x: scale, y: scale)
        let body = tint.map { [$0, $0] } ?? frog
        // Legs
        var legs = Path()
        for s in [-1.0, 1.0] {
            legs.addEllipse(in: CGRect(x: s * 8 - 3, y: -7, width: 6, height: 5))
            legs.addEllipse(in: CGRect(x: s * 8 - 3, y: 3, width: 6, height: 5))
        }
        f.fill(legs, with: .color(body[1]))
        f.glow(body[1].opacity(0.6), radius: 5) { layer in
            layer.fill(Path(ellipseIn: CGRect(x: -7, y: -7, width: 14, height: 14)), with: layer.linear(body, from: CGPoint(x: 0, y: -7), to: CGPoint(x: 0, y: 7)))
        }
        for s in [-1.0, 1.0] {
            f.fillCircle(CGPoint(x: s * 3.6, y: -5), radius: 2.6, with: .color(.white))
            f.fillCircle(CGPoint(x: s * 3.6, y: happy ? -4.6 : -5.6), radius: 1.2, with: .color(.black))
        }
    }
}
