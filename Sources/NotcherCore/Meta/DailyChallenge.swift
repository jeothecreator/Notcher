import Foundation

/// One challenge per day, identical for every player: same game, same seed,
/// same target.
public struct DailyChallenge: Equatable, Sendable {
    public let dayKey: String
    public let game: GameID
    public let target: Int
    public let seed: UInt64

    static let pool: [(GameID, Int)] = [
        (.runner, 3_000),
        (.lexi, 300),
        (.snake, 150),
        (.stack, 4_000),
        (.breakout, 1_200),
        (.sudoku, 600_000),
        (.invaders, 1_500),
        (.twenty48, 3_000),
        (.typer, 50),
        (.reaction, 260),
        (.gems, 2_500),
        (.astro, 2_000),
        (.mines, 150_000),
        (.four, 100),
    ]

    public init(dayKey: String, game: GameID, target: Int, seed: UInt64) {
        self.dayKey = dayKey
        self.game = game
        self.target = target
        self.seed = seed
    }

    public static func forDate(_ date: Date, calendar: Calendar = .current) -> DailyChallenge {
        let day = DayKey.dayNumber(for: date, calendar: calendar)
        // A stride that is coprime with the pool size visits every game before repeating.
        let index = ((day * 3) % pool.count + pool.count) % pool.count
        let (game, base) = pool[index]
        // Targets drift a little from week to week.
        let week = (day / 7) % 3
        let target: Int
        if game == .lexi || game == .four || game == .typer {
            target = base
        } else {
            switch game.scoreOrder {
            case .higherIsBetter: target = base + base * week / 5
            case .lowerIsBetter: target = base - base * week / 20
            }
        }
        var mix = SeededRandom(seed: UInt64(bitPattern: Int64(day)) &* 0x9E37_79B9_7F4A_7C15 ^ 0x4E_4F_54_43_48_45_52)
        return DailyChallenge(dayKey: DayKey.key(for: date, calendar: calendar), game: game, target: target, seed: mix.next())
    }

    public func isMet(by value: Int) -> Bool {
        switch game.scoreOrder {
        case .higherIsBetter: return value >= target
        case .lowerIsBetter: return value <= target
        }
    }

    public var goal: String {
        switch game {
        case .reaction: return "React in under \(target) ms"
        case .mines: return "Clear the field in \(Format.duration(ms: target).dropLast(2))"
        case .sudoku: return "Solve in under \(Format.duration(ms: target).dropLast(2))"
        case .pong: return "Score \(target)+ points"
        case .lexi: return "Solve in \(LexiEngine.maxGuesses + 1 - target / 100) guesses or fewer"
        case .typer: return "Type \(target)+ words per minute"
        case .four: return "Beat the AI"
        default: return "Score \(Format.grouped(target))+"
        }
    }
}
