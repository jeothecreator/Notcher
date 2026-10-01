import NotcherCore
import SwiftUI

/// The expanded notch: a sidebar of pages, a grid of game posters and a
/// footer that describes whatever is under the pointer.
struct LauncherView: View {
    let arcade: ArcadeController

    static let sidebarWidth: CGFloat = 128
    static let gridSize = CGSize(width: 588, height: 182)
    static let spacing: CGFloat = 10

    var body: some View {
        let m = arcade.metrics
        VStack(spacing: 0) {
            LauncherHeader(arcade: arcade)
                .frame(height: m.notchHeight)
                .padding(.top, m.hasNotch ? 0 : 4)

            HStack(alignment: .top, spacing: 16) {
                LauncherSidebar(arcade: arcade)
                    .frame(width: Self.sidebarWidth, height: Self.gridSize.height + 30)
                ZStack(alignment: .topLeading) {
                    PageContent(arcade: arcade, page: arcade.page)
                        .id(arcade.page)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.animation(.easeOut(duration: 0.08))
                        ))
                }
                .frame(width: Self.gridSize.width, height: Self.gridSize.height + 30, alignment: .topLeading)
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            LauncherFooter(arcade: arcade)
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 24)
        .background(AmbientGlow(arcade: arcade))
    }
}

// MARK: - Header

struct LauncherHeader: View {
    let arcade: ArcadeController

    var body: some View {
        let m = arcade.metrics
        let streak = arcade.save.stats.dailyStreak(today: Date())
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                NotcherMark(size: 12)
                Text("notcher")
                    .font(Theme.rounded(13.5, .heavy))
                    .foregroundStyle(Theme.primary)
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(LinearGradient(colors: Theme.dailyColors, startPoint: .top, endPoint: .bottom))
                        Text("\(streak)")
                            .foregroundStyle(Theme.primary)
                    }
                    .font(Theme.mono(10.5, .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.dailyColors[1].opacity(0.14)))
                    .padding(.leading, 4)
                    .help("Daily challenge streak")
                }
            }
            Spacer(minLength: m.notchWidth + 24)
            HStack(spacing: 6) {
                HeaderButton(symbol: "trophy.fill", item: .trophies, arcade: arcade, help: "Achievements and records")
                HeaderButton(symbol: "gearshape.fill", item: .settings, arcade: arcade, help: "Settings")
                QuitButton(arcade: arcade)
            }
        }
    }
}

struct HeaderButton: View {
    let symbol: String
    let item: LauncherItem
    let arcade: ArcadeController
    var help: String = ""

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
                .overlay(Circle().strokeBorder(Color.white.opacity(hovered ? 0.14 : 0), lineWidth: 0.75))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverItem(item)
        .help(help)
        .animation(Theme.snappy, value: hovered)
    }
}

/// Click once to arm, again to quit. Disarms itself after three seconds.
struct QuitButton: View {
    let arcade: ArcadeController

    var body: some View {
        let armed = arcade.quitArmed
        let hovered = arcade.hovered == .quit || (arcade.isFocused && arcade.hovered == nil && arcade.selection == .quit)
        let red = Color(hex: 0xFF5A5F)
        Button {
            arcade.activate(.quit)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "power")
                    .font(.system(size: 10.5, weight: .bold))
                if armed {
                    Text("Quit Notcher")
                        .font(Theme.rounded(10.5, .bold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundStyle(armed ? Color.white : (hovered ? red : Theme.secondary))
            .padding(.horizontal, armed ? 10 : 0)
            .frame(minWidth: 24, minHeight: 24)
            .background(
                Capsule().fill(armed ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF6B6B), Color(hex: 0xE5484D)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(hovered ? red.opacity(0.16) : Theme.surface))
            )
            .shadow(color: armed ? red.opacity(0.5) : .clear, radius: 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverItem(.quit)
        .help("Quit Notcher")
        .animation(Theme.snappy, value: armed)
        .animation(Theme.snappy, value: hovered)
    }
}

// MARK: - Sidebar

struct LauncherSidebar: View {
    let arcade: ArcadeController

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(LauncherPage.all, id: \.self) { page in
                SidebarRow(arcade: arcade, page: page)
            }
            Spacer(minLength: 0)
            ProfileChip(arcade: arcade)
        }
    }
}

struct SidebarRow: View {
    let arcade: ArcadeController
    let page: LauncherPage

