import NotcherCore
import SwiftUI

// MARK: - Miner

struct MinerView: View {
    let session: GameSession
    let engine: MinerEngine
    let revision: Int

    static let gold = [Color(hex: 0xFFE3A3), Color(hex: 0xD08C2E)]

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    _ = revision
                    MinerRenderer.draw(engine, in: ctx, size: size)
                }
                coinCounter
                    .padding(14)
                popups
            }
            .frame(width: 300)
            .contentShape(Rectangle())
            .onTapGesture { session.press(.primary, isRepeat: false) }

            upgrades
                .padding(.vertical, 12)
                .padding(.trailing, 12)
        }
        .overlay {
            if engine.offlineEarnings > 0.5 {
                offlineBanner
                    .transition(.opacity)
            }
        }
    }

    private var coinCounter: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: Self.gold, startPoint: .top, endPoint: .bottom))
                Text(Format.grouped(Int(engine.state.coins)))
                    .font(Theme.mono(20, .heavy))
                    .foregroundStyle(Theme.primary)
                    .contentTransition(.numericText())
            }
            Text(engine.rate > 0 ? "+\(Format.compact(engine.rate))/s · \(Format.compact(engine.coinsPerHit)) per hit" : "\(Format.compact(engine.coinsPerHit)) per hit — hire workers to dig while you work")
                .font(Theme.rounded(9.5, .semibold))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var popups: some View {
        ZStack {
            ForEach(engine.popups) { popup in
                Text("+\(Format.compact(popup.amount))")
                    .font(Theme.mono(13, .heavy))
                    .foregroundStyle(LinearGradient(colors: Self.gold, startPoint: .top, endPoint: .bottom))
                    .opacity(max(0, 1 - popup.age))
                    .offset(x: CGFloat((popup.id * 37) % 60) - 30, y: -popup.age * 50)
                    .position(x: 150, y: 96)
            }
        }
        .allowsHitTesting(false)
    }

    private var upgrades: some View {
        VStack(spacing: 6) {
            ForEach(MinerEngine.Upgrade.allCases, id: \.self) { upgrade in
                UpgradeRow(engine: engine, upgrade: upgrade, selected: engine.selected == upgrade) {
                    engine.select(upgrade)
                    session.press(.confirm, isRepeat: false)
                }
            }
        }
    }

    private var offlineBanner: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LinearGradient(colors: Self.gold, startPoint: .top, endPoint: .bottom))
            Text("Welcome back")
                .font(Theme.rounded(18, .heavy))
                .foregroundStyle(Theme.primary)
            Text("Your crew mined +\(Format.grouped(Int(engine.offlineEarnings))) coins while you were working.")
                .font(Theme.rounded(11.5, .medium))
                .foregroundStyle(Theme.secondary)
            HintLabel(keys: "space", action: "collect")
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.78))
        .onTapGesture { session.press(.primary, isRepeat: false) }
    }
}

struct UpgradeRow: View {
    let engine: MinerEngine
    let upgrade: MinerEngine.Upgrade
    let selected: Bool
    let buy: () -> Void

