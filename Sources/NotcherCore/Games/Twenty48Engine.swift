import Foundation

/// 2048 with stable tile identities so the UI can animate slides and merges.
public final class Twenty48Engine: EngineBase, GameEngine {
    public static let size = 4

    public struct Tile: Identifiable, Equatable, Sendable {
        public let id: Int
        public var value: Int
        public var row: Int
        public var col: Int
        /// Tiles that were merged into another one this move. They slide to the
        /// merge position underneath the new tile and disappear on the next move.
        public var isGhost = false
        /// Created by a merge on the latest move.
        public var isMerged = false
    }

    struct Snapshot {
        var tiles: [Tile]
        var score: Int
    }

    public private(set) var tiles: [Tile] = []
    public private(set) var moves = 0
    public private(set) var bestTile = 0
    /// Set when 2048 is first reached; the player can keep going.
    public private(set) var hasWon = false
    public private(set) var showWinBanner = false
    public private(set) var undosLeft = 3
    /// Grows with every move; handy for UI animation triggers.
    public private(set) var moveCount = 0

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var nextID = 0
    private var history: Snapshot?

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.twenty48.rawValue)
        reset()
    }

    public var liveTiles: [Tile] { tiles.filter { !$0.isGhost } }
    public var canUndo: Bool { history != nil && undosLeft > 0 }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        tiles = []
        score = 0
        moves = 0
        bestTile = 0
        hasWon = false
        showWinBanner = false
        undosLeft = 3
        history = nil
        spawn()
        spawn()
        phase = .ready
    }

    public func restart() { reset() }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if let dir = Direction(key: key) {
            if phase == .paused { resume() }
            guard phase == .ready || phase == .playing else { return phase == .over }
            if showWinBanner { showWinBanner = false }
            if move(dir) {
                phase = .playing
            } else {
                play(.error)
            }
            return true
        }
        switch key {
        case .undo:
            undo()
            return true
        case .restart:
            reset()
            return true
        case .primary, .confirm:
            if showWinBanner {
                showWinBanner = false
                return true
            }
            if phase == .over {
                reset()
                return true
            }
            if phase == .paused { resume() }
            return true
        default:
            return false
        }
    }

    private func grid() -> [[Int?]] {
        var g = Array(repeating: Array(repeating: Int?.none, count: Self.size), count: Self.size)
        for (i, t) in tiles.enumerated() where !t.isGhost {
            g[t.row][t.col] = i
        }
        return g
    }

    /// Returns false when the move changed nothing.
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        let before = Snapshot(tiles: tiles.filter { !$0.isGhost }.map { var t = $0; t.isMerged = false; return t }, score: score)
        // Drop the ghosts from the previous move.
        tiles = before.tiles

        var moved = false
        var gained = 0
        let n = Self.size
        let g = grid()

        for line in 0..<n {
            // Cells ordered from the edge the tiles slide toward.
            let cells: [(Int, Int)] = (0..<n).map { i in
                switch direction {
                case .left: return (line, i)
                case .right: return (line, n - 1 - i)
                case .up: return (i, line)
                case .down: return (n - 1 - i, line)
                }
            }
            let indices = cells.compactMap { g[$0.0][$0.1] }
            var target = 0
            var lastIndex: Int? = nil // tile index that may still merge at target - 1
            for idx in indices {
                if let last = lastIndex, tiles[last].value == tiles[idx].value {
                    let (r, c) = cells[target - 1]
                    let value = tiles[idx].value * 2
                    // Both sources slide to the merge cell as ghosts…
                    tiles[last].isGhost = true
                    tiles[idx].isGhost = true
                    if tiles[idx].row != r || tiles[idx].col != c { moved = true }
                    tiles[idx].row = r
                    tiles[idx].col = c
                    // …and a fresh tile pops in on top.
                    tiles.append(Tile(id: nextID, value: value, row: r, col: c, isGhost: false, isMerged: true))
                    nextID += 1
                    gained += value
                    bestTile = max(bestTile, value)
                    lastIndex = nil
                    moved = true
                } else {
                    let (r, c) = cells[target]
                    if tiles[idx].row != r || tiles[idx].col != c { moved = true }
                    tiles[idx].row = r
                    tiles[idx].col = c
                    lastIndex = idx
                    target += 1
                }
            }
        }

        guard moved else {
            tiles = before.tiles
            return false
        }

        history = before
        moves += 1
        moveCount += 1
        score += gained
        play(gained > 0 ? .merge : .slide)
        if gained > 0 {
            emit(.maximum("2048.tile", bestTile))
        }
        if bestTile >= 2048 && !hasWon {
            hasWon = true
            showWinBanner = true
            play(.win)
            emit(.count("2048.wins", 1))
        }
        spawn()
        if !canMove() {
            phase = .over
            play(.lose)
            emit(.record(score))
            emit(.count("2048.games", 1))
        }
        return true
    }

    private func undo() {
        guard let snap = history, undosLeft > 0 else {
            play(.error)
            return
        }
        tiles = snap.tiles
        score = snap.score
        history = nil
        undosLeft -= 1
        moveCount += 1
        if phase == .over { phase = .playing }
        play(.slide)
    }

    private func spawn() {
        let live = tiles.filter { !$0.isGhost }
        var free: [(Int, Int)] = []
        for r in 0..<Self.size {
            for c in 0..<Self.size where !live.contains(where: { $0.row == r && $0.col == c }) {
                free.append((r, c))
            }
        }
        guard !free.isEmpty else { return }
        let (r, c) = free[rng.int(0...(free.count - 1))]
        let value = rng.chance(0.9) ? 2 : 4
        tiles.append(Tile(id: nextID, value: value, row: r, col: c))
        nextID += 1
        bestTile = max(bestTile, value)
    }

    func canMove() -> Bool {
        let live = tiles.filter { !$0.isGhost }
        if live.count < Self.size * Self.size { return true }
        var g = Array(repeating: Array(repeating: 0, count: Self.size), count: Self.size)
        for t in live { g[t.row][t.col] = t.value }
        for r in 0..<Self.size {
            for c in 0..<Self.size {
                if c + 1 < Self.size && g[r][c] == g[r][c + 1] { return true }
                if r + 1 < Self.size && g[r][c] == g[r + 1][c] { return true }
            }
        }
        return false
    }

    /// Test hook: replace the board with explicit values (0 = empty).
    func load(_ values: [[Int]]) {
        tiles = []
        for (r, row) in values.enumerated() {
            for (c, v) in row.enumerated() where v > 0 {
                tiles.append(Tile(id: nextID, value: v, row: r, col: c))
                nextID += 1
            }
        }
        phase = .playing
    }

    /// Test hook: board values (0 = empty).
    func values() -> [[Int]] {
        var g = Array(repeating: Array(repeating: 0, count: Self.size), count: Self.size)
        for t in tiles where !t.isGhost { g[t.row][t.col] = t.value }
        return g
    }
}
