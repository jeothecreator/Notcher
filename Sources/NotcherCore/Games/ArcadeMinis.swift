import Foundation

// MARK: - Flap

/// Flap through the gaps. One button.
public final class FlapEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let birdX = 150.0
    public static let birdRadius = 9.0
    public static let pipeWidth = 46.0

    public struct Pipe: Sendable {
        public var x: Double
        public var gapY: Double
        public var gapHeight: Double
        public var passed = false
    }

    public private(set) var birdY = FlapEngine.height / 2
    public private(set) var velocity = 0.0
    public private(set) var pipes: [Pipe] = []
    public private(set) var distance = 0.0
    public private(set) var particles = ParticleField()
    public private(set) var deathTime: Double?

    public var tilt: Double { clamp(velocity / 600, -0.5, 1.1) }
    var speed: Double { min(270, 165 + Double(score) * 3.5) }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: ArcadeMini.flap.boardKey)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        birdY = Self.height / 2
        velocity = 0
        pipes = []
        distance = 0
        score = 0
        deathTime = nil
        particles.removeAll()
        phase = .ready
    }

    public func restart() { reset() }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .primary, .up:
            guard !isRepeat else { return true }
            switch phase {
            case .ready:
                phase = .playing
                flap()
            case .playing:
                flap()
            case .paused:
                resume()
            case .over:
                if let d = deathTime, clock - d > 0.5 { reset() }
            }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    private func flap() {
        velocity = -380
        particles.burst(
            at: Vec2(Self.birdX - 6, birdY + 4), count: 4, speed: 30...80, life: 0.2...0.4, size: 1.5...2.5,
            tint: 0, spread: (Double.pi * 0.6)...(Double.pi * 0.9), rng: &rng
        )
        play(.flap)
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.5)
        switch phase {
        case .ready:
            birdY = Self.height / 2 + sin(clock * 3) * 6
            return
        case .over:
            // Let the bird fall to the floor.
            if birdY < Self.height - Self.birdRadius {
                velocity += 1500 * dt
                birdY = min(Self.height - Self.birdRadius, birdY + velocity * dt)
            }
            return
        case .paused:
            return
        case .playing:
            break
        }

        velocity = min(560, velocity + 1450 * dt)
        birdY += velocity * dt
        if birdY < Self.birdRadius {
            birdY = Self.birdRadius
            velocity = 0
        }
        let dx = speed * dt
        distance += dx
        for i in pipes.indices { pipes[i].x -= dx }
        pipes.removeAll { $0.x < -Self.pipeWidth - 10 }

        let spacing = 205.0
        if pipes.isEmpty || (pipes.last.map { Self.width - $0.x >= spacing } ?? true) {
            let gap = max(66, 96 - Double(score) * 1.2)
            let margin = 26 + gap / 2
            let y = rng.double(margin...(Self.height - margin))
            pipes.append(Pipe(x: Self.width + 20, gapY: y, gapHeight: gap))
        }

        for i in pipes.indices where !pipes[i].passed && pipes[i].x + Self.pipeWidth < Self.birdX {
            pipes[i].passed = true
            score += 1
            play(.coin)
        }

        let bird = Vec2(Self.birdX, birdY)
        let r = Self.birdRadius - 1.5
        let hit = pipes.contains { p in
            let top = Box(x: p.x, y: -50, w: Self.pipeWidth, h: p.gapY - p.gapHeight / 2 + 50)
            let bottom = Box(x: p.x, y: p.gapY + p.gapHeight / 2, w: Self.pipeWidth, h: Self.height)
            return top.circleHit(center: bird, radius: r) != nil || bottom.circleHit(center: bird, radius: r) != nil
        }
        if hit || birdY >= Self.height - Self.birdRadius {
            die()
        }
    }

    private func die() {
        phase = .over
        deathTime = clock
        particles.burst(at: Vec2(Self.birdX, birdY), count: 20, speed: 60...200, life: 0.4...0.8, size: 1.5...3.5, tint: 1, gravity: 300, rng: &rng)
        emit(.shake(0.6))
        play(.lose)
        emit(.record(score))
        emit(.count("arcade.played", 1))
        emit(.count("arcade.played.flap", 1))
    }
}

