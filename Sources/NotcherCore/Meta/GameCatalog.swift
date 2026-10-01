import Foundation

public enum GameCategory: String, CaseIterable, Codable, Sendable {
    case action, puzzle, brain, idle

    public var title: String {
        switch self {
        case .action: return "Action"
        case .puzzle: return "Puzzle"
        case .brain: return "Brain"
        case .idle: return "Idle"
        }
    }

    public var subtitle: String {
        switch self {
        case .action: return "Fast hands, short runs"
        case .puzzle: return "Think a little, play a lot"
        case .brain: return "Words, wits and reflexes"
        case .idle: return "Keeps going while you work"
        }
    }

    public var symbol: String {
        switch self {
        case .action: return "bolt.fill"
        case .puzzle: return "puzzlepiece.fill"
        case .brain: return "brain.head.profile"
        case .idle: return "leaf.fill"
        }
    }
}

public enum ScoreOrder: Sendable {
    case higherIsBetter, lowerIsBetter
}

public enum ScoreFormat: Sendable {
    case points
    case milliseconds
    /// Value is in milliseconds, shown as m:ss.t
    case duration
    /// Words per minute
    case wpm
}

public struct ControlHint: Hashable, Sendable {
    public let keys: String
    public let action: String

    public init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }
}

/// Every game on the launcher.
public enum GameID: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    // Action
    case runner, snake, pong, breakout, invaders, astro, trails, arcade
    // Puzzle
    case stack, twenty48, gems, sudoku, mines, solitaire
    // Brain
    case lexi, typer, reaction, four
    // Idle
    case miner, farm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .runner: return "Runner"
        case .snake: return "Snake"
        case .pong: return "Pong"
        case .breakout: return "Breakout"
        case .invaders: return "Invaders"
        case .astro: return "Astro"
        case .trails: return "Trails"
        case .arcade: return "Arcade"
        case .stack: return "Stack"
        case .twenty48: return "2048"
        case .gems: return "Gems"
        case .sudoku: return "Sudoku"
        case .mines: return "Mines"
        case .solitaire: return "Solitaire"
        case .lexi: return "Lexi"
        case .typer: return "Typer"
        case .reaction: return "Reaction"
        case .four: return "Four"
        case .miner: return "Miner"
        case .farm: return "Farm"
        }
    }

    public var tagline: String {
        switch self {
        case .runner: return "Jump, slide, survive."
        case .snake: return "Eat. Grow. Don't bite."
        case .pong: return "First to five wins."
        case .breakout: return "Smash every brick."
        case .invaders: return "Hold the line."
        case .astro: return "Drift, spin, shoot rocks."
        case .trails: return "Box them in with light."
        case .arcade: return "A new micro game daily."
        case .stack: return "Clear lines, chase Tetrises."
        case .twenty48: return "Slide your way to 2048."
        case .gems: return "Swap three, set off cascades."
        case .sudoku: return "Nine boxes, one answer."
        case .mines: return "Clear the field."
        case .solitaire: return "Klondike, pocket sized."
        case .lexi: return "Five letters, six guesses."
        case .typer: return "How fast can you type?"
        case .reaction: return "Wait for green."
        case .four: return "Four in a row beats the AI."
        case .miner: return "Dig while you work."
        case .farm: return "Plant now, harvest later."
        }
    }

    /// One or two sentences for the launcher's detail line.
    public var summary: String {
        switch self {
        case .runner: return "A synthwave endless runner. Hold space for higher jumps, slide under drones."
        case .snake: return "Classic snake with smooth movement. Every few apples the arena closes in."
        case .pong: return "Rally against an AI that gets sharper each match you win."
        case .breakout: return "Tough bricks, power-ups and combo multipliers across endless levels."
        case .invaders: return "Wave after wave marching down. Hide behind shields and catch the saucer."
        case .astro: return "Vector space rocks with drifting physics. Big rocks split into faster ones."
        case .trails: return "Light cycles on a neon grid. Outlast the AI riders to win the round."
        case .arcade: return "Flap, Dodge, Bullseye, Echo, Lander and Hop. Tab switches games."
        case .stack: return "Falling blocks with hold, ghost piece, 7-bag and wall kicks."
        case .twenty48: return "Merge tiles to reach 2048, with three undos per game."
        case .gems: return "Match three or more. Fours make line gems, fives make star gems. 30 moves."
        case .sudoku: return "Freshly generated puzzles with a single solution, notes and mistake checking."
        case .mines: return "Keyboard-first Minesweeper. The first reveal is always safe."
        case .solitaire: return "Klondike with drag and drop, double-click to send home and unlimited undo."
        case .lexi: return "Guess the five-letter word. Green is right, yellow is in the word."
        case .typer: return "A 30-second typing test. Score is words per minute."
        case .reaction: return "Hit space the moment the screen turns green."
        case .four: return "Drop discs and connect four before the AI does. It gets smarter as you win."
        case .miner: return "Mine crystals, hire workers and upgrade. Workers keep digging while you're away."
        case .farm: return "Crops grow in real time, from 30-second wheat to 45-minute starfruit."
        }
    }

    public var category: GameCategory {
        switch self {
        case .runner, .snake, .pong, .breakout, .invaders, .astro, .trails, .arcade: return .action
        case .stack, .twenty48, .gems, .sudoku, .mines, .solitaire: return .puzzle
        case .lexi, .typer, .reaction, .four: return .brain
        case .miner, .farm: return .idle
        }
    }

    public var scoreOrder: ScoreOrder {
        switch self {
        case .mines, .reaction, .solitaire, .sudoku: return .lowerIsBetter
        default: return .higherIsBetter
        }
    }

    public var scoreFormat: ScoreFormat {
        switch self {
        case .reaction: return .milliseconds
        case .mines, .solitaire, .sudoku: return .duration
        case .typer: return .wpm
        default: return .points
        }
    }

    /// Idle games don't record runs.
    public var hasScores: Bool {
        category != .idle
    }

    /// Added in the second release; shows a NEW badge until played.
    public var isNew: Bool {
        switch self {
        case .invaders, .astro, .trails, .stack, .gems, .sudoku, .lexi, .typer, .four: return true
        default: return false
        }
    }

    public var controls: [ControlHint] {
        switch self {
        case .runner: return [ControlHint("space", "jump"), ControlHint("↓", "slide")]
        case .snake: return [ControlHint("↑↓←→", "steer")]
        case .pong: return [ControlHint("↑↓", "move")]
        case .breakout: return [ControlHint("←→", "move"), ControlHint("space", "launch")]
        case .invaders: return [ControlHint("←→", "move"), ControlHint("space", "fire")]
        case .astro: return [ControlHint("←→", "turn"), ControlHint("↑", "thrust"), ControlHint("space", "fire"), ControlHint("↓", "warp")]
        case .trails: return [ControlHint("↑↓←→", "turn")]
        case .arcade: return [ControlHint("tab", "switch game"), ControlHint("space", "play")]
        case .stack: return [ControlHint("←→", "move"), ControlHint("↑", "rotate"), ControlHint("space", "drop"), ControlHint("C", "hold")]
        case .twenty48: return [ControlHint("↑↓←→", "slide"), ControlHint("U", "undo")]
        case .gems: return [ControlHint("↑↓←→", "move"), ControlHint("space", "select, then arrow to swap")]
        case .sudoku: return [ControlHint("↑↓←→", "move"), ControlHint("1–9", "fill"), ControlHint("F", "notes"), ControlHint("⌫", "erase")]
        case .mines: return [ControlHint("↑↓←→", "move"), ControlHint("↵", "reveal"), ControlHint("F", "flag")]
        case .solitaire: return [ControlHint("←→↑↓", "move"), ControlHint("↵", "pick/drop"), ControlHint("D", "draw"), ControlHint("U", "undo")]
        case .lexi: return [ControlHint("A–Z", "type"), ControlHint("↵", "guess"), ControlHint("⌫", "delete")]
        case .typer: return [ControlHint("type", "the words"), ControlHint("space", "next word")]
        case .reaction: return [ControlHint("space", "react")]
        case .four: return [ControlHint("←→", "column"), ControlHint("space", "drop")]
        case .miner: return [ControlHint("space", "mine"), ControlHint("↑↓ ↵", "upgrade")]
        case .farm: return [ControlHint("←→↑↓", "plot"), ControlHint("↵", "plant/harvest"), ControlHint("tab", "seed")]
        }
    }

    public static func inCategory(_ category: GameCategory) -> [GameID] {
        allCases.filter { $0.category == category }
    }
}

