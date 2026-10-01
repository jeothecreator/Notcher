import Foundation

/// Pong against an AI that gets sharper every match you win. First to five.
public final class PongEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let paddleWidth = 9.0
    public static let paddleHeight = 52.0
    public static let ballRadius = 6.0
    public static let pointsToWin = 5

    public struct Paddle: Sendable {
        public var y: Double
        public var velocity = 0.0
        /// 1 right after a hit, decays.
        public var flash = 0.0
    }

    public private(set) var player = Paddle(y: PongEngine.height / 2)
    public private(set) var ai = Paddle(y: PongEngine.height / 2)
    public private(set) var ball = Vec2(PongEngine.width / 2, PongEngine.height / 2)
    public private(set) var ballVelocity = Vec2.zero
    /// Recent ball positions, newest last.
    public private(set) var trail: [Vec2] = []
    public private(set) var playerPoints = 0
    public private(set) var aiPoints = 0
    public private(set) var level = 1
    public private(set) var matchesWon = 0
    public private(set) var totalPoints = 0
    public private(set) var rally = 0
    /// Seconds until the next serve, > 0 while waiting.
    public private(set) var serveTimer = 0.0
    /// Shown briefly between matches, e.g. "Level 2".
    public private(set) var banner: String?
    public private(set) var bannerTime = 0.0
    public private(set) var particles = ParticleField()

    public static let playerX = 22.0
    public static let aiX = PongEngine.width - 22.0 - PongEngine.paddleWidth

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var serveToPlayer = false
    private var aiError = 0.0
    private var aiReaction = 0.0

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.pong.rawValue)
        reset()
    }

    var aiMaxSpeed: Double { min(560, 230 + Double(level - 1) * 55) }
    var aiErrorRange: Double { max(4, 30 - Double(level - 1) * 5) }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        player = Paddle(y: Self.height / 2)
        ai = Paddle(y: Self.height / 2)
        playerPoints = 0
        aiPoints = 0
        level = 1
        matchesWon = 0
        totalPoints = 0
        score = 0
        banner = nil
        particles.removeAll()
        trail = []
        centerBall()
        serveToPlayer = false
        serveTimer = 0
        phase = .ready
    }

    public func restart() { reset() }

    private func centerBall() {
        ball = Vec2(Self.width / 2, Self.height / 2)
        ballVelocity = .zero
        trail = []
        rally = 0
    }

    private func serve() {
        let angle = rng.double(-0.45...0.45)
        let speed = 300 + Double(level - 1) * 18
        let dir: Double = serveToPlayer ? -1 : 1
        ballVelocity = Vec2(cos(angle) * speed * dir, sin(angle) * speed)
        aiError = rng.double(-aiErrorRange...aiErrorRange)
        play(.go)
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .up, .down, .primary:
            switch phase {
            case .ready:
                phase = .playing
                serveTimer = 0.5
            case .paused:
                resume()
            case .over:
                if key == .primary && !isRepeat {
                    reset()
                    phase = .playing
                    serveTimer = 0.5
                }
            case .playing:
                break
            }
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
        particles.update(dt, drag: 2)
        player.flash = max(0, player.flash - dt * 4)
        ai.flash = max(0, ai.flash - dt * 4)
        if banner != nil {
            bannerTime -= dt
            if bannerTime <= 0 { banner = nil }
        }
        guard phase == .playing else { return }

        // Player paddle with a little inertia.
        let axis = input.axis(.up, .down)
        player.velocity = approach(player.velocity, axis * 430, 16, dt)
        player.y = clamp(player.y + player.velocity * dt, Self.paddleHeight / 2, Self.height - Self.paddleHeight / 2)

        moveAI(dt)

        if serveTimer > 0 {
            serveTimer -= dt
            if serveTimer <= 0 { serve() }
            return
        }

        // Substeps keep a fast ball from tunnelling through paddles.
        let travel = ballVelocity.length * dt
        let steps = max(1, Int(ceil(travel / 4)))
        let sdt = dt / Double(steps)
        for _ in 0..<steps {
            if moveBall(sdt) { break }
        }
        trail.append(ball)
        if trail.count > 12 { trail.removeFirst() }
    }

    private func moveAI(_ dt: Double) {
        var target = Self.height / 2
        if ballVelocity.x > 0 {
            aiReaction -= dt
            target = predictY(atX: Self.aiX) + aiError
        } else {
            aiReaction = 0.12
            target = Self.height / 2 + (ball.y - Self.height / 2) * 0.3
        }
        let diff = target - ai.y
        let desired = aiReaction > 0 ? 0 : clamp(diff * 6, -aiMaxSpeed, aiMaxSpeed)
        ai.velocity = approach(ai.velocity, desired, 12, dt)
        ai.y = clamp(ai.y + ai.velocity * dt, Self.paddleHeight / 2, Self.height - Self.paddleHeight / 2)
    }

    /// Where the ball will cross `x`, accounting for wall bounces.
    func predictY(atX x: Double) -> Double {
        guard ballVelocity.x != 0 else { return ball.y }
        let t = (x - ball.x) / ballVelocity.x
        guard t > 0 else { return ball.y }
        let r = Self.ballRadius
        let span = Self.height - 2 * r
        var y = ball.y - r + ballVelocity.y * t
        let period = 2 * span
        y = y.truncatingRemainder(dividingBy: period)
        if y < 0 { y += period }
        if y > span { y = period - y }
        return y + r
    }

    /// Returns true when a point was scored.
    private func moveBall(_ dt: Double) -> Bool {
        let r = Self.ballRadius
        ball = ball + ballVelocity * dt

        if ball.y < r {
            ball.y = r
            ballVelocity.y = abs(ballVelocity.y)
            play(.wall)
        } else if ball.y > Self.height - r {
            ball.y = Self.height - r
            ballVelocity.y = -abs(ballVelocity.y)
            play(.wall)
        }

        let playerBox = Box(x: Self.playerX, y: player.y - Self.paddleHeight / 2, w: Self.paddleWidth, h: Self.paddleHeight)
        let aiBox = Box(x: Self.aiX, y: ai.y - Self.paddleHeight / 2, w: Self.paddleWidth, h: Self.paddleHeight)

        if ballVelocity.x < 0, playerBox.circleHit(center: ball, radius: r) != nil, ball.x > playerBox.minX {
            bounce(off: playerBox, paddleVelocity: player.velocity, direction: 1)
            player.flash = 1
            ball.x = playerBox.maxX + r
        } else if ballVelocity.x > 0, aiBox.circleHit(center: ball, radius: r) != nil, ball.x < aiBox.maxX {
            bounce(off: aiBox, paddleVelocity: ai.velocity, direction: -1)
            ai.flash = 1
            ball.x = aiBox.minX - r
            aiError = rng.double(-aiErrorRange...aiErrorRange)
        }

        if ball.x < -r * 2 {
            pointScored(byPlayer: false)
            return true
        }
        if ball.x > Self.width + r * 2 {
            pointScored(byPlayer: true)
            return true
        }
        return false
    }

    private func bounce(off paddle: Box, paddleVelocity: Double, direction: Double) {
        let offset = clamp((ball.y - paddle.midY) / (Self.paddleHeight / 2), -1, 1)
        let angle = offset * 0.95 // up to ~55°
        let speed = min(780, ballVelocity.length * 1.055)
        ballVelocity = Vec2(cos(angle) * speed * direction, sin(angle) * speed + paddleVelocity * 0.12)
        rally += 1
        particles.burst(
            at: ball, count: 8, speed: 40...160, life: 0.15...0.35, size: 1...2.5,
            tint: direction > 0 ? 0 : 1,
            spread: direction > 0 ? (-.pi / 2)...(.pi / 2) : (.pi / 2)...(3 * .pi / 2), rng: &rng
        )
        play(.hit)
        emit(.maximum("pong.rally", rally))
    }

    private func pointScored(byPlayer: Bool) {
        particles.burst(
            at: Vec2(clamp(ball.x, 0, Self.width), ball.y), count: 18, speed: 60...220, life: 0.3...0.7,
            size: 1.5...3, tint: byPlayer ? 0 : 1, rng: &rng
        )
        if byPlayer {
            playerPoints += 1
            totalPoints += 1
            emit(.count("pong.points", 1))
            play(.coin)
        } else {
            aiPoints += 1
            emit(.shake(0.35))
            play(.error)
        }
        score = totalPoints + matchesWon * 10
        centerBall()
        serveToPlayer = !byPlayer
        serveTimer = 0.7

        if playerPoints >= Self.pointsToWin {
            if aiPoints == 0 { emit(.count("pong.flawless", 1)) }
            matchesWon += 1
            level += 1
            score = totalPoints + matchesWon * 10
            playerPoints = 0
            aiPoints = 0
            banner = "Level \(level)"
            bannerTime = 1.6
            serveTimer = 1.6
            emit(.count("pong.wins", 1))
            emit(.maximum("pong.level", level))
            play(.levelUp)
        } else if aiPoints >= Self.pointsToWin {
            phase = .over
            emit(.record(score))
            emit(.count("pong.matches", 1))
            play(.lose)
        }
    }
}