// MARK: - Dodge

/// Dodge the falling stars, grab the gems.
public final class DodgeEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let playerY = 218.0
    public static let playerSize = Vec2(26, 12)

    public struct Rock: Sendable {
        public var position: Vec2
        public var velocity: Vec2
        public var radius: Double
        public var spin: Double
        public var isGem: Bool
    }

    public private(set) var playerX = DodgeEngine.width / 2
    public private(set) var playerVelocity = 0.0
    public private(set) var rocks: [Rock] = []
    public private(set) var survived = 0.0
    public private(set) var gems = 0
    public private(set) var particles = ParticleField()
    public private(set) var deathTime: Double?

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var spawnTimer = 0.0
    private var gemTimer = 3.0

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: ArcadeMini.dodge.boardKey)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        playerX = Self.width / 2
        playerVelocity = 0
        rocks = []
        survived = 0
        gems = 0
        score = 0
        deathTime = nil
        spawnTimer = 0.6
        gemTimer = 3
        particles.removeAll()
        phase = .ready
    }

    public func restart() { reset() }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .left, .right:
            if phase == .ready { phase = .playing }
            if phase == .paused { resume() }
            return true
        case .primary:
            switch phase {
            case .ready: phase = .playing
            case .paused: resume()
            case .over:
                if !isRepeat, let d = deathTime, clock - d > 0.5 { reset() }
            case .playing: break
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
        particles.update(dt, drag: 1.5)
        guard phase == .playing else { return }

        survived += dt
        let axis = input.axis(.left, .right)
        playerVelocity = approach(playerVelocity, axis * 440, 14, dt)
        playerX = clamp(playerX + playerVelocity * dt, 16, Self.width - 16)

        let intensity = min(1, survived / 70)
        spawnTimer -= dt
        if spawnTimer <= 0 {
            spawnTimer = max(0.12, 0.62 - intensity * 0.48) * rng.double(0.7...1.3)
            let r = rng.double(6...(11 + 6 * intensity))
            let vy = rng.double(110...(170 + 210 * intensity))
            let vx = rng.double(-30...30)
            rocks.append(Rock(position: Vec2(rng.double(10...(Self.width - 10)), -r), velocity: Vec2(vx, vy), radius: r, spin: rng.double(0...6), isGem: false))
        }
        gemTimer -= dt
        if gemTimer <= 0 {
            gemTimer = rng.double(3...5.5)
            rocks.append(Rock(position: Vec2(rng.double(30...(Self.width - 30)), -10), velocity: Vec2(0, 95), radius: 7, spin: 0, isGem: true))
        }

        for i in rocks.indices {
            rocks[i].position = rocks[i].position + rocks[i].velocity * dt
            rocks[i].spin += dt * 2
        }
        rocks.removeAll { $0.position.y > Self.height + 20 }

        let body = Box(x: playerX - Self.playerSize.x / 2, y: Self.playerY, w: Self.playerSize.x, h: Self.playerSize.y)
        var caught: [Int] = []
        for (i, rock) in rocks.enumerated() where body.circleHit(center: rock.position, radius: rock.radius * 0.82) != nil {
            if rock.isGem {
                caught.append(i)
            } else {
                die()
                return
            }
        }
        for i in caught.reversed() {
            let gem = rocks.remove(at: i)
            gems += 1
            particles.burst(at: gem.position, count: 12, speed: 40...150, life: 0.3...0.6, size: 1.5...3, tint: 2, rng: &rng)
            play(.bonus)
        }
        score = Int(survived * 10) + gems * 50
    }

    private func die() {
        phase = .over
        deathTime = clock
        particles.burst(at: Vec2(playerX, Self.playerY), count: 24, speed: 60...220, life: 0.4...0.9, size: 1.5...3.5, tint: 1, gravity: 300, rng: &rng)
        emit(.shake(0.7))
        play(.lose)
        emit(.record(score))
        emit(.count("arcade.played", 1))
        emit(.count("arcade.played.dodge", 1))
    }
}

