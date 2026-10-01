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
        }
    }

    public var phase: GamePhase { current.phase }
    public var score: Int { current.score }
    public var boardKey: String { current.boardKey }
    public var clock: Double { current.clock }
    public var shake: Double { current.shake }

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
