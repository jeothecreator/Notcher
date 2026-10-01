import Foundation

/// Endless runner. Space jumps (hold for height), ↓ slides or fast-falls.
public final class RunnerEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let groundY = 200.0

    static let minSpeed = 320.0
    static let maxSpeed = 820.0
    static let acceleration = 9.0
    static let gravity = 2600.0
    static let jumpVelocity = 820.0

    public enum ObstacleKind: Sendable { case block, spikes, drone }

    public struct Obstacle: Sendable {
        public var kind: ObstacleKind
        public var box: Box
        public var seed: Double

        var hitBox: Box {
            switch kind {
            case .spikes: return Box(x: box.x + 4, y: box.y + 5, w: box.w - 8, h: box.h - 5)
            case .drone: return box.insetBy(2)
            case .block: return box.insetBy(1)
            }
        }
    }

    public struct Coin: Sendable {
        public var position: Vec2
        public var spin: Double
    }

    public struct Player: Sendable {
        public var x = 92.0
        /// Bottom edge (feet).
        public var y = RunnerEngine.groundY
        public var vy = 0.0
        public var onGround = true
        public var sliding = false
        public var runCycle = 0.0
        /// 1 right after landing, decays to 0.
        public var squash = 0.0

        public var box: Box {
            sliding
                ? Box(x: x - 4, y: y - 15, w: 32, h: 15)
                : Box(x: x, y: y - 30, w: 22, h: 30)
        }
    }

    public private(set) var player = Player()
    public private(set) var obstacles: [Obstacle] = []
    public private(set) var coins: [Coin] = []
    public private(set) var particles = ParticleField()
    public private(set) var speed = RunnerEngine.minSpeed
    public private(set) var distance = 0.0
    public private(set) var coinsCollected = 0
    public private(set) var deathTime: Double?

    public var difficulty: Double {
        (speed - Self.minSpeed) / (Self.maxSpeed - Self.minSpeed)
    }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var spawnIn = 0.0
    private var coyote = 0.0
    private var jumpBuffer = 0.0
    private var jumpCut = false
    private var dustTimer = 0.0

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.runner.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        player = Player()
        obstacles = []
        coins = []
        particles.removeAll()
        speed = Self.minSpeed
        distance = 0
        coinsCollected = 0
        deathTime = nil
        score = 0
        spawnIn = 520
        coyote = 0
        jumpBuffer = 0
        jumpCut = false
        phase = .ready
    }

    public func restart() {
        reset()
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .primary, .up:
            switch phase {
            case .ready:
                phase = .playing
                jumpBuffer = 0.12
            case .playing:
                if !isRepeat { jumpBuffer = 0.12 }
            case .paused:
                resume()
            case .over:
                guard !isRepeat, let death = deathTime, clock - death > 0.45 else { return true }
                reset()
                phase = .playing
            }
            return true
        case .down:
            if phase == .ready { phase = .playing }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.2)
        switch phase {
        case .ready:
            player.runCycle += dt * 3
        case .playing:
            simulate(dt, input: input)
        case .paused, .over:
            break
        }
    }

    private func simulate(_ dt: Double, input: InputState) {
        speed = min(Self.maxSpeed, speed + Self.acceleration * dt)
        let dx = speed * dt
        distance += dx

        // Input
        let down = input.isHeld(.down)
        let jumpHeld = input.isHeld(.primary) || input.isHeld(.up)
        jumpBuffer -= dt
        coyote = player.onGround ? 0.09 : coyote - dt
        if jumpBuffer > 0 && coyote > 0 {
            player.vy = -Self.jumpVelocity
            player.onGround = false
            player.sliding = false
            coyote = 0
            jumpBuffer = 0
            jumpCut = false
            play(.jump)
        }
        if !player.onGround && !jumpHeld && !jumpCut && player.vy < -260 {
            player.vy *= 0.5
            jumpCut = true
        }

        // Physics
        var gravity = Self.gravity
        if down && !player.onGround { gravity *= 2.6 }
        player.vy += gravity * dt
        player.y += player.vy * dt
        if player.y >= Self.groundY {
            if !player.onGround {
                player.squash = 1
                particles.burst(
                    at: Vec2(player.x + 11, Self.groundY), count: 6, speed: 30...90, life: 0.25...0.45,
                    size: 1.5...3, tint: 0, gravity: -40, spread: (.pi)...(2 * .pi), rng: &rng
                )
            }
            player.y = Self.groundY
            player.vy = 0
            player.onGround = true
        } else {
            player.onGround = false
        }
        let wasSliding = player.sliding
        player.sliding = down && player.onGround
        if player.sliding && !wasSliding { play(.slide) }
        player.runCycle += dt * speed / 38
        player.squash = max(0, player.squash - dt * 5)

        if player.onGround {
            dustTimer -= dt
            if dustTimer <= 0 {
                dustTimer = player.sliding ? 0.03 : 0.12
                particles.burst(
                    at: Vec2(player.x + 2, Self.groundY - 1), count: 1, speed: 20...60, life: 0.2...0.4,
                    size: 1...2.2, tint: 0, gravity: -30, spread: (.pi * 1.05)...(.pi * 1.35), rng: &rng
                )
            }
        }

        // World scroll
        for i in obstacles.indices {
            obstacles[i].box.x -= dx
            if obstacles[i].kind == .drone {
                obstacles[i].box.y = Self.groundY - 38 + sin(clock * 6 + obstacles[i].seed) * 1.5
            }
        }
        obstacles.removeAll { $0.box.maxX < -40 }
        for i in coins.indices {
            coins[i].position.x -= dx
            coins[i].spin += dt * 6
        }
        coins.removeAll { $0.position.x < -20 }

        spawnIn -= dx
        if spawnIn <= 0 { spawnPattern() }

        // Coins
        let center = Vec2(player.box.midX, player.box.midY)
        var collected: [Int] = []
        for (i, coin) in coins.enumerated() where (coin.position - center).length < 20 {
            collected.append(i)
        }
        for i in collected.reversed() {
            let coin = coins.remove(at: i)
            coinsCollected += 1
            particles.burst(at: coin.position, count: 8, speed: 40...140, life: 0.25...0.5, size: 1.5...3, tint: 2, rng: &rng)
            play(.coin)
            emit(.count("runner.coins", 1))
        }

        score = Int(distance / 10) + coinsCollected * 25

        // Collisions
        let body = player.box.insetBy(3)
        if obstacles.contains(where: { $0.hitBox.intersects(body) }) {
            die()
        }
    }

    private func spawnPattern() {
        let d = difficulty
        let x = Self.width + 30
        let roll = rng.unit()
        var width = 0.0

        if roll < 0.12 && d > 0.25 {
            // Two blocks back to back: one long jump.
            let h1 = rng.double(24...34), h2 = rng.double(24...38)
            obstacles.append(Obstacle(kind: .block, box: Box(x: x, y: Self.groundY - h1, w: 20, h: h1), seed: 0))
            obstacles.append(Obstacle(kind: .block, box: Box(x: x + 44, y: Self.groundY - h2, w: 20, h: h2), seed: 0))
            width = 64
        } else if roll < 0.32 && distance > 1600 {
            let box = Box(x: x, y: Self.groundY - 38, w: 34, h: 16)
            obstacles.append(Obstacle(kind: .drone, box: box, seed: rng.double(0...6)))
            width = 34
        } else if roll < 0.55 {
            let w = rng.double(34...(56 + 14 * d))
            obstacles.append(Obstacle(kind: .spikes, box: Box(x: x, y: Self.groundY - 16, w: w, h: 16), seed: 0))
            width = w
        } else {
            let w = rng.double(18...30)
            let h = rng.double(26...(40 + 10 * d))
            obstacles.append(Obstacle(kind: .block, box: Box(x: x, y: Self.groundY - h, w: w, h: h), seed: 0))
            width = w
        }

        let gapTime = rng.double(0.95...1.7) - 0.25 * d
        let gap = speed * gapTime

        if rng.chance(0.38) {
            // An arc of coins in the gap that follows a jump.
            let count = rng.int(3...5)
            let startX = x + width + gap * 0.35
            let high = rng.chance(0.6)
            for i in 0..<count {
                let t = Double(i) / Double(max(1, count - 1))
                let lift = high ? 40 + sin(t * .pi) * 52 : 16
                coins.append(Coin(position: Vec2(startX + Double(i) * 24, Self.groundY - lift), spin: Double(i)))
            }
        }

        spawnIn = width + gap
    }

    private func die() {
        phase = .over
        deathTime = clock
        particles.burst(
            at: Vec2(player.box.midX, player.box.midY), count: 26, speed: 60...260, life: 0.4...0.9,
            size: 2...4, tint: 1, gravity: 420, rng: &rng
        )
        emit(.shake(0.8))
        play(.lose)
        emit(.record(score))
        emit(.count("runner.runs", 1))
        emit(.maximum("runner.score", score))
    }
}
