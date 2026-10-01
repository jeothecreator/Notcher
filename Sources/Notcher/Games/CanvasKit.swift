import AppKit
import NotcherCore
import SwiftUI

extension Vec2 {
    var point: CGPoint { CGPoint(x: x, y: y) }
}

extension Box {
    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

extension GraphicsContext {
    /// Draws whatever `body` draws with a soft glow behind it.
    func glow(_ color: Color, radius: CGFloat, _ body: (inout GraphicsContext) -> Void) {
        drawLayer { layer in
            layer.addFilter(.shadow(color: color, radius: radius))
            body(&layer)
        }
    }

    func fillCircle(_ center: CGPoint, radius: CGFloat, with shading: GraphicsContext.Shading) {
        fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: shading)
    }

    func linear(_ colors: [Color], from: CGPoint, to: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
    }

    /// Scales the context so a `logical` sized scene fills `size`, centered.
    mutating func fit(_ logical: CGSize, in size: CGSize) {
        let s = min(size.width / logical.width, size.height / logical.height)
        translateBy(x: (size.width - logical.width * s) / 2, y: (size.height - logical.height * s) / 2)
        scaleBy(x: s, y: s)
    }
}

/// Deterministic pseudo-random numbers for scenery (stars etc.).
@inline(__always) func hash01(_ i: Int, _ salt: Int = 0) -> Double {
    var x = UInt64(bitPattern: Int64(i &* 73_856_093 ^ salt &* 19_349_663))
    x ^= x >> 33
    x = x &* 0xFF51_AFD7_ED55_8CCD
    x ^= x >> 33
    x = x &* 0xC4CE_B9FE_1A85_EC53
    x ^= x >> 33
    return Double(x % 10_000) / 10_000
}

func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let ra = NSColor(a).usingColorSpace(.sRGB) ?? .white
    let rb = NSColor(b).usingColorSpace(.sRGB) ?? .white
    let t = max(0, min(1, t))
    return Color(
        .sRGB,
        red: ra.redComponent + (rb.redComponent - ra.redComponent) * t,
        green: ra.greenComponent + (rb.greenComponent - ra.greenComponent) * t,
        blue: ra.blueComponent + (rb.blueComponent - ra.blueComponent) * t,
        opacity: ra.alphaComponent + (rb.alphaComponent - ra.alphaComponent) * t
    )
}

/// Draws engine particles with a palette indexed by `tint`.
func drawParticles(_ particles: [Particle], in ctx: GraphicsContext, palette: [Color], scale: CGFloat = 1) {
    for p in particles {
        let alpha = max(0, 1 - p.progress)
        let color = palette[min(max(0, p.tint), palette.count - 1)].opacity(alpha)
        let r = p.size * scale * (0.6 + 0.4 * alpha)
        ctx.fillCircle(CGPoint(x: p.position.x * scale, y: p.position.y * scale), radius: r, with: .color(color))
    }
}

/// Subtle dotted grid used as a backdrop by several games.
func drawDotGrid(_ ctx: GraphicsContext, size: CGSize, spacing: CGFloat, color: Color) {
    var path = Path()
    var y = spacing / 2
    while y < size.height {
        var x = spacing / 2
        while x < size.width {
            path.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
            x += spacing
        }
        y += spacing
    }
    ctx.fill(path, with: .color(color))
}

/// Maps view points into a Canvas scene drawn with `fit(_:in:)`.
struct SceneMapping {
    let logical: CGSize
    let size: CGSize

    func point(_ p: CGPoint) -> CGPoint {
        let s = min(size.width / logical.width, size.height / logical.height)
        let ox = (size.width - logical.width * s) / 2
        let oy = (size.height - logical.height * s) / 2
        return CGPoint(x: (p.x - ox) / s, y: (p.y - oy) / s)
    }
}

/// Small caps label used in game side panels.
func panelLabel(_ text: String, in ctx: GraphicsContext, at point: CGPoint, anchor: UnitPoint = .topLeading, opacity: Double = 0.34) {
    let label = Text(text.uppercased()).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1.2).foregroundStyle(Color.white.opacity(opacity))
    ctx.draw(label, at: point, anchor: anchor)
}

/// A big monospaced value for side panels.
func panelValue(_ text: String, in ctx: GraphicsContext, at point: CGPoint, size: CGFloat = 20, color: Color = .white, anchor: UnitPoint = .topLeading) {
    let value = Text(text).font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit()).foregroundStyle(color)
    ctx.draw(value, at: point, anchor: anchor)
}
