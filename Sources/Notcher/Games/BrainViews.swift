import NotcherCore
import SwiftUI

// MARK: - Lexi

struct LexiView: View {
    let session: GameSession
    let engine: LexiEngine
    let revision: Int
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                _ = revision
                ctx.fit(LexiRenderer.logical, in: size)
                LexiRenderer.draw(engine, in: ctx)
            }
            .overlay(previewRendering ? nil : ClickCatcher(
                onClick: { point, _ in
                    let p = SceneMapping(logical: LexiRenderer.logical, size: proxy.size).point(point)
                    guard let key = LexiRenderer.key(at: p) else { return }
                    session.press(key, isRepeat: false)
                },
                onMove: nil
            ))
        }
    }
}

enum LexiRenderer {
    static let logical = CGSize(width: 640, height: 300)
    static let tile: CGFloat = 40
    static let gap: CGFloat = 6
    static let gridOrigin = CGPoint(x: 48, y: 15)
    static let correct = Color(hex: 0x52C46B)
    static let present = Color(hex: 0xE8B931)
    static let absent = Color(hex: 0x34343E)

    static let rows: [[String]] = [
        "qwertyuiop".map(String.init),
        "asdfghjkl".map(String.init),
        ["enter"] + "zxcvbnm".map(String.init) + ["del"],
    ]
    static let keyOrigin = CGPoint(x: 312, y: 150)
    static let keyHeight: CGFloat = 40
    static let keyGap: CGFloat = 5
    static let keyWidth: CGFloat = 26

    static func keyRects() -> [(label: String, rect: CGRect)] {
        var result: [(label: String, rect: CGRect)] = []
        for (r, row) in rows.enumerated() {
            let widths = row.map { $0.count > 1 ? keyWidth * 1.55 : keyWidth }
            let total = widths.reduce(0, +) + CGFloat(row.count - 1) * keyGap
            var x = keyOrigin.x + (10 * keyWidth + 9 * keyGap - total) / 2
            let y = keyOrigin.y + CGFloat(r) * (keyHeight + keyGap)
            for (label, width) in zip(row, widths) {
                result.append((label: label, rect: CGRect(x: x, y: y, width: width, height: keyHeight)))
                x += width + keyGap
            }
        }
        return result
    }

    static func key(at p: CGPoint) -> GameKey? {
        guard let hit = keyRects().first(where: { $0.rect.contains(p) }) else { return nil }
        switch hit.label {
        case "enter": return .confirm
        case "del": return .backspace
        default: return hit.label.first.map { .char($0) }
        }
    }

    static func color(_ mark: LexiEngine.Mark) -> Color {
        switch mark {
        case .correct: return correct
        case .present: return present
        case .absent: return absent
        }
    }

