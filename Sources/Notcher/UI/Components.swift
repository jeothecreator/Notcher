import NotcherCore
import SwiftUI

// MARK: - Glyphs

/// The icon for a game: an SF Symbol or a small custom vector glyph,
/// always painted with the game's gradient.
struct GameGlyph: View {
    let game: GameID
    var size: CGFloat = 22

    var body: some View {
        let style = game.style
        glyph
            .frame(width: size, height: size)
            .foregroundStyle(style.gradient)
    }

    @ViewBuilder private var glyph: some View {
        if let symbol = game.style.symbol {
            Image(systemName: symbol)
                .font(.system(size: size * 0.8, weight: .semibold))
        } else {
            switch game {
            case .snake:
                ZStack {
                    SnakeGlyph()
                        .stroke(style: StrokeStyle(lineWidth: size * 0.15, lineCap: .round, lineJoin: .round))
                    Circle()
                        .frame(width: size * 0.26, height: size * 0.26)
                        .offset(x: size * 0.33, y: -size * 0.27)
                }
            case .pong:
                PongGlyph()
            case .breakout:
                BreakoutGlyph()
            case .twenty48:
                Text("2048")
                    .font(.system(size: size * 0.4, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.06)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                            .strokeBorder(lineWidth: size * 0.07)
                    )
            case .mines:
                MineGlyph()
            case .invaders:
                InvaderGlyph()
            case .astro:
                AstroGlyph()
                    .stroke(style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
            case .trails:
                ZStack {
                    TrailsGlyph()
                        .stroke(style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                    Circle()
                        .frame(width: size * 0.22, height: size * 0.22)
                        .offset(x: size * 0.4, y: -size * 0.35)
                }
            case .stack:
                StackGlyph()
            case .gems:
                ZStack {
                    GemGlyph()
                    GemFacets()
                        .stroke(Color.black.opacity(0.32), style: StrokeStyle(lineWidth: max(0.75, size * 0.045), lineJoin: .round))
                }
            case .sudoku:
                ZStack {
                    SudokuGlyph()
                        .stroke(style: StrokeStyle(lineWidth: max(1, size * 0.07), lineJoin: .round))
                    SudokuGlyph.filledCells()
                }
            case .lexi:
                ZStack {
                    LexiGlyph(filled: true)
                    LexiGlyph(filled: false)
                        .stroke(style: StrokeStyle(lineWidth: max(0.8, size * 0.06)))
                        .opacity(0.6)
                }
            case .four:
                ZStack {
                    FourGlyph(filled: true)
                    FourGlyph(filled: false)
                        .stroke(style: StrokeStyle(lineWidth: max(0.8, size * 0.05)))
                        .opacity(0.45)
                }
            default:
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: size * 0.8, weight: .semibold))
            }
        }
    }
}

struct SnakeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.78))
        p.addCurve(
            to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.52),
            control1: CGPoint(x: r.minX + w * 0.32, y: r.minY + h * 0.98),
            control2: CGPoint(x: r.minX + w * 0.42, y: r.minY + h * 0.62)
        )
        p.addCurve(
            to: CGPoint(x: r.minX + w * 0.8, y: r.minY + h * 0.24),
            control1: CGPoint(x: r.minX + w * 0.58, y: r.minY + h * 0.4),
            control2: CGPoint(x: r.minX + w * 0.62, y: r.minY + h * 0.22)
        )
        return p
    }
}

struct PongGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addRoundedRect(in: CGRect(x: r.minX + w * 0.04, y: r.minY + h * 0.16, width: w * 0.13, height: h * 0.44), cornerSize: CGSize(width: w * 0.06, height: w * 0.06))
        p.addRoundedRect(in: CGRect(x: r.minX + w * 0.83, y: r.minY + h * 0.42, width: w * 0.13, height: h * 0.44), cornerSize: CGSize(width: w * 0.06, height: w * 0.06))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.42, y: r.minY + h * 0.36, width: w * 0.18, height: h * 0.18))
        return p
    }
}

struct BreakoutGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let bw = w * 0.28, bh = h * 0.14, gap = w * 0.06
        for row in 0..<2 {
            for col in 0..<3 {
                let x = r.minX + w * 0.02 + Double(col) * (bw + gap)
                let y = r.minY + h * 0.08 + Double(row) * (bh + gap)
                p.addRoundedRect(in: CGRect(x: x, y: y, width: bw, height: bh), cornerSize: CGSize(width: bh * 0.3, height: bh * 0.3))
            }
        }
        p.addEllipse(in: CGRect(x: r.minX + w * 0.52, y: r.minY + h * 0.56, width: w * 0.14, height: h * 0.14))
        p.addRoundedRect(in: CGRect(x: r.minX + w * 0.26, y: r.minY + h * 0.82, width: w * 0.48, height: h * 0.11), cornerSize: CGSize(width: h * 0.05, height: h * 0.05))
        return p
    }
}

