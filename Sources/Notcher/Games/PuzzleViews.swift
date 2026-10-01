import NotcherCore
import SwiftUI

// MARK: - Stack

struct StackView: View {
    let engine: StackEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(StackRenderer.logical, in: size)
            StackRenderer.draw(engine, in: ctx)
        }
    }
}

enum StackRenderer {
    static let logical = CGSize(width: 640, height: 300)
    static let cell: CGFloat = 13.5
    static var origin: CGPoint {
        CGPoint(x: (logical.width - CGFloat(StackEngine.columns) * cell) / 2, y: 15)
    }

    /// i, o, t, s, z, j, l
    static let colors: [Color] = [
        Color(hex: 0x5EEAFF), Color(hex: 0xFFE066), Color(hex: 0xC77DFF), Color(hex: 0x7CF08A),
        Color(hex: 0xFF6B7A), Color(hex: 0x5B8CFF), Color(hex: 0xFFA94D),
    ]

    static func color(_ kind: StackEngine.Kind) -> Color { colors[kind.rawValue % colors.count] }

    static func drawBlock(_ rect: CGRect, color: Color, in ctx: GraphicsContext, alpha: Double = 1) {
        let r = rect.insetBy(dx: 0.6, dy: 0.6)
        let corner = r.width * 0.2
        ctx.fill(Path(roundedRect: r, cornerRadius: corner),
                 with: ctx.linear([mix(color, .white, 0.35).opacity(alpha), color.opacity(alpha), mix(color, .black, 0.25).opacity(alpha)],
                                  from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY)))
        ctx.fill(Path(roundedRect: CGRect(x: r.minX + 2, y: r.minY + 1.6, width: r.width - 4, height: 1.6), cornerRadius: 0.8),
                 with: .color(.white.opacity(0.45 * alpha)))
    }

    /// A piece centred on a point, for the hold and next panels.
    static func drawMini(_ kind: StackEngine.Kind, center: CGPoint, cell: CGFloat, in ctx: GraphicsContext, alpha: Double = 1) {
        let cells = kind.cells(rotation: 0)
        let minX = cells.map(\.x).min() ?? 0, maxX = cells.map(\.x).max() ?? 0
        let minY = cells.map(\.y).min() ?? 0, maxY = cells.map(\.y).max() ?? 0
        let w = CGFloat(maxX - minX + 1) * cell, h = CGFloat(maxY - minY + 1) * cell
        for c in cells {
            let rect = CGRect(x: center.x - w / 2 + CGFloat(c.x - minX) * cell, y: center.y - h / 2 + CGFloat(c.y - minY) * cell, width: cell, height: cell)
            drawBlock(rect, color: color(kind), in: ctx, alpha: alpha)
        }
    }

    static func draw(_ e: StackEngine, in ctx: GraphicsContext) {
        let w = logical.width, h = logical.height
        let t = e.clock
        let o = origin
        let cols = StackEngine.columns, rows = StackEngine.visibleRows, hidden = StackEngine.hiddenRows
        let well = CGRect(x: o.x, y: o.y, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x0A0B18), Color(hex: 0x0E0A22)], from: .zero, to: CGPoint(x: 0, y: h)))
        for i in 0..<40 {
            let x = hash01(i, 21) * w, y = hash01(i, 22) * h
            ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.08 + 0.15 * hash01(i, 23))))
        }

        // Danger when the stack nears the top.
        let danger = e.board.prefix(hidden + 4).contains { row in row.contains { $0 != nil } }
        let levelColor = colors[(e.level - 1) % colors.count]
        let border = danger ? Color(hex: 0xFF453A) : levelColor
        ctx.glow(border.opacity(danger ? 0.5 + 0.3 * sin(t * 8) : 0.35), radius: 10) { layer in
            layer.fill(Path(roundedRect: well.insetBy(dx: -4, dy: -4), cornerRadius: 8), with: .color(Color(hex: 0x07070F)))
        }
        ctx.stroke(Path(roundedRect: well.insetBy(dx: -4, dy: -4), cornerRadius: 8), with: .color(border.opacity(danger ? 0.6 : 0.22)), lineWidth: 1)
        var grid = Path()
        for c in 1..<cols {
            grid.move(to: CGPoint(x: well.minX + CGFloat(c) * cell, y: well.minY))
            grid.addLine(to: CGPoint(x: well.minX + CGFloat(c) * cell, y: well.maxY))
        }
        for r in 1..<rows {
            grid.move(to: CGPoint(x: well.minX, y: well.minY + CGFloat(r) * cell))
            grid.addLine(to: CGPoint(x: well.maxX, y: well.minY + CGFloat(r) * cell))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.035)), lineWidth: 0.5)

        func rect(_ x: Int, _ row: Int) -> CGRect {
            CGRect(x: well.minX + CGFloat(x) * cell, y: well.minY + CGFloat(row - hidden) * cell, width: cell, height: cell)
        }

        // Locked cells
        let clearing = Set(e.clearingRows)
        for row in hidden..<(hidden + rows) {
            for x in 0..<cols {
                guard let kind = e.board[row][x] else { continue }
                var r = rect(x, row)
                if clearing.contains(row) {
                    let p = e.clearProgress
                    r = r.insetBy(dx: r.width * 0.5 * p, dy: r.height * 0.2 * p)
                    drawBlock(r, color: mix(color(kind), .white, min(1, p * 2.5)), in: ctx, alpha: 1 - p * 0.6)
                } else {
                    drawBlock(r, color: color(kind), in: ctx)
                }
            }
        }
        if !clearing.isEmpty {
            for row in clearing where row >= hidden {
                let r = rect(0, row)
                ctx.glow(.white, radius: 12) { layer in
                    layer.fill(Path(CGRect(x: well.minX, y: r.minY, width: well.width, height: cell)), with: .color(.white.opacity(0.6 * (1 - e.clearProgress))))
                }
            }
        }

        // Ghost and active piece
        if let ghost = e.ghost, let current = e.current, e.phase == .playing {
            let c = color(current.kind)
            for cell in ghost.cells where cell.y >= hidden {
                let r = rect(cell.x, cell.y).insetBy(dx: 1, dy: 1)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(c.opacity(0.08)))
                ctx.stroke(Path(roundedRect: r, cornerRadius: 2.5), with: .color(c.opacity(0.45)), lineWidth: 1)
            }
        }
        if let current = e.current {
            let c = color(current.kind)
            ctx.glow(c.opacity(0.7), radius: 8) { layer in
                for cell in current.cells where cell.y >= hidden {
                    drawBlock(rect(cell.x, cell.y), color: c, in: layer)
                }
            }
        }
        if let lock = e.lastLock, t - lock.at < 0.22 {
            let a = 1 - (t - lock.at) / 0.22
            for cell in lock.cells where cell.y >= hidden {
                ctx.fill(Path(roundedRect: rect(cell.x, cell.y).insetBy(dx: 0.6, dy: 0.6), cornerRadius: 2.5), with: .color(.white.opacity(0.55 * a)))
            }
        }

        var particleLayer = ctx
        particleLayer.translateBy(x: well.minX, y: well.minY)
        drawParticles(e.particles.particles, in: particleLayer, palette: colors, scale: cell)

        // Hold
        let leftX = well.minX - 112
        let holdBox = CGRect(x: leftX, y: o.y, width: 88, height: 62)
        ctx.fill(Path(roundedRect: holdBox, cornerRadius: 10), with: .color(.white.opacity(0.04)))
        ctx.stroke(Path(roundedRect: holdBox, cornerRadius: 10), with: .color(.white.opacity(0.07)), lineWidth: 0.75)
        panelLabel("Hold", in: ctx, at: CGPoint(x: holdBox.minX + 10, y: holdBox.minY + 8))
        if let held = e.held {
            drawMini(held, center: CGPoint(x: holdBox.midX, y: holdBox.midY + 7), cell: 11, in: ctx, alpha: e.holdUsed ? 0.35 : 1)
        } else {
            let k = Text("C").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Color.white.opacity(0.18))
            ctx.draw(k, at: CGPoint(x: holdBox.midX, y: holdBox.midY + 7), anchor: .center)
        }

        // Stats
        panelLabel("Level", in: ctx, at: CGPoint(x: leftX + 2, y: o.y + 84))
        panelValue("\(e.level)", in: ctx, at: CGPoint(x: leftX + 2, y: o.y + 96), size: 22, color: levelColor)
        panelLabel("Lines", in: ctx, at: CGPoint(x: leftX + 2, y: o.y + 134))
        panelValue("\(e.lines)", in: ctx, at: CGPoint(x: leftX + 2, y: o.y + 146), size: 22)
        // Progress to next level
        let toNext = Double(e.lines % 10) / 10
        ctx.fill(Path(roundedRect: CGRect(x: leftX + 2, y: o.y + 176, width: 84, height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.08)))
        ctx.fill(Path(roundedRect: CGRect(x: leftX + 2, y: o.y + 176, width: 84 * toNext, height: 3), cornerRadius: 1.5), with: .color(levelColor.opacity(0.8)))
        if e.tetrises > 0 {
            panelLabel("Stacks", in: ctx, at: CGPoint(x: leftX + 2, y: o.y + 196))
            panelValue("\(e.tetrises)", in: ctx, at: CGPoint(x: leftX + 2, y: o.y + 208), size: 16, color: colors[0])
        }

        // Next queue
        let rightX = well.maxX + 24
        let nextBox = CGRect(x: rightX, y: o.y, width: 88, height: 206)
        ctx.fill(Path(roundedRect: nextBox, cornerRadius: 10), with: .color(.white.opacity(0.04)))
        ctx.stroke(Path(roundedRect: nextBox, cornerRadius: 10), with: .color(.white.opacity(0.07)), lineWidth: 0.75)
        panelLabel("Next", in: ctx, at: CGPoint(x: nextBox.minX + 10, y: nextBox.minY + 8))
        for (i, kind) in e.next.prefix(4).enumerated() {
            let first = i == 0
            let y = nextBox.minY + (first ? 46 : 92 + CGFloat(i - 1) * 40)
            drawMini(kind, center: CGPoint(x: nextBox.midX, y: y), cell: first ? 13 : 9.5, in: ctx, alpha: first ? 1 : 0.75)
        }

        // Clear banner
        if let banner = e.banner {
            let age = t - banner.at
            let a = max(0, min(1, (1.4 - age) * 2.5))
            let pop = 1 + 0.25 * max(0, 1 - age * 6)
            var b = ctx
            b.translateBy(x: well.midX, y: well.minY + 92)
            b.scaleBy(x: pop, y: pop)
            let text = Text(banner.text).font(.system(size: 17, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(a))
            b.glow(levelColor.opacity(a), radius: 10) { layer in
                layer.draw(text, at: .zero, anchor: .center)
            }
        }
    }
}

