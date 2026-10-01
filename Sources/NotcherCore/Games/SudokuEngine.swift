import Foundation

/// Sudoku with a seeded generator that guarantees a unique solution.
public final class SudokuEngine: EngineBase, GameEngine {
    public enum Difficulty: Int, CaseIterable, Sendable {
        case easy, medium, hard

        public var title: String {
            switch self {
            case .easy: return "Easy"
            case .medium: return "Medium"
            case .hard: return "Hard"
            }
        }

        var clues: Int {
            switch self {
            case .easy: return 38
            case .medium: return 31
            case .hard: return 26
            }
        }
    }

    public enum Unit: Equatable, Sendable {
        case row(Int), column(Int), box(Int)

        public func contains(_ i: Int) -> Bool {
            switch self {
            case .row(let r): return i / 9 == r
            case .column(let c): return i % 9 == c
            case .box(let b): return (i / 27) * 3 + (i % 9) / 3 == b
            }
        }
    }

    public private(set) var puzzle: [Int] = []
    public private(set) var solution: [Int] = []
    public private(set) var entries: [Int] = []
    /// Bit n set means note n (1…9) is shown.
    public private(set) var notes: [UInt16] = []
    public private(set) var cursor = GridPoint(4, 4)
    public private(set) var notesMode = false
    public private(set) var mistakes = 0
    public private(set) var elapsed = 0.0
    public private(set) var difficulty: Difficulty = .medium
    public private(set) var won = false
    public private(set) var lastPlaced: (index: Int, at: Double)?
    public private(set) var lastError: (index: Int, at: Double)?
    public private(set) var completed: [(unit: Unit, at: Double)] = []

    private let fixedSeed: UInt64?
    private var rng: SeededRandom

