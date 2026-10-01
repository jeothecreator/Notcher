import Foundation

public struct Achievement: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    /// SF Symbol name.
    public let symbol: String
    /// nil for general achievements.
    public let game: GameID?
    private let measure: (PlayerStats) -> (current: Int, target: Int)

    init(_ id: String, _ title: String, _ detail: String, symbol: String, game: GameID?,
         measure: @escaping (PlayerStats) -> (current: Int, target: Int)) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.game = game
        self.measure = measure
    }

    public func progress(_ stats: PlayerStats) -> (current: Int, target: Int) {
        let p = measure(stats)
        return (min(p.current, p.target), p.target)
    }

    public func isMet(_ stats: PlayerStats) -> Bool {
        let p = measure(stats)
        return p.current >= p.target
    }
}

public enum AchievementCatalog {
    static func atLeast(_ key: String, _ target: Int, in kind: KeyPath<PlayerStats, [String: Int]> = \.counters) -> (PlayerStats) -> (current: Int, target: Int) {
        { stats in (stats[keyPath: kind][key] ?? 0, target) }
    }

    /// For lower-is-better stats: met once the stat is at or below `limit`.
    static func atMost(_ key: String, _ limit: Int) -> (PlayerStats) -> (current: Int, target: Int) {
        { stats in
            guard let v = stats.minima[key] else { return (0, 1) }
            return (v <= limit ? 1 : 0, 1)
        }
    }

