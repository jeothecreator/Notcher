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
        // Invaders
        Achievement("invaders.wave", "Hold the Line", "Reach wave 3 in Invaders.", symbol: "shield.lefthalf.filled", game: .invaders,
                    measure: atLeast("invaders.wave", 3, in: \.maxima)),
        Achievement("invaders.saucer", "Close Encounter", "Shoot down the mystery saucer.", symbol: "dot.radiowaves.left.and.right", game: .invaders,
                    measure: atLeast("invaders.saucers", 1)),
        // Astro
        Achievement("astro.rocks", "Rock Breaker", "Destroy 100 space rocks.", symbol: "circle.hexagongrid.fill", game: .astro,
                    measure: atLeast("astro.rocks", 100)),
        Achievement("astro.score", "Space Ace", "Score 5,000 in Astro.", symbol: "airplane", game: .astro,
                    measure: atLeast("score.astro", 5_000, in: \.maxima)),
        // Trails
        Achievement("trails.round", "Last Rider", "Win a round of Trails.", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", game: .trails,
                    measure: atLeast("trails.rounds", 1)),
        Achievement("trails.legend", "Grid Legend", "Reach round 5 in Trails.", symbol: "square.grid.3x3.topleft.filled", game: .trails,
                    measure: atLeast("trails.round", 5, in: \.maxima)),
        // Stack
        Achievement("stack.lines", "Line Up", "Clear 40 lines in Stack.", symbol: "line.3.horizontal", game: .stack,
                    measure: atLeast("stack.lines", 40)),
        Achievement("stack.four", "Four at Once", "Clear four lines with one piece.", symbol: "square.stack.3d.up.fill", game: .stack,
                    measure: atLeast("stack.tetrises", 1)),
        // Gems
        Achievement("gems.cascade", "Chain Reaction", "Set off a four-step cascade.", symbol: "sparkles", game: .gems,
                    measure: atLeast("gems.cascade", 4, in: \.maxima)),
        Achievement("gems.score", "Jeweler", "Score 3,000 in Gems.", symbol: "rhombus.fill", game: .gems,
                    measure: atLeast("score.gems", 3_000, in: \.maxima)),
        // Sudoku
        Achievement("sudoku.win", "Solved", "Solve a Sudoku.", symbol: "checkmark.square.fill", game: .sudoku,
                    measure: atLeast("sudoku.wins", 1)),
        Achievement("sudoku.flawless", "Clean Sheet", "Solve a Sudoku without a mistake.", symbol: "checkmark.seal.fill", game: .sudoku,
                    measure: atLeast("sudoku.flawless", 1)),
        Achievement("sudoku.hard", "Hard Boiled", "Solve a hard Sudoku.", symbol: "flame.fill", game: .sudoku,
                    measure: atMost("sudoku.hard", Int.max)),
        // Lexi
        Achievement("lexi.win", "Wordsmith", "Solve a Lexi puzzle.", symbol: "textformat.abc", game: .lexi,
                    measure: atLeast("lexi.wins", 1)),
        Achievement("lexi.genius", "Genius", "Solve Lexi in two guesses.", symbol: "lightbulb.fill", game: .lexi,
                    measure: atLeast("lexi.best", 500, in: \.maxima)),
        // Typer
        Achievement("typer.60", "Swift Fingers", "Type 60 words per minute.", symbol: "keyboard.fill", game: .typer,
                    measure: atLeast("typer.wpm", 60, in: \.maxima)),
        Achievement("typer.90", "Keyboard Warrior", "Type 90 words per minute.", symbol: "bolt.fill", game: .typer,
                    measure: atLeast("typer.wpm", 90, in: \.maxima)),
        // Four
        Achievement("four.win", "Connected", "Beat the AI at Four.", symbol: "circle.grid.3x3.fill", game: .four,
                    measure: atLeast("four.wins", 1)),
        Achievement("four.level", "Grandmaster", "Reach level 5 in Four.", symbol: "crown.fill", game: .four,
                    measure: atLeast("four.level", 5, in: \.maxima)),
        // Arcade cabinet additions
        Achievement("arcade.lander", "Smooth Landing", "Land three times in one Lander run.", symbol: "arrow.down.to.line", game: .arcade,
                    measure: atLeast("arcade.lander.landings", 3, in: \.maxima)),
        Achievement("arcade.hop", "Across the River", "Fill all five bays in Hop.", symbol: "tortoise.fill", game: .arcade,
                    measure: atLeast("arcade.hop.level", 2, in: \.maxima)),
        // General
        Achievement("general.speedrunner", "Speedrunner", "Launch 10 games.", symbol: "paperplane.fill", game: nil,
                    measure: { ($0.gameLaunches, 10) }),
        Achievement("general.tourist", "Tourist", "Play all 20 games.", symbol: "globe.americas.fill", game: nil,
                    measure: { stats in (GameID.allCases.filter { (stats.plays[$0.rawValue] ?? 0) > 0 }.count, GameID.allCases.count) }),
        Achievement("general.rat", "Arcade Rat", "Play 100 games.", symbol: "gamecontroller.fill", game: nil,
                    measure: { ($0.gamesPlayed, 100) }),
        Achievement("general.procrastinator", "Professional Procrastinator", "Play for 30 minutes in total.", symbol: "cup.and.saucer.fill", game: nil,
                    measure: { (Int($0.playSeconds / 60), 30) }),
        Achievement("general.backtowork", "Back to Work", "Exit with Esc 100 times.", symbol: "escape", game: nil,
                    measure: { ($0.escExits, 100) }),
        Achievement("general.daily", "Daily Devotee", "Complete 3 daily challenges.", symbol: "calendar", game: nil,
                    measure: { ($0.dailyCompleted.count, 3) }),
        // Your ROMs
        Achievement("rom.first", "Blow on the Cartridge", "Play a game from your own ROMs.", symbol: "memorychip.fill", game: nil,
                    measure: atLeast("rom.launches", 1)),
        Achievement("rom.systems", "Console Hopper", "Play NES, Game Boy and Game Boy Color games.", symbol: "square.stack.3d.up.fill", game: nil,
                    measure: { stats in (ConsoleSystem.allCases.filter { stats.counter("rom.system.\($0.rawValue)") > 0 }.count, ConsoleSystem.allCases.count) }),
        Achievement("rom.collector", "Collector", "Keep 10 games in your library.", symbol: "books.vertical.fill", game: nil,
                    measure: atLeast("rom.library", 10, in: \.maxima)),
        Achievement("rom.hour", "Retro Hour", "Play your ROMs for an hour in total.", symbol: "clock.fill", game: nil,
                    measure: { stats in (stats.counter("rom.seconds") / 60, 60) }),
    ]

    public static func achievement(id: String) -> Achievement? {
        all.first { $0.id == id }
    }

    /// Achievements that are met but not yet in `unlocked`.
    public static func newlyUnlocked(stats: PlayerStats, unlocked: Set<String>) -> [Achievement] {
        all.filter { !unlocked.contains($0.id) && $0.isMet(stats) }
    }
}
