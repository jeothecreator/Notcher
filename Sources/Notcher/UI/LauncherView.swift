import NotcherCore
import SwiftUI

struct LauncherView: View {
    let arcade: ArcadeController

    var body: some View {
        let m = arcade.metrics
        VStack(spacing: 0) {
            header(m)
                .frame(height: m.notchHeight)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    group(.quick)
                    Spacer(minLength: 0)
                    group(.brain)
                }
                HStack(alignment: .top, spacing: 16) {
                    group(.idle)
                    group(.classics)
                    DailyCard(arcade: arcade)
                }
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            footer
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 26)
        .background(ambientGlow)
    }

    // MARK: Header

    private func header(_ m: NotchMetrics) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                NotcherMark(size: 12)
                Text("notcher")
                    .font(Theme.rounded(13.5, .heavy))
                    .foregroundStyle(Theme.primary)
            }
            Spacer(minLength: m.notchWidth + 24)
            HStack(spacing: 8) {
                if arcade.save.stats.dailyStreak(today: Date()) > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFB340), Color(hex: 0xFF375F)], startPoint: .top, endPoint: .bottom))
                        Text("\(arcade.save.stats.dailyStreak(today: Date()))")
                            .foregroundStyle(Theme.primary)
                    }
                    .font(Theme.mono(11, .bold))
                    .padding(.trailing, 4)
                }
                HeaderButton(symbol: "trophy.fill", item: .trophies, arcade: arcade)
                HeaderButton(symbol: "gearshape.fill", item: .settings, arcade: arcade)
            }
        }
        .padding(.top, m.hasNotch ? 0 : 4)
    }

    // MARK: Groups

    private func group(_ category: GameCategory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(category.title.uppercased())
                .font(Theme.rounded(8.5, .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.tertiary)
                .padding(.leading, 2)
            HStack(spacing: 8) {
                ForEach(GameID.inCategory(category)) { game in
                    GameTile(game: game, arcade: arcade)
                }
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        let item = arcade.hovered ?? (arcade.isFocused ? arcade.selection : nil)
        HStack(spacing: 10) {
            switch item {
            case .game(let game):
                GameGlyph(game: game, size: 14)
                Text(game.title)
                    .font(Theme.rounded(11.5, .bold))
                    .foregroundStyle(Theme.primary)
                Text(game.tagline)
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
                HintRow(hints: game.controls)
            case .daily:
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFB340), Color(hex: 0xFF375F)], startPoint: .top, endPoint: .bottom))
                Text("Daily challenge")
                    .font(Theme.rounded(11.5, .bold))
                    .foregroundStyle(Theme.primary)
                Text("Same seed for everyone, today only.")
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
            case .trophies:
                Text("Leaderboards, achievements and stats")
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
            case .settings:
                Text("Settings")
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
            case nil:
                Text(Prefs.hoverLaunch == .click ? "Click a game to play" : "Hover a game to play")
                    .font(Theme.rounded(11, .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
                HintLabel(keys: "esc", action: "back to work")
                if Prefs.hotkey != .off {
                    HintLabel(keys: Prefs.hotkey.title, action: "open")
                }
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.15), value: item)
    }

    /// Soft light from the hovered game's colour.
    private var ambientGlow: some View {
        GeometryReader { proxy in
            if case .game(let game)? = arcade.hovered, let frame = arcade.itemFrames[.game(game)] {
                let origin = proxy.frame(in: .named("panel")).origin
                RadialGradient(
                    colors: [game.style.accent.opacity(0.22), .clear],
                    center: UnitPoint(
                        x: (frame.midX - origin.x) / max(1, proxy.size.width),
                        y: (frame.midY - origin.y) / max(1, proxy.size.height)
                    ),
                    startRadius: 4, endRadius: 260
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.3), value: arcade.hovered)
    }
}

// MARK: - Tile

struct GameTile: View {
    let game: GameID
    let arcade: ArcadeController
    @State private var charge: CGFloat = 0
    @Environment(\.previewRendering) private var previewRendering

    private var isHovered: Bool { arcade.hovered == .game(game) }
    private var isSelected: Bool { arcade.isFocused && arcade.selection == .game(game) && arcade.hovered == nil }
    private var isCharging: Bool { arcade.charging == .game(game) }