// MARK: - Bullseye

/// Stop the needle inside the zone. The zone shrinks, the needle speeds up.
public final class BullseyeEngine: EngineBase, GameEngine {
    /// Needle position 0…1.
    public private(set) var needle = 0.0
    public private(set) var direction = 1.0
    public private(set) var zoneCenter = 0.5
    public private(set) var zoneWidth = 0.22
    public private(set) var lives = 3
    public private(set) var hits = 0
    public private(set) var streak = 0
    /// Last result for feedback: (perfect?, clock time), or a miss.
    public private(set) var lastHit: (perfect: Bool, at: Double)?
    public private(set) var lastMiss: Double?

    var speed: Double { min(2.4, 0.6 + Double(hits) * 0.07) }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: ArcadeMini.bullseye.boardKey)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        needle = 0
        direction = 1
        zoneWidth = 0.22
        zoneCenter = 0.5
        lives = 3
        hits = 0
        streak = 0
        score = 0
        lastHit = nil
        lastMiss = nil
        phase = .ready
        newZone()
    }

    public func restart() { reset() }

    private func newZone() {
        let half = zoneWidth / 2
        var c = rng.double((0.08 + half)...(0.92 - half))
        // Keep the zone away from the needle so it isn't a free hit.
        if abs(c - needle) < 0.18 { c = needle > 0.5 ? max(0.08 + half, c - 0.35) : min(0.92 - half, c + 0.35) }
        zoneCenter = c
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        guard phase == .playing else { return }
        needle += direction * speed * dt
        if needle >= 1 {
            needle = 1 - (needle - 1)
            direction = -1
        } else if needle <= 0 {
            needle = -needle
            direction = 1
        }
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        guard key == .primary || key == .confirm || key == .restart else { return false }
        if key == .restart {
            reset()
            return true
        }
        guard !isRepeat else { return true }
        switch phase {
        case .ready:
            phase = .playing
        case .paused:
            resume()
        case .over:
            if let miss = lastMiss, clock - miss > 0.5 { reset() }
        case .playing:
            stop()
        }
        return true
    }

    private func stop() {
        let off = abs(needle - zoneCenter)
        if off <= zoneWidth / 2 {
            let perfect = off <= zoneWidth * 0.14
            hits += 1
            streak += 1
            score += 10 + (perfect ? 15 : 0) + min(20, streak * 2)
            lastHit = (perfect, clock)
            play(perfect ? .bonus : .coin)
            zoneWidth = max(0.045, zoneWidth * 0.93)
            newZone()
        } else {
            lives -= 1
            streak = 0
            lastMiss = clock
            emit(.shake(0.4))
            if lives <= 0 {
                phase = .over
                play(.lose)
                emit(.record(score))
                emit(.count("arcade.played", 1))
                emit(.count("arcade.played.bullseye", 1))
            } else {
                play(.error)
            }
        }
    }
}

// MARK: - Echo

/// Watch the pattern, then repeat it with the arrow keys.
public final class EchoEngine: EngineBase, GameEngine {
    public enum Stage: Equatable, Sendable {
        case showing
        case input
        case success
    }

    /// Pads: 0 up, 1 right, 2 down, 3 left.
    public private(set) var sequence: [Int] = []
    public private(set) var stage: Stage = .showing
    public private(set) var inputIndex = 0
    /// Lit pad and when it lit up.
    public private(set) var lit: (pad: Int, at: Double)?
    public private(set) var wrongPad: Int?

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var showIndex = 0
    private var timer = 0.0