struct MineGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let radius = min(r.width, r.height) * 0.27
        p.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        let spikeLength = min(r.width, r.height) * 0.46
        let spikeWidth = min(r.width, r.height) * 0.1
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4
            let spike = Path(roundedRect: CGRect(x: -spikeWidth / 2, y: -spikeLength, width: spikeWidth, height: spikeLength * 2), cornerRadius: spikeWidth / 2)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
            p.addPath(spike, transform: t)
        }
        return p
    }
}

/// The classic crab, as pixels.
struct InvaderGlyph: Shape {
    static let rows = [
        "..X.....X..",
        "...X...X...",
        "..XXXXXXX..",
        ".XX.XXX.XX.",
        "XXXXXXXXXXX",
        "X.XXXXXXX.X",
        "X.X.....X.X",
        "...XX.XX...",
    ]

    func path(in r: CGRect) -> Path {
        var p = Path()
        let px = min(r.width / 11, r.height / 8)
        let ox = r.midX - px * 5.5, oy = r.midY - px * 4
        for (y, row) in Self.rows.enumerated() {
            for (x, c) in row.enumerated() where c == "X" {
                p.addRect(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px + 0.2, height: px + 0.2))
            }
        }
        return p
    }
}

/// A jagged rock and a little ship.
struct AstroGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let center = CGPoint(x: r.minX + w * 0.6, y: r.minY + h * 0.4)
        let radii: [CGFloat] = [0.34, 0.27, 0.33, 0.24, 0.31, 0.36, 0.26, 0.32]
        for (i, k) in radii.enumerated() {
            let a = CGFloat(i) / CGFloat(radii.count) * 2 * .pi
            let pt = CGPoint(x: center.x + cos(a) * w * k, y: center.y + sin(a) * h * k)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        p.move(to: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.95))
        p.addLine(to: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.62))
        p.addLine(to: CGPoint(x: r.minX + w * 0.32, y: r.minY + h * 0.95))
        p.addLine(to: CGPoint(x: r.minX + w * 0.2, y: r.minY + h * 0.86))
        p.closeSubpath()
        return p
    }
}

struct TrailsGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX + w * 0.1, y: r.minY + h * 0.9))
        p.addLine(to: CGPoint(x: r.minX + w * 0.1, y: r.minY + h * 0.5))
        p.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.5))
        p.addLine(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.15))
        p.addLine(to: CGPoint(x: r.minX + w * 0.72, y: r.minY + h * 0.15))
        return p
    }
}

struct StackGlyph: Shape {
    static let cells = [(0, 0), (1, 0), (2, 0), (1, 1), (0, 2), (2, 2), (3, 2), (0, 3), (1, 3), (2, 3), (3, 3)]

    func path(in r: CGRect) -> Path {
        var p = Path()
        let cell = min(r.width, r.height) / 4
        let gap = cell * 0.14
        let ox = r.midX - cell * 2, oy = r.midY - cell * 2
        for (x, y) in Self.cells {
            let rect = CGRect(x: ox + CGFloat(x) * cell + gap / 2, y: oy + CGFloat(y) * cell + gap / 2, width: cell - gap, height: cell - gap)
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: cell * 0.18, height: cell * 0.18))
        }
        return p
    }
}

struct GemGlyph: Shape {
    static func outline(_ r: CGRect) -> [CGPoint] {
        let w = r.width, h = r.height
        return [
            CGPoint(x: r.minX + w * 0.28, y: r.minY + h * 0.16),
            CGPoint(x: r.minX + w * 0.72, y: r.minY + h * 0.16),
            CGPoint(x: r.minX + w * 0.94, y: r.minY + h * 0.4),
            CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.9),
            CGPoint(x: r.minX + w * 0.06, y: r.minY + h * 0.4),
        ]
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addLines(Self.outline(r))
        p.closeSubpath()
        return p
    }
}

struct GemFacets: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let o = GemGlyph.outline(r)
        p.move(to: o[4])
        p.addLine(to: o[2])
        let a = CGPoint(x: r.minX + w * 0.38, y: r.minY + h * 0.4)
        let b = CGPoint(x: r.minX + w * 0.62, y: r.minY + h * 0.4)
        p.move(to: o[0]); p.addLine(to: a); p.addLine(to: o[3])
        p.move(to: o[1]); p.addLine(to: b); p.addLine(to: o[3])
        return p
    }
}

