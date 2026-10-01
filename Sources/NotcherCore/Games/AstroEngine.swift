import Foundation

/// Vector space rocks: rotate, thrust, shoot and warp on a wrapping field.
public final class AstroEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let shipRadius = 7.0

    public struct Ship: Sendable {
        public var position = Vec2(AstroEngine.width / 2, AstroEngine.height / 2)
        public var velocity = Vec2.zero
        /// Radians; 0 points right, -π/2 points up.
        public var angle = -Double.pi / 2
        public var thrusting = false
    }

    public struct Rock: Sendable, Identifiable {
        public let id: Int
        public var position: Vec2
        public var velocity: Vec2
        /// 3 large, 2 medium, 1 small.
        public let size: Int
        public var angle: Double
        public let spin: Double
        /// Radius multipliers for the jagged outline.
        public let outline: [Double]

        public var radius: Double { [0, 7, 13, 24][size] }
    }

    public struct Bullet: Sendable {
        public var position: Vec2
        public var velocity: Vec2
        public var life: Double
    }

    public private(set) var ship = Ship()
    public private(set) var rocks: [Rock] = []
    public private(set) var bullets: [Bullet] = []
    public private(set) var particles = ParticleField()
    public private(set) var lives = 3
    public private(set) var wave = 1
    public private(set) var respawn = 0.0
    public private(set) var invulnerable = 0.0
    public private(set) var warpCooldown = 0.0
    public private(set) var waveBanner: Double?
    /// Trail of recent ship positions while thrusting.
    public private(set) var exhaust: [Vec2] = []

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var nextRockID = 0
    private var fireCooldown = 0.0
    private var nextExtraLife = 10_000
    private var overAt = 0.0
    private var waveDelay = 0.0

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.astro.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        ship = Ship()
        bullets = []
        particles.removeAll()
        exhaust = []
        lives = 3
        wave = 1
        score = 0
        respawn = 0
        invulnerable = 0
        warpCooldown = 0
        nextExtraLife = 10_000
        waveDelay = 0
        spawnWave()
        phase = .ready
    }

    public func restart() { reset() }

    private func spawnWave() {
        rocks = []
        let count = min(9, 2 + wave)
        for _ in 0..<count {
            var p = Vec2(0, 0)
            repeat {
                p = Vec2(rng.double(0...Self.width), rng.double(0...Self.height))
            } while (p - ship.position).length < 110
            rocks.append(makeRock(size: 3, at: p))
        }
        waveBanner = clock
    }

    private func makeRock(size: Int, at p: Vec2) -> Rock {
        let speed: Double
        switch size {
        case 3: speed = rng.double(26...48)
        case 2: speed = rng.double(48...80)
        default: speed = rng.double(75...115)
        }
        let a = rng.double(0...(2 * Double.pi))
        let boost = 1 + Double(wave - 1) * 0.07
        let outline = (0..<11).map { _ in rng.double(0.72...1.08) }
        let heading: Vec2 = Vec2(cos(a), sin(a))
        let velocity: Vec2 = heading * (speed * boost)
        defer { nextRockID += 1 }
        return Rock(
            id: nextRockID, position: p, velocity: velocity, size: size,
            angle: rng.double(0...6), spin: rng.double(-1.2...1.2), outline: outline
        )
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .primary:
            switch phase {
            case .ready: phase = .playing
            case .paused: resume()
            case .over:
                if !isRepeat && clock - overAt > 0.5 {
                    reset()
                    phase = .playing
                }
            case .playing: if !isRepeat { fire() }
            }
            return true
        case .left, .right, .up:
            if phase == .ready { phase = .playing }
            if phase == .paused { resume() }
            return true
        case .down:
            if phase == .playing && !isRepeat { warp() }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    private var forward: Vec2 { Vec2(cos(ship.angle), sin(ship.angle)) }

    private func fire() {
        guard respawn <= 0, fireCooldown <= 0, bullets.count < 6 else { return }
        let nose = ship.position + forward * 9
        bullets.append(Bullet(position: nose, velocity: forward * 430 + ship.velocity * 0.6, life: 0.75))
        fireCooldown = 0.16
        play(.laser)
    }

    private func warp() {
        guard respawn <= 0, warpCooldown <= 0 else { return }
        particles.burst(at: ship.position, count: 16, speed: 40...140, life: 0.25...0.5, size: 1...2.5, tint: 3, rng: &rng)
        ship.position = Vec2(rng.double(30...(Self.width - 30)), rng.double(30...(Self.height - 30)))
        ship.velocity = .zero
        invulnerable = max(invulnerable, 0.7)
        warpCooldown = 3
        particles.burst(at: ship.position, count: 16, speed: 40...140, life: 0.25...0.5, size: 1...2.5, tint: 3, rng: &rng)
        play(.powerUp)
        emit(.count("astro.warps", 1))
    }

    // MARK: Tick

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.2)
        if let b = waveBanner, clock - b > 1.6 { waveBanner = nil }
        moveRocks(dt)
        guard phase == .playing else { return }

        fireCooldown -= dt
        warpCooldown = max(0, warpCooldown - dt)
        invulnerable = max(0, invulnerable - dt)

        if respawn > 0 {
            respawn -= dt
            if respawn <= 0 {
                if lives <= 0 {
                    gameOver()
                    return
                }
                let center = Vec2(Self.width / 2, Self.height / 2)
                if rocks.contains(where: { distance($0.position, center) < $0.radius + 50 }) {
                    respawn = 0.2 // wait for the centre to clear
                } else {
                    ship = Ship()
                    invulnerable = 2
                }
            }
        } else {
            steer(dt, input: input)
        }

        moveBullets(dt)
        collide()

        if rocks.isEmpty {
            waveDelay += dt
            if waveDelay > 1.2 {
                waveDelay = 0
                wave += 1
                emit(.maximum("astro.wave", wave))
                play(.levelUp)
                spawnWave()
            }
        }
    }

    private func steer(_ dt: Double, input: InputState) {
        ship.angle += input.axis(.left, .right) * 4.4 * dt
        ship.thrusting = input.isHeld(.up)
        if ship.thrusting {
            ship.velocity = ship.velocity + forward * (300 * dt)
            let speed = ship.velocity.length
            if speed > 260 { ship.velocity = ship.velocity * (260 / speed) }
            if Int(clock * 60) % 2 == 0 {
                let back = ship.position - forward * 8
                particles.burst(
                    at: back, count: 1, speed: 40...90, life: 0.15...0.35, size: 1...2.2, tint: 2,
                    spread: (ship.angle + Double.pi - 0.35)...(ship.angle + Double.pi + 0.35), rng: &rng
                )
            }
            play(.thrust)
        }
        ship.velocity = ship.velocity * max(0, 1 - 0.45 * dt)
        ship.position = wrap(ship.position + ship.velocity * dt)
        if input.isHeld(.primary) { fire() }
    }

    private func moveRocks(_ dt: Double) {
        for i in rocks.indices {
            rocks[i].position = wrap(rocks[i].position + rocks[i].velocity * dt)
            rocks[i].angle += rocks[i].spin * dt
        }
    }

    private func moveBullets(_ dt: Double) {
        for i in bullets.indices {
            bullets[i].position = wrap(bullets[i].position + bullets[i].velocity * dt)
            bullets[i].life -= dt
        }
        bullets.removeAll { $0.life <= 0 }
    }

    private func collide() {
        var spent: Set<Int> = []
        for (bi, bullet) in bullets.enumerated() {
            if let ri = rocks.firstIndex(where: { distance($0.position, bullet.position) < $0.radius }) {
                spent.insert(bi)
                split(ri, impact: bullet.velocity)
            }
        }
        bullets = bullets.enumerated().filter { !spent.contains($0.offset) }.map(\.element)

        guard respawn <= 0, invulnerable <= 0 else { return }
        if let ri = rocks.firstIndex(where: { distance($0.position, ship.position) < $0.radius * 0.86 + Self.shipRadius }) {
            split(ri, impact: ship.velocity)
            lives -= 1
            particles.burst(at: ship.position, count: 34, speed: 40...220, life: 0.5...1.2, size: 1.5...3.5, tint: 1, rng: &rng)
            emit(.shake(0.8))
            play(.explode)
            respawn = 1.4
            ship.thrusting = false
        }
    }

    private func split(_ index: Int, impact: Vec2) {
        let rock = rocks.remove(at: index)
        let points = [0, 100, 50, 20][rock.size]
        score += points
        emit(.count("astro.rocks", 1))
        particles.burst(at: rock.position, count: 6 + rock.size * 6, speed: 30...160, life: 0.3...0.8, size: 1...2.6, tint: 0, rng: &rng)
        play(rock.size == 3 ? .explode : .brick)
        if rock.size == 3 { emit(.shake(0.25)) }
        if rock.size > 1 {
            for _ in 0..<2 {
                var child = makeRock(size: rock.size - 1, at: rock.position)
                child.velocity = child.velocity + impact * 0.04
                rocks.append(child)
            }
        }
        if score >= nextExtraLife {
            nextExtraLife += 10_000
            lives = min(5, lives + 1)
            play(.powerUp)
        }
    }

    /// Shortest distance on the wrapping field.
    func distance(_ a: Vec2, _ b: Vec2) -> Double {
        var dx = abs(a.x - b.x), dy = abs(a.y - b.y)
        if dx > Self.width / 2 { dx = Self.width - dx }
        if dy > Self.height / 2 { dy = Self.height - dy }
        return (dx * dx + dy * dy).squareRoot()
    }

    private func wrap(_ p: Vec2) -> Vec2 {
        var x = p.x.truncatingRemainder(dividingBy: Self.width)
        var y = p.y.truncatingRemainder(dividingBy: Self.height)
        if x < 0 { x += Self.width }
        if y < 0 { y += Self.height }
        return Vec2(x, y)
    }

    private func gameOver() {
        phase = .over
        overAt = clock
        play(.lose)
        emit(.record(score))
        emit(.count("astro.games", 1))
    }
}
