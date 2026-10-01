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