    var noteLength: Double { max(0.22, 0.46 - Double(sequence.count) * 0.018) }

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: ArcadeMini.echo.boardKey)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        sequence = [rng.int(0...3)]
        stage = .showing
        inputIndex = 0
        showIndex = 0
        timer = 0.6
        lit = nil
        wrongPad = nil
        score = 0
        phase = .ready
    }

    public func restart() { reset() }

    static func cue(for pad: Int) -> SoundCue {
        [SoundCue.note1, .note2, .note3, .note4][pad % 4]
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        if let l = lit, clock - l.at > noteLength * 0.8 { lit = nil }
        guard phase == .playing else { return }
        switch stage {
        case .showing:
            timer -= dt
            if timer <= 0 {
                if showIndex < sequence.count {
                    let pad = sequence[showIndex]
                    lit = (pad, clock)
                    play(Self.cue(for: pad))
                    showIndex += 1
                    timer = noteLength + 0.12
                } else {
                    stage = .input
                    inputIndex = 0
                }
            }
        case .success:
            timer -= dt
            if timer <= 0 {
                sequence.append(rng.int(0...3))
                showIndex = 0
                stage = .showing
                timer = 0.3
            }
        case .input:
            break
        }
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        let pad: Int?
        switch key {
        case .up: pad = 0
        case .right: pad = 1
        case .down: pad = 2
        case .left: pad = 3
        case .primary, .confirm:
            pad = nil
        case .restart:
            reset()
            return true
        default:
            return false
        }
        guard !isRepeat else { return true }
        switch phase {
        case .ready:
            phase = .playing
            return true
        case .paused:
            resume()
            return true
        case .over:
            if pad == nil { reset() }
            return true
        case .playing:
            break
        }
        guard let pad, stage == .input else { return true }
        lit = (pad, clock)
        if sequence[inputIndex] == pad {
            play(Self.cue(for: pad))
            inputIndex += 1
            if inputIndex == sequence.count {
                score = sequence.count
                stage = .success
                timer = 0.7
                play(.levelUp)
            }
        } else {
            wrongPad = pad
            phase = .over
            emit(.shake(0.5))
            play(.lose)
            emit(.record(score))
            emit(.count("arcade.played", 1))
            emit(.count("arcade.played.echo", 1))
        }
        return true
    }
}

// MARK: - Cabinet

/// The Arcade tile: hosts one rotating mini game at a time.
public final class ArcadeEngine: GameEngine {
    public private(set) var mini: ArcadeMini
    public private(set) var current: GameEngine
    public let featured: ArcadeMini
    private var events: [GameEvent] = []

    public init(featured: ArcadeMini = .featured(on: Date())) {
        self.featured = featured
        self.mini = featured
        self.current = Self.make(featured)
    }

    static func make(_ mini: ArcadeMini) -> GameEngine {
        switch mini {
        case .flap: return FlapEngine()
        case .dodge: return DodgeEngine()
        case .bullseye: return BullseyeEngine()
        case .echo: return EchoEngine()
        case .lander: return LanderEngine()
        case .hop: return HopEngine()
        }
    }

    public var phase: GamePhase { current.phase }
    public var score: Int { current.score }
    public var boardKey: String { current.boardKey }
    public var clock: Double { current.clock }
    public var shake: Double { current.shake }
    public var acceptsText: Bool { current.acceptsText }

    public func switchTo(_ next: ArcadeMini) {
        guard next != mini else { return }
        mini = next
        current = Self.make(next)
        events.append(.sound(.select))
    }

    public func tick(_ dt: Double, input: InputState) { current.tick(dt, input: input) }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        let canSwitch = current.phase == .ready || current.phase == .over
        if canSwitch {
            let all = ArcadeMini.allCases
            switch key {
            case .cycle:
                let i = all.firstIndex(of: mini) ?? 0
                switchTo(all[(i + 1) % all.count])
                return true
            case .number(let n) where n >= 1 && n <= all.count:
                switchTo(all[n - 1])
                return true
            default:
                break
            }
        }
        return current.handle(key, isRepeat: isRepeat)
    }

    public func pause() { current.pause() }
    public func resume() { current.resume() }
    public func restart() { current.restart() }

    public func drainEvents() -> [GameEvent] {
        let mine = events
        events.removeAll()
        return mine + current.drainEvents()
    }
}

// MARK: - Lander