    static func draw(_ e: LexiEngine, in ctx: GraphicsContext) {
        let w = logical.width, h = logical.height
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x0D120B), Color(hex: 0x0B0B12)], from: .zero, to: CGPoint(x: w, y: h)))

        let n = LexiEngine.wordLength
        let currentRow = e.guesses.count
        for row in 0..<LexiEngine.maxGuesses {
            var shake = 0.0
            if row == currentRow, let rejected = e.rejectedAt, t - rejected < 0.4 {
                let k = 1 - (t - rejected) / 0.4
                shake = sin((t - rejected) * 70) * 7 * k
            }
            for i in 0..<n {
                let x = gridOrigin.x + CGFloat(i) * (tile + gap) + shake
                let y = gridOrigin.y + CGFloat(row) * (tile + gap)
                let rect = CGRect(x: x, y: y, width: tile, height: tile)
                if row < e.guesses.count {
                    let letter = Array(e.guesses[row])[i]
                    let mark = e.marks[row][i]
                    let start = e.revealedAt[row] + Double(i) * LexiEngine.flipStagger
                    let p = max(0, min(1, (t - start) / 0.3))
                    // Flip: squash to the middle, swap faces, open again.
                    let revealed = p >= 0.5
                    let squash = abs(cos(p * .pi))
                    var bounce = 0.0
                    if e.won && row == e.guesses.count - 1 {
                        let bt = t - (e.revealedAt[row] + Double(n) * LexiEngine.flipStagger + 0.15) - Double(i) * 0.08
                        if bt > 0 && bt < 0.3 { bounce = -sin(bt / 0.3 * .pi) * 9 }
                    }
                    var r = rect.offsetBy(dx: 0, dy: bounce)
                    r = CGRect(x: r.minX, y: r.midY - r.height * squash / 2, width: r.width, height: max(0.5, r.height * squash))
                    if revealed {
                        let c = color(mark)
                        ctx.glow(c.opacity(mark == .absent ? 0 : 0.5), radius: 6) { layer in
                            layer.fill(Path(roundedRect: r, cornerRadius: 7), with: layer.linear([mix(c, .white, 0.12), c], from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.maxY)))
                        }
                    } else {
                        ctx.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(0.04)))
                        ctx.stroke(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(0.32)), lineWidth: 1.4)
                    }
                    if squash > 0.2 {
                        var c = ctx
                        c.translateBy(x: r.midX, y: r.midY)
                        c.scaleBy(x: 1, y: squash)
                        let text = Text(String(letter).uppercased()).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color.white)
                        c.draw(text, at: .zero, anchor: .center)
                    }
                } else if row == currentRow {
                    let letters = Array(e.current)
                    let filled = i < letters.count
                    var r = rect
                    if filled && i == letters.count - 1 {
                        // Pop on the newest letter.
                        r = r.insetBy(dx: -1.5, dy: -1.5)
                    }
                    ctx.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(filled ? 0.06 : 0.025)))
                    ctx.stroke(Path(roundedRect: r, cornerRadius: 7), with: .color(.white.opacity(filled ? 0.45 : 0.14)), lineWidth: filled ? 1.6 : 1)
                    if filled {
                        let text = Text(String(letters[i]).uppercased()).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color.white)
                        ctx.draw(text, at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
                    } else if i == letters.count && e.phase != .over && sin(t * 6) > 0 {
                        ctx.fill(Path(roundedRect: CGRect(x: r.midX - 7, y: r.maxY - 9, width: 14, height: 2), cornerRadius: 1), with: .color(.white.opacity(0.5)))
                    }
                } else {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(.white.opacity(0.02)))
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 7), with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
            }
        }

        // Status above the keyboard
        let kx = keyOrigin.x
        let kw = 10 * keyWidth + 9 * keyGap
        if let message = e.message {
            let a = min(1, max(0, (1.6 - (t - message.at)) * 3))
            let text = Text(message.text).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color.black.opacity(a))
            let resolved = ctx.resolve(text)
            let size = resolved.measure(in: CGSize(width: 400, height: 40))
            let pill = CGRect(x: kx + kw / 2 - size.width / 2 - 14, y: 70, width: size.width + 28, height: 32)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 16), with: .color(Color.white.opacity(0.92 * a)))
            ctx.draw(resolved, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
        } else {
            let guessNumber = min(LexiEngine.maxGuesses, e.guesses.count + 1)
            panelLabel(e.phase == .over ? "Round over" : "Guess \(guessNumber) of \(LexiEngine.maxGuesses)", in: ctx, at: CGPoint(x: kx + kw / 2, y: 62), anchor: .top, opacity: 0.4)
            let hint = e.guesses.isEmpty && e.current.isEmpty ? "Type any five-letter word" : "Return to guess · ⌫ to delete"
            let text = Text(hint).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.55))
            ctx.draw(text, at: CGPoint(x: kx + kw / 2, y: 82), anchor: .top)
        }
        // Legend
        let legend: [(Color, String)] = [(correct, "Right spot"), (present, "In the word"), (absent, "Not in it")]
        var lx = kx + 30
        for (c, label) in legend {
            ctx.fill(Path(roundedRect: CGRect(x: lx, y: 120, width: 10, height: 10), cornerRadius: 3), with: .color(c))
            let text = Text(label).font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.45))
            ctx.draw(text, at: CGPoint(x: lx + 15, y: 125), anchor: .leading)
            lx += 92
        }

        // Keyboard
        for key in keyRects() {
            let r = key.rect
            let letter = key.label.count == 1 ? key.label.first : nil
            let mark = letter.flatMap { e.keyboard[$0] }
            let fill: Color = mark.map { color($0) } ?? Color.white.opacity(0.1)
            ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(fill))
            if mark == nil {
                ctx.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(.white.opacity(0.06)), lineWidth: 0.75)
            }
            let label: Text
            switch key.label {
            case "enter": label = Text("ENTER").font(.system(size: 8.5, weight: .heavy, design: .rounded))
            case "del": label = Text(Image(systemName: "delete.left")).font(.system(size: 12, weight: .semibold))
            default: label = Text(key.label.uppercased()).font(.system(size: 12.5, weight: .bold, design: .rounded))
            }
            ctx.draw(label.foregroundStyle(Color.white.opacity(mark == .absent ? 0.45 : 0.92)), at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
        }
    }
}