    var body: some View {
        let affordable = engine.canAfford(upgrade)
        let justBought = engine.lastPurchase.map { $0.upgrade == upgrade && engine.clock - $0.at < 0.4 } ?? false
        Button(action: buy) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: MinerView.gold, startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(upgrade.title)
                            .font(Theme.rounded(12, .bold))
                            .foregroundStyle(Theme.primary)
                        Text("Lv \(engine.level(of: upgrade))")
                            .font(Theme.mono(9.5, .bold))
                            .foregroundStyle(Theme.tertiary)
                    }
                    Text(upgrade.detail)
                        .font(Theme.rounded(9.5, .medium))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 4)
                Keycap(label: "\(upgrade.rawValue + 1)")
                HStack(spacing: 3) {
                    Image(systemName: "diamond.fill").font(.system(size: 8, weight: .bold))
                    Text(Format.compact(engine.cost(of: upgrade)))
                        .font(Theme.mono(11, .heavy))
                }
                .foregroundStyle(affordable ? Color.black : Theme.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(affordable ? AnyShapeStyle(LinearGradient(colors: MinerView.gold, startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.06))))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 47)
            .cardBackground(
                cornerRadius: 12,
                fill: justBought ? Color(hex: 0xFFCB45).opacity(0.25) : (selected ? Color.white.opacity(0.09) : Theme.surface),
                stroke: selected ? Color(hex: 0xFFCB45).opacity(0.6) : Theme.stroke
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: justBought)
    }

    private var symbol: String {
        switch upgrade {
        case .pickaxe: return "hammer.fill"
        case .workers: return "person.2.fill"
        case .speed: return "bolt.fill"
        case .storage: return "shippingbox.fill"
        }
    }
}