/// Touch down softly on a landing pad. Smaller pads pay more.
public final class LanderEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    static let gravity = 24.0
    static let thrustPower = 58.0

    public struct Pad: Sendable {
        public let x0: Double
        public let x1: Double
        public let y: Double
        public let multiplier: Int
    }

    public private(set) var terrain: [Vec2] = []
    public private(set) var pads: [Pad] = []
    public private(set) var position = Vec2(320, 40)
    public private(set) var velocity = Vec2.zero
    /// Radians, 0 = upright, positive = clockwise.
    public private(set) var angle = 0.0
    public private(set) var fuel = 100.0
    public private(set) var thrusting = false
    public private(set) var landings = 0
    public private(set) var landedAt: Double?
    public private(set) var crashedAt: Double?
    public private(set) var particles = ParticleField()
    public private(set) var stars: [Vec2] = []

    private let fixedSeed: UInt64?
    private var rng: SeededRandom

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: ArcadeMini.lander.boardKey)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        score = 0
        landings = 0
        fuel = 100
        particles.removeAll()
        stars = (0..<50).map { _ in Vec2(rng.double(0...Self.width), rng.double(0...150)) }
        newLevel()
        phase = .ready
    }

    public func restart() { reset() }

    private func newLevel() {
        position = Vec2(rng.double(120...520), 26)
        velocity = Vec2(rng.double(-24...24), 0)
        angle = 0
        landedAt = nil
        crashedAt = nil
        thrusting = false
        buildTerrain()
    }

    private func buildTerrain() {
        let step = 20.0
        let count = Int(Self.width / step) + 1
        var heights = [Double]()
        var h = rng.double(170...210)
        for _ in 0..<count {
            h = clamp(h + rng.double(-26...26), 120, 226)
            heights.append(h)
        }
        // Flatten pads: wide pads ×2, narrow ×5.
        pads = []
        let widths = landings < 3 ? [3, 2] : [2, 1]
        var used = Set<Int>()
        for w in widths {
            var start = 0
            repeat { start = rng.int(1...(count - w - 2)) } while (start...(start + w + 1)).contains(where: used.contains)
            let y = heights[start...(start + w)].max() ?? 200
            for i in start...(start + w) {
                heights[i] = y
                used.insert(i)
            }
            pads.append(Pad(x0: Double(start) * step, x1: Double(start + w) * step, y: y, multiplier: w == 1 ? 5 : (w == 2 ? 3 : 2)))
        }
        terrain = heights.enumerated().map { Vec2(Double($0.offset) * step, $0.element) }
    }

    func groundY(at x: Double) -> Double {
        let step = 20.0
        let i = clamp(Int(x / step), 0, terrain.count - 2)
        let a = terrain[i], b = terrain[i + 1]
        let t = clamp((x - a.x) / step, 0, 1)
        return a.y + (b.y - a.y) * t
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .up, .left, .right, .primary:
            switch phase {
            case .ready: phase = .playing
            case .paused: resume()
            case .over:
                if key == .primary, !isRepeat, let c = crashedAt, clock - c > 0.6 { reset() }
            case .playing: break
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
        particles.update(dt, drag: 1)
        guard phase == .playing else { return }

        if let landed = landedAt {
            if clock - landed > 1.6 {
                fuel = min(100, fuel + 35)
                newLevel()
            }
            return
        }

        angle = clamp(angle + input.axis(.left, .right) * 2.6 * dt, -1.5, 1.5)
        thrusting = (input.isHeld(.up) || input.isHeld(.primary)) && fuel > 0
        velocity.y += Self.gravity * dt
        if thrusting {
            velocity.x += sin(angle) * Self.thrustPower * dt
            velocity.y -= cos(angle) * Self.thrustPower * dt
            fuel = max(0, fuel - 16 * dt)
            let back = Vec2(position.x - sin(angle) * 8, position.y + cos(angle) * 8)
            particles.burst(
                at: back, count: 1, speed: 30...70, life: 0.15...0.35, size: 1...2.2, tint: 0,
                spread: (Double.pi / 2 + angle - 0.3)...(Double.pi / 2 + angle + 0.3), rng: &rng
            )
            play(.thrust)
        }
        position = position + velocity * dt
        if position.x < 8 || position.x > Self.width - 8 {
            position.x = clamp(position.x, 8, Self.width - 8)
            velocity.x = -velocity.x * 0.4
        }
        if position.y < 6 {
            position.y = 6
            velocity.y = max(0, velocity.y)
        }

        // Touchdown: feet are 8 below the centre.
        let feet = position.y + 8
        if feet >= groundY(at: position.x - 6) || feet >= groundY(at: position.x + 6) {
            let pad = pads.first { position.x - 6 >= $0.x0 && position.x + 6 <= $0.x1 }
            let gentle = velocity.y < 26 && abs(velocity.x) < 16 && abs(angle) < 0.22
            if let pad, gentle {
                position.y = pad.y - 8
                landedAt = clock
                landings += 1
                score += 50 * pad.multiplier + Int(fuel)
                velocity = .zero
                angle = 0
                play(.win)
                emit(.maximum("arcade.lander.landings", landings))
            } else {
                crashedAt = clock
                phase = .over
                particles.burst(at: position, count: 30, speed: 40...180, life: 0.5...1.1, size: 1.5...3.5, tint: 1, gravity: 60, rng: &rng)
                emit(.shake(0.8))
                play(.explode)
                emit(.record(score))
                emit(.count("arcade.played", 1))
                emit(.count("arcade.played.lander", 1))
            }
        }
    }
}

