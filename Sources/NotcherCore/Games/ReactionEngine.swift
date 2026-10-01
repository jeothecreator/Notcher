import Foundation

/// Wait for green, then hit Space as fast as you can.
public final class ReactionEngine: EngineBase, GameEngine {
    public enum Stage: Equatable, Sendable {
        case intro
        case waiting
        case go
        case result(Int)
        case early
    }

    public private(set) var stage: Stage = .intro
    /// Every valid attempt this session, oldest first.
    public private(set) var attempts: [Int] = []
    /// Clock time when the current stage started.
    public private(set) var stageStart = 0.0

    public var best: Int? { attempts.min() }
    public var average: Int? {
        let recent = attempts.suffix(5)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / recent.count
    }

    /// High-resolution time source in seconds. Injected for tests.
    private let now: () -> Double
    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var goAt = 0.0
    private var shownAt = 0.0

    public init(seed: UInt64? = nil, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        self.now = now
        super.init(boardKey: GameID.reaction.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        stage = .intro
        attempts = []
        score = 0
        phase = .ready
        stageStart = clock
    }

    public func restart() { reset() }

    private func setStage(_ s: Stage) {
        stage = s
        stageStart = clock
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        guard phase == .playing, stage == .waiting else { return }
        let t = now()
        if t >= goAt {
            shownAt = t
            setStage(.go)
            play(.go)
        }
    }

    private func startWaiting() {
        goAt = now() + rng.double(1.4...3.8)
        setStage(.waiting)
        phase = .playing
        play(.ready)
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .primary, .confirm, .up, .down, .left, .right:
            guard !isRepeat else { return true }
            if phase == .paused {
                resume()
                startWaiting()
                return true
            }
            switch stage {
            case .intro, .result, .early:
                startWaiting()
            case .waiting:
                setStage(.early)
                play(.error)
                emit(.count("reaction.early", 1))
            case .go:
                let ms = max(1, Int(((now() - shownAt) * 1000).rounded()))
                attempts.append(ms)
                score = ms
                setStage(.result(ms))
                play(ms < 200 ? .win : .coin)
                emit(.record(ms))
                emit(.minimum("reaction.ms", ms))
                emit(.count("reaction.attempts", 1))
            }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    public override func pause() {
        // A paused reaction test can't be fair; drop back to the intro.
        if phase == .playing {
            phase = .paused
            stage = .intro
        }
    }
}