// MARK: - Typer

struct TyperView: View {
    let engine: TyperEngine
    let revision: Int

    var body: some View {
        Canvas { ctx, size in
            _ = revision
            ctx.fit(CGSize(width: 640, height: 240), in: size)
            TyperRenderer.draw(engine, in: ctx)
        }
    }
}

enum TyperRenderer {
    static let accent = Color(hex: 0xF0ABFC)
    static let deep = Color(hex: 0xA855F7)
    static let wrong = Color(hex: 0xFF6B7A)
    static let fontSize: CGFloat = 21
    static let lineHeight: CGFloat = 36
    static let textWidth: CGFloat = 560

    static func draw(_ e: TyperEngine, in ctx: GraphicsContext) {
        let w = 640.0, h = 240.0
        let t = e.clock
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x120A1C), Color(hex: 0x0B0B14)], from: .zero, to: CGPoint(x: w, y: h)))

        // Top bar: time ring, WPM, accuracy
        let ringCenter = CGPoint(x: 52, y: 42)
        let frac = e.timeLeft / TyperEngine.duration
        ctx.stroke(Path(ellipseIn: CGRect(x: ringCenter.x - 22, y: ringCenter.y - 22, width: 44, height: 44)), with: .color(.white.opacity(0.08)), lineWidth: 4)
        var arc = Path()
        arc.addArc(center: ringCenter, radius: 22, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * frac), clockwise: false)
        ctx.glow(accent.opacity(0.6), radius: 6) { layer in
            layer.stroke(arc, with: .color(e.timeLeft < 5 && e.phase == .playing ? wrong : accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        let secs = Text("\(Int(e.timeLeft.rounded(.up)))").font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(Color.white)
        ctx.draw(secs, at: ringCenter, anchor: .center)

        panelLabel("WPM", in: ctx, at: CGPoint(x: 92, y: 22))
        panelValue("\(e.phase == .ready ? 0 : e.wpm)", in: ctx, at: CGPoint(x: 92, y: 33), size: 24, color: accent)
        panelLabel("Accuracy", in: ctx, at: CGPoint(x: 172, y: 22))
        panelValue("\(e.accuracy)%", in: ctx, at: CGPoint(x: 172, y: 33), size: 24)
        panelLabel("Words", in: ctx, at: CGPoint(x: 268, y: 22))
        panelValue("\(e.results.filter { $0 }.count)", in: ctx, at: CGPoint(x: 268, y: 33), size: 24)

        // Sparkline of WPM over time
        if e.samples.count > 1 {
            let sx = 400.0, sw = 210.0, sy = 22.0, sh = 38.0
            let peak = Double(max(40, e.samples.max() ?? 40))
            var line = Path()
            for (i, v) in e.samples.enumerated() {
                let x = sx + sw * Double(i) / (TyperEngine.duration - 1)
                let y = sy + sh - sh * Double(v) / peak
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.glow(accent.opacity(0.6), radius: 4) { layer in
                layer.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }

        // Words
        let font = Font.system(size: fontSize, weight: .medium, design: .monospaced)
        let cw = ctx.resolve(Text("m").font(font)).measure(in: CGSize(width: 100, height: 100)).width
        var lines: [[Int]] = [[]]
        var used: CGFloat = 0
        for (i, word) in e.words.enumerated() {
            let width = CGFloat(word.count + 1) * cw
            if used + width > textWidth && !lines[lines.count - 1].isEmpty {
                if lines.count > 3 && i > e.index + 40 { break }
                lines.append([])
                used = 0
            }
            lines[lines.count - 1].append(i)
            used += width
        }
        let currentLine = lines.firstIndex { $0.contains(e.index) } ?? 0
        let firstLine = max(0, currentLine - 1)
        let originX = (w - textWidth) / 2
        let top = 96.0
        for (li, line) in lines.enumerated() where li >= firstLine && li < firstLine + 3 {
            let y = top + Double(li - firstLine) * lineHeight + lineHeight / 2
            var x = originX
            for i in line {
                let word = Array(e.words[i])
                if i < e.index {
                    let ok = i < e.results.count ? e.results[i] : true
                    let text = Text(String(word)).font(font).foregroundStyle(ok ? Color.white.opacity(0.3) : wrong.opacity(0.65))
                    ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .leading)
                    if !ok {
                        ctx.fill(Path(CGRect(x: x, y: y + 9, width: CGFloat(word.count) * cw, height: 1.2)), with: .color(wrong.opacity(0.6)))
                    }
                } else if i == e.index {
                    let typed = Array(e.typed)
                    let count = max(word.count, typed.count)
                    ctx.fill(Path(roundedRect: CGRect(x: x - 4, y: y - lineHeight / 2 + 3, width: CGFloat(count) * cw + 8, height: lineHeight - 6), cornerRadius: 7),
                             with: .color(.white.opacity(0.06)))
                    for k in 0..<count {
                        let ch: Character = k < word.count ? word[k] : typed[k]
                        let color: Color
                        if k < typed.count {
                            color = (k < word.count && typed[k] == word[k]) ? .white : wrong
                        } else {
                            color = Color.white.opacity(0.4)
                        }
                        let text = Text(String(ch)).font(font).foregroundStyle(color)
                        ctx.draw(text, at: CGPoint(x: x + CGFloat(k) * cw, y: y), anchor: .leading)
                    }
                    // Caret
                    if e.phase != .over && (e.phase == .ready ? sin(t * 5) > 0 : true) {
                        let cx = x + CGFloat(typed.count) * cw
                        ctx.glow(accent, radius: 5) { layer in
                            layer.fill(Path(roundedRect: CGRect(x: cx - 1, y: y - 12, width: 2, height: 24), cornerRadius: 1), with: .color(accent))
                        }
                    }
                } else {
                    let text = Text(String(word)).font(font).foregroundStyle(Color.white.opacity(0.42))
                    ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .leading)
                }
                x += CGFloat(word.count + 1) * cw
            }
        }

        if e.phase == .ready {
            let hint = Text("Start typing to begin · space moves to the next word").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.4))
            ctx.draw(hint, at: CGPoint(x: w / 2, y: h - 14), anchor: .center)
        }
    }
}