// MARK: - Gems

struct GemsView: View {
    let session: GameSession
    let engine: GemsEngine
    let revision: Int
    @Environment(\.previewRendering) private var previewRendering
    @State private var dragHandled = false

    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                _ = revision
                ctx.fit(GemsRenderer.logical, in: size)
                GemsRenderer.draw(engine, in: ctx)
            }
            .overlay(previewRendering ? nil : ClickCatcher(
                onClick: { point, _ in
                    dragHandled = false
                    if engine.phase == .over {
                        session.press(.primary, isRepeat: false)
                        return
                    }
                    if let cell = GemsRenderer.cell(at: SceneMapping(logical: GemsRenderer.logical, size: proxy.size).point(point)) {
                        engine.select(cell)
                    }
                },
                onMove: nil,
                onDrag: { start, current in
                    guard !dragHandled else { return }
                    let map = SceneMapping(logical: GemsRenderer.logical, size: proxy.size)
                    let a = map.point(start), b = map.point(current)
                    let dx = b.x - a.x, dy = b.y - a.y
                    guard max(abs(dx), abs(dy)) > GemsRenderer.cell * 0.45, let cell = GemsRenderer.cell(at: a) else { return }
                    dragHandled = true
                    let dir: Direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    engine.swipe(from: cell, dir)
                }
            ))
        }
    }
}