enum MinerRenderer {
    static func draw(_ e: MinerEngine, in ctx: GraphicsContext, size: CGSize) {
        let t = e.clock
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0x2A1E12), Color(hex: 0x0C0906)]), center: CGPoint(x: 150, y: 130), startRadius: 10, endRadius: 220))

        // Cave floor
        var floor = Path()
        floor.move(to: CGPoint(x: 0, y: 190))
        floor.addQuadCurve(to: CGPoint(x: size.width, y: 186), control: CGPoint(x: size.width / 2, y: 176))
        floor.addLine(to: CGPoint(x: size.width, y: size.height))
        floor.addLine(to: CGPoint(x: 0, y: size.height))
        floor.closeSubpath()
        ctx.fill(floor, with: .color(Color(hex: 0x17110B)))

        // The crystal rock, cracking as hits accumulate.
        let center = CGPoint(x: 150, y: 128)
        let hitPhase = Double(e.state.hits % MinerEngine.hitsPerGem) / Double(MinerEngine.hitsPerGem)
        let wobble = e.swing * 2.5 * sin(t * 60)
        var rock = Path()
        let points = 9
        for i in 0..<points {
            let a = Double(i) / Double(points) * 2 * .pi - .pi / 2
            let r = 52 + 9 * hash01(i, 5)
            let p = CGPoint(x: center.x + cos(a) * r + wobble, y: center.y + sin(a) * r * 0.82)
            if i == 0 { rock.move(to: p) } else { rock.addLine(to: p) }
        }
        rock.closeSubpath()
        ctx.glow(Color(hex: 0x8B5CFF).opacity(0.25 + 0.35 * hitPhase), radius: 18) { layer in
            layer.fill(rock, with: layer.linear([Color(hex: 0x4A3F5C), Color(hex: 0x231C2E)], from: CGPoint(x: center.x, y: center.y - 50), to: CGPoint(x: center.x, y: center.y + 50)))
        }
        // Embedded gems that glow brighter as the next gem bonus nears.
        let gemSpots = [CGPoint(x: -18, y: -12), CGPoint(x: 16, y: 6), CGPoint(x: -4, y: 22), CGPoint(x: 24, y: -22)]
        for (i, offset) in gemSpots.enumerated() {
            let c = CGPoint(x: center.x + offset.x + wobble, y: center.y + offset.y)
            var gem = Path()
            let r = 6.0 + Double(i % 2) * 2
            gem.move(to: CGPoint(x: c.x, y: c.y - r))
            gem.addLine(to: CGPoint(x: c.x + r * 0.75, y: c.y))
            gem.addLine(to: CGPoint(x: c.x, y: c.y + r))
            gem.addLine(to: CGPoint(x: c.x - r * 0.75, y: c.y))
            gem.closeSubpath()
            let colors = i % 2 == 0 ? [Color(hex: 0xC6A8FF), Color(hex: 0x7A4CF0)] : [Color(hex: 0x8BE9FF), Color(hex: 0x2F8FE8)]
            ctx.glow(colors[0].opacity(0.4 + 0.6 * hitPhase), radius: 6 + 8 * hitPhase) { layer in
                layer.fill(gem, with: layer.linear(colors, from: CGPoint(x: c.x, y: c.y - r), to: CGPoint(x: c.x, y: c.y + r)))
            }
        }
        // Cracks
        if hitPhase > 0 {
            var cracks = Path()
            let count = Int(hitPhase * 6) + 1
            for i in 0..<count {
                let a = Double(i) * 1.7 + 0.4
                cracks.move(to: CGPoint(x: center.x + wobble, y: center.y))
                cracks.addLine(to: CGPoint(x: center.x + cos(a) * 22 + wobble, y: center.y + sin(a) * 18))
                cracks.addLine(to: CGPoint(x: center.x + cos(a + 0.3) * 44 + wobble, y: center.y + sin(a + 0.3) * 34))
            }
            ctx.stroke(cracks, with: .color(Color.black.opacity(0.45)), lineWidth: 1.4)
        }

        // Pickaxe swinging into the rock.
        var pick = ctx
        let swingAngle = -0.9 + 0.9 * (1 - e.swing)
        pick.translateBy(x: 228, y: 92)
        pick.rotate(by: .radians(-swingAngle))
        pick.fill(Path(roundedRect: CGRect(x: -3, y: -4, width: 6, height: 62), cornerRadius: 3), with: .color(Color(hex: 0x8A5A2B)))
        var head = Path()
        head.move(to: CGPoint(x: -30, y: 6))
        head.addQuadCurve(to: CGPoint(x: 30, y: 6), control: CGPoint(x: 0, y: -16))
        head.addQuadCurve(to: CGPoint(x: -30, y: 6), control: CGPoint(x: 0, y: -6))
        pick.fill(head, with: pick.linear([Color(hex: 0xE5E7EB), Color(hex: 0x9CA3AF)], from: CGPoint(x: 0, y: -10), to: CGPoint(x: 0, y: 6)))

        // Worker carts trundling along the floor.
        let workers = min(6, e.state.workers)
        for i in 0..<workers {
            let x = (t * 30 + Double(i) * 55).truncatingRemainder(dividingBy: size.width + 40) - 20
            let cart = CGRect(x: x, y: 190, width: 18, height: 10)
            ctx.fill(Path(roundedRect: cart, cornerRadius: 2), with: .color(Color(hex: 0x6B4A2A)))
            ctx.fillCircle(CGPoint(x: cart.minX + 4, y: cart.maxY + 1), radius: 2.5, with: .color(Color(hex: 0x3A2A1A)))
            ctx.fillCircle(CGPoint(x: cart.maxX - 4, y: cart.maxY + 1), radius: 2.5, with: .color(Color(hex: 0x3A2A1A)))
            ctx.fillCircle(CGPoint(x: cart.midX, y: cart.minY), radius: 4, with: .color(Color(hex: 0xFFCB45).opacity(0.9)))
        }

        drawParticles(e.particles.particles, in: ctx, palette: [Color(hex: 0xB8A98F), Color(hex: 0xC6A8FF)])

        let hint = Text("space to mine").font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.32))
        ctx.draw(hint, at: CGPoint(x: 150, y: size.height - 10), anchor: .bottom)
    }
}

// MARK: - Farm

struct FarmView: View {
    let session: GameSession
    let engine: FarmEngine
    let revision: Int

    static let plot = CGSize(width: 104, height: 96)

