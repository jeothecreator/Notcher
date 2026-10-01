import Foundation

/// Match-3 with animated swaps, cascades and special gems. 30 moves a game.
public final class GemsEngine: EngineBase, GameEngine {
    public static let size = 8
    public static let kinds = 6
    public static let starKind = 6
    public static let movesPerGame = 30
    static let swapDuration = 0.15
    static let clearDuration = 0.24

    public enum Special: Sendable { case none, row, column, bomb, star }

    public struct Gem: Identifiable, Sendable {
        public let id: Int
        public var kind: Int
        public var special: Special
        /// Visual offset from the gem's cell, in cells. Animates to zero.
        public var offset: Vec2
        var start: Vec2 = .zero
        var fallSpeed = 0.0
    }

    enum Stage {
        case idle
        case swapping(a: Int, b: Int, progress: Double, revert: Bool)
        case clearing(progress: Double)
        case falling
    }

    public struct Popup: Sendable {
        public let text: String
        public let position: Vec2
        public var age: Double
    }

    public private(set) var grid: [Gem?] = []
    public private(set) var cursor = GridPoint(3, 3)
    public private(set) var selected: GridPoint?
    public private(set) var movesLeft = GemsEngine.movesPerGame
    public private(set) var cascade = 0
    /// Gems being cleared right now (by id).
    public private(set) var clearing: Set<Int> = []
    public private(set) var clearProgress = 0.0
    public private(set) var popups: [Popup] = []
    public private(set) var particles = ParticleField()
    /// A suggested move after a few idle seconds.
    public private(set) var hint: (GridPoint, GridPoint)?
    /// Line or bomb effects to draw: (kind, cell, clock).
    public private(set) var blasts: [(special: Special, cell: GridPoint, at: Double)] = []

    var stage: Stage = .idle
    public var isBusy: Bool {
        if case .idle = stage { return false }
        return true
    }

    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var nextID = 0
    private var idleTime = 0.0
    private var lastSwap: (Int, Int)?
    private var overAt = 0.0

    public init(seed: UInt64? = nil) {
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.gems.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        score = 0
        movesLeft = Self.movesPerGame
        cascade = 0
        clearing = []
        popups = []
        blasts = []
        selected = nil
        hint = nil
        cursor = GridPoint(3, 3)
        particles.removeAll()
        stage = .idle
        fillBoard()
        phase = .ready
    }

    public func restart() { reset() }

    @inline(__always) func index(_ x: Int, _ y: Int) -> Int { y * Self.size + x }

    public func gem(_ x: Int, _ y: Int) -> Gem? { grid[index(x, y)] }

    private func newGem(kind: Int? = nil) -> Gem {
        defer { nextID += 1 }
        return Gem(id: nextID, kind: kind ?? rng.int(0...(Self.kinds - 1)), special: .none, offset: .zero)
    }

    private func fillBoard() {
        repeat {
            grid = Array(repeating: nil, count: Self.size * Self.size)
            for y in 0..<Self.size {
                for x in 0..<Self.size {
                    var gem = newGem()
                    while (x >= 2 && grid[index(x - 1, y)]?.kind == gem.kind && grid[index(x - 2, y)]?.kind == gem.kind)
                        || (y >= 2 && grid[index(x, y - 1)]?.kind == gem.kind && grid[index(x, y - 2)]?.kind == gem.kind) {
                        gem.kind = rng.int(0...(Self.kinds - 1))
                    }
                    gem.offset = Vec2(0, -Double(Self.size + 2 - y))
                    grid[index(x, y)] = gem
                }
            }
        } while findMove() == nil
        stage = .falling
    }

    // MARK: Matching

    struct Run {
        let cells: [Int]
        let horizontal: Bool
    }

    func findRuns() -> [Run] {
        var runs: [Run] = []
        for horizontal in [true, false] {
            for line in 0..<Self.size {
                var start = 0
                while start < Self.size {
                    func cell(_ k: Int) -> Int { horizontal ? index(k, line) : index(line, k) }
                    guard let kind = grid[cell(start)]?.kind, kind != Self.starKind else {
                        start += 1
                        continue
                    }
                    var end = start + 1
                    while end < Self.size, grid[cell(end)]?.kind == kind { end += 1 }
                    if end - start >= 3 { runs.append(Run(cells: (start..<end).map(cell), horizontal: horizontal)) }
                    start = end
                }
            }
        }
        return runs
    }