enum GemsRenderer {
    static let logical = CGSize(width: 640, height: 240)
    static let cell: CGFloat = 27
    static var origin: CGPoint {
        CGPoint(x: (logical.width - CGFloat(GemsEngine.size) * cell) / 2, y: (logical.height - CGFloat(GemsEngine.size) * cell) / 2)
    }

    static let palette: [[Color]] = [
        [Color(hex: 0xFFB3BE), Color(hex: 0xFF4D6A), Color(hex: 0xB0153A)],
        [Color(hex: 0xFFD9A8), Color(hex: 0xFF9A3D), Color(hex: 0xC2560F)],
        [Color(hex: 0xFFF6B0), Color(hex: 0xFFD93D), Color(hex: 0xC99A00)],
        [Color(hex: 0xC2FFD8), Color(hex: 0x3EE08F), Color(hex: 0x0E8A53)],
        [Color(hex: 0xC5DBFF), Color(hex: 0x4D8DFF), Color(hex: 0x1D4FC4)],
        [Color(hex: 0xEBCBFF), Color(hex: 0xB45CFF), Color(hex: 0x6A1FC2)],
        [Color.white, Color(hex: 0xFFE3F8), Color(hex: 0xA5F3FC)],
    ]

    static func cell(at p: CGPoint) -> GridPoint? {
        let o = origin
        let x = Int(floor((p.x - o.x) / cell)), y = Int(floor((p.y - o.y) / cell))
        guard x >= 0, y >= 0, x < GemsEngine.size, y < GemsEngine.size else { return nil }
        return GridPoint(x, y)
    }

