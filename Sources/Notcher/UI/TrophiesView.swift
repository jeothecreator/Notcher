import NotcherCore
import SwiftUI

struct TrophiesView: View {
    let arcade: ArcadeController

    enum Tab: String, CaseIterable {
        case leaderboards = "Leaderboards"
        case achievements = "Achievements"
        case stats = "Stats"
    }

    @State private var tab: Tab = .leaderboards

    var body: some View {
        let m = arcade.metrics
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    arcade.open(focus: arcade.isFocused)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("Arcade")
                            .font(Theme.rounded(12, .bold))
                    }
                    .foregroundStyle(Theme.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: m.notchWidth + 24)
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                    Text(arcade.save.profile.displayName)
                        .font(Theme.rounded(11.5, .bold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(height: m.notchHeight)

            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        withAnimation(Theme.snappy) { tab = t }
                    } label: {
                        Text(t.rawValue)
                            .font(Theme.rounded(11, .bold))
                            .foregroundStyle(tab == t ? Color.black : Theme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(tab == t ? Color.white : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("\(arcade.save.achievements.count)/\(AchievementCatalog.all.count) achievements")
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.top, 10)

            Group {
                switch tab {
                case .leaderboards: LeaderboardsPane(arcade: arcade)
                case .achievements: AchievementsPane(arcade: arcade)
                case .stats: StatsPane(arcade: arcade)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 26)
    }
}

// MARK: - Leaderboards

struct LeaderboardsPane: View {
    let arcade: ArcadeController

    enum Period: Hashable {
        case local(LeaderboardPeriod)
        case global
    }

    @State private var board = GameID.runner.rawValue
    @State private var period: Period = .local(.allTime)
    @State private var remote: [RemoteScore]?
    @State private var loading = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(BoardInfo.allBoards, id: \.self) { key in
                        boardRow(key)
                    }
                }
            }
            .frame(width: 176)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(LeaderboardPeriod.allCases, id: \.self) { p in
                        periodPill(p.title, .local(p))
                    }
                    if arcade.leaderboard.isConfigured {
                        periodPill("Global", .global)
                    }
                    Spacer()
                }
                entries
            }
        }
        .task(id: "\(board)|\(period)") {
            guard period == .global else { return }
            loading = true
            remote = await arcade.leaderboard.top(board: board, period: .allTime)
            loading = false
        }
    }

    private func boardRow(_ key: String) -> some View {
        let style = boardStyle(key)
        let selected = key == board
        let best = arcade.save.scores.best(key)
        return Button {
            board = key
        } label: {
            HStack(spacing: 7) {
                Group {
                    if let game = style.game {
                        GameGlyph(game: game, size: 13)
                    } else {
                        Image(systemName: style.symbol ?? "gamecontroller.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: style.colors, startPoint: .top, endPoint: .bottom))
                    }
                }
                .frame(width: 14)
                Text(BoardInfo.title(for: key).replacingOccurrences(of: "Arcade · ", with: ""))
                    .font(Theme.rounded(11, .bold))
                    .foregroundStyle(selected ? Theme.primary : Theme.secondary)
                Spacer(minLength: 4)
                Text(best.map { Format.score($0, board: key) } ?? "—")
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.white.opacity(0.09) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func periodPill(_ title: String, _ value: Period) -> some View {
        Button {
            period = value
        } label: {
            Text(title)
                .font(Theme.rounded(10, .bold))
                .foregroundStyle(period == value ? Theme.primary : Theme.tertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(period == value ? Color.white.opacity(0.12) : .clear))
                .overlay(Capsule().strokeBorder(Color.white.opacity(period == value ? 0.15 : 0.06), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var entries: some View {
        switch period {
        case .local(let p):
            let rows = arcade.save.scores.top(board, period: p, limit: 7)
            if rows.isEmpty {
                emptyState(p == .today ? "No runs today yet." : "No runs yet. Go set a score!")
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, entry in
                        entryRow(rank: index + 1, name: arcade.save.profile.displayName, value: entry.value, trailing: entry.date.formatted(.relative(presentation: .named)), mine: true)
                    }
                }
            }
        case .global:
            if loading {
                emptyState("Loading…")
            } else if let remote, !remote.isEmpty {
                VStack(spacing: 3) {
                    ForEach(Array(remote.prefix(7).enumerated()), id: \.offset) { index, entry in
                        entryRow(rank: index + 1, name: entry.name, value: entry.value, trailing: "", mine: entry.player_id == arcade.save.profile.id)
                    }
                }
            } else {
                emptyState("Couldn't reach the leaderboard server.")
            }
        }
    }

    private func entryRow(rank: Int, name: String, value: Int, trailing: String, mine: Bool) -> some View {
        let style = boardStyle(board)
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(Theme.mono(12, .heavy))
                .foregroundStyle(rank == 1 ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF9F0A)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.tertiary))
                .frame(width: 18, alignment: .trailing)
            Text(name)
                .font(Theme.rounded(11.5, .bold))
                .foregroundStyle(mine ? Theme.primary : Theme.secondary)
                .lineLimit(1)
            Spacer()
            Text(trailing)
                .font(Theme.rounded(9.5, .medium))
                .foregroundStyle(Theme.tertiary)
            Text(Format.score(value, board: board))
                .font(Theme.mono(12.5, .heavy))
                .foregroundStyle(LinearGradient(colors: [.white, style.colors[0]], startPoint: .top, endPoint: .bottom))
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(rank == 1 ? style.colors[0].opacity(0.1) : Theme.surface))
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(Theme.rounded(11.5, .medium))
            .foregroundStyle(Theme.tertiary)
            .frame(maxWidth: .infinity, maxHeight: 160)
    }
}

// MARK: - Achievements

struct AchievementsPane: View {
    let arcade: ArcadeController

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(AchievementCatalog.all) { achievement in
                    badge(achievement)
                }
            }
        }
    }

    private func badge(_ a: Achievement) -> some View {
        let unlocked = arcade.save.achievements[a.id] != nil
        let colors = a.game?.style.colors ?? [Color(hex: 0xFFE07A), Color(hex: 0xFF9F0A)]
        let progress = a.progress(arcade.save.stats)
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(unlocked ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.06)))
                Image(systemName: unlocked ? a.symbol : "lock.fill")
                    .font(.system(size: unlocked ? 11 : 9, weight: .bold))
                    .foregroundStyle(unlocked ? Color.black.opacity(0.75) : Theme.tertiary)
            }
            .frame(width: 26, height: 26)
            .shadow(color: unlocked ? colors[0].opacity(0.5) : .clear, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .font(Theme.rounded(10.5, .bold))
                    .foregroundStyle(unlocked ? Theme.primary : Theme.secondary)
                    .lineLimit(1)
                if unlocked {
                    Text(a.detail)
                        .font(Theme.rounded(8.5, .medium))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                } else {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * CGFloat(progress.current) / CGFloat(max(1, progress.target)))
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .cardBackground(cornerRadius: 10)
        .help(a.detail)
    }
}

