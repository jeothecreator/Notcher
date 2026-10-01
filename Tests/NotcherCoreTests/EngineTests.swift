import XCTest
@testable import NotcherCore

/// Runs an engine for `seconds` at 120 fps.
func simulate(_ engine: GameEngine, seconds: Double, input: InputState = InputState()) {
    let dt = 1.0 / 120
    for _ in 0..<Int(seconds / dt) { engine.tick(dt, input: input) }
}

final class SnakeTests: XCTestCase {
    func testStartsOnArrowAndMoves() {
        let s = SnakeEngine(seed: 1)
        XCTAssertEqual(s.phase, .ready)
        let head = s.body[0]
        s.handle(.right, isRepeat: false)
        XCTAssertEqual(s.phase, .playing)
        s.step()
        XCTAssertEqual(s.body[0], GridPoint(head.x + 1, head.y))
        XCTAssertEqual(s.body.count, 4)
    }

    func testCannotReverse() {
        let s = SnakeEngine(seed: 1)
        s.handle(.right, isRepeat: false)
        s.handle(.left, isRepeat: false)
        s.step()
        XCTAssertEqual(s.direction, .right)
        XCTAssertEqual(s.phase, .playing)
    }

    func testStartingBackwardsFlipsTheSnake() {
        let s = SnakeEngine(seed: 1)
        let tail = s.body.last!
        s.handle(.left, isRepeat: false)
        XCTAssertEqual(s.body[0], tail)
        s.step()
        XCTAssertEqual(s.phase, .playing)
    }

    func testHitsWall() {
        let s = SnakeEngine(seed: 3)
        s.handle(.up, isRepeat: false)
        for _ in 0..<SnakeEngine.rows { if s.phase == .playing { s.step() } }
        XCTAssertEqual(s.phase, .over)
        let events = s.drainEvents()
        XCTAssertTrue(events.contains(.record(s.score)))
    }

    func testTurnQueue() {
        let s = SnakeEngine(seed: 1)
        s.handle(.right, isRepeat: false)
        let head = s.body[0]
        s.handle(.up, isRepeat: false)
        s.handle(.left, isRepeat: false)
        s.step()
        s.step()
        XCTAssertEqual(s.body[0], GridPoint(head.x - 1, head.y - 1))
    }

    func testSimulationIsStable() {
        let s = SnakeEngine(seed: 9)
        s.handle(.down, isRepeat: false)
        simulate(s, seconds: 5)
        XCTAssertEqual(s.phase, .over)
    }
}

final class Twenty48Tests: XCTestCase {
    func testMergeLeft() {
        let g = Twenty48Engine(seed: 1)
        g.load([[2, 2, 2, 2], [2, 2, 4, 0], [0, 0, 0, 0], [4, 0, 4, 8]])
        XCTAssertTrue(g.move(.left))
        let v = g.values()
        XCTAssertEqual(Array(v[0]), [4, 4, 0, 0])
        XCTAssertEqual(Array(v[1]), [4, 4, 0, 0])
        XCTAssertEqual(Array(v[3]), [8, 8, 0, 0])
        XCTAssertEqual(g.score, 4 + 4 + 4 + 8)
        // One new tile spawned in an empty cell.
        XCTAssertEqual(v.flatMap { $0 }.filter { $0 > 0 }.count, 7)
    }