    static func shape(_ kind: Int, in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let s = r.width / 2
        func poly(_ n: Int, rotation: Double, radius: Double) {
            for i in 0..<n {
                let a = rotation + Double(i) / Double(n) * 2 * .pi
                let pt = CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        switch kind {
        case 0: p.addEllipse(in: r.insetBy(dx: s * 0.08, dy: s * 0.08))
        case 1: poly(6, rotation: .pi / 6, radius: s * 0.95)
        case 2: poly(3, rotation: -.pi / 2, radius: s * 1.05)
        case 3: p.addRoundedRect(in: r.insetBy(dx: s * 0.14, dy: s * 0.14), cornerSize: CGSize(width: s * 0.28, height: s * 0.28))
        case 4: poly(4, rotation: -.pi / 2, radius: s * 1.0)
        case 5: poly(5, rotation: -.pi / 2, radius: s * 0.98)
        default:
            for i in 0..<16 {
                let a = -CGFloat.pi / 2 + CGFloat(i) / 16 * 2 * .pi
                let radius = i % 2 == 0 ? s * 1.02 : s * 0.48
                let pt = CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        return p
    }

    static func drawGem(_ g: GemsEngine.Gem, in r: CGRect, ctx: GraphicsContext, t: Double) {
        let colors = palette[min(g.kind, palette.count - 1)]
        let path = shape(g.kind, in: r)
        let glowColor = g.kind == GemsEngine.starKind ? Color(hex: 0xFFB3F0) : colors[1]
        let special = g.special != .none
        ctx.glow(glowColor.opacity(special ? 0.9 : 0.4), radius: special ? 8 : 4) { layer in
            if g.kind == GemsEngine.starKind {
                let hue = t.truncatingRemainder(dividingBy: 3) / 3
                layer.fill(path, with: .conicGradient(
                    Gradient(colors: [Color(hex: 0xFF8AC2), Color(hex: 0xFFE07A), Color(hex: 0x7CFFCB), Color(hex: 0x8AB4FF), Color(hex: 0xFF8AC2)]),
                    center: CGPoint(x: r.midX, y: r.midY), angle: .radians(hue * 2 * .pi)
                ))
            } else {
                layer.fill(path, with: layer.linear([colors[0], colors[1], colors[2]], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY)))
            }
        }
        // Facet highlight and sparkle
        let inner = shape(g.kind, in: r.insetBy(dx: r.width * 0.28, dy: r.height * 0.28)).offsetBy(dx: -r.width * 0.06, dy: -r.height * 0.06)
        ctx.fill(inner, with: .color(.white.opacity(0.28)))
        ctx.fillCircle(CGPoint(x: r.minX + r.width * 0.32, y: r.minY + r.height * 0.3), radius: r.width * 0.06, with: .color(.white.opacity(0.9)))

        switch g.special {
        case .row, .column:
            var stripes = Path()
            for k in -1...1 {
                let off = CGFloat(k) * r.width * 0.18
                if g.special == .row {
                    stripes.move(to: CGPoint(x: r.minX + 3, y: r.midY + off)); stripes.addLine(to: CGPoint(x: r.maxX - 3, y: r.midY + off))
                } else {
                    stripes.move(to: CGPoint(x: r.midX + off, y: r.minY + 3)); stripes.addLine(to: CGPoint(x: r.midX + off, y: r.maxY - 3))
                }
            }
            var clipped = ctx
            clipped.clip(to: path)
            clipped.stroke(stripes, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        case .bomb:
            let pulse = 0.5 + 0.5 * sin(t * 7)
            ctx.stroke(Path(ellipseIn: r.insetBy(dx: -1.5, dy: -1.5)), with: .color(.white.opacity(0.4 + 0.5 * pulse)), lineWidth: 1.4)
            ctx.fillCircle(CGPoint(x: r.midX, y: r.midY), radius: r.width * 0.12, with: .color(.white.opacity(0.9)))
        case .star, .none:
            break
        }
    }

    static func draw(_ e: GemsEngine, in ctx: GraphicsContext) {
        let w = logical.width, h = logical.height
        let t = e.clock
        let o = origin
        let n = GemsEngine.size
        let board = CGRect(x: o.x, y: o.y, width: CGFloat(n) * cell, height: CGFloat(n) * cell)

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x0A1512), Color(hex: 0x0B0C1A)], from: .zero, to: CGPoint(x: w, y: h)))
        ctx.fill(Path(roundedRect: board.insetBy(dx: -6, dy: -6), cornerRadius: 12), with: .color(.black.opacity(0.35)))
        ctx.stroke(Path(roundedRect: board.insetBy(dx: -6, dy: -6), cornerRadius: 12), with: .color(.white.opacity(0.07)), lineWidth: 0.75)
        for y in 0..<n {
            for x in 0..<n where (x + y) % 2 == 0 {
                ctx.fill(Path(roundedRect: CGRect(x: board.minX + CGFloat(x) * cell, y: board.minY + CGFloat(y) * cell, width: cell, height: cell), cornerRadius: 4),
                         with: .color(.white.opacity(0.03)))
            }
        }

        // Hint pulse
        if let hint = e.hint, e.selected == nil {
            let a = 0.25 + 0.25 * sin(t * 5)
            for p in [hint.0, hint.1] {
                let r = CGRect(x: board.minX + CGFloat(p.x) * cell, y: board.minY + CGFloat(p.y) * cell, width: cell, height: cell).insetBy(dx: 1, dy: 1)
                ctx.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(.white.opacity(a)), lineWidth: 1.2)
            }
        }

