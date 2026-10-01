import Foundation

/// Marching invaders with destructible bunkers, a mystery saucer and waves.
public final class InvadersEngine: EngineBase, GameEngine {
    public static let width = 640.0
    public static let height = 240.0
    public static let rows = 5
    public static let columns = 11
    public static let alienSize = Vec2(22, 14)
    public static let spacing = Vec2(34, 19)
    public static let playerY = 218.0
    public static let playerSize = Vec2(26, 12)
    public static let bunkerColumns = 11
    public static let bunkerRows = 7
    public static let bunkerCell = 4.0
    public static let bunkerY = 172.0

    public struct Alien: Sendable {
        public let row: Int
        public let col: Int
        public var alive = true
        /// Points by row: top row is worth the most.
        public var points: Int { row == 0 ? 30 : (row < 3 ? 20 : 10) }
    }

    public struct Shot: Sendable {
        public var position: Vec2
        public var velocity: Double
        public var phase: Double
    }

    public struct Bunker: Sendable {
        public let x: Double
        public var cells: [Bool]

        public func isSolid(_ c: Int, _ r: Int) -> Bool { cells[r * InvadersEngine.bunkerColumns + c] }
    }

    public struct Saucer: Sendable {
        public var x: Double
        public var direction: Double
        public let points: Int
    }

    public struct Popup: Sendable {
        public let text: String
        public let position: Vec2
        public var age: Double
    }

