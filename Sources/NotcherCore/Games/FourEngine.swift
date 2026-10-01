import Foundation

/// Four in a row against a negamax AI that thinks deeper every game you win.
public final class FourEngine: EngineBase, GameEngine {
    public static let columns = 7
    public static let rows = 6
    static let dropSpeed = 26.0 // rows per second²

    public enum Turn: Sendable { case player, ai }

    /// A disc on its way down.
    public struct Drop: Sendable {
        public let column: Int
        public let row: Int
        public let owner: Int
        /// Current visual row (fractional), starts above the board.
        public var y: Double
        var speed: Double
    }

    /// 0 empty, 1 player, 2 AI. Row 0 is the top.
    public private(set) var board: [Int] = []
    public private(set) var cursor = 3
    public private(set) var turn: Turn = .player
    public private(set) var drop: Drop?
    public private(set) var level = 1
    public private(set) var wins = 0
    public private(set) var winLine: [Int] = []
    /// Who won the last game: 1 player, 2 AI, 0 draw.
    public private(set) var result: (winner: Int, at: Double)?
    public private(set) var particles = ParticleField()
    public private(set) var thinking = false

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var aiDelay = 0.0
    private var playerStarts = true
    private var overAt = 0.0

    public var depth: Int { min(7, 2 + level) }

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.four.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        level = 1
        wins = 0
        score = 0
        playerStarts = true
        particles.removeAll()
        newBoard()
        phase = .ready
    }

    public func restart() { reset() }

    private func newBoard() {
        board = Array(repeating: 0, count: Self.columns * Self.rows)
        winLine = []
        result = nil
        drop = nil
        cursor = 3
        turn = playerStarts ? .player : .ai
        aiDelay = 0.5
    }

    @inline(__always) func at(_ c: Int, _ r: Int) -> Int { board[r * Self.columns + c] }

    /// Lowest empty row in a column, or nil when full.
    public func landingRow(_ column: Int) -> Int? {
        for r in stride(from: Self.rows - 1, through: 0, by: -1) where at(column, r) == 0 { return r }
        return nil
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .over {
            if (key == .primary || key == .confirm), !isRepeat, clock - overAt > 0.6 {
                reset()
                phase = .playing
            }
            return true
        }
        if phase == .paused {
            resume()
            return true
        }
        switch key {
        case .left:
            cursor = (cursor + Self.columns - 1) % Self.columns
            play(.tick)
        case .right:
            cursor = (cursor + 1) % Self.columns
            play(.tick)
        case .number(let n) where n >= 1 && n <= Self.columns:
            cursor = n - 1
            dropDisc()
        case .primary, .confirm, .down:
            if !isRepeat { dropDisc() }
        case .restart:
            reset()
        default:
            return false
        }
        if phase == .ready { phase = .playing }
        return true
    }

    public func choose(column: Int) {
        guard (0..<Self.columns).contains(column) else { return }
        cursor = column
    }

    public func dropDisc() {
        if phase == .ready { phase = .playing }
        guard phase == .playing, turn == .player, drop == nil, result == nil else { return }
        guard let row = landingRow(cursor) else {
            play(.error)
            return
        }
        drop = Drop(column: cursor, row: row, owner: 1, y: -1, speed: 0)
        play(.drop)
    }

    // MARK: Tick

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.5)
        guard phase == .playing else { return }

        if let r = result {
            if clock - r.at > 1.8 {
                if r.winner == 2 {
                    phase = .over
                    overAt = clock
                    emit(.record(score))
                    emit(.count("four.games", 1))
                    return
                }
                playerStarts.toggle()
                newBoard()
            }
            return
        }

        if var d = drop {
            d.speed += Self.dropSpeed * dt
            d.y += d.speed * dt
            if d.y >= Double(d.row) {
                board[d.row * Self.columns + d.column] = d.owner
                drop = nil
                play(.place)
                particles.burst(
                    at: Vec2(Double(d.column) + 0.5, Double(d.row) + 0.9), count: 6, speed: 1...3, life: 0.2...0.4,
                    size: 0.04...0.08, tint: d.owner, spread: (Double.pi)...(2 * Double.pi), rng: &rng
                )
                afterMove(owner: d.owner)
            } else {
                drop = d
            }
            return
        }

        if turn == .ai {
            aiDelay -= dt
            thinking = true
            if aiDelay <= 0 {
                let column = bestMove()
                thinking = false
                if let row = landingRow(column) {
                    drop = Drop(column: column, row: row, owner: 2, y: -1, speed: 0)
                    play(.drop)
                }
            }
        }
    }

    private func afterMove(owner: Int) {
        if let line = Self.winningLine(board, owner) {
            winLine = line
            result = (owner, clock)
            if owner == 1 {
                wins += 1
                score += 100 * level + emptyCells() * 2
                level += 1
                play(.win)
                emit(.count("four.wins", 1))
                emit(.maximum("four.level", level))
            } else {
                play(.lose)
                emit(.shake(0.4))
            }
            return
        }
        if !board.contains(0) {
            result = (0, clock)
            score += 25
            play(.ready)
            return
        }
        turn = owner == 1 ? .ai : .player
        aiDelay = 0.35
    }

    private func emptyCells() -> Int { board.filter { $0 == 0 }.count }

    // MARK: AI

    static let order = [3, 2, 4, 1, 5, 0, 6]

    private var nodes = 0
    private var aborted = false
    static let nodeBudget = 60_000

    /// Iterative deepening: keep the best move of the deepest finished search.
    func bestMove() -> Int {
        var chosen = Self.order.first { landingRow($0) != nil } ?? 0
        nodes = 0
        aborted = false
        // Early levels make the odd human mistake.
        let noise = level == 1 ? 40 : (level == 2 ? 15 : 0)
        for d in 1...depth {
            var b = board
            var bestScore = Int.min
            var best = chosen
            var alpha = Int.min + 1
            for c in Self.order {
                guard let r = Self.landing(b, c) else { continue }
                b[r * Self.columns + c] = 2
                var value = -negamax(&b, depth: d - 1, alpha: Int.min + 1, beta: -alpha, player: 1)
                b[r * Self.columns + c] = 0
                if aborted { break }
                if noise > 0 && abs(value) < 50_000 { value += rng.int(-noise...noise) }
                if value > bestScore {
                    bestScore = value
                    best = c
                }
                alpha = max(alpha, value)
            }
            if aborted { break }
            chosen = best
            if bestScore >= 50_000 { break } // found a forced win
        }
        return chosen
    }

    private func negamax(_ b: inout [Int], depth: Int, alpha: Int, beta: Int, player: Int) -> Int {
        nodes += 1
        if nodes > Self.nodeBudget {
            aborted = true
            return 0
        }
        let opponent = 3 - player
        if Self.winningLine(b, opponent) != nil { return -100_000 - depth }
        if depth == 0 || !b.contains(0) { return Self.evaluate(b, for: player) }
        var alpha = alpha
        var best = Int.min + 1
        for c in Self.order {
            guard let r = Self.landing(b, c) else { continue }
            b[r * Self.columns + c] = player
            let value = -negamax(&b, depth: depth - 1, alpha: -beta, beta: -alpha, player: opponent)
            b[r * Self.columns + c] = 0
            if aborted { return 0 }
            best = max(best, value)
            alpha = max(alpha, value)
            if alpha >= beta { break }
        }
        return best
    }

    static func landing(_ b: [Int], _ c: Int) -> Int? {
        for r in stride(from: rows - 1, through: 0, by: -1) where b[r * columns + c] == 0 { return r }
        return nil
    }

    /// All 69 lines of four, as board indices.
    static let windows: [[Int]] = {
        var w: [[Int]] = []
        for r in 0..<rows {
            for c in 0..<columns {
                for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                    let cells = (0..<4).map { (c + dc * $0, r + dr * $0) }
                    if cells.allSatisfy({ $0.0 >= 0 && $0.0 < columns && $0.1 >= 0 && $0.1 < rows }) {
                        w.append(cells.map { $0.1 * columns + $0.0 })
                    }
                }
            }
        }
        return w
    }()

    static func winningLine(_ b: [Int], _ player: Int) -> [Int]? {
        windows.first { $0.allSatisfy { b[$0] == player } }
    }

    static func evaluate(_ b: [Int], for player: Int) -> Int {
        let opponent = 3 - player
        var score = 0
        for r in 0..<rows {
            if b[r * columns + 3] == player { score += 3 }
            if b[r * columns + 3] == opponent { score -= 3 }
        }
        for w in windows {
            var mine = 0, theirs = 0, empty = 0
            for i in w {
                switch b[i] {
                case player: mine += 1
                case 0: empty += 1
                default: theirs += 1
                }
            }
            if mine == 3 && empty == 1 { score += 6 }
            else if mine == 2 && empty == 2 { score += 2 }
            if theirs == 3 && empty == 1 { score -= 8 }
            else if theirs == 2 && empty == 2 { score -= 1 }
        }
        return score
    }

    /// Test hook.
    func load(_ cells: [Int], turn: Turn) {
        board = cells
        self.turn = turn
        phase = .playing
    }
}
