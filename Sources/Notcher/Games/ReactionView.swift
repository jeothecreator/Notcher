import NotcherCore
import SwiftUI

struct ReactionView: View {
    let engine: ReactionEngine
    let revision: Int

    var body: some View {
        ZStack {
            background
            content
        }
    }

    @ViewBuilder private var background: some View {
        switch engine.stage {
        case .waiting:
            LinearGradient(colors: [Color(hex: 0x3A0D16), Color(hex: 0x24070D)], startPoint: .top, endPoint: .bottom)
        case .go:
            ZStack {
                LinearGradient(colors: [Color(hex: 0x4BE37A), Color(hex: 0x1FA84E)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 300)
            }
        case .early:
            LinearGradient(colors: [Color(hex: 0x3D2A08), Color(hex: 0x241805)], startPoint: .top, endPoint: .bottom)
        case .intro, .result:
            RadialGradient(colors: [Color(hex: 0x34C759).opacity(0.12), Theme.field], center: .center, startRadius: 10, endRadius: 340)
        }
    }

    @ViewBuilder private var content: some View {
        switch engine.stage {
        case .intro:
            VStack(spacing: 10) {
                GameGlyph(game: .reaction, size: 30)
                Text("Reaction")
                    .font(Theme.rounded(22, .heavy))
                    .foregroundStyle(Theme.primary)
                Text("Wait for green, then hit space as fast as you can.")
                    .font(Theme.rounded(11.5, .medium))
                    .foregroundStyle(Theme.secondary)
                startHint("to begin")
            }
        case .waiting:
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color(hex: 0xFF6B6B))
                            .frame(width: 9, height: 9)
                            .opacity(0.3 + 0.7 * max(0, sin(engine.clock * 5 - Double(i) * 0.7)))
                    }
                }
                Text("Wait for green…")
                    .font(Theme.rounded(26, .heavy))
                    .foregroundStyle(Color(hex: 0xFFB3B3))
            }
        case .go:
            Text("NOW!")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 8)
        case .early:
            VStack(spacing: 8) {
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFD66B))
                Text("Too soon!")
                    .font(Theme.rounded(26, .heavy))
                    .foregroundStyle(Color(hex: 0xFFE3A3))
                startHint("to try again")
            }
        case .result(let ms):
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text(rating(ms).uppercased())
                        .font(Theme.rounded(11, .heavy))
                        .tracking(2)
                        .foregroundStyle(ratingColor(ms))
                    Text("\(ms)")
                        .font(.system(size: 72, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(LinearGradient(colors: [.white, ratingColor(ms)], startPoint: .top, endPoint: .bottom))
                    + Text(" ms")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                    startHint("to go again")
                }
                history
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST ATTEMPTS")
                .font(Theme.rounded(8.5, .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiary)
            let recent = Array(engine.attempts.suffix(5))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(recent.enumerated()), id: \.offset) { item in
                    let ms = item.element
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(ratingColor(ms))
                            .frame(width: 16, height: max(6, min(70, 70 * 160 / Double(max(ms, 1)))))
                        Text("\(ms)")
                            .font(Theme.mono(8, .bold))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .frame(height: 86, alignment: .bottom)
            if let avg = engine.average, let best = engine.best {
                Text("avg \(avg) ms · best \(best) ms")
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func startHint(_ action: String) -> some View {
        HStack(spacing: 5) {
            Text("Press").foregroundStyle(Theme.secondary)
            Keycap(label: "space", highlighted: true)
            Text(action).foregroundStyle(Theme.secondary)
        }
        .font(Theme.rounded(11, .semibold))
        .padding(.top, 6)
    }

    private func rating(_ ms: Int) -> String {
        switch ms {
        case ..<180: return "Lightning"
        case ..<230: return "Excellent"
        case ..<280: return "Great"
        case ..<350: return "Good"
        default: return "Sleepy"
        }
    }

    private func ratingColor(_ ms: Int) -> Color {
        switch ms {
        case ..<180: return Color(hex: 0x8BE9FF)
        case ..<230: return Color(hex: 0x6EE7A0)
        case ..<280: return Color(hex: 0xC6F76B)
        case ..<350: return Color(hex: 0xFFD66B)
        default: return Color(hex: 0xFF8A80)
        }
    }
}
