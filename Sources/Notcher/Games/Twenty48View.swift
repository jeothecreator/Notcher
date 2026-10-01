import NotcherCore
import SwiftUI

struct Twenty48View: View {
    let session: GameSession
    let engine: Twenty48Engine
    let revision: Int

    static let cell: CGFloat = 50
    static let gap: CGFloat = 6
    static var boardSize: CGFloat { cell * 4 + gap * 5 }

    var body: some View {
        HStack(spacing: 28) {
            board
            sidebar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color(hex: 0xFF9F0A).opacity(0.1), .clear], center: .leading, startRadius: 10, endRadius: 360)
        )
    }

    private var board: some View {
        let size = Self.boardSize
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
            ForEach(0..<16, id: \.self) { i in
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .frame(width: Self.cell, height: Self.cell)
                    .position(Self.center(row: i / 4, col: i % 4))
            }
            ForEach(engine.tiles) { tile in
                TileView(value: tile.value, merged: tile.isMerged)
                    .frame(width: Self.cell, height: Self.cell)
                    .position(Self.center(row: tile.row, col: tile.col))
                    .zIndex(tile.isGhost ? 0 : 1)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.4).combined(with: .opacity).animation(.spring(response: 0.22, dampingFraction: 0.62).delay(0.06)),
                            removal: .opacity.animation(.easeOut(duration: 0.05))
                        )
                    )
            }

            if engine.showWinBanner {
                VStack(spacing: 6) {
                    Text("2048!")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF9F0A)], startPoint: .top, endPoint: .bottom))
                    HintLabel(keys: "space", action: "keep going")
                }
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.7)))
                .zIndex(3)
                .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.17, dampingFraction: 0.9), value: engine.moveCount)
    }

    static func center(row: Int, col: Int) -> CGPoint {
        CGPoint(
            x: gap + CGFloat(col) * (cell + gap) + cell / 2,
            y: gap + CGFloat(row) * (cell + gap) + cell / 2
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            statBlock("SCORE", Format.grouped(engine.score), big: true)
            HStack(spacing: 24) {
                statBlock("TOP TILE", Format.grouped(engine.bestTile), big: false)
                statBlock("MOVES", Format.grouped(engine.moves), big: false)
            }
            HStack(spacing: 6) {
                Keycap(label: "U")
                Text("undo")
                    .font(Theme.rounded(10.5, .medium))
                    .foregroundStyle(Theme.secondary)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i < engine.undosLeft ? Color(hex: 0xFFB340) : Color.white.opacity(0.12))
                            .frame(width: 5, height: 5)
                    }
                }
            }
            if engine.phase == .ready {
                HStack(spacing: 5) {
                    Keycap(label: "↑↓←→", highlighted: true)
                    Text("to start sliding")
                        .font(Theme.rounded(10.5, .semibold))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(width: 210, alignment: .leading)
    }

    private func statBlock(_ title: String, _ value: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Theme.rounded(8.5, .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiary)
            Text(value)
                .font(Theme.mono(big ? 30 : 15, .heavy))
                .foregroundStyle(big ? AnyShapeStyle(LinearGradient(colors: [.white, Color(hex: 0xFFB340)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.primary))
                .contentTransition(.numericText())
        }
    }
}

struct TileView: View {
    let value: Int
    let merged: Bool

    var body: some View {
        let style = Self.style(for: value)
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
            Text("\(value)")
                .font(.system(size: value >= 1000 ? 15 : (value >= 100 ? 18 : 22), weight: .black, design: .rounded))
                .foregroundStyle(style.text)
                .minimumScaleFactor(0.5)
                .padding(3)
        }
        .shadow(color: (value >= 128 ? style.colors[0] : .clear).opacity(0.5), radius: value >= 128 ? 8 : 0)
    }

    static func style(for value: Int) -> (colors: [Color], text: Color) {
        let dark = Color(hex: 0x16161C)
        switch value {
        case 2: return ([Color(hex: 0x34333F), Color(hex: 0x2A2933)], Color(hex: 0xEDEBF5))
        case 4: return ([Color(hex: 0x45404F), Color(hex: 0x37333F)], Color(hex: 0xF5F3FB))
        case 8: return ([Color(hex: 0xFFB36B), Color(hex: 0xFF8A3D)], .white)
        case 16: return ([Color(hex: 0xFF9A6B), Color(hex: 0xFF6A3D)], .white)
        case 32: return ([Color(hex: 0xFF7F75), Color(hex: 0xF04E4E)], .white)
        case 64: return ([Color(hex: 0xFF6B8E), Color(hex: 0xE5245F)], .white)
        case 128: return ([Color(hex: 0xFFE59A), Color(hex: 0xFFC94A)], dark)
        case 256: return ([Color(hex: 0xFFDA6B), Color(hex: 0xFFB800)], dark)
        case 512: return ([Color(hex: 0xFFCB45), Color(hex: 0xFF9F0A)], dark)
        case 1024: return ([Color(hex: 0x8CF2B0), Color(hex: 0x34C759)], dark)
        case 2048: return ([Color(hex: 0x8BE9FF), Color(hex: 0x22B5E8)], dark)
        default: return ([Color(hex: 0xD2B8FF), Color(hex: 0x8B5CFF)], .white)
        }
    }
}
