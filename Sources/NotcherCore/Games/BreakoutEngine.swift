import Foundation

/// Breakout with tough bricks, power-ups, combos and endless levels.
public final class BreakoutEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let columns = 14
    public static let paddleY = 222.0
    public static let paddleHeight = 8.0
    public static let ballRadius = 5.0
    static let margin = 16.0
    static let gap = 4.0
    static let top = 22.0
    static let brickHeight = 11.0

    public static var brickWidth: Double {
        (width - 2 * margin - Double(columns - 1) * gap) / Double(columns)
    }

    public struct Brick: Sendable, Identifiable {
        public let id: Int
        public let row: Int
        public let col: Int
        public var hp: Int
        public let maxHP: Int
        public let box: Box
        /// 1 right after a hit, decays.
        public var flash = 0.0
    }

    public enum PowerKind: CaseIterable, Sendable {
        case wide, multi, slow, life

        public var letter: String {
            switch self {
            case .wide: return "W"
            case .multi: return "M"
            case .slow: return "S"
            case .life: return "+"
            }
        }
    }

    public struct PowerUp: Sendable {
        public let kind: PowerKind
        public var position: Vec2
    }

    public struct Ball: Sendable {
        public var position: Vec2
        public var velocity: Vec2
        public var stuck: Bool
        public var trail: [Vec2] = []
    }

    public private(set) var bricks: [Brick] = []
    public private(set) var balls: [Ball] = []
    public private(set) var powerUps: [PowerUp] = []
    public private(set) var paddleX = BreakoutEngine.width / 2
    public private(set) var paddleVelocity = 0.0
    public private(set) var lives = 3
    public private(set) var level = 1
    public private(set) var combo = 0
    public private(set) var wideTime = 0.0
    public private(set) var slowTime = 0.0
    public private(set) var banner: String?
    public private(set) var bannerTime = 0.0
    public private(set) var particles = ParticleField()

    public var paddleWidth: Double { wideTime > 0 ? 124 : 82 }
    public var multiplier: Int { 1 + combo / 4 }
    var baseSpeed: Double { min(540, 330 + Double(level - 1) * 18) }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var nextBrickID = 0

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.breakout.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        lives = 3
        level = 1
        combo = 0
        score = 0
        wideTime = 0
        slowTime = 0
        banner = nil
        powerUps = []
        particles.removeAll()
        paddleX = Self.width / 2
        paddleVelocity = 0
        buildLevel()
        resetBall()
        phase = .ready
    }

    public func restart() { reset() }

    private func resetBall() {
        balls = [Ball(position: Vec2(paddleX, Self.paddleY - Self.ballRadius - 1), velocity: .zero, stuck: true)]
        combo = 0
    }

    /// Brick hit points for a level layout, 0 for an empty cell.
    static func layout(level: Int, row: Int, col: Int, rng: inout SeededRandom) -> Int {
        let c = Double(col) - Double(columns - 1) / 2
        switch (level - 1) % 5 {
        case 0:
            return row < 5 ? 1 : 0
        case 1:
            if row == 0 { return 2 }
            return row < 6 && (row + col) % 2 == 0 ? 1 : 0
        case 2:
            let d = abs(c) / 7 + abs(Double(row) - 2.5) / 3
            if d > 1.05 { return 0 }
            return d < 0.5 ? 2 : 1
        case 3:
            if col % 3 == 2 { return 0 }
            return row < 2 ? 2 : (row < 6 ? 1 : 0)
        default:
            return 0 // handled by the random layout
        }
    }

    private func buildLevel() {
        bricks = []
        let bw = Self.brickWidth
        let random = (level - 1) % 5 == 4
        let half = Self.columns / 2
        var mirrored: [Int: Int] = [:]
        for row in 0..<6 {
            for col in 0..<Self.columns {
                var hp: Int
                if random {
                    let mirrorCol = col < half ? col : Self.columns - 1 - col
                    let key = row * 100 + mirrorCol
                    if let existing = mirrored[key] {
                        hp = existing
                    } else {
                        hp = rng.chance(0.72) ? (rng.chance(0.2 + 0.04 * Double(level)) ? 2 : 1) : 0
                        mirrored[key] = hp
                    }
                } else {
                    hp = Self.layout(level: level, row: row, col: col, rng: &rng)
                }
                // Later loops get tougher.
                if hp == 1 && level > 5 && rng.chance(min(0.4, Double(level - 5) * 0.06)) { hp = 2 }
                guard hp > 0 else { continue }
                let box = Box(
                    x: Self.margin + Double(col) * (bw + Self.gap),
                    y: Self.top + Double(row) * (Self.brickHeight + Self.gap),
                    w: bw, h: Self.brickHeight
                )
                bricks.append(Brick(id: nextBrickID, row: row, col: col, hp: hp, maxHP: hp, box: box))
                nextBrickID += 1
            }
        }
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .primary, .up:
            switch phase {
            case .ready:
                phase = .playing
                launch()
            case .playing:
                launch()
            case .paused:
                resume()
            case .over:
                if !isRepeat {
                    reset()
                    phase = .playing
                }
            }
            return true
        case .left, .right:
            if phase == .ready { phase = .playing }
            if phase == .paused { resume() }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    private func launch() {
        for i in balls.indices where balls[i].stuck {
            let lean = clamp(paddleVelocity / 560, -1, 1) * 0.5
            let angle = -Double.pi / 2 + lean + rng.double(-0.15...0.15)
            balls[i].velocity = Vec2(cos(angle), sin(angle)) * currentSpeed
            balls[i].stuck = false
            play(.hit)
        }
    }

    var currentSpeed: Double { baseSpeed * (slowTime > 0 ? 0.7 : 1) }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.5)
        for i in bricks.indices where bricks[i].flash > 0 {
            bricks[i].flash = max(0, bricks[i].flash - dt * 5)
        }
        if banner != nil {
            bannerTime -= dt
            if bannerTime <= 0 { banner = nil }
        }
        guard phase == .playing || phase == .ready else { return }

        let axis = input.axis(.left, .right)
        paddleVelocity = approach(paddleVelocity, axis * 580, 18, dt)
        let half = paddleWidth / 2
        paddleX = clamp(paddleX + paddleVelocity * dt, half + 4, Self.width - half - 4)
        guard phase == .playing else {
            stickBalls()
            return
        }

        let wasSlow = slowTime > 0
        wideTime = max(0, wideTime - dt)
        slowTime = max(0, slowTime - dt)
        if wasSlow && slowTime == 0 { rescaleBalls() }

        stickBalls()
        for i in balls.indices where !balls[i].stuck {
            let travel = balls[i].velocity.length * dt
            let steps = max(1, Int(ceil(travel / 3)))
            for _ in 0..<steps {
                moveBall(index: i, dt: dt / Double(steps))
            }
            balls[i].trail.append(balls[i].position)
            if balls[i].trail.count > 10 { balls[i].trail.removeFirst() }
        }

        let lost = balls.filter { $0.position.y > Self.height + 12 }.count
        balls.removeAll { $0.position.y > Self.height + 12 }
        if lost > 0 && balls.isEmpty { loseLife() }

        updatePowerUps(dt)

        if bricks.isEmpty { nextLevel() }
    }

    private func stickBalls() {
        for i in balls.indices where balls[i].stuck {
            balls[i].position = Vec2(paddleX, Self.paddleY - Self.ballRadius - 1)
        }
    }

    private func rescaleBalls() {
        for i in balls.indices where !balls[i].stuck {
            let l = balls[i].velocity.length
            if l > 0 { balls[i].velocity = balls[i].velocity * (currentSpeed / l) }
        }
    }

    private func moveBall(index i: Int, dt: Double) {
        let r = Self.ballRadius
        var ball = balls[i]
        ball.position = ball.position + ball.velocity * dt

        if ball.position.x < r {
            ball.position.x = r
            ball.velocity.x = abs(ball.velocity.x)
            play(.wall)
        } else if ball.position.x > Self.width - r {
            ball.position.x = Self.width - r
            ball.velocity.x = -abs(ball.velocity.x)
            play(.wall)
        }
        if ball.position.y < r {
            ball.position.y = r
            ball.velocity.y = abs(ball.velocity.y)
            play(.wall)
        }

        // Paddle
        let paddle = Box(x: paddleX - paddleWidth / 2, y: Self.paddleY, w: paddleWidth, h: Self.paddleHeight)
        if ball.velocity.y > 0, paddle.circleHit(center: ball.position, radius: r) != nil, ball.position.y < Self.paddleY + 4 {
            let offset = clamp((ball.position.x - paddleX) / (paddleWidth / 2), -1, 1)
            let angle = -Double.pi / 2 + offset * 1.05
            let speed = ball.velocity.length
            ball.velocity = Vec2(cos(angle) * speed, sin(angle) * speed)
            ball.position.y = Self.paddleY - r - 0.5
            combo = 0
            play(.hit)
        }

        // Bricks: resolve at most one per substep.
        if let index = bricks.firstIndex(where: { $0.box.circleHit(center: ball.position, radius: r) != nil }),
           let normal = bricks[index].box.circleHit(center: ball.position, radius: r) {
            if normal.x != 0 {
                ball.velocity.x = abs(ball.velocity.x) * normal.x
                ball.position.x += normal.x * 1.5
            } else {
                ball.velocity.y = abs(ball.velocity.y) * normal.y
                ball.position.y += normal.y * 1.5
            }
            hitBrick(at: index)
        }
        balls[i] = ball
    }

    private func hitBrick(at index: Int) {
        bricks[index].hp -= 1
        bricks[index].flash = 1
        let brick = bricks[index]
        combo += 1
        emit(.maximum("breakout.combo", combo))
        let center = Vec2(brick.box.midX, brick.box.midY)
        if brick.hp > 0 {
            play(.wall)
            score += 5 * multiplier
            return
        }
        bricks.remove(at: index)
        score += 10 * brick.maxHP * multiplier
        emit(.count("breakout.bricks", 1))
        particles.burst(at: center, count: 12, speed: 40...170, life: 0.3...0.6, size: 1.5...3.2, tint: brick.row, gravity: 260, rng: &rng)
        play(.brick)
        if rng.chance(0.13) {
            var kinds: [PowerKind] = [.wide, .multi, .slow, .wide, .multi]
            if lives < 5 { kinds.append(.life) }
            let kind = kinds[rng.int(0...(kinds.count - 1))]
            powerUps.append(PowerUp(kind: kind, position: center))
        }
    }

    private func updatePowerUps(_ dt: Double) {
        let paddle = Box(x: paddleX - paddleWidth / 2, y: Self.paddleY - 2, w: paddleWidth, h: Self.paddleHeight + 4)
        var caught: [PowerKind] = []
        powerUps = powerUps.compactMap { p in
            var p = p
            p.position.y += 95 * dt
            let box = Box(x: p.position.x - 11, y: p.position.y - 6, w: 22, h: 12)
            if box.intersects(paddle) {
                caught.append(p.kind)
                return nil
            }
            return p.position.y > Self.height + 10 ? nil : p
        }
        for kind in caught { apply(kind) }
    }

    private func apply(_ kind: PowerKind) {
        play(.powerUp)
        emit(.count("breakout.powerups", 1))
        switch kind {
        case .wide:
            wideTime = 12
        case .slow:
            slowTime = 9
            rescaleBalls()
        case .life:
            lives = min(5, lives + 1)
        case .multi:
            guard let source = balls.first(where: { !$0.stuck }) ?? balls.first else { return }
            let speed = currentSpeed
            for spin in [-0.5, 0.5] {
                var b = source
                b.stuck = false
                b.trail = []
                let base = source.stuck ? -Double.pi / 2 : atan2(source.velocity.y, source.velocity.x)
                b.velocity = Vec2(cos(base + spin), sin(base + spin)) * speed
                if b.velocity.y > -60 { b.velocity.y = -abs(b.velocity.y) - 60 }
                balls.append(b)
            }
        }
    }

    private func loseLife() {
        lives -= 1
        wideTime = 0
        slowTime = 0
        powerUps = []
        emit(.shake(0.5))
        if lives <= 0 {
            phase = .over
            play(.lose)
            emit(.record(score))
            emit(.count("breakout.games", 1))
            balls = []
        } else {
            play(.error)
            resetBall()
        }
    }

    private func nextLevel() {
        score += 100 * level
        emit(.count("breakout.levels", 1))
        level += 1
        emit(.maximum("breakout.level", level))
        banner = "Level \(level)"
        bannerTime = 1.6
        play(.levelUp)
        powerUps = []
        buildLevel()
        resetBall()
    }
}