// MARK: - Four

struct FourView: View {
    let session: GameSession
    let engine: FourEngine
    let revision: Int
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                _ = revision
                ctx.fit(FourRenderer.logical, in: size)
                FourRenderer.draw(engine, in: ctx)
            }
            .overlay(previewRendering ? nil : ClickCatcher(
                onClick: { point, _ in
                    if engine.phase == .over {
                        session.press(.primary, isRepeat: false)
                        return
                    }
                    let p = SceneMapping(logical: FourRenderer.logical, size: proxy.size).point(point)
                    if let column = FourRenderer.column(at: p) {
                        engine.choose(column: column)
                        session.press(.primary, isRepeat: false)
                    }
                },
                onMove: { point in
                    guard let point else { return }
                    let p = SceneMapping(logical: FourRenderer.logical, size: proxy.size).point(point)
                    if let column = FourRenderer.column(at: p), column != engine.cursor { engine.choose(column: column) }
                }
            ))
        }
    }
}

enum FourRenderer {
    static let logical = CGSize(width: 640, height: 240)
    static let cell: CGFloat = 30
    static var origin: CGPoint {
        CGPoint(x: (logical.width - CGFloat(FourEngine.columns) * cell) / 2, y: 46)
    }
    static let player = [Color(hex: 0xFFF0A8), Color(hex: 0xFFC53D), Color(hex: 0xD99100)]
    static let ai = [Color(hex: 0xFFB0B8), Color(hex: 0xFF5F6D), Color(hex: 0xC0263A)]

