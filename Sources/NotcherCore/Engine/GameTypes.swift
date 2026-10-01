import Foundation

/// Abstract keys the games understand. The app maps physical keys onto these;
/// Esc is never forwarded to games — it always means "back to work".
public enum GameKey: Hashable, Sendable {
    case up, down, left, right
    /// Space
    case primary
    /// Return / Enter
    case confirm
    /// F
    case flag
    /// R
    case restart
    /// U or ⌘Z
    case undo
    /// Tab or D
    case cycle
    /// A
    case auto
    /// P
    case pause
    /// 1…9
    case number(Int)

    public var isArrow: Bool {
        switch self {
        case .up, .down, .left, .right: return true
        default: return false
        }
    }
}

public enum GamePhase: Equatable, Sendable {
    /// Waiting for the first key press.
    case ready
    case playing
    case paused
    /// The run ended. Engines keep animating (particles, explosions) while over.
    case over
}

/// Sound effects. The app owns the synthesizer; engines only name cues.
public enum SoundCue: String, CaseIterable, Sendable {
    case tick, select, launch
    case jump, land, coin, hit, wall, brick, eat, bonus
    case merge, slide, flag, reveal, explode, lose, win, levelUp, powerUp
    case error, ready, go, card, place, harvest, plant, buy, flap
    case note1, note2, note3, note4
}

public enum GameEvent: Equatable, Sendable {
    case sound(SoundCue)
    /// A cumulative stat counter, e.g. `snake.apples`.
    case count(String, Int)
    /// "Highest ever" stat, e.g. `snake.length`.
    case maximum(String, Int)
    /// "Lowest ever" stat, e.g. `reaction.ms`.
    case minimum(String, Int)
    /// A result that goes on the leaderboard for the engine's board.
    case record(Int)
    /// Screen shake, 0…1.
    case shake(Double)
}

/// Keys that are currently held down. Real-time games read this every frame.
public final class InputState {
    public private(set) var held: Set<GameKey> = []

    public init() {}

    public func press(_ key: GameKey) { held.insert(key) }
    public func release(_ key: GameKey) { held.remove(key) }
    public func clear() { held.removeAll() }
    public func isHeld(_ key: GameKey) -> Bool { held.contains(key) }

    /// -1 for left/up, +1 for right/down, 0 when neither or both are held.
    public func axis(_ negative: GameKey, _ positive: GameKey) -> Double {
        (isHeld(positive) ? 1 : 0) - (isHeld(negative) ? 1 : 0)
    }
}

/// Every game in Notcher implements this. Engines are plain, deterministic
/// state machines: the app feeds them time and keys and draws what they hold.
public protocol GameEngine: AnyObject {
    var phase: GamePhase { get }
    /// Score shown in the HUD.
    var score: Int { get }
    /// Leaderboard key, e.g. `runner` or `arcade.flap`.
    var boardKey: String { get }
    /// Seconds since the engine was created; drives idle animations.
    var clock: Double { get }
    /// Screen shake 0…1, decays on its own.
    var shake: Double { get }

    func tick(_ dt: Double, input: InputState)
    /// Returns true when the key did something.
    @discardableResult func handle(_ key: GameKey, isRepeat: Bool) -> Bool
    func pause()
    func resume()
    func restart()
    func drainEvents() -> [GameEvent]
}

/// Shared plumbing for engines: phase, score, events and pausing.
public class EngineBase {
    public internal(set) var phase: GamePhase = .ready
    public internal(set) var score: Int = 0
    public internal(set) var clock: Double = 0
    public internal(set) var shake: Double = 0
    public var boardKey: String
    var events: [GameEvent] = []

    init(boardKey: String) {
        self.boardKey = boardKey
    }

    func emit(_ event: GameEvent) {
        events.append(event)
        if case .shake(let amount) = event {
            shake = max(shake, amount)
        }
    }

    func play(_ cue: SoundCue) { emit(.sound(cue)) }

    public func drainEvents() -> [GameEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    public func pause() {
        if phase == .playing { phase = .paused }
    }

    public func resume() {
        if phase == .paused { phase = .playing }
    }

    /// Call at the top of every subclass tick.
    func advanceClock(_ dt: Double) {
        clock += dt
        shake = max(0, shake - dt * 3)
    }
}
