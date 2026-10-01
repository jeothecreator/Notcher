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
            default: break
            }
        }
    }
}

/// Pills for the four mini games; Tab cycles.
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