    var body: some View {
        let now = engine.now
        HStack(spacing: 14) {
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<FarmEngine.columns, id: \.self) { col in
                            let index = row * FarmEngine.columns + col
                            PlotView(engine: engine, index: index, now: now)
                                .onTapGesture {
                                    engine.setCursor(index)
                                    session.press(.confirm, isRepeat: false)
                                }
                        }
                    }
                }
            }
            seedPicker
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x0E1A10), Color(hex: 0x070B07)], startPoint: .top, endPoint: .bottom)
        )
    }

    private var seedPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("SEEDS")
                    .font(Theme.rounded(8.5, .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Keycap(label: "tab")
            }
            ForEach(Crop.allCases, id: \.self) { crop in
                let selected = engine.crop == crop
                Button {
                    session.press(.number(crop.rawValue + 1), isRepeat: false)
                } label: {
                    HStack(spacing: 6) {
                        CropGlyph(crop: crop, stage: 3)
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(crop.title)
                                .font(Theme.rounded(10.5, .bold))
                                .foregroundStyle(selected ? Theme.primary : Theme.primary.opacity(0.75))
                            Text("\(crop.seedCost) → \(crop.sellPrice) · \(Self.duration(crop.growSeconds))")
                                .font(Theme.mono(8.5, .semibold))
                                .foregroundStyle(Theme.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 33)
                    .cardBackground(cornerRadius: 9, fill: selected ? Color(hex: 0x34C759).opacity(0.18) : Theme.surface,
                                    stroke: selected ? Color(hex: 0x7BE07B).opacity(0.6) : Theme.stroke)
                    .opacity(engine.state.coins >= crop.seedCost ? 1 : 0.5)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 150)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 { return "\(s / 3600)h" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }
}

struct PlotView: View {
    let engine: FarmEngine
    let index: Int
    let now: Date

    var body: some View {
        let plot = engine.state.plots[index]
        let unlocked = index < engine.state.unlocked
        let selected = engine.cursor == index
        let growth = plot.growth(at: now)
        let ready = plot.isReady(at: now)
        let bounce = engine.lastAction.map { $0.plot == index && engine.clock - $0.at < 0.3 } ?? false

        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(unlocked ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4A3424), Color(hex: 0x2C1F15)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.03)))
            if unlocked {
                // Furrows
                VStack(spacing: 9) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.18)).frame(height: 2.5)
                    }
                }
                .padding(.horizontal, 14)

                if let crop = plot.crop, let growth {
                    CropGlyph(crop: crop, stage: ready ? 3 : min(2, Int(growth * 3)))
                        .frame(width: 48, height: 48)
                        .scaleEffect(ready ? 1 + 0.05 * sin(engine.clock * 5) : 1)
                        .shadow(color: ready ? Color(hex: 0xFFE07A).opacity(0.6) : .clear, radius: 10)
                        .offset(y: -6)
                    VStack {
                        Spacer()
                        if ready {
                            Text("READY")
                                .font(Theme.rounded(8.5, .heavy))
                                .tracking(1)
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: 0xFFE07A)))
                        } else {
                            VStack(spacing: 2) {
                                Text(Self.remaining(plot.secondsLeft(at: now)))
                                    .font(Theme.mono(8.5, .bold))
                                    .foregroundStyle(Theme.secondary)
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.black.opacity(0.35))
                                        Capsule().fill(Color(hex: 0x7BE07B)).frame(width: proxy.size.width * growth)
                                    }
                                }
                                .frame(height: 3)
                                .padding(.horizontal, 18)
                            }
                        }
                    }
                    .padding(.bottom, 7)
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Plant \(engine.crop.title)")
                            .font(Theme.rounded(8.5, .bold))
                    }
                    .foregroundStyle(Color.white.opacity(selected ? 0.6 : 0.25))
                }
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(index == engine.state.unlocked ? "\(FarmEngine.unlockCost(forPlot: index)) coins" : "Locked")
                        .font(Theme.mono(9, .bold))
                }
                .foregroundStyle(Color.white.opacity(index == engine.state.unlocked ? 0.55 : 0.22))
            }

            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(hex: 0x9BEA7C), lineWidth: 2)
                    .shadow(color: Color(hex: 0x9BEA7C).opacity(0.6), radius: 6)
            }
        }
        .frame(width: FarmView.plot.width, height: FarmView.plot.height)
        .scaleEffect(bounce ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bounce)
        .contentShape(Rectangle())
    }

    static func remaining(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Little vector crops, drawn per growth stage 0…3.
struct CropGlyph: View {
    let crop: Crop
    let stage: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let stem = Color(hex: 0x5FD068)
            let base = CGPoint(x: w / 2, y: h * 0.92)
            if stage == 0 {
                ctx.fillCircle(CGPoint(x: base.x, y: base.y - h * 0.06), radius: w * 0.07, with: .color(Color(hex: 0xC8A27A)))
                return
            }
            let height = h * (stage == 1 ? 0.3 : (stage == 2 ? 0.55 : 0.72))
            var stalk = Path()
            stalk.move(to: base)
            stalk.addLine(to: CGPoint(x: base.x, y: base.y - height))
            ctx.stroke(stalk, with: .color(stem), style: StrokeStyle(lineWidth: max(1.5, w * 0.05), lineCap: .round))
            for side in [-1.0, 1.0] {
                var leaf = Path()
                let y = base.y - height * 0.45
                leaf.move(to: CGPoint(x: base.x, y: y))
                leaf.addQuadCurve(to: CGPoint(x: base.x + side * w * 0.26, y: y - h * 0.12), control: CGPoint(x: base.x + side * w * 0.2, y: y + h * 0.04))
                leaf.addQuadCurve(to: CGPoint(x: base.x, y: y), control: CGPoint(x: base.x + side * w * 0.06, y: y - h * 0.14))
                ctx.fill(leaf, with: .color(stem))
            }
            guard stage >= 3 else { return }
            let top = CGPoint(x: base.x, y: base.y - height)
            switch crop {
            case .wheat:
                for i in 0..<5 {
                    let y = top.y + Double(i) * h * 0.06
                    for side in [-1.0, 1.0] {
                        ctx.fill(Path(ellipseIn: CGRect(x: top.x + side * w * 0.06 - w * 0.05, y: y, width: w * 0.1, height: h * 0.07)), with: .color(Color(hex: 0xF5C451)))
                    }
                }
            case .carrot:
                var carrot = Path()
                carrot.move(to: CGPoint(x: top.x - w * 0.14, y: top.y + h * 0.12))
                carrot.addLine(to: CGPoint(x: top.x + w * 0.14, y: top.y + h * 0.12))
                carrot.addLine(to: CGPoint(x: top.x, y: top.y + h * 0.5))
                carrot.closeSubpath()
                ctx.fill(carrot, with: .color(Color(hex: 0xFF8A3D)))
            case .tomato:
                for (dx, dy) in [(-0.14, 0.08), (0.14, 0.12), (0.0, 0.24)] {
                    ctx.fillCircle(CGPoint(x: top.x + w * dx, y: top.y + h * dy), radius: w * 0.12, with: .color(Color(hex: 0xFF4D4D)))
                }
            case .pumpkin:
                let c = CGPoint(x: top.x, y: base.y - h * 0.2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.32, y: c.y - h * 0.18, width: w * 0.64, height: h * 0.36)), with: .color(Color(hex: 0xFF9F0A)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - w * 0.12, y: c.y - h * 0.18, width: w * 0.24, height: h * 0.36)), with: .color(Color(hex: 0xD9730A)), lineWidth: 1.2)
            case .starfruit:
                var star = Path()
                for i in 0..<10 {
                    let a = Double(i) * .pi / 5 - .pi / 2
                    let r = i % 2 == 0 ? w * 0.24 : w * 0.1
                    let p = CGPoint(x: top.x + cos(a) * r, y: top.y + h * 0.08 + sin(a) * r)
                    if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
                }
                star.closeSubpath()
                ctx.glow(Color(hex: 0xFFE07A), radius: 6) { layer in
                    layer.fill(star, with: .color(Color(hex: 0xFFE07A)))
                }
            }
        }
    }
}