    static func column(at p: CGPoint) -> Int? {
        let x = Int(floor((p.x - origin.x) / cell))
        guard x >= 0, x < FourEngine.columns, p.y > 0, p.y < origin.y + CGFloat(FourEngine.rows) * cell + 8 else { return nil }
        return x
    }

    static func drawDisc(_ owner: Int, center c: CGPoint, radius r: CGFloat, in ctx: GraphicsContext, alpha: Double = 1) {
        let colors = owner == 1 ? player : ai
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: ctx.linear(colors.map { $0.opacity(alpha) }, from: CGPoint(x: c.x - r, y: c.y - r), to: CGPoint(x: c.x + r, y: c.y + r)))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24)),
                   with: .color(colors[2].opacity(0.55 * alpha)), lineWidth: 1.4)
        ctx.fillCircle(CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.38), radius: r * 0.16, with: .color(.white.opacity(0.7 * alpha)))
    }

    static func draw(_ e: FourEngine, in ctx: GraphicsContext) {
        let w = logical.width, h = logical.height
        let t = e.clock
        let o = origin
        let cols = FourEngine.columns, rows = FourEngine.rows
        let board = CGRect(x: o.x, y: o.y, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)

        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: ctx.linear([Color(hex: 0x150D10), Color(hex: 0x0C0C18)], from: .zero, to: CGPoint(x: w, y: h)))

        let yourTurn = e.turn == .player && e.drop == nil && e.result == nil && e.phase != .over
        // Column highlight and hovering disc
        if yourTurn {
            let cx = o.x + (CGFloat(e.cursor) + 0.5) * cell
            ctx.fill(Path(roundedRect: CGRect(x: cx - cell / 2 + 2, y: o.y, width: cell - 4, height: board.height), cornerRadius: 8), with: .color(player[1].opacity(0.07)))
            let bob = sin(t * 5) * 2
            ctx.glow(player[1].opacity(0.6), radius: 8) { layer in
                drawDisc(1, center: CGPoint(x: cx, y: o.y - 20 + bob), radius: cell * 0.4, in: layer)
            }
        }

        // Discs (behind the frame)
        for r in 0..<rows {
            for c in 0..<cols {
                let owner = e.board[r * cols + c]
                guard owner != 0 else { continue }
                let center = CGPoint(x: o.x + (CGFloat(c) + 0.5) * cell, y: o.y + (CGFloat(r) + 0.5) * cell)
                drawDisc(owner, center: center, radius: cell * 0.4, in: ctx)
            }
        }
        if let d = e.drop {
            let center = CGPoint(x: o.x + (CGFloat(d.column) + 0.5) * cell, y: o.y + (CGFloat(d.y) + 0.5) * cell)
            drawDisc(d.owner, center: center, radius: cell * 0.4, in: ctx)
        }

        // Frame with holes
        var frame = Path(roundedRect: board.insetBy(dx: -6, dy: -6), cornerRadius: 12)
        for r in 0..<rows {
            for c in 0..<cols {
                let center = CGPoint(x: o.x + (CGFloat(c) + 0.5) * cell, y: o.y + (CGFloat(r) + 0.5) * cell)
                frame.addEllipse(in: CGRect(x: center.x - cell * 0.42, y: center.y - cell * 0.42, width: cell * 0.84, height: cell * 0.84))
            }
        }
        ctx.fill(frame, with: ctx.linear([Color(hex: 0x2B3478), Color(hex: 0x1A1F4D)], from: CGPoint(x: 0, y: board.minY), to: CGPoint(x: 0, y: board.maxY)), style: FillStyle(eoFill: true))
        ctx.stroke(Path(roundedRect: board.insetBy(dx: -6, dy: -6), cornerRadius: 12), with: .color(.white.opacity(0.12)), lineWidth: 1)

        // Winning line
        if e.winLine.count >= 4, let first = e.winLine.first, let last = e.winLine.last {
            func center(_ i: Int) -> CGPoint {
                CGPoint(x: o.x + (CGFloat(i % cols) + 0.5) * cell, y: o.y + (CGFloat(i / cols) + 0.5) * cell)
            }
            let owner = e.board[first]
            let color = owner == 1 ? player[1] : ai[1]
            var line = Path()
            line.move(to: center(first))
            line.addLine(to: center(last))
            let pulse = 0.6 + 0.4 * sin(t * 8)
            ctx.glow(color, radius: 10) { layer in
                layer.stroke(line, with: .color(Color.white.opacity(0.9 * pulse)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            for i in e.winLine {
                ctx.stroke(Path(ellipseIn: CGRect(x: center(i).x - cell * 0.44, y: center(i).y - cell * 0.44, width: cell * 0.88, height: cell * 0.88)),
                           with: .color(Color.white.opacity(0.8 * pulse)), lineWidth: 1.6)
            }
        }

        var particleLayer = ctx
        particleLayer.translateBy(x: o.x, y: o.y)
        drawParticles(e.particles.particles, in: particleLayer, palette: [player[1], player[1], ai[1]], scale: cell)

        // Left panel
        let lx = board.minX - 150
        panelLabel("Level", in: ctx, at: CGPoint(x: lx, y: o.y))
        panelValue("\(e.level)", in: ctx, at: CGPoint(x: lx, y: o.y + 12), size: 28, color: player[1])
        panelLabel("AI depth", in: ctx, at: CGPoint(x: lx, y: o.y + 56))
        for i in 0..<7 {
            ctx.fill(Path(roundedRect: CGRect(x: lx + CGFloat(i) * 13, y: o.y + 70, width: 10, height: 6), cornerRadius: 2),
                     with: .color(i < e.depth ? ai[1].opacity(0.85) : .white.opacity(0.08)))
        }
        panelLabel("Wins", in: ctx, at: CGPoint(x: lx, y: o.y + 92))
        panelValue("\(e.wins)", in: ctx, at: CGPoint(x: lx, y: o.y + 104), size: 22)

        // Right panel: whose turn
        let rx = board.maxX + 40
        panelLabel("Turn", in: ctx, at: CGPoint(x: rx, y: o.y))
        let status: String
        let statusOwner: Int
        if let result = e.result {
            status = result.winner == 1 ? "You win!" : (result.winner == 2 ? "AI wins" : "Draw")
            statusOwner = result.winner == 0 ? 1 : result.winner
        } else if e.turn == .ai {
            let dots = String(repeating: ".", count: Int(t * 3) % 4)
            status = "Thinking" + dots
            statusOwner = 2
        } else {
            status = "Your move"
            statusOwner = 1
        }
        drawDisc(statusOwner, center: CGPoint(x: rx + 10, y: o.y + 28), radius: 9, in: ctx)
        let text = Text(status).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color.white.opacity(0.9))
        ctx.draw(text, at: CGPoint(x: rx + 26, y: o.y + 28), anchor: .leading)
        if e.phase == .ready || (e.wins == 0 && e.board.allSatisfy { $0 == 0 }) {
            let hint = Text("←→ or the mouse to aim,\nspace or click to drop.\nWin to level up the AI.").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Color.white.opacity(0.4))
            ctx.draw(hint, at: CGPoint(x: rx, y: o.y + 52), anchor: .topLeading)
        }
        // Column numbers
        for c in 0..<cols {
            let n = Text("\(c + 1)").font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(Color.white.opacity(c == e.cursor && yourTurn ? 0.6 : 0.2))
            ctx.draw(n, at: CGPoint(x: o.x + (CGFloat(c) + 0.5) * cell, y: board.maxY + 14), anchor: .center)
        }
    }
}