    public static let all: [Achievement] = [
        // Runner
        Achievement("runner.first", "First Run", "Finish a run in Runner.", symbol: "figure.run", game: .runner,
                    measure: atLeast("runner.runs", 1)),
        Achievement("runner.100", "Warming Up", "Score 100 in Runner.", symbol: "flame", game: .runner,
                    measure: atLeast("score.runner", 100, in: \.maxima)),
        Achievement("runner.10k", "Speed Demon", "Score 10,000 in Runner.", symbol: "hare.fill", game: .runner,
                    measure: atLeast("score.runner", 10_000, in: \.maxima)),
        Achievement("runner.coins", "Pocket Change", "Collect 100 coins in Runner.", symbol: "circle.circle.fill", game: .runner,
                    measure: atLeast("runner.coins", 100)),
        // Snake
        Achievement("snake.hungry", "Hungry", "Eat 10 apples in one game.", symbol: "fork.knife", game: .snake,
                    measure: atLeast("snake.applesInGame", 10, in: \.maxima)),
        Achievement("snake.gems", "Shiny", "Grab 5 bonus gems.", symbol: "diamond.fill", game: .snake,
                    measure: atLeast("snake.gems", 5)),
        Achievement("snake.god", "Snake God", "Reach a length of 100.", symbol: "crown.fill", game: .snake,
                    measure: atLeast("snake.length", 100, in: \.maxima)),
        // Pong
        Achievement("pong.win", "Match Point", "Win a match of Pong.", symbol: "trophy.fill", game: .pong,
                    measure: atLeast("pong.wins", 1)),
        Achievement("pong.rally", "Long Rally", "Keep a 20-hit rally going.", symbol: "arrow.left.arrow.right", game: .pong,
                    measure: atLeast("pong.rally", 20, in: \.maxima)),
        Achievement("pong.flawless", "Flawless", "Win a match 5–0.", symbol: "sparkles", game: .pong,
                    measure: atLeast("pong.flawless", 1)),
        // Breakout
        Achievement("breakout.clear", "Demolition", "Clear a level in Breakout.", symbol: "square.grid.3x3.fill", game: .breakout,
                    measure: atLeast("breakout.levels", 1)),
        Achievement("breakout.combo", "Combo King", "Hit a 15-brick combo.", symbol: "bolt.horizontal.fill", game: .breakout,
                    measure: atLeast("breakout.combo", 15, in: \.maxima)),
        Achievement("breakout.bricks", "Wrecking Ball", "Break 500 bricks.", symbol: "hammer.fill", game: .breakout,
                    measure: atLeast("breakout.bricks", 500)),
        // 2048
        Achievement("2048.512", "Getting There", "Make a 512 tile.", symbol: "square.stack.3d.up.fill", game: .twenty48,
                    measure: atLeast("2048.tile", 512, in: \.maxima)),
        Achievement("2048.2048", "2048!", "Make the 2048 tile.", symbol: "star.fill", game: .twenty48,
                    measure: atLeast("2048.tile", 2048, in: \.maxima)),
        // Mines
        Achievement("mines.win", "Sweeper", "Clear a minefield.", symbol: "flag.fill", game: .mines,
                    measure: atLeast("mines.wins", 1)),
        Achievement("mines.fast", "Bomb Squad", "Clear a minefield in under a minute.", symbol: "timer", game: .mines,
                    measure: atMost("mines.time", 60_000)),
        // Reaction
        Achievement("reaction.250", "Quick", "React in under 250 ms.", symbol: "bolt.fill", game: .reaction,
                    measure: atMost("reaction.ms", 250)),
        Achievement("reaction.180", "Lightning", "React in under 180 ms.", symbol: "bolt.circle.fill", game: .reaction,
                    measure: atMost("reaction.ms", 180)),
        // Miner
        Achievement("miner.10k", "Prospector", "Mine 10,000 coins.", symbol: "mountain.2.fill", game: .miner,
                    measure: atLeast("miner.lifetime", 10_000, in: \.maxima)),
        Achievement("miner.pickaxe", "Sharpened", "Upgrade your pickaxe to level 10.", symbol: "wrench.and.screwdriver.fill", game: .miner,
                    measure: atLeast("miner.pickaxe", 10, in: \.maxima)),
        // Farm
        Achievement("farm.first", "Green Thumb", "Harvest your first crop.", symbol: "leaf.fill", game: .farm,
                    measure: atLeast("farm.harvests", 1)),
        Achievement("farm.starfruit", "Starfruit", "Harvest a starfruit.", symbol: "star.circle.fill", game: .farm,
                    measure: atLeast("farm.starfruit", 1)),
        Achievement("farm.100", "Harvest Moon", "Harvest 100 crops.", symbol: "moon.stars.fill", game: .farm,
                    measure: atLeast("farm.harvests", 100)),
        // Solitaire
        Achievement("solitaire.win", "Patience", "Win a game of Solitaire.", symbol: "suit.spade.fill", game: .solitaire,
                    measure: atLeast("solitaire.wins", 1)),
        Achievement("solitaire.fast", "Card Shark", "Win Solitaire in under 3 minutes.", symbol: "suit.diamond.fill", game: .solitaire,
                    measure: atMost("solitaire.time", 180_000)),
        // Arcade
        Achievement("arcade.explorer", "Explorer", "Play every Arcade game.", symbol: "map.fill", game: .arcade,
                    measure: { stats in
                        (ArcadeMini.allCases.filter { stats.counter("arcade.played.\($0.rawValue)") > 0 }.count, ArcadeMini.allCases.count)
                    }),
        Achievement("arcade.flap", "Frequent Flyer", "Score 20 in Flap.", symbol: "bird.fill", game: .arcade,
                    measure: atLeast("score.arcade.flap", 20, in: \.maxima)),
        // General
        Achievement("general.speedrunner", "Speedrunner", "Launch 10 games.", symbol: "paperplane.fill", game: nil,
                    measure: { ($0.gameLaunches, 10) }),
        Achievement("general.tourist", "Tourist", "Play all 11 games.", symbol: "globe.americas.fill", game: nil,
                    measure: { stats in (GameID.allCases.filter { (stats.plays[$0.rawValue] ?? 0) > 0 }.count, GameID.allCases.count) }),
        Achievement("general.rat", "Arcade Rat", "Play 100 games.", symbol: "gamecontroller.fill", game: nil,
                    measure: { ($0.gamesPlayed, 100) }),
        Achievement("general.procrastinator", "Professional Procrastinator", "Play for 30 minutes in total.", symbol: "cup.and.saucer.fill", game: nil,
                    measure: { (Int($0.playSeconds / 60), 30) }),
        Achievement("general.backtowork", "Back to Work", "Exit with Esc 100 times.", symbol: "escape", game: nil,
                    measure: { ($0.escExits, 100) }),
        Achievement("general.daily", "Daily Devotee", "Complete 3 daily challenges.", symbol: "calendar", game: nil,
                    measure: { ($0.dailyCompleted.count, 3) }),
    ]

    public static func achievement(id: String) -> Achievement? {
        all.first { $0.id == id }
    }

    /// Achievements that are met but not yet in `unlocked`.
    public static func newlyUnlocked(stats: PlayerStats, unlocked: Set<String>) -> [Achievement] {
        all.filter { !unlocked.contains($0.id) && $0.isMet(stats) }
    }
}
