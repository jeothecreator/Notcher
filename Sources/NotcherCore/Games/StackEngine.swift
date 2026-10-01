import Foundation

/// Falling-block puzzle with SRS rotation and wall kicks, 7-bag, hold,
/// ghost piece, lock delay, combos and back-to-back bonuses.
public final class StackEngine: EngineBase, GameEngine {
    public static let columns = 10
    public static let visibleRows = 20
    public static let hiddenRows = 2
    public static var totalRows: Int { visibleRows + hiddenRows }
    static let lockDelay = 0.5
    static let maxLockResets = 15
    static let clearDuration = 0.28

    public enum Kind: Int, CaseIterable, Sendable {
        case i, o, t, s, z, j, l

        /// Cells of rotation state 0 inside the piece's bounding box (y down).
        var spawnCells: [GridPoint] {
            switch self {
            case .i: return [GridPoint(0, 1), GridPoint(1, 1), GridPoint(2, 1), GridPoint(3, 1)]
            case .o: return [GridPoint(0, 0), GridPoint(1, 0), GridPoint(0, 1), GridPoint(1, 1)]
            case .t: return [GridPoint(1, 0), GridPoint(0, 1), GridPoint(1, 1), GridPoint(2, 1)]
            case .s: return [GridPoint(1, 0), GridPoint(2, 0), GridPoint(0, 1), GridPoint(1, 1)]
            case .z: return [GridPoint(0, 0), GridPoint(1, 0), GridPoint(1, 1), GridPoint(2, 1)]
            case .j: return [GridPoint(0, 0), GridPoint(0, 1), GridPoint(1, 1), GridPoint(2, 1)]
            case .l: return [GridPoint(2, 0), GridPoint(0, 1), GridPoint(1, 1), GridPoint(2, 1)]
            }
        }

        var boxSize: Int {
            switch self {
            case .i: return 4
            case .o: return 2
            default: return 3
            }
        }

        public func cells(rotation: Int) -> [GridPoint] {
            let n = boxSize
            var cells = spawnCells
            guard self != .o else { return cells }
            for _ in 0..<((rotation % 4 + 4) % 4) {
                cells = cells.map { GridPoint(n - 1 - $0.y, $0.x) }
            }
            return cells
        }
    }

    public struct Piece: Equatable, Sendable {
        public var kind: Kind
        public var rotation: Int
        public var x: Int
        public var y: Int

        public var cells: [GridPoint] {
            kind.cells(rotation: rotation).map { GridPoint($0.x + x, $0.y + y) }
        }
    }

    public struct ClearBanner: Sendable {
        public let text: String
        public let at: Double
    }

