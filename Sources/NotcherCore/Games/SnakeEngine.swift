import Foundation

public struct GridPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }
}

public enum Direction: Sendable, CaseIterable {
    case up, down, left, right

    public var delta: GridPoint {
        switch self {
        case .up: return GridPoint(0, -1)
        case .down: return GridPoint(0, 1)
        case .left: return GridPoint(-1, 0)
        case .right: return GridPoint(1, 0)
        }
    }

    public var opposite: Direction {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    init?(key: GameKey) {
        switch key {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        default: return nil
        }
    }
}

/// Classic snake on a 32×12 grid. Every few apples the arena closes in.
public final class SnakeEngine: EngineBase, GameEngine {
    public static let columns = 32
    public static let rows = 12
    static let shrinkEvery = 6
    static let maxShrink = 3

    /// Head first.
    public private(set) var body: [GridPoint] = []
    /// Body positions before the latest step, for smooth interpolation.
    public private(set) var previousBody: [GridPoint] = []
    public private(set) var direction: Direction = .right
    public private(set) var apple = GridPoint(0, 0)
    /// A bonus gem that appears briefly. `gemTimeLeft` counts down.
    public private(set) var gem: GridPoint?
    public private(set) var gemTimeLeft = 0.0
    public private(set) var apples = 0
    /// How many rings the arena has shrunk by.
    public private(set) var inset = 0
    /// True while the next shrink is waiting for the border to clear.
    public private(set) var shrinkPending = false
    public private(set) var particles = ParticleField()
    public private(set) var deathTime: Double?
    /// 0…1 progress between grid steps.
    public var stepProgress: Double { min(1, accumulator / interval) }
    public var interval: Double { max(0.055, 0.118 - Double(apples) * 0.0028) }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var queue: [Direction] = []
    private var accumulator = 0.0
    private var growth = 0
    private var lastAppleTime = 0.0

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.snake.rawValue)
        reset()
    }

    /// The playable cells: x in minX...maxX, y in minY...maxY.
    public var arena: (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        (inset, Self.columns - 1 - inset, inset, Self.rows - 1 - inset)
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        let y = Self.rows / 2
        body = (0..<4).map { GridPoint(12 - $0, y) }
        previousBody = body
        direction = .right
        queue = []
        accumulator = 0
        growth = 0
        apples = 0
        inset = 0
        shrinkPending = false
        gem = nil
        gemTimeLeft = 0
        score = 0
        deathTime = nil
        particles.removeAll()
        phase = .ready
        apple = randomFreeCell() ?? GridPoint(20, y)
    }

    public func restart() { reset() }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if let dir = Direction(key: key) {
            switch phase {
            case .ready:
                if dir == direction.opposite {
                    body.reverse()
                    previousBody = body
                }
                direction = dir
                queue = []
                phase = .playing
            case .playing:
                guard !isRepeat else { return true }
                let last = queue.last ?? direction
                if dir != last && dir != last.opposite && queue.count < 3 {
                    queue.append(dir)
                }
            case .paused:
                resume()
            case .over:
                break
            }
            return true
        }
        switch key {
        case .primary, .confirm:
            if phase == .over, let death = deathTime, clock - death > 0.4 {
                reset()
                return true
            }
            if phase == .paused { resume(); return true }
            if phase == .ready { phase = .playing; return true }
            return phase == .playing
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 2)
        guard phase == .playing else { return }

        if gem != nil {
            gemTimeLeft -= dt
            if gemTimeLeft <= 0 { gem = nil }
        }

        accumulator += dt
        // Never more than two steps in a single frame.
        var steps = 0
        while accumulator >= interval && phase == .playing && steps < 2 {
            accumulator -= interval
            step()
            steps += 1
        }
        if steps == 2 { accumulator = min(accumulator, interval * 0.5) }
    }

    func step() {
        if let next = queue.first {
            queue.removeFirst()
            if next != direction.opposite { direction = next }
        }
        let head = body[0]
        let d = direction.delta
        let newHead = GridPoint(head.x + d.x, head.y + d.y)

        let a = arena
        let outside = newHead.x < a.minX || newHead.x > a.maxX || newHead.y < a.minY || newHead.y > a.maxY
        // The tail cell frees up this step unless we are growing.
        let collisionBody = growth > 0 ? body[...] : body.dropLast()
        if outside || collisionBody.contains(newHead) {
            die()
            return
        }

        previousBody = body
        body.insert(newHead, at: 0)
        if growth > 0 {
            growth -= 1
        } else {
            body.removeLast()
        }

        if newHead == apple {
            eatApple()
        } else if let g = gem, newHead == g {
            gem = nil
            score += 30
            growth += 1
            burst(at: g, tint: 2, count: 16)
            play(.bonus)
            emit(.count("snake.gems", 1))
        }

        if shrinkPending { tryShrink() }
    }

    private func eatApple() {
        apples += 1
        growth += 1
        // Quick successive apples are worth a little more.
        let quick = clock - lastAppleTime < 3.5 ? 5 : 0
        lastAppleTime = clock
        score += 10 + quick
        burst(at: apple, tint: 1, count: 12)
        play(.eat)
        emit(.count("snake.apples", 1))
        emit(.maximum("snake.length", body.count + growth))
        emit(.maximum("snake.applesInGame", apples))

        if apples % Self.shrinkEvery == 0 && inset < Self.maxShrink {
            shrinkPending = true
            tryShrink()
        }
        apple = randomFreeCell() ?? apple
        if gem == nil && apples % 5 == 0 {
            gem = randomFreeCell()
            gemTimeLeft = 5
        }
    }

    private func tryShrink() {
        let next = inset + 1
        let minX = next, maxX = Self.columns - 1 - next, minY = next, maxY = Self.rows - 1 - next
        func inside(_ p: GridPoint) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }
        guard body.allSatisfy(inside), inside(apple) else { return }
        inset = next
        shrinkPending = false
        if let g = gem, !inside(g) { gem = nil }
        emit(.shake(0.25))
        play(.wall)
    }

    private func randomFreeCell() -> GridPoint? {
        let a = arena
        let occupied = Set(body)
        var free: [GridPoint] = []
        // When a shrink is pending keep new items inside the next ring.
        let pad = shrinkPending ? 1 : 0
        for y in (a.minY + pad)...(a.maxY - pad) {
            for x in (a.minX + pad)...(a.maxX - pad) {
                let p = GridPoint(x, y)
                if !occupied.contains(p) && p != apple && p != gem { free.append(p) }
            }
        }
        guard !free.isEmpty else { return nil }
        return free[rng.int(0...(free.count - 1))]
    }

    private func burst(at p: GridPoint, tint: Int, count: Int) {
        let center = Vec2(Double(p.x) + 0.5, Double(p.y) + 0.5)
        particles.burst(at: center, count: count, speed: 2...7, life: 0.25...0.55, size: 0.08...0.18, tint: tint, rng: &rng)
    }

    private func die() {
        phase = .over
        deathTime = clock
        let head = body[0]
        particles.burst(
            at: Vec2(Double(head.x) + 0.5, Double(head.y) + 0.5), count: 24, speed: 2...9,
            life: 0.4...0.9, size: 0.1...0.22, tint: 3, rng: &rng
        )
        emit(.shake(0.6))
        play(.lose)
        emit(.record(score))
        emit(.count("snake.games", 1))
    }
}