        // Selection & cursor
        if let s = e.selected {
            let r = CGRect(x: board.minX + CGFloat(s.x) * cell, y: board.minY + CGFloat(s.y) * cell, width: cell, height: cell).insetBy(dx: 0.5, dy: 0.5)
            ctx.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(0.14)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(0.7 + 0.3 * sin(t * 9))), lineWidth: 1.4)
        }
        if e.phase != .over {
            let c = e.cursor
            let r = CGRect(x: board.minX + CGFloat(c.x) * cell, y: board.minY + CGFloat(c.y) * cell, width: cell, height: cell).insetBy(dx: 0.5, dy: 0.5)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(0.45)), lineWidth: 1)
        }

        // Gems
        var clipped = ctx
        clipped.clip(to: Path(board.insetBy(dx: -2, dy: -2)))
        for y in 0..<n {
            for x in 0..<n {
                guard let g = e.gem(x, y) else { continue }
                let base = CGRect(x: board.minX + (CGFloat(x) + g.offset.x) * cell, y: board.minY + (CGFloat(y) + g.offset.y) * cell, width: cell, height: cell)
                var r = base.insetBy(dx: cell * 0.14, dy: cell * 0.14)
                var layer = clipped
                if e.clearing.contains(g.id) {
                    let p = e.clearProgress
                    let grow = 1 + 0.35 * p
                    r = CGRect(x: base.midX - r.width * grow / 2, y: base.midY - r.height * grow / 2, width: r.width * grow, height: r.height * grow)
                    layer.opacity = max(0, 1 - p)
                }
                drawGem(g, in: r, ctx: layer, t: t)
            }
        }

        // Blasts
        for blast in e.blasts {
            let age = t - blast.at
            let a = max(0, 1 - age / 0.45)
            let cx = board.minX + (CGFloat(blast.cell.x) + 0.5) * cell
            let cy = board.minY + (CGFloat(blast.cell.y) + 0.5) * cell
            ctx.glow(.white, radius: 12) { layer in
                switch blast.special {
                case .row:
                    layer.fill(Path(roundedRect: CGRect(x: board.minX - 4, y: cy - 4 * a, width: board.width + 8, height: 8 * a), cornerRadius: 4), with: .color(.white.opacity(a)))
                case .column:
                    layer.fill(Path(roundedRect: CGRect(x: cx - 4 * a, y: board.minY - 4, width: 8 * a, height: board.height + 8), cornerRadius: 4), with: .color(.white.opacity(a)))
                case .bomb:
                    let radius = cell * (0.6 + 1.8 * (1 - a))
                    layer.stroke(Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(a)), lineWidth: 3 * a + 0.5)
                case .star:
                    let radius = cell * (0.4 + 4 * (1 - a))
                    layer.fill(Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)), with: .color(Color(hex: 0xFFE3F8).opacity(a * 0.4)))
                case .none:
                    break
                }
            }
        }

        var particleLayer = ctx
        particleLayer.translateBy(x: board.minX, y: board.minY)
        drawParticles(e.particles.particles, in: particleLayer, palette: palette.map { $0[1] }, scale: cell)

        for p in e.popups {
            let a = max(0, 1 - p.age / 0.9)
            let text = Text(p.text).font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(Color.white.opacity(a))
            ctx.draw(text, at: CGPoint(x: board.minX + p.position.x * cell, y: board.minY + p.position.y * cell - p.age * 22), anchor: .center)
        }

        // Left panel: moves
        let lx = board.minX - 150
        panelLabel("Moves", in: ctx, at: CGPoint(x: lx, y: o.y + 6))
        let low = e.movesLeft <= 5
        panelValue("\(e.movesLeft)", in: ctx, at: CGPoint(x: lx, y: o.y + 18), size: 34, color: low ? Color(hex: 0xFF6B6B) : .white)
        let frac = Double(e.movesLeft) / Double(GemsEngine.movesPerGame)
        ctx.fill(Path(roundedRect: CGRect(x: lx, y: o.y + 64, width: 110, height: 4), cornerRadius: 2), with: .color(.white.opacity(0.08)))
        ctx.fill(Path(roundedRect: CGRect(x: lx, y: o.y + 64, width: 110 * frac, height: 4), cornerRadius: 2),
                 with: ctx.linear([Color(hex: 0x6EF7B5), Color(hex: 0x0EA371)], from: CGPoint(x: lx, y: 0), to: CGPoint(x: lx + 110, y: 0)))
        if e.cascade > 1 {
            let text = Text("CASCADE ×\(e.cascade)").font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF8AC2)], startPoint: .leading, endPoint: .trailing))
            ctx.draw(text, at: CGPoint(x: lx, y: o.y + 92), anchor: .topLeading)
        }

        // Right panel: legend
        let rx = board.maxX + 34
        panelLabel("Specials", in: ctx, at: CGPoint(x: rx, y: o.y + 6))
        let legend: [(GemsEngine.Special, String)] = [(.row, "Match 4 · line"), (.bomb, "L or T · bomb"), (.star, "Match 5 · star")]
        for (i, item) in legend.enumerated() {
            let y = o.y + 26 + CGFloat(i) * 30
            let r = CGRect(x: rx, y: y, width: 20, height: 20)
            let gem = GemsEngine.Gem(id: -1, kind: item.0 == .star ? GemsEngine.starKind : 4 - i, special: item.0 == .star ? .star : item.0, offset: .zero)
            drawGem(gem, in: r, ctx: ctx, t: t)
            let label = Text(item.1).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.5))
            ctx.draw(label, at: CGPoint(x: rx + 28, y: y + 10), anchor: .leading)
        }
        if e.phase == .ready {
            let hint = Text("Click or press space on a gem,\nthen pick a neighbour to swap.").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Color.white.opacity(0.4))
            ctx.draw(hint, at: CGPoint(x: rx, y: o.y + 124), anchor: .topLeading)
        }
    }
}