// MARK: - Stats

struct StatsPane: View {
    let arcade: ArcadeController

    var body: some View {
        let stats = arcade.save.stats
        let mostPlayed = stats.plays.max { $0.value < $1.value }.flatMap { GameID(rawValue: $0.key) }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            tile("Games played", Format.grouped(stats.gamesPlayed), "gamecontroller.fill", GameID.arcade.style.colors)
            tile("Time played", Format.playTime(seconds: stats.playSeconds), "clock.fill", GameID.pong.style.colors)
            tile("Back to work", Format.grouped(stats.escExits), "escape", GameID.farm.style.colors)
            tile("Launches", Format.grouped(stats.gameLaunches), "paperplane.fill", GameID.runner.style.colors)
            tile("Daily streak", "\(stats.dailyStreak(today: Date()))", "flame.fill", [Color(hex: 0xFFB340), Color(hex: 0xFF375F)])
            tile("Favourite", mostPlayed?.title ?? "—", "heart.fill", GameID.breakout.style.colors)
        }
    }

    private func tile(_ title: String, _ value: String, _ symbol: String, _ colors: [Color]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .background(Circle().fill(colors[0].opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(Theme.rounded(8, .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiary)
                Text(value)
                    .font(Theme.mono(18, .heavy))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(height: 66)
        .cardBackground(cornerRadius: 14)
    }
}