/// A 3×3 box with a couple of cells filled in.
struct SudokuGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height) * 0.86
        let box = CGRect(x: r.midX - s / 2, y: r.midY - s / 2, width: s, height: s)
        p.addRoundedRect(in: box, cornerSize: CGSize(width: s * 0.16, height: s * 0.16))
        for i in 1...2 {
            let t = CGFloat(i) / 3
            p.move(to: CGPoint(x: box.minX + s * t, y: box.minY))
            p.addLine(to: CGPoint(x: box.minX + s * t, y: box.maxY))
            p.move(to: CGPoint(x: box.minX, y: box.minY + s * t))
            p.addLine(to: CGPoint(x: box.maxX, y: box.minY + s * t))
        }
        return p
    }

    struct Cells: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let s = min(r.width, r.height) * 0.86
            let box = CGRect(x: r.midX - s / 2, y: r.midY - s / 2, width: s, height: s)
            let c = s / 3
            for (x, y) in [(0, 0), (2, 1), (1, 2)] {
                p.addRoundedRect(
                    in: CGRect(x: box.minX + CGFloat(x) * c + c * 0.22, y: box.minY + CGFloat(y) * c + c * 0.22, width: c * 0.56, height: c * 0.56),
                    cornerSize: CGSize(width: c * 0.12, height: c * 0.12)
                )
            }
            return p
        }
    }

    static func filledCells() -> Cells { Cells() }
}

/// Two rows of letter tiles: the top one solved.
struct LexiGlyph: Shape {
    let filled: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = min(r.width, r.height) * 0.28
        let gap = t * 0.18
        let total = t * 3 + gap * 2
        let ox = r.midX - total / 2
        let rowY: CGFloat = filled ? r.midY - t - gap / 2 : r.midY + gap / 2
        for i in 0..<3 {
            p.addRoundedRect(
                in: CGRect(x: ox + CGFloat(i) * (t + gap), y: rowY, width: t, height: t),
                cornerSize: CGSize(width: t * 0.22, height: t * 0.22)
            )
        }
        return p
    }
}

/// A 3×3 rack with a winning diagonal.
struct FourGlyph: Shape {
    let filled: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        let s = min(r.width, r.height)
        let d = s / 3
        let ox = r.midX - s / 2, oy = r.midY - s / 2
        for y in 0..<3 {
            for x in 0..<3 where (x + y == 2) == filled {
                let inset = filled ? d * 0.08 : d * 0.18
                p.addEllipse(in: CGRect(x: ox + CGFloat(x) * d + inset, y: oy + CGFloat(y) * d + inset, width: d - inset * 2, height: d - inset * 2))
            }
        }
        return p
    }
}

// MARK: - Keycaps & hints

struct Keycap: View {
    let label: String
    var highlighted = false

    var body: some View {
        Text(label)
            .font(Theme.rounded(9.5, .semibold))
            .foregroundStyle(highlighted ? Color.black : Theme.primary.opacity(0.85))
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(highlighted ? Color.white : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            )
    }
}

struct HintLabel: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: 4) {
            Keycap(label: keys)
            Text(action)
                .font(Theme.rounded(10, .medium))
                .foregroundStyle(Theme.secondary)
        }
    }
}

struct HintRow: View {
    let hints: [ControlHint]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(hints, id: \.self) { hint in
                HintLabel(keys: hint.keys, action: hint.action)
            }
        }
    }
}

// MARK: - Score text

struct ScoreText: View {
    let value: Int
    let format: ScoreFormat
    var size: CGFloat = 15

    var body: some View {
        Text(Format.score(value, format: format))
            .font(Theme.mono(size, .bold))
            .contentTransition(.numericText(value: Double(value)))
            .animation(Theme.snappy, value: value)
    }
}

/// Small rounded label, e.g. "DAILY" or "NEW BEST".
struct Chip: View {
    let text: String
    var colors: [Color] = [Color.white.opacity(0.18), Color.white.opacity(0.1)]
    var foreground: Color = .white

    var body: some View {
        Text(text)
            .font(Theme.rounded(8.5, .heavy))
            .tracking(0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
    }
}

// MARK: - Transitions

struct BlurModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

extension AnyTransition {
    /// Content materialising out of the notch.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(
                active: BlurModifier(radius: 8, opacity: 0),
                identity: BlurModifier(radius: 0, opacity: 1)
            )
            .combined(with: .scale(scale: 0.96, anchor: .top))
            .animation(.easeOut(duration: 0.26).delay(0.1)),
            removal: AnyTransition.modifier(
                active: BlurModifier(radius: 6, opacity: 0),
                identity: BlurModifier(radius: 0, opacity: 1)
            )
            .animation(.easeIn(duration: 0.1))
        )
    }
}

// MARK: - Helpers

extension View {
    /// Subtle glass panel used for tiles and cards.
    func cardBackground(cornerRadius: CGFloat = 14, fill: Color = Theme.surface, stroke: Color = Theme.stroke) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(stroke, lineWidth: 0.75)
        )
    }
}

// MARK: - Preview rendering

private struct PreviewRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while views are rendered to images (ImageRenderer can't draw AppKit-backed views).
    var previewRendering: Bool {
        get { self[PreviewRenderingKey.self] }
        set { self[PreviewRenderingKey.self] = newValue }
    }
}

/// A vertical ScrollView, or plain content when rendering previews.
struct VerticalScroll<Content: View>: View {
    @Environment(\.previewRendering) private var previewRendering
    @ViewBuilder let content: Content

    var body: some View {
        if previewRendering {
            VStack(spacing: 0) {
                content
                Spacer(minLength: 0)
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                content
            }
        }
    }
}
