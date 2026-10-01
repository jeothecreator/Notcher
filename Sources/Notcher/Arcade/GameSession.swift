import NotcherCore
import Observation
import SwiftUI

/// What the game-over card shows.
struct RunSummary: Equatable {
    var board: String
    var record: RecordResult
    /// nil when this wasn't a daily challenge run.
    var dailyMet: Bool?
}

/// One live game: the engine plus the bits of state SwiftUI observes.
@MainActor
@Observable
final class GameSession {
    let game: GameID
    let engine: GameEngine
    let daily: DailyChallenge?

    /// Bumped whenever the view should redraw.
    private(set) var revision = 0
    private(set) var phase: GamePhase
    private(set) var score: Int
    /// Leaderboard key; changes when the Arcade cabinet switches games.
    private(set) var boardKey: String
    var summary: RunSummary?

    let input = InputState()
    @ObservationIgnored var onEvents: ((GameSession, [GameEvent]) -> Void)?
    @ObservationIgnored var onPhaseChange: ((GameSession, GamePhase, GamePhase) -> Void)?
    @ObservationIgnored private var redrawTimer = 0.0

    init(game: GameID, engine: GameEngine, daily: DailyChallenge? = nil) {
        self.game = game
        self.engine = engine
        self.daily = daily
        self.phase = engine.phase
        self.score = engine.score
        self.boardKey = engine.boardKey
    }

    var isDaily: Bool { daily != nil }

    /// Seconds between redraws for games that don't animate every frame.
    private var redrawInterval: Double {
        switch game {
        case .twenty48: return 0.25
        case .solitaire, .farm: return 0.1
        case .sudoku: return 1.0 / 30
        case .lexi, .typer: return 1.0 / 60
        default: return 0
        }
    }

    func tick(_ dt: Double) {
        engine.tick(min(dt, 1.0 / 20), input: input)
        redrawTimer += dt
        let changed = sync()
        if changed || redrawTimer >= redrawInterval {
            redrawTimer = 0
            revision &+= 1
        }
    }

    @discardableResult
    func press(_ key: GameKey, isRepeat: Bool) -> Bool {
        if !isRepeat { input.press(key) }
        let handled = engine.handle(key, isRepeat: isRepeat)
        _ = sync()
        revision &+= 1
        return handled
    }

    func release(_ key: GameKey) {
        input.release(key)
    }

    func pause() {
        input.clear()
        engine.pause()
        _ = sync()
        revision &+= 1
    }

    func restart() {
        summary = nil
        engine.restart()
        _ = sync()
        revision &+= 1
    }

    /// Pulls events and phase/score changes out of the engine.
    private func sync() -> Bool {
        var changed = false
        let events = engine.drainEvents()
        if !events.isEmpty {
            onEvents?(self, events)
            changed = true
        }
        if engine.phase != phase {
            let old = phase
            phase = engine.phase
            if old == .over { summary = nil }
            onPhaseChange?(self, old, phase)
            changed = true
        }
        if engine.score != score {
            score = engine.score
            changed = true
        }
        if engine.boardKey != boardKey {
            boardKey = engine.boardKey
            changed = true
        }
        return changed
    }
}