    public init(seed: UInt64? = nil, difficulty: Difficulty = .medium) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        self.difficulty = difficulty
        super.init(boardKey: GameID.sudoku.rawValue)
        newPuzzle()
    }

    public var cursorIndex: Int { cursor.y * 9 + cursor.x }
    public func isGiven(_ i: Int) -> Bool { puzzle[i] != 0 }
    public func value(_ i: Int) -> Int { puzzle[i] != 0 ? puzzle[i] : entries[i] }
    public func isWrong(_ i: Int) -> Bool { entries[i] != 0 && entries[i] != solution[i] }

    /// How many of digit `n` are correctly on the board.
    public func placed(_ n: Int) -> Int {
        (0..<81).filter { value($0) == n && !isWrong($0) }.count
    }

    private func newPuzzle() {
        rng = SeededRandom(seed: fixedSeed.map { $0 &+ UInt64(difficulty.rawValue) } ?? SeededRandom.randomSeed())
        let generated = Self.generate(clues: difficulty.clues, rng: &rng)
        puzzle = generated.puzzle
        solution = generated.solution
        entries = Array(repeating: 0, count: 81)
        notes = Array(repeating: 0, count: 81)
        cursor = GridPoint(4, 4)
        notesMode = false
        mistakes = 0
        elapsed = 0
        won = false
        lastPlaced = nil
        lastError = nil
        completed = []
        score = 0
        phase = .ready
    }

    public func restart() { newPuzzle() }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        completed.removeAll { clock - $0.at > 1 }
        if phase == .playing {
            elapsed += dt
            score = Int(elapsed * 1000)
        }
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .paused {
            resume()
            return true
        }
        if phase == .over {
            if key == .primary || key == .confirm || key == .restart {
                if !isRepeat { newPuzzle() }
                return true
            }
            return false
        }
        switch key {
        case .up: moveCursor(0, -1)
        case .down: moveCursor(0, 1)
        case .left: moveCursor(-1, 0)
        case .right: moveCursor(1, 0)
        case .number(let n) where n >= 1 && n <= 9:
            if !isRepeat { enter(n) }
        case .number(0), .backspace:
            erase()
        case .flag:
            notesMode.toggle()
            play(.select)
        case .cycle:
            guard phase == .ready else { return true }
            difficulty = Difficulty(rawValue: (difficulty.rawValue + 1) % Difficulty.allCases.count) ?? .medium
            newPuzzle()
            play(.select)
        case .restart:
            newPuzzle()
        case .primary, .confirm:
            if phase == .ready { phase = .playing }
        default:
            return false
        }
        return true
    }

    private func moveCursor(_ dx: Int, _ dy: Int) {
        cursor = GridPoint((cursor.x + dx + 9) % 9, (cursor.y + dy + 9) % 9)
        play(.tick)
    }

    public func select(_ x: Int, _ y: Int) {
        guard (0..<9).contains(x), (0..<9).contains(y) else { return }
        cursor = GridPoint(x, y)
    }

    public func toggleNotes() {
        notesMode.toggle()
    }

    /// Places a digit (or toggles a note) at the cursor.
    public func enter(_ n: Int) {
        guard phase == .ready || phase == .playing else { return }
        let i = cursorIndex
        guard !isGiven(i) else {
            play(.error)
            return
        }
        if phase == .ready { phase = .playing }
        if notesMode {
            guard entries[i] == 0 else { return }
            notes[i] ^= 1 << UInt16(n)
            play(.tick)
            return
        }
        if entries[i] == n { return }
        entries[i] = n
        notes[i] = 0
        if n != solution[i] {
            mistakes += 1
            lastError = (i, clock)
            play(.error)
            emit(.shake(0.15))
            emit(.count("sudoku.mistakes", 1))
            return
        }
        lastPlaced = (i, clock)
        play(.place)
        // Clear this digit from notes in the same row, column and box.
        for p in Self.peers(of: i) { notes[p] &= ~(1 << UInt16(n)) }
        for unit in Self.units(of: i) where (0..<81).filter({ unit.contains($0) }).allSatisfy({ value($0) == solution[$0] }) {
            completed.append((unit, clock))
            play(.harvest)
        }
        if (0..<81).allSatisfy({ value($0) == solution[$0] }) {
            won = true
            phase = .over
            score = Int(elapsed * 1000)
            play(.win)
            emit(.record(score))
            emit(.count("sudoku.wins", 1))
            emit(.minimum("sudoku.\(difficulty.title.lowercased())", score))
            if mistakes == 0 { emit(.count("sudoku.flawless", 1)) }
        }
    }

    public func erase() {
        let i = cursorIndex
        guard !isGiven(i), phase != .over else { return }
        if entries[i] != 0 || notes[i] != 0 { play(.slide) }
        entries[i] = 0
        notes[i] = 0
    }

    // MARK: Units

    static func units(of i: Int) -> [Unit] {
        [.row(i / 9), .column(i % 9), .box((i / 27) * 3 + (i % 9) / 3)]
    }

    static func peers(of i: Int) -> [Int] {
        let units = units(of: i)
        return (0..<81).filter { j in j != i && units.contains { $0.contains(j) } }
    }

    // MARK: Generator & solver

    static func generate(clues: Int, rng: inout SeededRandom) -> (puzzle: [Int], solution: [Int]) {
        var solver = Solver(Array(repeating: 0, count: 81))
        _ = solver.fill(rng: &rng)
        let solution = solver.grid
        var puzzle = solution
        var filled = 81
        var order = Array(0..<81)
        order.shuffle(using: &rng)
        for index in order where filled > clues {
            let backup = puzzle[index]
            puzzle[index] = 0
            if countSolutions(puzzle, limit: 2) == 1 {
                filled -= 1
            } else {
                puzzle[index] = backup
            }
        }
        return (puzzle, solution)
    }

    static func countSolutions(_ grid: [Int], limit: Int) -> Int {
        var solver = Solver(grid)
        return solver.count(limit: limit)
    }

    /// Bitmask backtracking solver (bit n set = digit n used).
    struct Solver {
        var grid: [Int]
        var rows = [UInt16](repeating: 0, count: 9)
        var cols = [UInt16](repeating: 0, count: 9)
        var boxes = [UInt16](repeating: 0, count: 9)

        init(_ grid: [Int]) {
            self.grid = grid
            for i in 0..<81 where grid[i] != 0 { set(i, grid[i]) }
        }

        @inline(__always) static func box(_ i: Int) -> Int { (i / 27) * 3 + (i % 9) / 3 }

        @inline(__always) func free(_ i: Int) -> UInt16 {
            ~(rows[i / 9] | cols[i % 9] | boxes[Self.box(i)]) & 0x3FE
        }

        mutating func set(_ i: Int, _ n: Int) {
            let bit = UInt16(1) << UInt16(n)
            grid[i] = n
            rows[i / 9] |= bit
            cols[i % 9] |= bit
            boxes[Self.box(i)] |= bit
        }

        mutating func clear(_ i: Int) {
            let bit = ~(UInt16(1) << UInt16(grid[i]))
            rows[i / 9] &= bit
            cols[i % 9] &= bit
            boxes[Self.box(i)] &= bit
            grid[i] = 0
        }

        enum Pick {
            case full
            case dead
            case cell(Int, UInt16)
        }

        /// The most constrained empty cell.
        func pick() -> Pick {
            var bestIndex = -1
            var bestMask: UInt16 = 0
            var bestCount = 10
            for i in 0..<81 where grid[i] == 0 {
                let mask = free(i)
                let c = mask.nonzeroBitCount
                if c == 0 { return .dead }
                if c < bestCount {
                    bestIndex = i
                    bestMask = mask
                    bestCount = c
                    if c == 1 { break }
                }
            }
            return bestIndex < 0 ? .full : .cell(bestIndex, bestMask)
        }

        mutating func fill(rng: inout SeededRandom) -> Bool {
            switch pick() {
            case .full: return true
            case .dead: return false
            case .cell(let i, let mask):
                var digits = (1...9).filter { mask & (UInt16(1) << UInt16($0)) != 0 }
                digits.shuffle(using: &rng)
                for n in digits {
                    set(i, n)
                    if fill(rng: &rng) { return true }
                    clear(i)
                }
                return false
            }
        }

        mutating func count(limit: Int) -> Int {
            switch pick() {
            case .full: return 1
            case .dead: return 0
            case .cell(let i, let mask):
                var total = 0
                for n in 1...9 where mask & (UInt16(1) << UInt16(n)) != 0 {
                    set(i, n)
                    total += count(limit: limit - total)
                    clear(i)
                    if total >= limit { break }
                }
                return total
            }
        }
    }

    /// Test hook: fill everything but the cursor cell with the solution.
    func fillAllButCursor() {
        for i in 0..<81 where !isGiven(i) && i != cursorIndex { entries[i] = solution[i] }
        phase = .playing
    }
}
