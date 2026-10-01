import SwiftUI

/// The notch silhouette: concave flares at the top so it melts into the
/// bezel, rounded corners at the bottom like the Dynamic Island.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-left flare.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        // Bottom-left corner.
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        // Bottom-right corner.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Top-right flare.
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}