/// Micro games that rotate inside the Arcade cabinet.
public enum ArcadeMini: String, CaseIterable, Codable, Sendable {
    case flap, dodge, bullseye, echo, lander, hop

    public var title: String {
        switch self {
        case .flap: return "Flap"
        case .dodge: return "Dodge"
        case .bullseye: return "Bullseye"
        case .echo: return "Echo"
        case .lander: return "Lander"
        case .hop: return "Hop"
        }
    }

    public var tagline: String {
        switch self {
        case .flap: return "Space to flap through the gaps."
        case .dodge: return "←→ to dodge the falling stars."
        case .bullseye: return "Space when the needle is in the zone."
        case .echo: return "Repeat the pattern with the arrows."
        case .lander: return "↑ thrust, ←→ rotate. Touch down softly."
        case .hop: return "Arrows to hop across the road and river."
        }
    }

    public var boardKey: String { "arcade.\(rawValue)" }

    /// The micro game featured on a given day.
    public static func featured(on date: Date, calendar: Calendar = .current) -> ArcadeMini {
        let day = DayKey.dayNumber(for: date, calendar: calendar)
        let all = ArcadeMini.allCases
        return all[((day % all.count) + all.count) % all.count]
    }
}

/// Metadata for any score key (a game, or an Arcade micro game).
public enum BoardInfo {
    public static func title(for board: String) -> String {
        if let game = GameID(rawValue: board) { return game.title }
        if board.hasPrefix("arcade."), let mini = ArcadeMini(rawValue: String(board.dropFirst(7))) {
            return "Arcade · \(mini.title)"
        }
        return board.capitalized
    }

    public static func order(for board: String) -> ScoreOrder {
        GameID(rawValue: board)?.scoreOrder ?? .higherIsBetter
    }

    public static func format(for board: String) -> ScoreFormat {
        GameID(rawValue: board)?.scoreFormat ?? .points
    }

    /// Every key that can hold scores, in launcher order.
    public static var allBoards: [String] {
        GameID.allCases.filter { $0.hasScores && $0 != .arcade }.map(\.rawValue)
            + ArcadeMini.allCases.map(\.boardKey)
    }
}
