import AppKit
import NotcherCore
import SwiftUI

struct MinesView: View {
    let session: GameSession
    let engine: MinesEngine
    let revision: Int

    static let logical = CGSize(width: 640, height: 240)
    static let stride: CGFloat = 29
    static let cellSize: CGFloat = 27
    static var origin: CGPoint {
        CGPoint(
            x: (logical.width - (CGFloat(MinesEngine.columns) * stride - (stride - cellSize))) / 2,
            y: (logical.height - (CGFloat(MinesEngine.rows) * stride - (stride - cellSize))) / 2
        )
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { ctx, size in
                _ = revision
                ctx.fit(Self.logical, in: size)
                MinesRenderer.draw(engine, in: ctx)
            }
            .overlay(
                ClickCatcher(
                    onClick: { point, secondary in
                        guard let cell = Self.cell(at: point, in: proxy.size) else { return }
                        engine.setCursor(cell.x, cell.y)
                        if secondary {
                            session.press(.flag, isRepeat: false)
                        } else {
                            session.press(engine.phase == .over ? .primary : .confirm, isRepeat: false)
                        }
                    },
                    onMove: { point in
                        guard let point, let cell = Self.cell(at: point, in: proxy.size) else { return }
                        if cell != engine.cursor { engine.setCursor(cell.x, cell.y) }
                    }
                )
            )
        }
    }

    static func cell(at point: CGPoint, in size: CGSize) -> GridPoint? {
        let s = min(size.width / logical.width, size.height / logical.height)
        let ox = (size.width - logical.width * s) / 2
        let oy = (size.height - logical.height * s) / 2
        let lx = (point.x - ox) / s - origin.x
        let ly = (point.y - oy) / s - origin.y
        guard lx >= 0, ly >= 0 else { return nil }
        let x = Int(lx / stride), y = Int(ly / stride)
        guard x < MinesEngine.columns, y < MinesEngine.rows else { return nil }
        return GridPoint(x, y)
    }
}

enum MinesRenderer {
    static let numberColors: [Color] = [
        Color(hex: 0x5AC8FA), Color(hex: 0x6EE7A0), Color(hex: 0xFFB340), Color(hex: 0xC084FC),
        Color(hex: 0xFF6B6B), Color(hex: 0x5EEAD4), Color(hex: 0xFDE047), Color(hex: 0xE5E7EB),
    ]
    static let accent = Color(hex: 0xFF8A80)

    static func draw(_ e: MinesEngine, in ctx: GraphicsContext) {
        let size = MinesView.logical
        let t = e.clock
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: ctx.linear([Color(hex: 0x14090B), Color(hex: 0x08070A)], from: .zero, to: CGPoint(x: 0, y: size.height)))

        let numbers = (1...8).map { n in
            ctx.resolve(Text("\(n)").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(numberColors[n - 1]))
        }
        var flag = ctx.resolve(Image(systemName: "flag.fill"))
        flag.shading = .color(Color(hex: 0xFF5A5F))

        let origin = MinesView.origin
        let stride = MinesView.stride, cs = MinesView.cellSize
        for y in 0..<MinesEngine.rows {
            for x in 0..<MinesEngine.columns {
                let cell = e.cell(x, y)
                let rect = CGRect(x: origin.x + CGFloat(x) * stride, y: origin.y + CGFloat(y) * stride, width: cs, height: cs)
                let shown = cell.state == .revealed && t >= cell.revealedAt
                if shown {
                    let age = t - cell.revealedAt
                    let scale = min(1, 0.65 + age * 4)
                    let r = rect.insetBy(dx: rect.width * (1 - scale) / 2, dy: rect.height * (1 - scale) / 2)
                    let exploded = e.exploded == GridPoint(x, y)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(exploded ? Color(hex: 0xE5484D) : Color.white.opacity(0.035)))
                    if cell.isMine {
                        drawMine(ctx, in: r, bright: exploded)
                    } else if cell.adjacent > 0 {
                        ctx.draw(numbers[cell.adjacent - 1], at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
                    }
                } else {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 5),
                             with: ctx.linear([Color(hex: 0x33313D), Color(hex: 0x24232C)], from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY)))
                    ctx.fill(Path(roundedRect: CGRect(x: rect.minX + 3, y: rect.minY + 1.5, width: rect.width - 6, height: 1.5), cornerRadius: 0.75), with: .color(.white.opacity(0.12)))
                    if cell.state == .flagged {
                        ctx.draw(flag, in: rect.insetBy(dx: 7.5, dy: 7))
                        if e.phase == .over && !e.won && !cell.isMine {
                            var cross = Path()
                            cross.move(to: CGPoint(x: rect.minX + 6, y: rect.minY + 6))
                            cross.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.maxY - 6))
                            cross.move(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 6))
                            cross.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 6))
                            ctx.stroke(cross, with: .color(.white.opacity(0.8)), lineWidth: 1.6)
                        }
                    }
                }
            }
        }

        // Cursor
        if e.phase != .over || e.won == false {
            let c = e.cursor
            let rect = CGRect(x: origin.x + CGFloat(c.x) * stride, y: origin.y + CGFloat(c.y) * stride, width: cs, height: cs).insetBy(dx: -1.5, dy: -1.5)
            let pulse = 0.75 + 0.25 * sin(t * 6)
            ctx.glow(accent, radius: 6) { layer in
                layer.stroke(Path(roundedRect: rect, cornerRadius: 6.5), with: .color(accent.opacity(pulse)), lineWidth: 2)
            }
        }

        if e.phase == .ready {
            let hint = Text("Reveal any tile — the first one is always safe").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.45))
            ctx.draw(hint, at: CGPoint(x: size.width / 2, y: size.height - 1), anchor: .bottom)
        }
    }

    static func drawMine(_ ctx: GraphicsContext, in rect: CGRect, bright: Bool) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width * 0.22
        var spikes = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            spikes.move(to: CGPoint(x: c.x + cos(a) * r * 0.6, y: c.y + sin(a) * r * 0.6))
            spikes.addLine(to: CGPoint(x: c.x + cos(a) * r * 1.6, y: c.y + sin(a) * r * 1.6))
        }
        let color = bright ? Color.black : Color(hex: 0xFF8A80)
        ctx.stroke(spikes, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.fillCircle(c, radius: r, with: .color(color))
        ctx.fillCircle(CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.35), radius: r * 0.28, with: .color(.white.opacity(0.6)))
    }
}

// MARK: - Mouse helper

/// Left/right clicks and hover from AppKit, in top-left view coordinates.
struct ClickCatcher: NSViewRepresentable {
    var onClick: (CGPoint, Bool) -> Void
    var onMove: ((CGPoint?) -> Void)?

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onClick = onClick
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: ClickCatcherView, context: Context) {
        view.onClick = onClick
        view.onMove = onMove
    }
}

final class ClickCatcherView: NSView {
    var onClick: ((CGPoint, Bool) -> Void)?
    var onMove: ((CGPoint?) -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseDown(with event: NSEvent) {
        let secondary = event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option)
        onClick?(convert(event.locationInWindow, from: nil), secondary)
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil), true)
    }

    override func mouseMoved(with event: NSEvent) {
        onMove?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onMove?(nil)
    }
}
