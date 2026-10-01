import Foundation

public enum GameCategory: String, CaseIterable, Codable, Sendable {
    case quick, brain, idle, classics

    public var title: String {
        switch self {
        case .quick: return "Quick"
        case .brain: return "Brain"
        case .idle: return "Idle"
        case .classics: return "Classics"
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
}

public struct ControlHint: Hashable, Sendable {
    public let keys: String
    public let action: String

    public init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }
}

/// The eleven games on the launcher.
public enum GameID: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case runner, snake, pong, breakout
    case twenty48, mines, reaction
    case miner, farm
    case solitaire, arcade

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .runner: return "Runner"
        case .snake: return "Snake"
        case .pong: return "Pong"
        case .breakout: return "Breakout"
        case .twenty48: return "2048"
        case .mines: return "Mines"
        case .reaction: return "Reaction"
        case .miner: return "Miner"
        case .farm: return "Farm"
        case .solitaire: return "Solitaire"
        case .arcade: return "Arcade"
        }
    }

    public var tagline: String {
        switch self {
        case .runner: return "Jump, slide, survive."
        case .snake: return "Eat. Grow. Don't bite."
        case .pong: return "First to five."
        case .breakout: return "Smash every brick."
        case .twenty48: return "Slide to 2048."
        case .mines: return "Clear the field."
        case .reaction: return "Wait for green."
        case .miner: return "Dig while you work."
        case .farm: return "Plant now, harvest later."
        case .solitaire: return "Klondike, pocket sized."
        case .arcade: return "A new micro game daily."
        }
    }

    public var category: GameCategory {
        switch self {
        case .runner, .snake, .pong, .breakout: return .quick
        case .twenty48, .mines, .reaction: return .brain
        case .miner, .farm: return .idle
        case .solitaire, .arcade: return .classics
        }
    }

    public var scoreOrder: ScoreOrder {
        switch self {
        case .mines, .reaction, .solitaire: return .lowerIsBetter
        default: return .higherIsBetter
        }
    }

    public var scoreFormat: ScoreFormat {
        switch self {
        case .reaction: return .milliseconds
        case .mines, .solitaire: return .duration
        default: return .points
        }
    }

    /// Idle games have no leaderboard runs.
    public var isCompetitive: Bool {
        category != .idle
    }

    public var controls: [ControlHint] {
        switch self {
        case .runner: return [ControlHint("space", "jump"), ControlHint("↓", "slide")]
        case .snake: return [ControlHint("↑↓←→", "steer")]
        case .pong: return [ControlHint("↑↓", "move")]
        case .breakout: return [ControlHint("←→", "move"), ControlHint("space", "launch")]
        case .twenty48: return [ControlHint("↑↓←→", "slide"), ControlHint("U", "undo")]
        case .mines: return [ControlHint("↑↓←→", "move"), ControlHint("↵", "reveal"), ControlHint("F", "flag")]
        case .reaction: return [ControlHint("space", "react")]
        case .miner: return [ControlHint("space", "mine"), ControlHint("↑↓ ↵", "upgrade")]
        case .farm: return [ControlHint("←→↑↓", "plot"), ControlHint("↵", "plant/harvest"), ControlHint("tab", "seed")]
        case .solitaire: return [ControlHint("←→↑↓", "move"), ControlHint("↵", "pick/drop"), ControlHint("D", "draw"), ControlHint("U", "undo")]
        case .arcade: return [ControlHint("tab", "switch game"), ControlHint("space", "play")]
        }
    }

    public static func inCategory(_ category: GameCategory) -> [GameID] {
        allCases.filter { $0.category == category }
    }
}

/// Mini games that rotate inside the Arcade cabinet.
public enum ArcadeMini: String, CaseIterable, Codable, Sendable {
    case flap, dodge, bullseye, echo

    public var title: String {
        switch self {
        case .flap: return "Flap"
        case .dodge: return "Dodge"
        case .bullseye: return "Bullseye"
        case .echo: return "Echo"
        }
    }

    public var tagline: String {
        switch self {
        case .flap: return "Space to flap through the gaps."
        case .dodge: return "←→ to dodge the falling stars."
        case .bullseye: return "Space when the needle is in the zone."
        case .echo: return "Repeat the pattern with the arrows."
        }
    }

    public var boardKey: String { "arcade.\(rawValue)" }

    /// The mini game featured on a given day.
    public static func featured(on date: Date, calendar: Calendar = .current) -> ArcadeMini {
        let day = DayKey.dayNumber(for: date, calendar: calendar)
        let all = ArcadeMini.allCases
        return all[((day % all.count) + all.count) % all.count]
    }
}

/// Leaderboard metadata for any board key (game or arcade mini game).
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

    /// Every board that can hold scores, in launcher order.
    public static var allBoards: [String] {
        GameID.allCases.filter { $0.isCompetitive && $0 != .arcade }.map(\.rawValue)
            + ArcadeMini.allCases.map(\.boardKey)
    }
}