    /// A pair of cells whose swap makes a match, or nil.
    func findMove() -> (GridPoint, GridPoint)? {
        for y in 0..<Self.size {
            for x in 0..<Self.size {
                for (dx, dy) in [(1, 0), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx < Self.size, ny < Self.size else { continue }
                    let a = index(x, y), b = index(nx, ny)
                    if grid[a]?.kind == Self.starKind || grid[b]?.kind == Self.starKind { return (GridPoint(x, y), GridPoint(nx, ny)) }
                    grid.swapAt(a, b)
                    let ok = !findRuns().isEmpty
                    grid.swapAt(a, b)
                    if ok { return (GridPoint(x, y), GridPoint(nx, ny)) }
                }
            }
        }
        return nil
    }

    // MARK: Input

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .paused {
            resume()
            return true
        }
        if phase == .over {
            if (key == .primary || key == .confirm), !isRepeat, clock - overAt > 0.5 { reset() }
            return key == .primary || key == .confirm
        }
        if key == .restart {
            reset()
            return true
        }
        guard let dir = Direction(key: key) else {
            if key == .primary || key == .confirm {
                if !isRepeat { select(cursor) }
                return true
            }
            return false
        }
        if let s = selected {
            let target = GridPoint(s.x + dir.delta.x, s.y + dir.delta.y)
            selected = nil
            if inBounds(target) {
                cursor = target
                swap(s, target)
            }
        } else {
            cursor = GridPoint(clamp(cursor.x + dir.delta.x, 0, Self.size - 1), clamp(cursor.y + dir.delta.y, 0, Self.size - 1))
            play(.tick)
        }
        return true
    }

    func inBounds(_ p: GridPoint) -> Bool {
        p.x >= 0 && p.x < Self.size && p.y >= 0 && p.y < Self.size
    }

    /// Click or Space: select a gem, or swap with the selected neighbour.
    public func select(_ p: GridPoint) {
        guard inBounds(p), phase != .over else { return }
        cursor = p
        if let s = selected {
            selected = nil
            if abs(s.x - p.x) + abs(s.y - p.y) == 1 {
                swap(s, p)
            } else if s != p {
                selected = p
                play(.select)
            }
        } else {
            selected = p
            play(.select)
        }
    }

    /// Mouse drag from a gem in a direction.
    public func swipe(from p: GridPoint, _ dir: Direction) {
        let target = GridPoint(p.x + dir.delta.x, p.y + dir.delta.y)
        guard inBounds(p), inBounds(target) else { return }
        selected = nil
        cursor = target
        swap(p, target)
    }

    func swap(_ p: GridPoint, _ q: GridPoint) {
        guard case .idle = stage, phase != .over, movesLeft > 0 else { return }
        if phase == .ready { phase = .playing }
        let a = index(p.x, p.y), b = index(q.x, q.y)
        guard grid[a] != nil, grid[b] != nil else { return }
        hint = nil
        idleTime = 0
        grid.swapAt(a, b)
        grid[a]?.start = Vec2(Double(q.x - p.x), Double(q.y - p.y))
        grid[b]?.start = Vec2(Double(p.x - q.x), Double(p.y - q.y))
        grid[a]?.offset = grid[a]?.start ?? .zero
        grid[b]?.offset = grid[b]?.start ?? .zero
        let starSwap = grid[a]?.kind == Self.starKind || grid[b]?.kind == Self.starKind
        let valid = starSwap || !findRuns().isEmpty
        stage = .swapping(a: a, b: b, progress: 0, revert: !valid)
        lastSwap = (a, b)
        play(.slide)
    }

    // MARK: Tick

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        particles.update(dt, drag: 1.6)
        for i in popups.indices { popups[i].age += dt }
        popups.removeAll { $0.age > 0.9 }
        blasts.removeAll { clock - $0.at > 0.45 }
        guard phase != .paused else { return }

        switch stage {
        case .idle:
            if phase == .playing {
                idleTime += dt
                if idleTime > 6, hint == nil { hint = findMove() }
            }
        case .swapping(let a, let b, let progress, let revert):
            let p = min(1, progress + dt / Self.swapDuration)
            for i in [a, b] {
                if let start = grid[i]?.start { grid[i]?.offset = start * (1 - easeInOut(p)) }
            }
            if p < 1 {
                stage = .swapping(a: a, b: b, progress: p, revert: revert)
            } else if revert {
                // Invalid: swap back.
                grid.swapAt(a, b)
                let pa = GridPoint(a % Self.size, a / Self.size), pb = GridPoint(b % Self.size, b / Self.size)
                grid[a]?.start = Vec2(Double(pb.x - pa.x), Double(pb.y - pa.y))
                grid[b]?.start = Vec2(Double(pa.x - pb.x), Double(pa.y - pb.y))
                grid[a]?.offset = grid[a]?.start ?? .zero
                grid[b]?.offset = grid[b]?.start ?? .zero
                stage = .swapping(a: a, b: b, progress: 0, revert: false)
                lastSwap = nil
                play(.error)
            } else if lastSwap == nil {
                stage = .idle
            } else {
                movesLeft -= 1
                cascade = 0
                resolve(swapped: (a, b))
            }
        case .clearing(let progress):
            let p = progress + dt / Self.clearDuration
            if p < 1 {
                clearProgress = p
                stage = .clearing(progress: p)
            } else {
                removeCleared()
            }
        case .falling:
            var settled = true
            for i in grid.indices where (grid[i]?.offset.y ?? 0) < 0 {
                grid[i]?.fallSpeed += 46 * dt
                grid[i]?.offset.y += (grid[i]?.fallSpeed ?? 0) * dt
                if (grid[i]?.offset.y ?? 0) >= 0 {
                    grid[i]?.offset.y = 0
                    grid[i]?.fallSpeed = 0
                } else {
                    settled = false
                }
            }
            if settled {
                if findRuns().isEmpty {
                    finishTurn()
                } else {
                    resolve(swapped: nil)
                }
            }
        }
    }

    private func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

    // MARK: Resolution

    private func resolve(swapped: (Int, Int)?) {
        cascade += 1
        emit(.maximum("gems.cascade", cascade))
        var doomed = Set<Int>()
        var created: [(Int, Special, Int)] = [] // cell, special, kind

        // Star swaps clear a whole colour.
        if let pair = swapped, let ga = grid[pair.0], let gb = grid[pair.1], ga.kind == Self.starKind || gb.kind == Self.starKind {
            let a = pair.0, b = pair.1
            let star = ga.kind == Self.starKind ? a : b
            let other = star == a ? gb : ga
            doomed.insert(star)
            if other.kind == Self.starKind {
                doomed.formUnion(grid.indices.filter { grid[$0] != nil })
            } else {
                doomed.formUnion(grid.indices.filter { grid[$0]?.kind == other.kind })
            }
            blasts.append((.star, GridPoint(star % Self.size, star / Self.size), clock))
            emit(.shake(0.5))
        }

        let runs = findRuns()
        var cellRuns: [Int: Int] = [:]
        for run in runs {
            doomed.formUnion(run.cells)
            for c in run.cells { cellRuns[c, default: 0] += 1 }
        }
        // Specials born from big matches.
        let swapCells = swapped.map { [$0.0, $0.1] } ?? []
        for run in runs {
            let kind = grid[run.cells[0]]?.kind ?? 0
            let anchor = run.cells.first(where: { swapCells.contains($0) }) ?? run.cells[run.cells.count / 2]
            if let corner = run.cells.first(where: { (cellRuns[$0] ?? 0) > 1 }) {
                if !created.contains(where: { $0.0 == corner }) { created.append((corner, .bomb, kind)) }
            } else if run.cells.count >= 5 {
                created.append((anchor, .star, Self.starKind))
            } else if run.cells.count == 4 {
                created.append((anchor, run.horizontal ? .column : .row, kind))
            }
        }

        // Chain-react specials caught in the blast.
        var queue = Array(doomed)
        var visited = Set<Int>()
        while let cell = queue.popLast() {
            guard !visited.contains(cell), let gem = grid[cell] else { continue }
            visited.insert(cell)
            let x = cell % Self.size, y = cell / Self.size
            var extra: [Int] = []
            switch gem.special {
            case .row: extra = (0..<Self.size).map { index($0, y) }
            case .column: extra = (0..<Self.size).map { index(x, $0) }
            case .bomb:
                for dy in -1...1 {
                    for dx in -1...1 where inBounds(GridPoint(x + dx, y + dy)) { extra.append(index(x + dx, y + dy)) }
                }
            case .star:
                if !doomed.contains(where: { grid[$0]?.kind == Self.starKind && $0 != cell }) {
                    let target = rng.int(0...(Self.kinds - 1))
                    extra = grid.indices.filter { grid[$0]?.kind == target }
                }
            case .none:
                break
            }
            if gem.special != .none {
                blasts.append((gem.special, GridPoint(x, y), clock))
                emit(.shake(0.3))
                play(.explode)
            }
            for e in extra where !doomed.contains(e) {
                doomed.insert(e)
                queue.append(e)
            }
        }

        // Created specials survive in place.
        for (cell, special, kind) in created {
            doomed.remove(cell)
            grid[cell]?.special = special
            grid[cell]?.kind = kind
            emit(.count("gems.specials", 1))
        }

        guard !doomed.isEmpty else {
            finishTurn()
            return
        }
        let points = doomed.count * 10 * cascade + created.count * 50
        score += points
        emit(.count("gems.cleared", doomed.count))
        let cells = doomed.map { GridPoint($0 % Self.size, $0 / Self.size) }
        let cx = Double(cells.map(\.x).reduce(0, +)) / Double(cells.count) + 0.5
        let cy = Double(cells.map(\.y).reduce(0, +)) / Double(cells.count) + 0.5
        popups.append(Popup(text: cascade > 1 ? "+\(points) ×\(cascade)" : "+\(points)", position: Vec2(cx, cy), age: 0))
        clearing = Set(doomed.compactMap { grid[$0]?.id })
        for c in doomed {
            guard let g = grid[c] else { continue }
            particles.burst(
                at: Vec2(Double(c % Self.size) + 0.5, Double(c / Self.size) + 0.5), count: 7, speed: 1.5...5,
                life: 0.3...0.6, size: 0.05...0.12, tint: g.kind, gravity: 6, rng: &rng
            )
        }
        play(cascade > 1 ? .bonus : .merge)
        clearProgress = 0
        stage = .clearing(progress: 0)
    }

    private func removeCleared() {
        for i in grid.indices where grid[i].map({ clearing.contains($0.id) }) ?? false {
            grid[i] = nil
        }
        clearing = []
        // Gravity: compact each column and drop new gems in from above.
        for x in 0..<Self.size {
            var column: [Gem] = []
            for y in stride(from: Self.size - 1, through: 0, by: -1) {
                if let g = grid[index(x, y)] { column.append(g) }
            }
            var y = Self.size - 1
            var oldRows: [Int] = []
            for yy in stride(from: Self.size - 1, through: 0, by: -1) where grid[index(x, yy)] != nil { oldRows.append(yy) }
            for (k, gem) in column.enumerated() {
                var g = gem
                let drop = y - oldRows[k]
                g.offset = Vec2(0, g.offset.y - Double(drop))
                g.fallSpeed = 0
                grid[index(x, y)] = g
                y -= 1
            }
            let missing = y + 1
            while y >= 0 {
                var g = newGem()
                g.offset = Vec2(0, -Double(missing) - 0.4)
                grid[index(x, y)] = g
                y -= 1
            }
        }
        stage = .falling
    }

    private func finishTurn() {
        stage = .idle
        idleTime = 0
        lastSwap = nil
        if movesLeft <= 0 {
            phase = .over
            overAt = clock
            play(.win)
            emit(.record(score))
            emit(.count("gems.games", 1))
            return
        }
        if findMove() == nil {
            shuffle()
        }
    }

    private func shuffle() {
        var gems = grid.compactMap { $0 }
        repeat {
            gems.shuffle(using: &rng)
            for (i, g) in gems.enumerated() {
                var gem = g
                gem.offset = Vec2(0, -0.6)
                grid[i] = gem
            }
        } while !findRuns().isEmpty || findMove() == nil
        stage = .falling
        popups.append(Popup(text: "Shuffle", position: Vec2(4, 4), age: 0))
        play(.slide)
    }

    /// Test hook: set kinds row by row (-1 = star).
    func load(_ kinds: [[Int]]) {
        for (y, row) in kinds.enumerated() {
            for (x, k) in row.enumerated() {
                var g = newGem(kind: k < 0 ? Self.starKind : k)
                if k < 0 { g.special = .star }
                grid[index(x, y)] = g
            }
        }
        stage = .idle
        phase = .playing
    }

    /// Test hook: finish all animations.
    func settle() {
        for _ in 0..<600 {
            tick(1.0 / 60, input: InputState())
            if case .idle = stage { return }
        }
    }
}