// MARK: - Sudoku

struct SudokuView: View {
    let session: GameSession
    let engine: SudokuEngine
    let revision: Int
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                _ = revision
                ctx.fit(SudokuRenderer.logical, in: size)
                SudokuRenderer.draw(engine, in: ctx)
            }
            .overlay(previewRendering ? nil : ClickCatcher(
                onClick: { point, secondary in
                    let p = SceneMapping(logical: SudokuRenderer.logical, size: proxy.size).point(point)
                    switch SudokuRenderer.hit(p) {
                    case .cell(let x, let y)?:
                        engine.select(x, y)
                        if secondary { session.press(.flag, isRepeat: false) }
                    case .digit(let n)?:
                        session.press(.number(n), isRepeat: false)
                    case .notes?:
                        session.press(.flag, isRepeat: false)
                    case .erase?:
                        session.press(.backspace, isRepeat: false)
                    case .difficulty?:
                        session.press(.cycle, isRepeat: false)
                    case nil:
                        if engine.phase == .over { session.press(.primary, isRepeat: false) }
                    }
                },
                onMove: nil
            ))
        }
    }
}

enum SudokuRenderer {
    static let logical = CGSize(width: 640, height: 300)
    static let cell: CGFloat = 30
    static let boardOrigin = CGPoint(x: 185, y: 15)
    static let accent = Color(hex: 0x67E8F9)
    static let padOrigin = CGPoint(x: 480, y: 32)
    static let padKey = CGSize(width: 40, height: 38)
    static let padGap: CGFloat = 6

    enum Hit: Equatable {
        case cell(Int, Int)
        case digit(Int)
        case notes, erase, difficulty
    }

    static func padRect(_ n: Int) -> CGRect {
        let i = n - 1
        return CGRect(
            x: padOrigin.x + CGFloat(i % 3) * (padKey.width + padGap),
            y: padOrigin.y + CGFloat(i / 3) * (padKey.height + padGap),
            width: padKey.width, height: padKey.height
        )
    }

    static var notesRect: CGRect {
        CGRect(x: padOrigin.x, y: padOrigin.y + 3 * (padKey.height + padGap), width: padKey.width * 1.5 + padGap / 2, height: 30)
    }

    static var eraseRect: CGRect {
        let n = notesRect
        return CGRect(x: n.maxX + padGap, y: n.minY, width: n.width, height: n.height)
    }

    static var difficultyRect: CGRect { CGRect(x: 30, y: 30, width: 130, height: 24) }