    /// Row 0 is the top hidden row.
    public private(set) var board: [[Kind?]] = []
    public private(set) var current: Piece?
    public private(set) var held: Kind?
    public private(set) var holdUsed = false
    public private(set) var next: [Kind] = []
    public private(set) var lines = 0
    public private(set) var level = 1
    public private(set) var clearingRows: [Int] = []
    public private(set) var clearProgress = 0.0
    public private(set) var banner: ClearBanner?
    public private(set) var combo = -1
    public private(set) var backToBack = false
    public private(set) var tetrises = 0
    public private(set) var particles = ParticleField()
    /// Clock time of the last lock, for a small landing flash.
    public private(set) var lastLock: (cells: [GridPoint], at: Double)?

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var bag: [Kind] = []
    private var fallTimer = 0.0
    private var lockTimer = 0.0
    private var lockResets = 0
    private var dasDirection = 0
    private var dasTimer = 0.0
    private var arrTimer = 0.0
    private var overAt = 0.0

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.stack.rawValue)
        reset()
    }

    /// Seconds per row at the current level.
    public var gravity: Double {
        max(0.012, pow(0.8 - Double(level) * 0.007, Double(level)))
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        board = Array(repeating: Array(repeating: nil, count: Self.columns), count: Self.totalRows)
        bag = []
        next = []
        refill()
        held = nil
        holdUsed = false
        lines = 0
        level = 1
        score = 0
        combo = -1
        backToBack = false
        tetrises = 0
        clearingRows = []
        banner = nil
        lastLock = nil
        particles.removeAll()
        fallTimer = 0
        lockTimer = 0
        dasDirection = 0
        current = nil
        phase = .ready
        spawn()
    }

    public func restart() { reset() }

    private func refill() {
        while next.count < 5 {
            if bag.isEmpty {
                bag = Kind.allCases
                bag.shuffle(using: &rng)
            }
            next.append(bag.removeLast())
        }
    }

    // MARK: Collision

    func fits(_ piece: Piece) -> Bool {
        for c in piece.cells {
            if c.x < 0 || c.x >= Self.columns || c.y >= Self.totalRows { return false }
            if c.y >= 0 && board[c.y][c.x] != nil { return false }
        }
        return true
    }

    public var ghost: Piece? {
        guard var p = current else { return nil }
        while true {
            var down = p
            down.y += 1
            if !fits(down) { return p }
            p = down
        }
    }

    // MARK: Spawning

    private func spawn(kind forced: Kind? = nil) {
        let kind = forced ?? next.removeFirst()
        refill()
        let x = kind == .o ? 4 : 3
        var piece = Piece(kind: kind, rotation: 0, x: x, y: 0)
        guard fits(piece) else {
            current = piece
            gameOver()
            return
        }
        var down = piece
        down.y += 1
        if fits(down) { piece = down }
        current = piece
        fallTimer = 0
        lockTimer = 0
        lockResets = 0
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .over {
            if key == .primary || key == .confirm, !isRepeat, clock - overAt > 0.5 {
                reset()
                phase = .playing
            }
            return key == .primary || key == .confirm
        }
        if phase == .paused {
            resume()
            return true
        }
        switch key {
        case .left, .right, .up, .down, .primary, .cycle, .confirm:
            if phase == .ready {
                phase = .playing
                if key == .primary || key == .confirm { return true }
            }
        case .restart:
            reset()
            return true
        default:
            return false
        }
        guard clearingRows.isEmpty, current != nil else { return true }
        switch key {
        case .left, .right:
            guard !isRepeat else { return true }
            let dir = key == .left ? -1 : 1
            shift(dir)
            dasDirection = dir
            dasTimer = 0.16
            arrTimer = 0
        case .up:
            if !isRepeat { rotate(1) }
        case .confirm:
            if !isRepeat { rotate(-1) }
        case .primary:
            if !isRepeat { hardDrop() }
        case .cycle:
            if !isRepeat { hold() }
        case .down:
            break
        default:
            return false
        }
        return true
    }

    @discardableResult
    func shift(_ dir: Int) -> Bool {
        guard var p = current else { return false }
        p.x += dir
        guard fits(p) else { return false }
        current = p
        didManipulate()
        play(.tick)
        return true
    }

    @discardableResult
    func rotate(_ dir: Int) -> Bool {
        guard let p = current, p.kind != .o else { return false }
        let from = (p.rotation % 4 + 4) % 4
        let to = ((from + dir) % 4 + 4) % 4
        for kick in Self.kicks(kind: p.kind, from: from, to: to) {
            var candidate = p
            candidate.rotation = to
            candidate.x += kick.x
            candidate.y -= kick.y // tables are y-up
            if fits(candidate) {
                current = candidate
                didManipulate()
                play(.slide)
                return true
            }
        }
        return false
    }

    private func didManipulate() {
        if lockTimer > 0 && lockResets < Self.maxLockResets {
            lockTimer = 0
            lockResets += 1
        }
    }

    func hardDrop() {
        guard let start = current, let target = ghost else { return }
        let distance = target.y - start.y
        score += distance * 2
        current = target
        for c in target.cells where distance > 0 {
            particles.burst(
                at: Vec2(Double(c.x) + 0.5, Double(c.y - Self.hiddenRows)), count: 2, speed: 2...6, life: 0.15...0.35,
                size: 0.05...0.12, tint: target.kind.rawValue, spread: (-Double.pi * 0.9)...(-Double.pi * 0.1), rng: &rng
            )
        }
        emit(.shake(0.12))
        lock()
    }

    func hold() {
        guard !holdUsed, let p = current else { return }
        let previous = held
        held = p.kind
        holdUsed = true
        play(.select)
        if let previous {
            spawn(kind: previous)
        } else {
            spawn()
        }
        holdUsed = true
    }

    // MARK: Tick

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 2)
        if let b = banner, clock - b.at > 1.4 { banner = nil }
        guard phase == .playing else { return }

        if !clearingRows.isEmpty {
            clearProgress += dt / Self.clearDuration
            if clearProgress >= 1 { finishClear() }
            return
        }
        guard var p = current else { return }

        // Auto-shift while a direction is held.
        if dasDirection != 0 {
            let key: GameKey = dasDirection < 0 ? .left : .right
            if input.isHeld(key) {
                dasTimer -= dt
                if dasTimer <= 0 {
                    arrTimer -= dt
                    while arrTimer <= 0 {
                        if !shift(dasDirection) { break }
                        arrTimer += 0.033
                    }
                }
            } else {
                dasDirection = 0
            }
            guard let moved = current else { return }
            p = moved
        }

        let soft = input.isHeld(.down)
        let interval = soft ? min(gravity, 0.03) : gravity
        var down = p
        down.y += 1
        if fits(down) {
            lockTimer = 0
            fallTimer += dt
            while fallTimer >= interval {
                fallTimer -= interval
                var step = p
                step.y += 1
                guard fits(step) else { break }
                p = step
                if soft { score += 1 }
            }
            current = p
        } else {
            fallTimer = 0
            lockTimer += dt
            if lockTimer >= Self.lockDelay { lock() }
        }
    }

    // MARK: Locking & clearing

    private func lock() {
        guard let p = current else { return }
        for c in p.cells where c.y >= 0 {
            board[c.y][c.x] = p.kind
        }
        lastLock = (p.cells, clock)
        current = nil
        holdUsed = false
        play(.land)
        // Lock out: piece came to rest entirely in the hidden rows.
        if p.cells.allSatisfy({ $0.y < Self.hiddenRows }) {
            gameOver()
            return
        }
        let full = (0..<Self.totalRows).filter { row in board[row].allSatisfy { $0 != nil } }
        if full.isEmpty {
            combo = -1
            spawn()
        } else {
            award(full.count)
            clearingRows = full
            clearProgress = 0
            for row in full {
                for x in 0..<Self.columns {
                    particles.burst(
                        at: Vec2(Double(x) + 0.5, Double(row - Self.hiddenRows) + 0.5), count: 2, speed: 3...10,
                        life: 0.3...0.7, size: 0.06...0.16, tint: board[row][x]?.rawValue ?? 0, gravity: 18, rng: &rng
                    )
                }
            }
        }
    }

    private func award(_ count: Int) {
        let base = [0, 100, 300, 500, 800][min(count, 4)]
        var points = base * level
        let tetris = count == 4
        let chained = tetris && backToBack
        if chained { points = points * 3 / 2 }
        backToBack = tetris
        combo += 1
        if combo > 0 { points += 50 * combo * level }
        score += points
        lines += count
        let newLevel = 1 + lines / 10
        if newLevel > level {
            level = newLevel
            play(.levelUp)
            emit(.maximum("stack.level", level))
        } else {
            play(tetris ? .bonus : .brick)
        }
        if tetris {
            tetrises += 1
            emit(.count("stack.tetrises", 1))
            emit(.shake(0.45))
        }
        emit(.count("stack.lines", count))
        let label: String
        switch count {
        case 1: label = "Single"
        case 2: label = "Double"
        case 3: label = "Triple"
        default: label = chained ? "Back-to-back Stack!" : "Stack!"
        }
        banner = ClearBanner(text: combo > 0 ? "\(label) · Combo \(combo)" : label, at: clock)
    }

    private func finishClear() {
        let remaining = board.enumerated().filter { !clearingRows.contains($0.offset) }.map(\.element)
        let empty = Array(repeating: Array(repeating: Kind?.none, count: Self.columns), count: clearingRows.count)
        board = empty + remaining
        clearingRows = []
        clearProgress = 0
        spawn()
    }

    private func gameOver() {
        phase = .over
        overAt = clock
        emit(.shake(0.6))
        play(.lose)
        emit(.record(score))
        emit(.count("stack.games", 1))
    }

    // MARK: Kicks

    static func kicks(kind: Kind, from: Int, to: Int) -> [GridPoint] {
        let jlstz: [String: [(Int, Int)]] = [
            "01": [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
            "10": [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
            "12": [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
            "21": [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
            "23": [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
            "32": [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
            "30": [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
            "03": [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
        ]
        let iKicks: [String: [(Int, Int)]] = [
            "01": [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
            "10": [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
            "12": [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
            "21": [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
            "23": [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
            "32": [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
            "30": [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
            "03": [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
        ]
        let table = kind == .i ? iKicks : jlstz
        return (table["\(from)\(to)"] ?? [(0, 0)]).map { GridPoint($0.0, $0.1) }
    }

    /// Test hook: fill rows from the bottom with a hole at `gap`.
    func loadRows(_ rows: Int, gap: Int) {
        for r in 0..<rows {
            let row = Self.totalRows - 1 - r
            for x in 0..<Self.columns where x != gap {
                board[row][x] = .o
            }
        }
    }

    /// Test hook.
    func setCurrent(_ piece: Piece) {
        current = piece
        phase = .playing
    }
}