    var body: some View {
        let current = arcade.page == page
        let hovered = arcade.hovered == .page(page)
        let keyed = arcade.isFocused && arcade.hovered == nil && arcade.selection == .page(page)
        Button {
            arcade.activate(.page(page))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbol)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(current ? AnyShapeStyle(LinearGradient(colors: page.colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Theme.tertiary))
                    .frame(width: 16)
                Text(page.title)
                    .font(Theme.rounded(12, .bold))
                    .foregroundStyle(current || hovered ? Theme.primary : Theme.secondary)
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(current ? 0.09 : (hovered ? 0.05 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(keyed ? 0.32 : 0), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: page.colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: current ? 14 : 0)
                    .shadow(color: page.colors[0].opacity(0.7), radius: 4)
                    .offset(x: -1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverItem(.page(page))
        .animation(Theme.snappy, value: current)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder private var trailing: some View {
        switch page {
        case .forYou:
            if !arcade.dailyDone {
                Circle()
                    .fill(LinearGradient(colors: Theme.dailyColors, startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.dailyColors[1].opacity(0.8), radius: 3)
                    .help("Today's challenge is waiting")
            }
        case .category:
            Text("\(page.games.count)")
                .font(Theme.mono(9.5, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

struct ProfileChip: View {
    let arcade: ArcadeController

    var body: some View {
        let unlocked = arcade.save.achievements.count
        let total = AchievementCatalog.all.count
        Button {
            arcade.showTrophies()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: CGFloat(unlocked) / CGFloat(max(1, total)))
                        .stroke(LinearGradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF9F0A)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 2)
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(arcade.save.profile.displayName)
                        .font(Theme.rounded(10.5, .bold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                    Text("\(unlocked)/\(total) trophies")
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .cardBackground(cornerRadius: 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pages

struct PageContent: View {
    let arcade: ArcadeController
    let page: LauncherPage

    var body: some View {
        VStack(alignment: .leading, spacing: LauncherView.spacing) {
            PageHeading(arcade: arcade, page: page)
                .frame(height: 20)
            switch page {
            case .forYou:
                forYou
            case .category:
                categoryGrid(page.games)
            }
        }
    }

    private static func tileSize(columns: Int, rows: Int) -> CGSize {
        let grid = LauncherView.gridSize
        let s = LauncherView.spacing
        return CGSize(
            width: ((grid.width - CGFloat(columns - 1) * s) / CGFloat(columns)).rounded(.down),
            height: ((grid.height - CGFloat(rows - 1) * s) / CGFloat(rows)).rounded(.down)
        )
    }

    private var forYou: some View {
        let picks = arcade.forYouGames
        let tile = Self.tileSize(columns: 4, rows: 2)
        return VStack(alignment: .leading, spacing: LauncherView.spacing) {
            HStack(spacing: LauncherView.spacing) {
                DailyCard(arcade: arcade, size: CGSize(width: tile.width * 2 + LauncherView.spacing, height: tile.height))
                ForEach(Array(picks.prefix(2))) { game in
                    GameTile(game: game, arcade: arcade, size: tile)
                }
            }
            HStack(spacing: LauncherView.spacing) {
                ForEach(Array(picks.dropFirst(2).prefix(4))) { game in
                    GameTile(game: game, arcade: arcade, size: tile)
                }
            }
        }
    }

    private func categoryGrid(_ games: [GameID]) -> some View {
        let columns = games.count <= 2 ? 2 : 4
        let rows = games.count <= 4 ? 1 : 2
        let tile = Self.tileSize(columns: columns, rows: rows)
        return VStack(alignment: .leading, spacing: LauncherView.spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: LauncherView.spacing) {
                    ForEach(Array(games[(row * columns)..<min(games.count, (row + 1) * columns)])) { game in
                        GameTile(game: game, arcade: arcade, size: tile)
                    }
                }
            }
        }
    }
}

struct PageHeading: View {
    let arcade: ArcadeController
    let page: LauncherPage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Theme.rounded(14, .heavy))
                .foregroundStyle(Theme.primary)
            Text(subtitle)
                .font(Theme.rounded(11, .medium))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if case .category = page {
                Text("\(page.games.count) games")
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var title: String {
        switch page {
        case .forYou:
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12: return "Good morning"
            case 12..<18: return "Good afternoon"
            default: return "Good evening"
            }
        case .category(let c):
            return c.title
        }
    }

    private var subtitle: String {
        switch page {
        case .forYou:
            return arcade.save.stats.recent.isEmpty ? "Twenty games, one notch. Esc is always one key away." : "Pick up where you left off."
        case .category(let c):
            return c.subtitle
        }
    }
}

// MARK: - Game tile

/// A poster for one game. Compact tiles show the title and best score; tall
/// tiles add the tagline or a short description.
struct GameTile: View {
    let game: GameID
    let arcade: ArcadeController
    let size: CGSize
    @State private var charge: CGFloat = 0
    @Environment(\.previewRendering) private var previewRendering

    private var isHovered: Bool { arcade.hovered == .game(game) }
    private var isSelected: Bool { arcade.isFocused && arcade.selection == .game(game) && arcade.hovered == nil }
    private var isCharging: Bool { arcade.charging == .game(game) }
    private var tall: Bool { size.height > 120 }

    var body: some View {
        let style = game.style
        let active = isHovered || isSelected
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button {
            arcade.activate(.game(game))
        } label: {
            ZStack(alignment: .topLeading) {
                shape.fill(Color(hex: 0x111116))
                shape.fill(LinearGradient(
                    colors: [style.accent.opacity(active ? 0.26 : 0.12), style.deep.opacity(active ? 0.12 : 0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                GameGlyph(game: game, size: tall ? 118 : 72)
                    .opacity(active ? 0.24 : 0.12)
                    .rotationEffect(.degrees(-14))
                    .offset(x: size.width - (tall ? 92 : 56), y: size.height - (tall ? 96 : 58))
                    .blur(radius: active ? 0 : 0.5)
                TileLabel(game: game, arcade: arcade, tall: tall, wide: size.width > 200, active: active)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(active ? style.accent.opacity(0.6) : Theme.stroke, lineWidth: active ? 1 : 0.75))
            .overlay(
                shape
                    .trim(from: 0, to: previewRendering && isCharging ? 0.62 : charge)
                    .stroke(style.gradient, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .shadow(color: style.accent.opacity(0.8), radius: 4)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.04 : 1)
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
}

struct TileLabel: View {
    let game: GameID
    let arcade: ArcadeController
    let tall: Bool
    let wide: Bool
    let active: Bool

    var body: some View {
        let style = game.style
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                GameGlyph(game: game, size: tall ? 26 : 20)
                    .shadow(color: style.accent.opacity(active ? 0.8 : 0.3), radius: active ? 8 : 4)
                Spacer(minLength: 0)
                badge
            }
            Spacer(minLength: 0)
            Text(game.title)
                .font(Theme.rounded(tall ? 17 : 13, .heavy))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
            if tall {
                Text(wide ? game.summary : game.tagline)
                    .font(Theme.rounded(10.5, .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(wide ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Text(status)
                .font(Theme.mono(9.5, .semibold))
                .foregroundStyle(active ? AnyShapeStyle(style.accent) : AnyShapeStyle(Theme.tertiary))
                .lineLimit(1)
                .padding(.top, tall ? 7 : 1)
        }
        .padding(tall ? 14 : 11)
    }

    @ViewBuilder private var badge: some View {
        if arcade.isPaused(game) {
            Chip(text: "PAUSED")
        } else if arcade.isUnplayedNew(game) {
            Chip(text: "NEW", colors: game.style.colors, foreground: .black)
        }
    }

    private var status: String {
        switch game {
        case .miner:
            guard let state = arcade.minerState else { return "Start digging" }
            return "◆ " + Format.compact(MinerEngine.projectedCoins(state, at: Date()))
        case .farm:
            guard let state = arcade.farmState else { return "Plant your first seed" }
            let ready = state.readyCount(at: Date())
            return ready > 0 ? "\(ready) ready to harvest" : "\(state.coins) coins"
        case .arcade:
            return "Today: " + ArcadeMini.featured(on: Date()).title
        default:
            guard let best = arcade.save.scores.best(game.rawValue) else {
                return arcade.isUnplayedNew(game) ? "Just added" : "Not played yet"
            }
            return "Best " + Format.score(best, format: game.scoreFormat)
        }
    }
}

// MARK: - Daily

struct DailyCard: View {
    let arcade: ArcadeController
    let size: CGSize
    @State private var charge: CGFloat = 0
    @Environment(\.previewRendering) private var previewRendering

    private var isHovered: Bool { arcade.hovered == .daily }
    private var isSelected: Bool { arcade.isFocused && arcade.selection == .daily && arcade.hovered == nil }
    private var isCharging: Bool { arcade.charging == .daily }

    var body: some View {
        let challenge = arcade.daily
        let colors = Theme.dailyColors
        let active = isHovered || isSelected
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button {
            arcade.activate(.daily)
        } label: {
            ZStack(alignment: .topLeading) {
                shape.fill(Color(hex: 0x141110))
                shape.fill(LinearGradient(
                    colors: [colors[0].opacity(active ? 0.26 : 0.14), colors[1].opacity(active ? 0.16 : 0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                GameGlyph(game: challenge.game, size: 84)
                    .opacity(0.1)
                    .rotationEffect(.degrees(-14))
                    .offset(x: size.width - 74, y: 12)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: arcade.dailyDone ? "checkmark" : "flame.fill")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                    .frame(width: 40, height: 40)
                    .shadow(color: colors[1].opacity(active ? 0.7 : 0.35), radius: active ? 12 : 6)

                    VStack(alignment: .leading, spacing: 2) {
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
                                .font(Theme.rounded(13.5, .heavy))
                                .foregroundStyle(Theme.primary)
                        }
                        Text(challenge.goal)
                            .font(Theme.rounded(10.5, .semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                        Text(arcade.dailyBest.map { "Today's best " + Format.score($0, format: challenge.game.scoreFormat) } ?? "Same puzzle for everyone")
                            .font(Theme.mono(9, .semibold))
                            .foregroundStyle(Theme.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)

                Text(Self.timeLeft(Date()))
                    .font(Theme.mono(9, .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: colors.map { $0.opacity(active ? 0.7 : 0.28) }, startPoint: .leading, endPoint: .trailing), lineWidth: 1))
            .overlay(
                shape
                    .trim(from: 0, to: previewRendering && isCharging ? 0.62 : charge)
                    .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.02 : 1)
        .shadow(color: colors[1].opacity(active ? 0.3 : 0), radius: 14, y: 4)
        .animation(Theme.snappy, value: active)
        .hoverItem(.daily)
        .onChange(of: isCharging) { _, charging in
            if charging {
                charge = 0
                withAnimation(.linear(duration: arcade.chargeDuration)) { charge = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { charge = 0 }
            }
        }
    }

    /// "5h left" until the next challenge.
    static func timeLeft(_ now: Date) -> String {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return "" }
        let minutes = max(0, Int(tomorrow.timeIntervalSince(now) / 60))
        return minutes >= 60 ? "\(minutes / 60)h left" : "\(minutes)m left"
    }
}

// MARK: - Footer

struct LauncherFooter: View {
    let arcade: ArcadeController

    var body: some View {
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
                    .lineLimit(1)
                Spacer(minLength: 8)
                HintRow(hints: game.controls)
            case .daily:
                Image(systemName: "flame.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: Theme.dailyColors, startPoint: .top, endPoint: .bottom))
                Text("Daily challenge")
                    .font(Theme.rounded(11.5, .bold))
                    .foregroundStyle(Theme.primary)
                Text("Same seed for everyone. Complete it daily to build a streak.")
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
            case .page(let page):
                Image(systemName: page.symbol)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: page.colors, startPoint: .top, endPoint: .bottom))
                Text(page.title)
                    .font(Theme.rounded(11.5, .bold))
                    .foregroundStyle(Theme.primary)
                Text(pageDetail(page))
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HintLabel(keys: "tab", action: "next page")
            case .trophies:
                label("Trophies", "Achievements, personal records and stats")
            case .settings:
                label("Settings", "Hover timing, shortcut, sound and more")
                HintLabel(keys: "⌘,", action: "open")
            case .quit:
                label(arcade.quitArmed ? "Click again to quit" : "Quit Notcher", "Your progress is saved automatically")
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

    @ViewBuilder
    private func label(_ title: String, _ detail: String) -> some View {
        Text(title)
            .font(Theme.rounded(11.5, .bold))
            .foregroundStyle(Theme.primary)
        Text(detail)
            .font(Theme.rounded(11, .medium))
            .foregroundStyle(Theme.secondary)
        Spacer(minLength: 8)
    }

    private func pageDetail(_ page: LauncherPage) -> String {
        switch page {
        case .forYou: return "Today's challenge, recent games and new arrivals"
        case .category(let c): return GameID.inCategory(c).map(\.title).joined(separator: " · ")
        }
    }
}

// MARK: - Glow

/// Soft light from the hovered game's colour.
struct AmbientGlow: View {
    let arcade: ArcadeController

    var body: some View {
        GeometryReader { proxy in
            if case .game(let game)? = arcade.hovered, let frame = arcade.itemFrames[.game(game)] {
                let origin = proxy.frame(in: .named("panel")).origin
                RadialGradient(
                    colors: [game.style.accent.opacity(0.2), .clear],
                    center: UnitPoint(
                        x: (frame.midX - origin.x) / max(1, proxy.size.width),
                        y: (frame.midY - origin.y) / max(1, proxy.size.height)
                    ),
                    startRadius: 4, endRadius: 280
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.3), value: arcade.hovered)
    }
}
