import Foundation

/// Light cycles: outlast the AI riders on a neon grid.
public final class TrailsEngine: EngineBase, GameEngine {
    public static let columns = 80
    public static let rows = 30
    public static let cell = 8.0

    public struct Bike: Sendable {
        public let index: Int
        public var head: GridPoint
        public var direction: Direction
        public var alive = true
        /// Every cell visited, oldest first.
        public var path: [GridPoint]
        public var crashedAt: Double?
        public var isPlayer: Bool { index == 0 }
    }

    public private(set) var bikes: [Bike] = []
    public private(set) var round = 1
    public private(set) var lives = 3
    public private(set) var particles = ParticleField()
    /// Seconds until the round starts moving.
    public private(set) var countdown = 0.0
    /// Set when a round ends: true if the player won it.
    public private(set) var roundResult: (won: Bool, at: Double)?
    /// 0…1 progress between grid steps, for smooth heads.
    public var stepProgress: Double { min(1, timer / interval) }

    var interval: Double { max(0.032, 0.052 - Double(round - 1) * 0.003) }
    var opponentCount: Int { min(3, 1 + (round - 1) / 2) }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var grid: [Int8] = []
    private var queue: [Direction] = []
    private var timer = 0.0
    private var overAt = 0.0
    private var survivedSteps = 0

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.trails.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        round = 1
        lives = 3
        score = 0
        particles.removeAll()
        startRound()
        phase = .ready
    }

    public func restart() { reset() }

    private func startRound() {
        grid = Array(repeating: -1, count: Self.columns * Self.rows)
        queue = []
        timer = 0
        roundResult = nil
        survivedSteps = 0
        let midY = Self.rows / 2
        var starts: [(GridPoint, Direction)] = [(GridPoint(8, midY), .right)]
        let spots: [(GridPoint, Direction)] = [
            (GridPoint(Self.columns - 9, midY), .left),
            (GridPoint(Self.columns / 2, 3), .down),
            (GridPoint(Self.columns / 2, Self.rows - 4), .up),
        ]
        starts += spots.prefix(opponentCount)
        bikes = starts.enumerated().map { i, s in
            Bike(index: i, head: s.0, direction: s.1, path: [s.0])
        }
        for b in bikes { mark(b.head, b.index) }
        countdown = 1.2
    }

    private func index(_ p: GridPoint) -> Int { p.y * Self.columns + p.x }

    private func inside(_ p: GridPoint) -> Bool {
        p.x >= 0 && p.x < Self.columns && p.y >= 0 && p.y < Self.rows
    }

    private func free(_ p: GridPoint) -> Bool {
        inside(p) && grid[index(p)] < 0
    }

    private func mark(_ p: GridPoint, _ bike: Int) {
        if inside(p) { grid[index(p)] = Int8(bike) }
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if let dir = Direction(key: key) {
            switch phase {
            case .ready:
                phase = .playing
                if dir != bikes[0].direction.opposite { queue = [dir] }
            case .paused:
                resume()
            case .playing:
                guard !isRepeat, bikes.indices.contains(0) else { return true }
                let last = queue.last ?? bikes[0].direction
                if dir != last && dir != last.opposite && queue.count < 2 { queue.append(dir) }
            case .over:
                break
            }
            return true
        }
        switch key {
        case .primary, .confirm:
            if phase == .over, !isRepeat, clock - overAt > 0.6 {
                reset()
                phase = .playing
            } else if phase == .ready {
                phase = .playing
            } else if phase == .paused {
                resume()
            }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    // MARK: Tick

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.4)
        guard phase == .playing else { return }

        if let result = roundResult {
            if clock - result.at > 1.4 {
                if result.won {
                    round += 1
                    emit(.maximum("trails.round", round))
                } else if lives <= 0 {
                    gameOver()
                    return
                }
                startRound()
            }
            return
        }
        if countdown > 0 {
            countdown -= dt
            if countdown <= 0 { play(.go) }
            return
        }

        timer += dt
        var steps = 0
        while timer >= interval && roundResult == nil && steps < 2 {
            timer -= interval
            step()
            steps += 1
        }
    }

    func step() {
        // Choose directions.
        if bikes[0].alive, let next = queue.first {
            queue.removeFirst()
            if next != bikes[0].direction.opposite { bikes[0].direction = next }
        }
        for i in bikes.indices.dropFirst() where bikes[i].alive {
            bikes[i].direction = decide(for: i)
        }

        // Move simultaneously.
        var targets: [Int: GridPoint] = [:]
        for b in bikes where b.alive {
            let d = b.direction.delta
            targets[b.index] = GridPoint(b.head.x + d.x, b.head.y + d.y)
        }
        var crashed: Set<Int> = []
        for (i, t) in targets {
            if !free(t) { crashed.insert(i) }
            for (j, u) in targets where j != i && u == t { crashed.insert(i) }
        }
        for (i, t) in targets where !crashed.contains(i) {
            bikes[i].head = t
            bikes[i].path.append(t)
            mark(t, i)
        }
        for i in crashed { crash(i) }

        if bikes[0].alive {
            survivedSteps += 1
            if survivedSteps % 10 == 0 { score += 1 }
        }
        checkRound()
    }

    private func crash(_ i: Int) {
        bikes[i].alive = false
        bikes[i].crashedAt = clock
        let h = bikes[i].head
        particles.burst(
            at: Vec2(Double(h.x) + 0.5, Double(h.y) + 0.5), count: 26, speed: 4...22, life: 0.4...1.0,
            size: 0.15...0.4, tint: i, rng: &rng
        )
        if i == 0 {
            emit(.shake(0.7))
            play(.explode)
        } else {
            emit(.shake(0.25))
            play(.brick)
            emit(.count("trails.knockouts", 1))
        }
    }

    private func checkRound() {
        let playerAlive = bikes[0].alive
        let rivalsAlive = bikes.dropFirst().contains(where: \.alive)
        if !playerAlive {
            lives -= 1
            roundResult = (false, clock)
            play(.lose)
        } else if !rivalsAlive {
            score += 100 * round + survivedSteps / 2
            roundResult = (true, clock)
            emit(.count("trails.rounds", 1))
            play(.win)
        }
    }

    // MARK: AI

    private func decide(for i: Int) -> Direction {
        let bike = bikes[i]
        let current = bike.direction
        let options = [current, turnLeft(current), turnRight(current)]
        let player = bikes[0]
        var best = current
        var bestScore = -Double.infinity
        for d in options {
            let next = GridPoint(bike.head.x + d.delta.x, bike.head.y + d.delta.y)
            guard free(next) else { continue }
            var value = Double(space(from: next, limit: 500))
            if d == current { value += 3 }
            // Later rounds hunt the player: head for the cell in front of them.
            if round > 1 && player.alive {
                let ahead = GridPoint(player.head.x + player.direction.delta.x * 4, player.head.y + player.direction.delta.y * 4)
                let distance = Double(abs(ahead.x - next.x) + abs(ahead.y - next.y))
                value -= distance * 0.6 * min(1, Double(round - 1) * 0.35)
            }
            value += rng.double(0...4)
            if value > bestScore {
                bestScore = value
                best = d
            }
        }
        return best
    }

    private func turnLeft(_ d: Direction) -> Direction {
        switch d {
        case .up: return .left
        case .left: return .down
        case .down: return .right
        case .right: return .up
        }
    }

    private func turnRight(_ d: Direction) -> Direction { turnLeft(turnLeft(turnLeft(d))) }

    /// Reachable free cells from `start`, capped.
    func space(from start: GridPoint, limit: Int) -> Int {
        var seen = Set([start])
        var stack = [start]
        while let p = stack.popLast(), seen.count < limit {
            for d in Direction.allCases {
                let n = GridPoint(p.x + d.delta.x, p.y + d.delta.y)
                if free(n) && !seen.contains(n) {
                    seen.insert(n)
                    stack.append(n)
                }
            }
        }
        return min(seen.count, limit)
    }

    private func gameOver() {
        phase = .over
        overAt = clock
        emit(.record(score))
        emit(.count("trails.games", 1))
    }
}