    var body: some View {
        let style = game.style
        let active = isHovered || isSelected
        Button {
            arcade.activate(.game(game))
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [style.accent.opacity(0.28), style.deep.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Theme.surface))
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(active ? style.accent.opacity(0.55) : Theme.stroke, lineWidth: active ? 1 : 0.75)
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .trim(from: 0, to: previewRendering && isCharging ? 0.62 : charge)
                    .stroke(style.gradient, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .shadow(color: style.accent.opacity(0.8), radius: 4)

                VStack(spacing: 5) {
                    GameGlyph(game: game, size: 26)
                        .shadow(color: style.accent.opacity(active ? 0.7 : 0), radius: 8)
                    Text(game.title)
                        .font(Theme.rounded(10.5, .bold))
                        .foregroundStyle(active ? Theme.primary : Theme.primary.opacity(0.82))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.mono(8.5, .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
                .padding(.top, 3)

                if arcade.isPaused(game) {
                    Circle()
                        .fill(style.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: style.accent, radius: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(8)
                }
            }
            .frame(width: 74, height: 74)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.08 : 1)
        .shadow(color: style.accent.opacity(active ? 0.35 : 0), radius: 14, y: 4)
        .animation(Theme.snappy, value: active)
        .hoverItem(.game(game))
        .onChange(of: isCharging) { _, charging in
            if charging {
                charge = 0
                withAnimation(.linear(duration: arcade.chargeDuration)) { charge = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { charge = 0 }
            }
        }
    }

    private var subtitle: String {
        switch game {
        case .miner:
            guard let state = arcade.minerState else { return "Start digging" }
            return "◆ " + Format.compact(MinerEngine.projectedCoins(state, at: Date()))
        case .farm:
            guard let state = arcade.farmState else { return "Plant seeds" }
            let ready = state.readyCount(at: Date())
            return ready > 0 ? "\(ready) ready" : "\(state.coins) coins"
        case .arcade:
            return "Today: " + ArcadeMini.featured(on: Date()).title
        default:
            guard let best = arcade.save.scores.best(game.rawValue) else { return "New" }
            return Format.score(best, format: game.scoreFormat)
        }
    }
}

struct HeaderButton: View {
    let symbol: String
    let item: LauncherItem
    let arcade: ArcadeController

    var body: some View {
        let hovered = arcade.hovered == item || (arcade.isFocused && arcade.hovered == nil && arcade.selection == item)
        Button {
            arcade.activate(item)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? Theme.primary : Theme.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovered ? Theme.surfaceHover : Theme.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverItem(item)
        .animation(Theme.snappy, value: hovered)
    }
}

// MARK: - Daily

struct DailyCard: View {
    let arcade: ArcadeController
    @State private var charge: CGFloat = 0

    private var isHovered: Bool { arcade.hovered == .daily }
    private var isSelected: Bool { arcade.isFocused && arcade.selection == .daily && arcade.hovered == nil }

    var body: some View {
        let challenge = arcade.daily
        let colors = [Color(hex: 0xFFB340), Color(hex: 0xFF375F)]
        let active = isHovered || isSelected
        Button {
            arcade.activate(.daily)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: arcade.dailyDone ? "checkmark" : "flame.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.78))
                }
                .frame(width: 38, height: 38)
                .shadow(color: colors[1].opacity(active ? 0.7 : 0.3), radius: active ? 12 : 6)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("DAILY CHALLENGE")
                            .font(Theme.rounded(8.5, .heavy))
                            .tracking(1)
                            .foregroundStyle(Theme.tertiary)
                        if arcade.dailyDone { Chip(text: "DONE", colors: colors, foreground: .black) }
                    }
                    HStack(spacing: 5) {
                        GameGlyph(game: challenge.game, size: 13)
                        Text(challenge.game.title)
                            .font(Theme.rounded(12.5, .bold))
                            .foregroundStyle(Theme.primary)
                    }
                    Text(challenge.goal)
                        .font(Theme.rounded(10.5, .semibold))
                        .foregroundStyle(Theme.secondary)
                    Text(arcade.dailyBest.map { "Today's best: " + Format.score($0, format: challenge.game.scoreFormat) } ?? "Not played yet")
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(LinearGradient(colors: [colors[0].opacity(active ? 0.2 : 0.1), colors[1].opacity(active ? 0.14 : 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(LinearGradient(colors: colors.map { $0.opacity(active ? 0.7 : 0.3) }, startPoint: .leading, endPoint: .trailing), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .trim(from: 0, to: charge)
                    .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            )
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.03 : 1)
        .animation(Theme.snappy, value: active)
        .hoverItem(.daily)
        .padding(.top, 17)
        .onChange(of: arcade.charging == .daily) { _, charging in
            if charging {
                charge = 0
                withAnimation(.linear(duration: arcade.chargeDuration)) { charge = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { charge = 0 }
            }
        }
    }
}
