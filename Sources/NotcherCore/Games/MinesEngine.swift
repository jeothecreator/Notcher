import Foundation

/// Keyboard-first Minesweeper. The first reveal is always safe.
public final class MinesEngine: EngineBase, GameEngine {
    public static let columns = 20
    public static let rows = 8
    public static let mineCount = 24

    public enum CellState: Sendable { case hidden, revealed, flagged }

    public struct Cell: Sendable {
        public var isMine = false
        public var adjacent = 0
        public var state: CellState = .hidden
        /// Seconds (engine clock) when the cell was revealed; for cascade animation.
        public var revealedAt = 0.0
    }

    public private(set) var cells: [Cell] = Array(repeating: Cell(), count: MinesEngine.columns * MinesEngine.rows)
    public private(set) var cursor = GridPoint(MinesEngine.columns / 2, MinesEngine.rows / 2)
    public private(set) var elapsed = 0.0
    public private(set) var won = false
    public private(set) var exploded: GridPoint?
    public private(set) var minesPlaced = false

    public var flagsPlaced: Int { cells.filter { $0.state == .flagged }.count }
    public var minesLeft: Int { Self.mineCount - flagsPlaced }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom

    public init(seed: UInt64? = nil) {
        self.fixedSeed = seed
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.mines.rawValue)
        reset()
    }

    public func cell(_ x: Int, _ y: Int) -> Cell { cells[y * Self.columns + x] }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        cells = Array(repeating: Cell(), count: Self.columns * Self.rows)
        cursor = GridPoint(Self.columns / 2, Self.rows / 2)
        elapsed = 0
        won = false
        exploded = nil
        minesPlaced = false
        score = 0
        phase = .ready
    }

    public func restart() { reset() }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        if phase == .playing { elapsed += dt }
        score = Int(elapsed * 1000)
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .paused {
            resume()
            return true
        }
        switch key {
        case .up: moveCursor(0, -1)
        case .down: moveCursor(0, 1)
        case .left: moveCursor(-1, 0)
        case .right: moveCursor(1, 0)
        case .primary, .confirm:
            if phase == .over {
                if !isRepeat { reset() }
                return true
            }
            if !isRepeat { reveal(cursor.x, cursor.y) }
        case .flag:
            if !isRepeat { toggleFlag(cursor.x, cursor.y) }
        case .restart:
            reset()
        default:
            return false
        }
        return true
    }

    private func moveCursor(_ dx: Int, _ dy: Int) {
        cursor = GridPoint(
            (cursor.x + dx + Self.columns) % Self.columns,
            (cursor.y + dy + Self.rows) % Self.rows
        )
        play(.tick)
    }

    public func setCursor(_ x: Int, _ y: Int) {
        guard (0..<Self.columns).contains(x), (0..<Self.rows).contains(y) else { return }
        cursor = GridPoint(x, y)
    }

    private func neighbors(_ x: Int, _ y: Int) -> [GridPoint] {
        var out: [GridPoint] = []
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < Self.columns && ny >= 0 && ny < Self.rows {
                    out.append(GridPoint(nx, ny))
                }
            }
        }
        return out
    }

    private func index(_ p: GridPoint) -> Int { p.y * Self.columns + p.x }

    private func placeMines(avoiding safe: GridPoint) {
        var forbidden = Set(neighbors(safe.x, safe.y))
        forbidden.insert(safe)
        var candidates: [GridPoint] = []
        for y in 0..<Self.rows {
            for x in 0..<Self.columns where !forbidden.contains(GridPoint(x, y)) {
                candidates.append(GridPoint(x, y))
            }
        }
        candidates.shuffle(using: &rng)
        for p in candidates.prefix(Self.mineCount) {
            cells[index(p)].isMine = true
        }
        for y in 0..<Self.rows {
            for x in 0..<Self.columns {
                cells[y * Self.columns + x].adjacent = neighbors(x, y).filter { cells[index($0)].isMine }.count
            }
        }
        minesPlaced = true
    }

    /// Reveal a cell (or chord on an already revealed number).
    public func reveal(_ x: Int, _ y: Int) {
        guard phase == .ready || phase == .playing else { return }
        cursor = GridPoint(x, y)
        if !minesPlaced {
            placeMines(avoiding: GridPoint(x, y))
            phase = .playing
        }
        let i = y * Self.columns + x
        switch cells[i].state {
        case .flagged:
            play(.error)
            return
        case .revealed:
            chord(x, y)
            return
        case .hidden:
            break
        }
        if cells[i].isMine {
            explode(at: GridPoint(x, y))
            return
        }
        let count = flood(from: GridPoint(x, y))
        emit(.count("mines.revealed", count))
        play(count > 1 ? .reveal : .tick)
        checkWin()
    }

    private func chord(_ x: Int, _ y: Int) {
        let cell = cells[y * Self.columns + x]
        guard cell.adjacent > 0 else { return }
        let around = neighbors(x, y)
        let flags = around.filter { cells[index($0)].state == .flagged }.count
        guard flags == cell.adjacent else {
            play(.error)
            return
        }
        var revealed = 0
        for p in around where cells[index(p)].state == .hidden {
            if cells[index(p)].isMine {
                explode(at: p)
                return
            }
            revealed += flood(from: p)
        }
        if revealed > 0 {
            emit(.count("mines.revealed", revealed))
            play(.reveal)
        }
        checkWin()
    }

    /// Breadth-first reveal; returns how many cells were opened.
    private func flood(from start: GridPoint) -> Int {
        var queue = [start]
        var head = 0
        var opened = 0
        while head < queue.count {
            let p = queue[head]
            head += 1
            let i = index(p)
            guard cells[i].state == .hidden, !cells[i].isMine else { continue }
            cells[i].state = .revealed
            // Cascade outward from the start for a ripple effect.
            let distance = Double(max(abs(p.x - start.x), abs(p.y - start.y)))
            cells[i].revealedAt = clock + distance * 0.025
            opened += 1
            if cells[i].adjacent == 0 {
                for n in neighbors(p.x, p.y) where cells[index(n)].state == .hidden {
                    queue.append(n)
                }
            }
        }
        return opened
    }

    public func toggleFlag(_ x: Int, _ y: Int) {
        guard phase == .ready || phase == .playing else { return }
        cursor = GridPoint(x, y)
        let i = y * Self.columns + x
        switch cells[i].state {
        case .hidden:
            cells[i].state = .flagged
            play(.flag)
        case .flagged:
            cells[i].state = .hidden
            play(.tick)
        case .revealed:
            chord(x, y)
        }
    }

    private func explode(at p: GridPoint) {
        exploded = p
        won = false
        phase = .over
        for i in cells.indices where cells[i].isMine {
            let x = i % Self.columns, y = i / Self.columns
            let d = Double(max(abs(x - p.x), abs(y - p.y)))
            cells[i].revealedAt = clock + d * 0.04
            if cells[i].state != .flagged { cells[i].state = .revealed }
        }
        emit(.shake(0.9))
        play(.explode)
        emit(.count("mines.losses", 1))
    }

    private func checkWin() {
        let hiddenSafe = cells.contains { !$0.isMine && $0.state != .revealed }
        guard !hiddenSafe else { return }
        won = true
        phase = .over
        for i in cells.indices where cells[i].isMine { cells[i].state = .flagged }
        score = Int(elapsed * 1000)
        play(.win)
        emit(.record(score))
        emit(.count("mines.wins", 1))
        emit(.minimum("mines.time", score))
    }

    /// Test hook: place mines at explicit points.
    func loadMines(_ mines: [GridPoint]) {
        cells = Array(repeating: Cell(), count: Self.columns * Self.rows)
        for p in mines { cells[index(p)].isMine = true }
        for y in 0..<Self.rows {
            for x in 0..<Self.columns {
                cells[y * Self.columns + x].adjacent = neighbors(x, y).filter { cells[index($0)].isMine }.count
            }
        }
        minesPlaced = true
        phase = .playing
    }
}