// MARK: - Hop

/// Hop across traffic and the river into the five bays.
public final class HopEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let lane = 24.0
    public static let rows = 10
    public static let hopX = 32.0
    public static let bays: [Double] = [64, 192, 320, 448, 576]

    public enum LaneKind: Sendable { case safe, road, river, goal }

    public struct Mover: Sendable {
        public var x: Double
        public let width: Double
        /// Palette index for cars; ignored for logs.
        public let style: Int
    }

    public struct Lane: Sendable {
        public let kind: LaneKind
        public let speed: Double
        public var movers: [Mover]
    }

    public private(set) var lanes: [Lane] = []
    public private(set) var frogX = HopEngine.width / 2
    public private(set) var frogRow = HopEngine.rows - 1
    public private(set) var hopFrom: (x: Double, row: Int, at: Double)?
    public private(set) var filled: [Bool] = Array(repeating: false, count: 5)
    public private(set) var lives = 3
    public private(set) var level = 1
    public private(set) var timeLeft = 30.0
    public private(set) var deathAt: Double?
    public private(set) var particles = ParticleField()

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var bestRow = HopEngine.rows - 1

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: ArcadeMini.hop.boardKey)
        reset()
    }

    public static func kind(of row: Int) -> LaneKind {
        switch row {
        case 0: return .goal
        case 1...3: return .river
        case 5...8: return .road
        default: return .safe
        }
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        score = 0
        lives = 3
        level = 1
        filled = Array(repeating: false, count: 5)
        particles.removeAll()
        buildLanes()
        respawn()
        phase = .ready
    }

    public func restart() { reset() }

    private func buildLanes() {
        let boost = 1 + Double(level - 1) * 0.14
        lanes = (0..<Self.rows).map { row in
            switch Self.kind(of: row) {
            case .road:
                let speeds: [Double] = [-70, 95, -55, 120]
                let speed = speeds[row - 5] * boost
                let width = row == 6 ? 64.0 : 36.0
                let count = row == 6 ? 3 : 4
                let gap = Self.width / Double(count)
                let movers = (0..<count).map { Mover(x: Double($0) * gap + rng.double(0...(gap * 0.4)), width: width, style: rng.int(0...3)) }
                return Lane(kind: .road, speed: speed, movers: movers)
            case .river:
                let speeds: [Double] = [60, -45, 75]
                let speed = speeds[row - 1] * boost
                let width = [130.0, 96.0, 160.0][row - 1]
                let count = 3
                let gap = Self.width / Double(count)
                let movers = (0..<count).map { Mover(x: Double($0) * gap + rng.double(0...(gap * 0.3)), width: width, style: 0) }
                return Lane(kind: .river, speed: speed, movers: movers)
            case .goal:
                return Lane(kind: .goal, speed: 0, movers: [])
            case .safe:
                return Lane(kind: .safe, speed: 0, movers: [])
            }
        }
    }

    private func respawn() {
        frogX = Self.width / 2
        frogRow = Self.rows - 1
        bestRow = Self.rows - 1
        hopFrom = nil
        timeLeft = 30
        deathAt = nil
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if let dir = Direction(key: key) {
            switch phase {
            case .ready: phase = .playing
            case .paused:
                resume()
                return true
            case .over: return true
            case .playing: break
            }
            guard deathAt == nil, !isRepeat else { return true }
            hopFrom = (frogX, frogRow, clock)
            switch dir {
            case .up: frogRow = max(0, frogRow - 1)
            case .down: frogRow = min(Self.rows - 1, frogRow + 1)
            case .left: frogX = max(16, frogX - Self.hopX)
            case .right: frogX = min(Self.width - 16, frogX + Self.hopX)
            }
            play(.flap)
            if frogRow < bestRow {
                bestRow = frogRow
                score += 10
            }
            if frogRow == 0 { reachGoal() }
            return true
        }
        switch key {
        case .primary, .confirm:
            if phase == .ready { phase = .playing }
            if phase == .paused { resume() }
            if phase == .over, let d = deathAt, clock - d > 0.6 { reset() }
            return true
        case .restart:
            reset()
            return true
        default:
            return false
        }
    }

    private func reachGoal() {
        guard let bay = Self.bays.firstIndex(where: { abs($0 - frogX) < 22 }), !filled[bay] else {
            die()
            return
        }
        filled[bay] = true
        score += 50 + Int(timeLeft) * 5
        particles.burst(at: Vec2(Self.bays[bay], Self.lane / 2), count: 20, speed: 40...140, life: 0.4...0.8, size: 1.5...3, tint: 2, rng: &rng)
        play(.bonus)
        if filled.allSatisfy({ $0 }) {
            score += 500
            level += 1
            filled = Array(repeating: false, count: 5)
            emit(.maximum("arcade.hop.level", level))
            play(.levelUp)
            buildLanes()
        }
        respawn()
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.4)
        guard phase == .playing else { return }

        for i in lanes.indices where lanes[i].speed != 0 {
            for j in lanes[i].movers.indices {
                var x = lanes[i].movers[j].x + lanes[i].speed * dt
                let w = lanes[i].movers[j].width
                if lanes[i].speed > 0 && x > Self.width { x -= Self.width + w }
                if lanes[i].speed < 0 && x + w < 0 { x += Self.width + w }
                lanes[i].movers[j].x = x
            }
        }

        if let d = deathAt {
            if clock - d > 0.9 {
                if lives <= 0 {
                    phase = .over
                    emit(.record(score))
                    emit(.count("arcade.played", 1))
                    emit(.count("arcade.played.hop", 1))
                    return
                }
                respawn()
            }
            return
        }

        timeLeft -= dt
        if timeLeft <= 0 {
            die()
            return
        }

        let lane = lanes[frogRow]
        let frog = Box(x: frogX - 9, y: 0, w: 18, h: 1)
        switch lane.kind {
        case .road:
            if lane.movers.contains(where: { Box(x: $0.x, y: 0, w: $0.width, h: 1).intersects(frog) }) { die() }
        case .river:
            if lane.movers.contains(where: { frogX > $0.x + 4 && frogX < $0.x + $0.width - 4 }) {
                frogX += lane.speed * dt
                if frogX < 4 || frogX > Self.width - 4 { die() }
            } else {
                die()
            }
        case .safe, .goal:
            break
        }
    }

    private func die() {
        guard deathAt == nil else { return }
        lives -= 1
        deathAt = clock
        let y = Double(frogRow) * Self.lane + Self.lane / 2
        particles.burst(at: Vec2(frogX, y), count: 22, speed: 40...160, life: 0.4...0.9, size: 1.5...3, tint: 1, rng: &rng)
        emit(.shake(0.5))
        play(lanes[frogRow].kind == .river ? .lose : .explode)
    }
}