    func testMergeRightAndDown() {
        let g = Twenty48Engine(seed: 1)
        g.load([[2, 2, 4, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        g.move(.right)
        XCTAssertEqual(Array(g.values()[0].suffix(2)), [4, 4])

        let d = Twenty48Engine(seed: 1)
        d.load([[2, 0, 0, 0], [2, 0, 0, 0], [4, 0, 0, 0], [0, 0, 0, 0]])
        d.move(.down)
        XCTAssertEqual(d.values()[3][0], 4)
        XCTAssertEqual(d.values()[2][0], 4)
    }

    func testNoopMove() {
        let g = Twenty48Engine(seed: 1)
        g.load([[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertFalse(g.move(.left))
        XCTAssertFalse(g.move(.up))
    }

    func testGameOver() {
        let g = Twenty48Engine(seed: 1)
        g.load([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]])
        XCTAssertFalse(g.canMove())
        g.load([[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 4]])
        XCTAssertTrue(g.canMove())
    }

    func testUndo() {
        let g = Twenty48Engine(seed: 5)
        g.load([[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        g.handle(.left, isRepeat: false)
        XCTAssertEqual(g.score, 4)
        g.handle(.undo, isRepeat: false)
        XCTAssertEqual(g.score, 0)
        XCTAssertEqual(Array(g.values()[0]), [2, 2, 0, 0])
        XCTAssertEqual(g.undosLeft, 2)
    }

    func testStableIDs() {
        let g = Twenty48Engine(seed: 5)
        g.load([[0, 0, 0, 2], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        let id = g.liveTiles[0].id
        g.move(.left)
        XCTAssertTrue(g.liveTiles.contains { $0.id == id && $0.col == 0 })
    }
}

final class MinesTests: XCTestCase {
    func testFirstRevealIsSafe() {
        for seed in 1...30 {
            let m = MinesEngine(seed: UInt64(seed))
            m.reveal(5, 4)
            XCTAssertEqual(m.phase, .playing, "seed \(seed)")
            XCTAssertFalse(m.cell(5, 4).isMine)
            XCTAssertEqual(m.cell(5, 4).adjacent, 0)
            XCTAssertEqual(m.cells.filter(\.isMine).count, MinesEngine.mineCount)
        }
    }

    func testWinAndLose() {
        let m = MinesEngine(seed: 1)
        m.loadMines([GridPoint(0, 0)])
        m.reveal(10, 4)
        XCTAssertEqual(m.phase, .over)
        XCTAssertTrue(m.won)
        XCTAssertTrue(m.drainEvents().contains { if case .record = $0 { return true }; return false })

        let l = MinesEngine(seed: 1)
        l.loadMines([GridPoint(0, 0), GridPoint(19, 7)])
        l.reveal(0, 0)
        XCTAssertEqual(l.phase, .over)
        XCTAssertFalse(l.won)
        XCTAssertEqual(l.exploded, GridPoint(0, 0))
    }

    func testFlagsAndChord() {
        let m = MinesEngine(seed: 1)
        m.loadMines([GridPoint(1, 0), GridPoint(10, 7)])
        m.reveal(0, 0)
        XCTAssertEqual(m.cell(0, 0).adjacent, 1)
        XCTAssertEqual(m.cell(0, 1).state, .hidden)
        m.toggleFlag(1, 0)
        XCTAssertEqual(m.minesLeft, MinesEngine.mineCount - 1)
        m.reveal(0, 0) // chord
        XCTAssertEqual(m.cell(0, 1).state, .revealed)
        XCTAssertNotEqual(m.phase, .over)
    }

    func testCursorWraps() {
        let m = MinesEngine(seed: 1)
        m.setCursor(0, 0)
        m.handle(.left, isRepeat: false)
        XCTAssertEqual(m.cursor, GridPoint(MinesEngine.columns - 1, 0))
    }
}

final class SolitaireTests: XCTestCase {
    func testDeal() {
        let s = SolitaireEngine(seed: 1)
        for i in 0..<7 {
            XCTAssertEqual(s.board.tableau[i].count, i + 1)
            XCTAssertTrue(s.board.tableau[i].last!.faceUp)
            XCTAssertEqual(s.board.tableau[i].filter(\.faceUp).count, 1)
        }
        XCTAssertEqual(s.board.stock.count, 24)
        let all = s.board.stock + s.board.tableau.flatMap { $0 }
        XCTAssertEqual(Set(all.map(\.id)).count, 52)
    }

    func testRules() {
        let s = SolitaireEngine(seed: 1)
        var b = SolitaireBoard()
        b.tableau[0] = [Card(rank: 9, suit: .clubs, faceUp: false), Card(rank: 8, suit: .hearts)]
        b.tableau[1] = [Card(rank: 7, suit: .spades)]
        b.tableau[2] = [Card(rank: 7, suit: .diamonds)]
        b.waste = [Card(rank: 1, suit: .hearts)]
        s.load(b)
        XCTAssertFalse(s.move(from: .tableau(2), count: 1, to: .tableau(0)), "red on red")
        XCTAssertTrue(s.move(from: .tableau(1), count: 1, to: .tableau(0)))
        XCTAssertTrue(s.move(from: .waste, count: 1, to: .foundation(0)))
        XCTAssertFalse(s.move(from: .tableau(2), count: 1, to: .foundation(0)), "7 on ace")
        // Move the 8–7 run onto an empty column? Only kings may go there.
        XCTAssertFalse(s.move(from: .tableau(0), count: 2, to: .tableau(1)))
    }

    func testFlipAfterMove() {
        let s = SolitaireEngine(seed: 1)
        var b = SolitaireBoard()
        b.tableau[0] = [Card(rank: 3, suit: .clubs, faceUp: false), Card(rank: 13, suit: .hearts)]
        s.load(b)
        XCTAssertTrue(s.move(from: .tableau(0), count: 1, to: .tableau(1)))
        XCTAssertTrue(s.board.tableau[0][0].faceUp)
        s.undo()
        XCTAssertFalse(s.board.tableau[0][0].faceUp)
        XCTAssertEqual(s.board.tableau[0].count, 2)
    }

    func testDrawAndRecycle() {
        let s = SolitaireEngine(seed: 2)
        for _ in 0..<24 { s.draw() }
        XCTAssertTrue(s.board.stock.isEmpty)
        XCTAssertEqual(s.board.waste.count, 24)
        s.draw()
        XCTAssertEqual(s.board.stock.count, 24)
        XCTAssertTrue(s.board.waste.isEmpty)
        XCTAssertFalse(s.board.stock.contains { $0.faceUp })
    }

    func testKeyboardPickAndDrop() {
        let s = SolitaireEngine(seed: 1)
        var b = SolitaireBoard()
        b.tableau[0] = [Card(rank: 8, suit: .hearts)]
        b.tableau[1] = [Card(rank: 7, suit: .spades)]
        s.load(b)
        s.handle(.right, isRepeat: false) // cursor → tableau(1)
        s.handle(.confirm, isRepeat: false) // pick up
        XCTAssertEqual(s.held, SolitaireEngine.Hold(from: .tableau(1), count: 1))
        s.handle(.left, isRepeat: false)
        s.handle(.confirm, isRepeat: false) // drop
        XCTAssertNil(s.held)
        XCTAssertEqual(s.board.tableau[0].count, 2)
    }

    func testAutoFinishWins() {
        let s = SolitaireEngine(seed: 1)
        var b = SolitaireBoard()
        for suit in Suit.allCases {
            b.foundations[suit.rawValue] = (1...12).map { Card(rank: $0, suit: suit) }
        }
        b.tableau[0] = [Card(rank: 13, suit: .spades), Card(rank: 13, suit: .hearts)].reversed()
        b.tableau[1] = [Card(rank: 13, suit: .diamonds)]
        b.tableau[2] = [Card(rank: 13, suit: .clubs)]
        s.load(b)
        s.smartMove(from: .tableau(2))
        simulate(s, seconds: 2)
        XCTAssertTrue(s.won)
        XCTAssertEqual(s.phase, .over)
    }
}

final class RealtimeEngineTests: XCTestCase {
    func testRunnerDiesWithoutInput() {
        let r = RunnerEngine(seed: 4)
        r.handle(.primary, isRepeat: false)
        simulate(r, seconds: 30)
        XCTAssertEqual(r.phase, .over)
        XCTAssertGreaterThan(r.score, 0)
    }

    func testRunnerJumps() {
        let r = RunnerEngine(seed: 4)
        let input = InputState()
        input.press(.primary)
        r.handle(.primary, isRepeat: false)
        r.tick(1.0 / 120, input: input)
        simulate(r, seconds: 0.1, input: input)
        XCTAssertLessThan(r.player.y, RunnerEngine.groundY)
        XCTAssertFalse(r.player.onGround)
    }

    func testRunnerSlides() {
        let r = RunnerEngine(seed: 4)
        let input = InputState()
        input.press(.down)
        r.handle(.down, isRepeat: false)
        simulate(r, seconds: 0.1, input: input)
        XCTAssertTrue(r.player.sliding)
        XCTAssertLessThan(r.player.box.h, 20)
    }

    func testPongPrediction() {
        let p = PongEngine(seed: 1)
        p.handle(.up, isRepeat: false)
        simulate(p, seconds: 1)
        let y = p.predictY(atX: PongEngine.aiX)
        XCTAssertGreaterThanOrEqual(y, PongEngine.ballRadius - 0.001)
        XCTAssertLessThanOrEqual(y, PongEngine.height - PongEngine.ballRadius + 0.001)
    }

    func testPongEventuallyEnds() {
        let p = PongEngine(seed: 1)
        p.handle(.up, isRepeat: false)
        simulate(p, seconds: 240)
        XCTAssertEqual(p.phase, .over)
    }

    func testBreakoutLevels() {
        for level in 1...12 {
            var rng = SeededRandom(seed: 1)
            let count = (0..<6).flatMap { row in
                (0..<BreakoutEngine.columns).map { BreakoutEngine.layout(level: level, row: row, col: $0, rng: &rng) }
            }.filter { $0 > 0 }.count
            if (level - 1) % 5 != 4 { XCTAssertGreaterThan(count, 10, "level \(level)") }
        }
        let b = BreakoutEngine(seed: 2)
        XCTAssertFalse(b.bricks.isEmpty)
        b.handle(.primary, isRepeat: false)
        XCTAssertFalse(b.balls[0].stuck)
        simulate(b, seconds: 60)
        XCTAssertGreaterThan(b.score, 0)
    }

    func testReactionTiming() {
        var t = 100.0
        let r = ReactionEngine(seed: 1, now: { t })
        r.handle(.primary, isRepeat: false)
        XCTAssertEqual(r.stage, .waiting)
        // Too early.
        r.handle(.primary, isRepeat: false)
        XCTAssertEqual(r.stage, .early)
        r.handle(.primary, isRepeat: false)
        t += 10
        r.tick(0.01, input: InputState())
        XCTAssertEqual(r.stage, .go)
        t += 0.187
        r.handle(.primary, isRepeat: false)
        XCTAssertEqual(r.stage, .result(187))
        XCTAssertEqual(r.best, 187)
        XCTAssertTrue(r.drainEvents().contains(.record(187)))
    }

    func testArcadeMinisRun() {
        let minis: [GameEngine] = [FlapEngine(seed: 1), DodgeEngine(seed: 1), BullseyeEngine(seed: 1), EchoEngine(seed: 1)]
        for m in minis {
            m.handle(.primary, isRepeat: false)
            simulate(m, seconds: 20)
            m.handle(.primary, isRepeat: false)
            m.handle(.up, isRepeat: false)
            simulate(m, seconds: 5)
        }
        XCTAssertEqual(minis[0].phase, .over, "Flap falls without input")
        XCTAssertEqual(minis[1].boardKey, "arcade.dodge")
    }

    func testBullseyeHitAndMiss() {
        let b = BullseyeEngine(seed: 3)
        b.handle(.primary, isRepeat: false)
        // Run until the needle is inside the zone, then stop it.
        let input = InputState()
        var guardCount = 0
        while abs(b.needle - b.zoneCenter) > b.zoneWidth * 0.3 && guardCount < 10_000 {
            b.tick(1.0 / 240, input: input)
            guardCount += 1
        }
        b.handle(.primary, isRepeat: false)
        XCTAssertEqual(b.hits, 1)
        XCTAssertGreaterThan(b.score, 0)
    }

    func testEchoSequence() {
        let e = EchoEngine(seed: 1)
        e.handle(.primary, isRepeat: false)
        simulate(e, seconds: 2)
        XCTAssertEqual(e.stage, .input)
        let keys: [GameKey] = [.up, .right, .down, .left]
        e.handle(keys[e.sequence[0]], isRepeat: false)
        XCTAssertEqual(e.score, 1)
        simulate(e, seconds: 3)
        XCTAssertEqual(e.sequence.count, 2)
        let wrong = keys[(e.sequence[0] + 1) % 4]
        e.handle(wrong, isRepeat: false)
        XCTAssertEqual(e.phase, .over)
    }

    func testArcadeCabinetSwitches() {
        let a = ArcadeEngine(featured: .flap)
        XCTAssertEqual(a.boardKey, "arcade.flap")
        a.handle(.cycle, isRepeat: false)
        XCTAssertEqual(a.mini, .dodge)
        a.handle(.number(4), isRepeat: false)
        XCTAssertEqual(a.mini, .echo)
        a.handle(.primary, isRepeat: false)
        XCTAssertEqual(a.phase, .playing)
        a.handle(.cycle, isRepeat: false)
        XCTAssertEqual(a.mini, .echo, "no switching mid-game")
    }
}

final class IdleEngineTests: XCTestCase {
    func testMinerOfflineIsCapped() {
        var state = MinerState(now: Date(timeIntervalSince1970: 0))
        state.workers = 2
        let rate = MinerEngine.rate(for: state)
        XCTAssertGreaterThan(rate, 0)
        let hour = Date(timeIntervalSince1970: 3600)
        XCTAssertEqual(MinerEngine.projectedCoins(state, at: hour), rate * 3600, accuracy: 0.001)
        let dayLater = Date(timeIntervalSince1970: 86_400)
        let capped = MinerEngine.storageHours(0) * 3600 * rate
        XCTAssertEqual(MinerEngine.projectedCoins(state, at: dayLater), capped, accuracy: 0.001)

        let engine = MinerEngine(state: state, date: { dayLater })
        XCTAssertEqual(engine.offlineEarnings, capped, accuracy: 0.001)
    }

    func testMinerBuyAndMine() {
        var now = Date(timeIntervalSince1970: 0)
        let engine = MinerEngine(state: MinerState(now: now), date: { now })
        XCTAssertFalse(engine.buy(.pickaxe))
        for _ in 0..<10 { engine.mine() }
        XCTAssertGreaterThanOrEqual(engine.state.coins, 25)
        XCTAssertTrue(engine.buy(.pickaxe))
        XCTAssertEqual(engine.state.pickaxe, 2)
        now = now.addingTimeInterval(10)
        engine.tick(0.016, input: InputState())
        XCTAssertEqual(engine.state.lastUpdate, now)
    }

    func testFarmGrowth() {
        var now = Date(timeIntervalSince1970: 1_000)
        let farm = FarmEngine(state: FarmState(), date: { now })
        farm.selectCrop(.wheat)
        farm.interact(0)
        XCTAssertEqual(farm.state.plots[0].crop, .wheat)
        XCTAssertEqual(farm.state.coins, 25 - Crop.wheat.seedCost)
        farm.interact(0) // not ready
        XCTAssertEqual(farm.state.harvests, 0)
        now = now.addingTimeInterval(Crop.wheat.growSeconds)
        XCTAssertEqual(farm.state.readyCount(at: now), 1)
        farm.interact(0)
        XCTAssertEqual(farm.state.harvests, 1)
        XCTAssertEqual(farm.state.coins, 25 - Crop.wheat.seedCost + Crop.wheat.sellPrice)
        XCTAssertNil(farm.state.plots[0].crop)
    }

    func testFarmUnlock() {
        var state = FarmState()
        state.coins = 1_000
        let farm = FarmEngine(state: state, date: { Date(timeIntervalSince1970: 0) })
        farm.interact(6) // not the next plot
        XCTAssertEqual(farm.state.unlocked, 4)
        farm.interact(4)
        XCTAssertEqual(farm.state.unlocked, 5)
        XCTAssertEqual(farm.state.coins, 1_000 - FarmEngine.unlockCost(forPlot: 4))
    }
}