    public private(set) var aliens: [Alien] = []
    public private(set) var formation = Vec2(0, 0)
    public private(set) var direction = 1.0
    /// Alternates on every march step; drives the two-frame animation.
    public private(set) var frame = 0
    public private(set) var playerX = InvadersEngine.width / 2
    public private(set) var playerShots: [Shot] = []
    public private(set) var alienShots: [Shot] = []
    public private(set) var bunkers: [Bunker] = []
    public private(set) var saucer: Saucer?
    public private(set) var popups: [Popup] = []
    public private(set) var lives = 3
    public private(set) var wave = 1
    public private(set) var particles = ParticleField()
    /// Seconds left before the player respawns after being hit.
    public private(set) var respawn = 0.0
    public private(set) var invulnerable = 0.0
    public private(set) var waveBanner: Double?

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var marchTimer = 0.0
    private var fireTimer = 1.5
    private var saucerTimer = 16.0
    private var cooldown = 0.0
    private var playerVelocity = 0.0
    private var overAt = 0.0

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.invaders.rawValue)
        reset()
    }

    public var aliveCount: Int { aliens.filter(\.alive).count }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        score = 0
        lives = 3
        wave = 1
        playerX = Self.width / 2
        playerVelocity = 0
        particles.removeAll()
        popups = []
        respawn = 0
        invulnerable = 0
        buildBunkers()
        startWave()
        phase = .ready
    }

    public func restart() { reset() }

    private func startWave() {
        aliens = []
        for r in 0..<Self.rows {
            for c in 0..<Self.columns {
                aliens.append(Alien(row: r, col: c))
            }
        }
        let formationWidth = Double(Self.columns - 1) * Self.spacing.x + Self.alienSize.x
        formation = Vec2((Self.width - formationWidth) / 2, 26 + Double(min(wave - 1, 4)) * 6)
        direction = 1
        frame = 0
        marchTimer = 0
        fireTimer = 1.5
        saucerTimer = rng.double(14...22)
        playerShots = []
        alienShots = []
        saucer = nil
        waveBanner = clock
    }

    private func buildBunkers() {
        let pattern: [String] = [
            "..#######..",
            ".#########.",
            "###########",
            "###########",
            "###########",
            "###.....###",
            "##.......##",
        ]
        let cells = pattern.flatMap { $0.map { $0 == "#" } }
        bunkers = [110.0, 250.0, 390.0, 530.0].map { Bunker(x: $0 - Double(Self.bunkerColumns) * Self.bunkerCell / 2, cells: cells) }
    }

    public func alienBox(_ a: Alien) -> Box {
        Box(
            x: formation.x + Double(a.col) * Self.spacing.x,
            y: formation.y + Double(a.row) * Self.spacing.y,
            w: Self.alienSize.x, h: Self.alienSize.y
        )
    }

    var marchInterval: Double {
        let fraction = Double(aliveCount) / Double(Self.rows * Self.columns)
        return max(0.045, (0.06 + 0.6 * fraction) * pow(0.88, Double(wave - 1)))
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        switch key {
        case .primary, .up:
            switch phase {
            case .ready:
                phase = .playing
            case .paused:
                resume()
            case .over:
                if !isRepeat && clock - overAt > 0.5 {
                    reset()
                    phase = .playing
                }
            case .playing:
                fire()
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

    private func fire() {
        guard respawn <= 0, cooldown <= 0, playerShots.count < 2 else { return }
        playerShots.append(Shot(position: Vec2(playerX, Self.playerY - 4), velocity: -520, phase: 0))
        cooldown = 0.28
        play(.laser)
    }

    // MARK: Tick

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.5)
        for i in popups.indices { popups[i].age += dt }
        popups.removeAll { $0.age > 0.9 }
        if let b = waveBanner, clock - b > 1.6 { waveBanner = nil }
        guard phase == .playing else { return }

        cooldown -= dt
        invulnerable = max(0, invulnerable - dt)

        // Player
        if respawn > 0 {
            respawn -= dt
            if respawn <= 0 {
                if lives <= 0 {
                    gameOver()
                    return
                }
                invulnerable = 1.4
                playerX = Self.width / 2
            }
        } else {
            let axis = input.axis(.left, .right)
            playerVelocity = approach(playerVelocity, axis * 300, 18, dt)
            playerX = clamp(playerX + playerVelocity * dt, 20, Self.width - 20)
            if input.isHeld(.primary) || input.isHeld(.up) { fire() }
        }

        march(dt)
        updateShots(dt)
        updateSaucer(dt)
        alienFire(dt)

        if aliveCount == 0 {
            score += 250 * wave
            emit(.maximum("invaders.wave", wave + 1))
            wave += 1
            play(.levelUp)
            startWave()
        }
    }

    private func march(_ dt: Double) {
        marchTimer += dt
        guard marchTimer >= marchInterval else { return }
        marchTimer = 0
        frame ^= 1
        let alive = aliens.filter(\.alive)
        guard !alive.isEmpty else { return }
        let boxes = alive.map(alienBox)
        let minX = boxes.map(\.minX).min() ?? 0
        let maxX = boxes.map(\.maxX).max() ?? 0
        let step = 7.0
        if (direction > 0 && maxX + step > Self.width - 10) || (direction < 0 && minX - step < 10) {
            formation.y += 10
            direction = -direction
        } else {
            formation.x += step * direction
        }
        play(.march)

        // Aliens chew through bunkers and win if they reach the player.
        for box in alive.map(alienBox) {
            erodeBunkers(in: box)
            if box.maxY >= Self.playerY - 4 {
                lives = 0
                explodePlayer()
                return
            }
        }
    }

    private func updateShots(_ dt: Double) {
        for i in playerShots.indices {
            playerShots[i].position.y += playerShots[i].velocity * dt
        }
        for i in alienShots.indices {
            alienShots[i].position.y += alienShots[i].velocity * dt
            alienShots[i].phase += dt * 14
        }

        // Player shots vs aliens, saucer, bunkers and enemy shots.
        var spent: Set<Int> = []
        for (si, shot) in playerShots.enumerated() {
            let box = Box(x: shot.position.x - 1.5, y: shot.position.y - 5, w: 3, h: 10)
            if let index = aliens.indices.first(where: { aliens[$0].alive && alienBox(aliens[$0]).intersects(box) }) {
                killAlien(index)
                spent.insert(si)
                continue
            }
            if let s = saucer, Box(x: s.x - 16, y: 8, w: 32, h: 12).intersects(box) {
                score += s.points
                popups.append(Popup(text: "\(s.points)", position: Vec2(s.x, 16), age: 0))
                particles.burst(at: Vec2(s.x, 14), count: 26, speed: 40...200, life: 0.4...0.9, size: 1.5...3.5, tint: 5, rng: &rng)
                saucer = nil
                play(.bonus)
                emit(.count("invaders.saucers", 1))
                spent.insert(si)
                continue
            }
            if hitBunker(at: shot.position, radius: 1) {
                spent.insert(si)
                continue
            }
            if let enemy = alienShots.firstIndex(where: { abs($0.position.x - shot.position.x) < 4 && abs($0.position.y - shot.position.y) < 8 }) {
                particles.burst(at: shot.position, count: 6, speed: 30...90, life: 0.2...0.4, size: 1...2, tint: 6, rng: &rng)
                alienShots.remove(at: enemy)
                spent.insert(si)
                continue
            }
            if shot.position.y < -10 { spent.insert(si) }
        }
        playerShots = playerShots.enumerated().filter { !spent.contains($0.offset) }.map(\.element)

        // Enemy shots vs bunkers and the player.
        var gone: Set<Int> = []
        let player = Box(x: playerX - Self.playerSize.x / 2, y: Self.playerY - Self.playerSize.y / 2, w: Self.playerSize.x, h: Self.playerSize.y)
        for (i, shot) in alienShots.enumerated() {
            if hitBunker(at: shot.position, radius: 1) {
                gone.insert(i)
                continue
            }
            if respawn <= 0, invulnerable <= 0, player.contains(shot.position) {
                gone.insert(i)
                lives -= 1
                explodePlayer()
                continue
            }
            if shot.position.y > Self.height + 10 { gone.insert(i) }
        }
        alienShots = alienShots.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
    }

    private func killAlien(_ index: Int) {
        aliens[index].alive = false
        let a = aliens[index]
        let box = alienBox(a)
        score += a.points * (1 + (wave - 1) / 3)
        particles.burst(at: Vec2(box.midX, box.midY), count: 14, speed: 40...170, life: 0.3...0.6, size: 1.5...3, tint: a.row, rng: &rng)
        play(.brick)
        emit(.count("invaders.kills", 1))
    }

    private func explodePlayer() {
        particles.burst(at: Vec2(playerX, Self.playerY), count: 30, speed: 40...220, life: 0.5...1.1, size: 1.5...3.5, tint: 7, gravity: 120, rng: &rng)
        emit(.shake(0.7))
        play(.explode)
        respawn = 1.2
        alienShots = []
        playerShots = []
    }

    private func updateSaucer(_ dt: Double) {
        if var s = saucer {
            s.x += s.direction * 95 * dt
            saucer = (s.x < -30 || s.x > Self.width + 30) ? nil : s
            return
        }
        saucerTimer -= dt
        if saucerTimer <= 0 {
            saucerTimer = rng.double(16...26)
            let fromLeft = rng.chance(0.5)
            let points = [50, 100, 150, 300][rng.int(0...3)]
            saucer = Saucer(x: fromLeft ? -20 : Self.width + 20, direction: fromLeft ? 1 : -1, points: points)
            play(.powerUp)
        }
    }

    private func alienFire(_ dt: Double) {
        fireTimer -= dt
        guard fireTimer <= 0, respawn <= 0 else { return }
        let fraction = Double(aliveCount) / Double(Self.rows * Self.columns)
        fireTimer = rng.double(0.5...1.2) * (0.45 + 0.55 * fraction) * pow(0.9, Double(wave - 1))
        guard alienShots.count < 2 + min(wave, 3) else { return }
        // Bottom alien of a random column; prefer columns near the player.
        var columns = Set(aliens.filter(\.alive).map(\.col)).sorted()
        guard !columns.isEmpty else { return }
        if rng.chance(0.45) {
            columns.sort { abs(columnX($0) - playerX) < abs(columnX($1) - playerX) }
            columns = Array(columns.prefix(2))
        }
        let col = columns[rng.int(0...(columns.count - 1))]
        guard let shooter = aliens.filter({ $0.alive && $0.col == col }).max(by: { $0.row < $1.row }) else { return }
        let box = alienBox(shooter)
        alienShots.append(Shot(position: Vec2(box.midX, box.maxY + 4), velocity: 150 + Double(wave) * 14, phase: rng.double(0...6)))
    }

    private func columnX(_ col: Int) -> Double {
        formation.x + Double(col) * Self.spacing.x + Self.alienSize.x / 2
    }

    // MARK: Bunkers

    private func hitBunker(at p: Vec2, radius: Int) -> Bool {
        let cell = Self.bunkerCell
        for b in bunkers.indices {
            let bx = bunkers[b].x
            let c = Int(floor((p.x - bx) / cell))
            let r = Int(floor((p.y - Self.bunkerY) / cell))
            guard c >= 0, c < Self.bunkerColumns, r >= 0, r < Self.bunkerRows else { continue }
            guard bunkers[b].isSolid(c, r) else { continue }
            for dr in -radius...radius {
                for dc in -radius...radius {
                    let cc = c + dc, rr = r + dr
                    guard cc >= 0, cc < Self.bunkerColumns, rr >= 0, rr < Self.bunkerRows else { continue }
                    if (dc == 0 && dr == 0) || rng.chance(0.45) {
                        bunkers[b].cells[rr * Self.bunkerColumns + cc] = false
                    }
                }
            }
            particles.burst(at: p, count: 5, speed: 20...80, life: 0.2...0.4, size: 1...2, tint: 6, rng: &rng)
            play(.wall)
            return true
        }
        return false
    }

    private func erodeBunkers(in box: Box) {
        let cell = Self.bunkerCell
        for b in bunkers.indices {
            for r in 0..<Self.bunkerRows {
                for c in 0..<Self.bunkerColumns where bunkers[b].isSolid(c, r) {
                    let cellBox = Box(x: bunkers[b].x + Double(c) * cell, y: Self.bunkerY + Double(r) * cell, w: cell, h: cell)
                    if cellBox.intersects(box) { bunkers[b].cells[r * Self.bunkerColumns + c] = false }
                }
            }
        }
    }

    private func gameOver() {
        phase = .over
        overAt = clock
        play(.lose)
        emit(.record(score))
        emit(.count("invaders.games", 1))
    }

    /// Test hook: kill every alien except one.
    func leaveOneAlien() {
        for i in aliens.indices { aliens[i].alive = i == 0 }
    }
}