    static func hit(_ p: CGPoint) -> Hit? {
        let bx = p.x - boardOrigin.x, by = p.y - boardOrigin.y
        if bx >= 0, by >= 0, bx < cell * 9, by < cell * 9 {
            return .cell(Int(bx / cell), Int(by / cell))
        }
        for n in 1...9 where padRect(n).contains(p) { return .digit(n) }
        if notesRect.contains(p) { return .notes }
        if eraseRect.contains(p) { return .erase }
        if difficultyRect.contains(p) { return .difficulty }
        return nil
    }

    static func draw(_ e: SudokuEngine, in ctx: GraphicsContext) {
        let w = logical.width, h = logical.height
        let t = e.clock
        let o = boardOrigin
        let board = CGRect(x: o.x, y: o.y, width: cell * 9, height: cell * 9)

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x081418), Color(hex: 0x0A0D18)], from: .zero, to: CGPoint(x: w, y: h)))
        ctx.fill(Path(roundedRect: board.insetBy(dx: -3, dy: -3), cornerRadius: 10), with: .color(Color(hex: 0x0E1219)))

        let cursor = e.cursorIndex
        let cx = cursor % 9, cy = cursor / 9
        let cursorValue = e.value(cursor)
        let playing = e.phase != .over

        func rect(_ i: Int) -> CGRect {
            CGRect(x: board.minX + CGFloat(i % 9) * cell, y: board.minY + CGFloat(i / 9) * cell, width: cell, height: cell)
        }

        // Highlights
        for i in 0..<81 {
            let x = i % 9, y = i / 9
            var alpha = 0.0
            if playing && (x == cx || y == cy || (x / 3 == cx / 3 && y / 3 == cy / 3)) { alpha = 0.055 }
            if playing && cursorValue != 0 && e.value(i) == cursorValue { alpha = 0.16 }
            if alpha > 0 { ctx.fill(Path(rect(i)), with: .color(accent.opacity(alpha))) }
            if let err = e.lastError, err.index == i, t - err.at < 0.7 {
                ctx.fill(Path(rect(i)), with: .color(Color(hex: 0xFF453A).opacity(0.35 * (1 - (t - err.at) / 0.7))))
            }
        }
        for unit in e.completed {
            let a = max(0, 1 - (t - unit.at))
            for i in 0..<81 where unit.unit.contains(i) {
                ctx.fill(Path(rect(i)), with: .color(accent.opacity(0.28 * a)))
            }
        }
        if playing {
            let r = rect(cursor).insetBy(dx: 1, dy: 1)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(accent.opacity(e.notesMode ? 0.12 : 0.24)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(accent.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: e.notesMode ? [3, 2] : []))
        }

        // Grid
        var thin = Path(), thick = Path()
        for k in 1..<9 {
            let x = board.minX + CGFloat(k) * cell, y = board.minY + CGFloat(k) * cell
            if k % 3 == 0 {
                thick.move(to: CGPoint(x: x, y: board.minY)); thick.addLine(to: CGPoint(x: x, y: board.maxY))
                thick.move(to: CGPoint(x: board.minX, y: y)); thick.addLine(to: CGPoint(x: board.maxX, y: y))
            } else {
                thin.move(to: CGPoint(x: x, y: board.minY)); thin.addLine(to: CGPoint(x: x, y: board.maxY))
                thin.move(to: CGPoint(x: board.minX, y: y)); thin.addLine(to: CGPoint(x: board.maxX, y: y))
            }
        }
        ctx.stroke(thin, with: .color(.white.opacity(0.08)), lineWidth: 0.6)
        ctx.stroke(thick, with: .color(.white.opacity(0.26)), lineWidth: 1.4)
        ctx.stroke(Path(roundedRect: board.insetBy(dx: -0.5, dy: -0.5), cornerRadius: 6), with: .color(.white.opacity(0.3)), lineWidth: 1.4)

        // Digits and notes
        for i in 0..<81 {
            let r = rect(i)
            let v = e.value(i)
            if v != 0 {
                let given = e.isGiven(i)
                let wrong = e.isWrong(i)
                let color: Color = wrong ? Color(hex: 0xFF6B6B) : (given ? Color.white.opacity(0.9) : accent)
                var scale = 1.0
                if let placed = e.lastPlaced, placed.index == i { scale = 1 + 0.3 * max(0, 1 - (t - placed.at) / 0.2) }
                var c = ctx
                c.translateBy(x: r.midX, y: r.midY + 0.5)
                c.scaleBy(x: scale, y: scale)
                let text = Text("\(v)").font(.system(size: 16, weight: given ? .semibold : .bold, design: .rounded)).foregroundStyle(color)
                c.draw(text, at: .zero, anchor: .center)
            } else if e.notes[i] != 0 {
                for n in 1...9 where e.notes[i] & (1 << n) != 0 {
                    let nx = r.minX + (CGFloat((n - 1) % 3) + 0.5) * cell / 3
                    let ny = r.minY + (CGFloat((n - 1) / 3) + 0.5) * cell / 3
                    let text = Text("\(n)").font(.system(size: 7.5, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(n == cursorValue ? 0.9 : 0.5))
                    ctx.draw(text, at: CGPoint(x: nx, y: ny), anchor: .center)
                }
            }
        }

        // Left panel
        let lx: CGFloat = 30
        panelLabel("Difficulty", in: ctx, at: CGPoint(x: lx, y: 15))
        let dr = difficultyRect
        ctx.fill(Path(roundedRect: dr, cornerRadius: 7), with: .color(.white.opacity(0.05)))
        var dx = dr.minX + 4
        for d in SudokuEngine.Difficulty.allCases {
            let selected = d == e.difficulty
            let label = Text(d.title).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(selected ? Color.black : Color.white.opacity(e.phase == .ready ? 0.5 : 0.25))
            let width: CGFloat = d == .medium ? 50 : 36
            let pill = CGRect(x: dx, y: dr.minY + 3, width: width, height: dr.height - 6)
            if selected { ctx.fill(Path(roundedRect: pill, cornerRadius: 5), with: .color(accent)) }
            ctx.draw(label, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
            dx += width + 2
        }
        if e.phase == .ready {
            let hint = Text("Tab to change").font(.system(size: 8.5, weight: .medium, design: .rounded)).foregroundStyle(Color.white.opacity(0.3))
            ctx.draw(hint, at: CGPoint(x: lx, y: dr.maxY + 5), anchor: .topLeading)
        }

        panelLabel("Mistakes", in: ctx, at: CGPoint(x: lx, y: 88))
        panelValue("\(e.mistakes)", in: ctx, at: CGPoint(x: lx, y: 100), size: 22, color: e.mistakes > 0 ? Color(hex: 0xFF8A80) : .white)

        let filled = (0..<81).filter { e.value($0) != 0 && !e.isWrong($0) }.count
        panelLabel("Progress", in: ctx, at: CGPoint(x: lx, y: 140))
        panelValue("\(filled * 100 / 81)%", in: ctx, at: CGPoint(x: lx, y: 152), size: 22)
        ctx.fill(Path(roundedRect: CGRect(x: lx, y: 182, width: 120, height: 4), cornerRadius: 2), with: .color(.white.opacity(0.08)))
        ctx.fill(Path(roundedRect: CGRect(x: lx, y: 182, width: 120 * CGFloat(filled) / 81, height: 4), cornerRadius: 2), with: .color(accent))

        if e.notesMode {
            let notes = Text("NOTES ON").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1).foregroundStyle(Color.black)
            let r = CGRect(x: lx, y: 206, width: 70, height: 20)
            ctx.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(Color(hex: 0xFFE07A)))
            ctx.draw(notes, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
        }

        // Number pad
        panelLabel("Numbers", in: ctx, at: CGPoint(x: padOrigin.x, y: 15))
        for n in 1...9 {
            let r = padRect(n)
            let left = 9 - e.placed(n)
            let done = left <= 0
            let highlighted = cursorValue == n
            ctx.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(highlighted ? accent.opacity(0.22) : .white.opacity(done ? 0.02 : 0.06)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 9), with: .color(highlighted ? accent.opacity(0.6) : .white.opacity(0.06)), lineWidth: 0.75)
            let digit = Text("\(n)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(done ? Color.white.opacity(0.18) : (e.notesMode ? Color(hex: 0xFFE07A) : Color.white.opacity(0.92)))
            ctx.draw(digit, at: CGPoint(x: r.midX, y: r.midY - 3), anchor: .center)
            let count = Text(done ? "✓" : "\(left)").font(.system(size: 7.5, weight: .bold, design: .rounded)).foregroundStyle(Color.white.opacity(0.3))
            ctx.draw(count, at: CGPoint(x: r.midX, y: r.maxY - 6), anchor: .center)
        }
        for (r, title, key, on) in [(notesRect, "Notes", "F", e.notesMode), (eraseRect, "Erase", "⌫", false)] {
            ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(on ? Color(hex: 0xFFE07A).opacity(0.22) : .white.opacity(0.06)))
            let label = Text("\(title)  \(key)").font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(on ? Color(hex: 0xFFE07A) : Color.white.opacity(0.6))
            ctx.draw(label, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
        }
    }
}
