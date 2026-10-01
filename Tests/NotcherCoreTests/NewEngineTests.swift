import XCTest
@testable import NotcherCore

final class StackTests: XCTestCase {
    func testSpawnAndHardDrop() {
        let s = StackEngine(seed: 1)
        XCTAssertNotNil(s.current)
        s.handle(.primary, isRepeat: false) // start
        let kind = s.current?.kind
        s.handle(.primary, isRepeat: false) // hard drop
        XCTAssertGreaterThan(s.score, 0)
        XCTAssertNotEqual(s.board.flatMap { $0 }.compactMap { $0 }.count, 0)
        XCTAssertNotNil(s.current)
        XCTAssertNotEqual(s.next.count, 0)
        _ = kind
    }

    func testTetrisClearsFourLines() {
        let s = StackEngine(seed: 1)
        s.loadRows(4, gap: 0)
        // Vertical I: rotation 1 occupies box column 2, so x = -2 puts it in column 0.
        s.setCurrent(StackEngine.Piece(kind: .i, rotation: 1, x: -2, y: 0))
        s.hardDrop()
        XCTAssertEqual(s.clearingRows.count, 4)
        simulate(s, seconds: 0.5)
        XCTAssertEqual(s.lines, 4)
        XCTAssertEqual(s.tetrises, 1)
        XCTAssertGreaterThanOrEqual(s.score, 800)
        let filled = s.board.flatMap { $0 }.compactMap { $0 }.count
        XCTAssertEqual(filled, 0, "board is empty after the tetris")
    }

    func testRotationAndHold() {
        let s = StackEngine(seed: 3)
        s.setCurrent(StackEngine.Piece(kind: .t, rotation: 0, x: 3, y: 4))
        XCTAssertTrue(s.rotate(1))
        XCTAssertEqual(s.current?.rotation, 1)
        // Against the left wall a kick lets the rotation succeed.
        s.setCurrent(StackEngine.Piece(kind: .t, rotation: 1, x: -1, y: 4))
        XCTAssertTrue(s.fits(s.current!))
        XCTAssertTrue(s.rotate(1))
        s.hold()
        XCTAssertEqual(s.held, .t)
        XCTAssertTrue(s.holdUsed)
    }

    func testLockOutEndsGame() {
        let s = StackEngine(seed: 2)
        s.handle(.left, isRepeat: false)
        s.loadRows(StackEngine.visibleRows, gap: 9)
        s.hardDrop()
        simulate(s, seconds: 1)
        XCTAssertEqual(s.phase, .over)
    }

    func testCellsRotateWithinBox() {
        for kind in StackEngine.Kind.allCases {
            for r in 0..<4 {
                let cells = kind.cells(rotation: r)
                XCTAssertEqual(cells.count, 4)
                XCTAssertEqual(Set(cells).count, 4)
            }
        }
    }
}

final class ActionEngineTests: XCTestCase {
    func testInvadersShootAliens() {
        let e = InvadersEngine(seed: 4)
        e.handle(.primary, isRepeat: false)
        let input = InputState()
        input.press(.primary)
        simulate(e, seconds: 4, input: input)
        XCTAssertGreaterThan(e.score, 0)
        XCTAssertLessThan(e.aliveCount, InvadersEngine.rows * InvadersEngine.columns)
    }

    func testInvadersNextWave() {
        let e = InvadersEngine(seed: 4)
        e.handle(.primary, isRepeat: false)
        e.leaveOneAlien()
        let fast = e.marchInterval
        XCTAssertLessThan(fast, 0.1)
        XCTAssertEqual(e.aliveCount, 1)
    }

    func testAstroWrapDistance() {
        let e = AstroEngine(seed: 1)
        XCTAssertEqual(e.distance(Vec2(5, 5), Vec2(AstroEngine.width - 5, 5)), 10, accuracy: 0.001)
        XCTAssertEqual(e.rocks.count, 3)
        XCTAssertTrue(e.rocks.allSatisfy { ($0.position - e.ship.position).length >= 110 })
        e.handle(.primary, isRepeat: false)
        let input = InputState()
        input.press(.primary)
        input.press(.left)
        simulate(e, seconds: 8, input: input)
        XCTAssertGreaterThan(e.score + (3 - e.lives), 0, "either hit something or got hit")
    }

    func testTrailsRoundsResolve() {
        let t = TrailsEngine(seed: 2)
        t.handle(.right, isRepeat: false)
        simulate(t, seconds: 12)
        XCTAssertTrue(t.lives < 3 || t.round > 1)
        XCTAssertEqual(t.space(from: GridPoint(0, 0), limit: 50), 50)
    }
}

final class SudokuTests: XCTestCase {
    func testGeneratorProducesUniquePuzzle() {
        for (seed, difficulty) in [(1, SudokuEngine.Difficulty.easy), (2, .medium), (3, .hard)] {
            let s = SudokuEngine(seed: UInt64(seed), difficulty: difficulty)
            XCTAssertEqual(SudokuEngine.countSolutions(s.puzzle, limit: 2), 1)
            for i in 0..<81 where s.puzzle[i] != 0 {
                XCTAssertEqual(s.puzzle[i], s.solution[i])
            }
            // Every row, column and box of the solution holds 1…9.
            for k in 0..<9 {
                XCTAssertEqual(Set((0..<9).map { s.solution[k * 9 + $0] }), Set(1...9))
                XCTAssertEqual(Set((0..<9).map { s.solution[$0 * 9 + k] }), Set(1...9))
            }
            let givens = s.puzzle.filter { $0 != 0 }.count
            XCTAssertLessThanOrEqual(givens, 45)
        }
    }

    func testSolveAndMistakes() {
        let s = SudokuEngine(seed: 5, difficulty: .easy)
        guard let empty = (0..<81).first(where: { !s.isGiven($0) }) else { return XCTFail("no empty cell") }
        s.select(empty % 9, empty / 9)
        let wrong = s.solution[empty] % 9 + 1
        s.handle(.number(wrong), isRepeat: false)
        XCTAssertEqual(s.mistakes, 1)
        XCTAssertTrue(s.isWrong(empty))
        s.handle(.backspace, isRepeat: false)
        XCTAssertEqual(s.value(empty), 0)
        s.fillAllButCursor()
        s.handle(.number(s.solution[empty]), isRepeat: false)
        XCTAssertTrue(s.won)
        XCTAssertEqual(s.phase, .over)
    }

    func testNotes() {
        let s = SudokuEngine(seed: 6)
        guard let empty = (0..<81).first(where: { !s.isGiven($0) }) else { return XCTFail("no empty cell") }
        s.select(empty % 9, empty / 9)
        s.handle(.flag, isRepeat: false)
        s.handle(.number(4), isRepeat: false)
        XCTAssertEqual(s.notes[empty] & (1 << 4), 1 << 4)
        XCTAssertEqual(s.value(empty), 0)
    }
}

final class GemsTests: XCTestCase {
    /// No runs anywhere: neighbours differ horizontally by 1 and vertically by 2.
    func quietBoard() -> [[Int]] {
        (0..<8).map { y in (0..<8).map { x in (x + 2 * y) % 6 } }
    }

    func testFreshBoardHasNoMatchesAndAMove() {
        let g = GemsEngine(seed: 3)
        g.settle()
        XCTAssertTrue(g.findRuns().isEmpty)
        XCTAssertNotNil(g.findMove())
    }

    func testValidSwapScores() {
        let g = GemsEngine(seed: 1)
        var board = quietBoard()
        board[0][1] = 0
        board[1][2] = 0
        g.load(board)
        XCTAssertTrue(g.findRuns().isEmpty)
        g.swap(GridPoint(2, 0), GridPoint(2, 1))
        g.settle()
        XCTAssertGreaterThan(g.score, 0)
        XCTAssertEqual(g.movesLeft, GemsEngine.movesPerGame - 1)
    }

    func testInvalidSwapReverts() {
        let g = GemsEngine(seed: 1)
        g.load(quietBoard())
        let before = g.gem(0, 0)?.id
        g.swap(GridPoint(0, 0), GridPoint(1, 0))
        g.settle()
        XCTAssertEqual(g.gem(0, 0)?.id, before)
        XCTAssertEqual(g.movesLeft, GemsEngine.movesPerGame)
        XCTAssertEqual(g.score, 0)
    }

    func testFiveMakesStarGem() {
        let g = GemsEngine(seed: 1)
        var board = quietBoard()
        // Row 0 becomes 0 0 _ 0 0 with a 0 waiting below the gap.
        board[0][1] = 0
        board[0][3] = 0
        board[0][4] = 0
        board[1][2] = 0
        g.load(board)
        XCTAssertTrue(g.findRuns().isEmpty)
        g.swap(GridPoint(2, 0), GridPoint(2, 1))
        g.settle()
        XCTAssertGreaterThan(g.score, 50)
        XCTAssertTrue(g.grid.contains { $0?.special == .star })
    }
}

final class WordGameTests: XCTestCase {
    func testMarking() {
        XCTAssertEqual(LexiEngine.mark("lever", against: "hello"), [.present, .correct, .absent, .absent, .absent])
        XCTAssertEqual(LexiEngine.mark("eerie", against: "crane"), [.absent, .absent, .present, .absent, .correct])
        XCTAssertEqual(LexiEngine.mark("crane", against: "crane"), Array(repeating: .correct, count: 5))
    }

    func testWordList() {
        let words = WordList(dictionaryPath: nil)
        XCTAssertGreaterThan(words.answers.count, 500)
        XCTAssertTrue(words.answers.allSatisfy { $0.count == 5 })
        XCTAssertTrue(words.isValid("CRANE"))
        XCTAssertTrue(words.isValid("hello"))
        XCTAssertFalse(words.isValid("zzzzz"))
        XCTAssertFalse(words.isValid("abc"))
        XCTAssertGreaterThan(words.typingWords.count, 100)
    }

    func testLexiWin() {
        let lexi = LexiEngine(seed: 1, words: WordList(dictionaryPath: nil))
        lexi.setAnswer("crane")
        for c in "zzzzz" { lexi.handle(.char(c), isRepeat: false) }
        lexi.handle(.confirm, isRepeat: false)
        XCTAssertTrue(lexi.guesses.isEmpty, "invalid word is rejected")
        for _ in 0..<5 { lexi.handle(.backspace, isRepeat: false) }
        for c in "CRANE" { lexi.handle(.char(c), isRepeat: false) }
        lexi.handle(.confirm, isRepeat: false)
        XCTAssertEqual(lexi.guesses, ["crane"])
        simulate(lexi, seconds: 4)
        XCTAssertTrue(lexi.won)
        XCTAssertEqual(lexi.phase, .over)
        XCTAssertEqual(lexi.score, 600)
        XCTAssertEqual(lexi.keyboard["c"], .correct)
    }

    func testTyper() {
        let typer = TyperEngine(seed: 2, words: WordList(dictionaryPath: nil))
        let word = typer.currentWord
        for c in word { typer.handle(.char(c), isRepeat: false) }
        typer.handle(.primary, isRepeat: false)
        XCTAssertEqual(typer.results, [true])
        XCTAssertEqual(typer.correctChars, word.count + 1)
        typer.handle(.char("q"), isRepeat: false)
        typer.handle(.char("q"), isRepeat: false)
        XCTAssertGreaterThan(typer.mistakes, 0)
        simulate(typer, seconds: 31)
        XCTAssertEqual(typer.phase, .over)
        XCTAssertEqual(typer.score, typer.wpm)
    }
}

final class FourTests: XCTestCase {
    func testWinDetection() {
        var b = Array(repeating: 0, count: 42)
        for c in 0..<4 { b[5 * 7 + c] = 1 }
        XCTAssertNotNil(FourEngine.winningLine(b, 1))
        XCTAssertNil(FourEngine.winningLine(b, 2))
        XCTAssertEqual(FourEngine.windows.count, 69)
    }

    func testAIBlocksAndWins() {
        let f = FourEngine(seed: 9)
        // Player threatens the bottom row; the AI must block column 3.
        var b = Array(repeating: 0, count: 42)
        b[5 * 7 + 0] = 1
        b[5 * 7 + 1] = 1
        b[5 * 7 + 2] = 1
        b[4 * 7 + 0] = 2
        b[4 * 7 + 1] = 2
        f.load(b, turn: .ai)
        XCTAssertEqual(f.bestMove(), 3)

        // AI has three stacked in column 6: take the win.
        var w = Array(repeating: 0, count: 42)
        w[5 * 7 + 6] = 2
        w[4 * 7 + 6] = 2
        w[3 * 7 + 6] = 2
        w[5 * 7 + 0] = 1
        w[5 * 7 + 1] = 1
        w[4 * 7 + 0] = 1
        f.load(w, turn: .ai)
        XCTAssertEqual(f.bestMove(), 6)
    }

    func testPlayerDropAnimatesAndLands() {
        let f = FourEngine(seed: 1)
        f.handle(.primary, isRepeat: false)
        XCTAssertNotNil(f.drop)
        simulate(f, seconds: 1)
        XCTAssertEqual(f.board.filter { $0 == 1 }.count, 1)
        simulate(f, seconds: 2)
        XCTAssertEqual(f.board.filter { $0 == 2 }.count, 1, "the AI answered")
    }
}

final class NewArcadeTests: XCTestCase {
    func testLanderCrashesWithoutThrust() {
        let l = LanderEngine(seed: 1)
        l.handle(.primary, isRepeat: false)
        simulate(l, seconds: 10)
        XCTAssertEqual(l.phase, .over)
        XCTAssertFalse(l.pads.isEmpty)
        XCTAssertTrue(l.pads.allSatisfy { $0.x1 > $0.x0 })
    }

    func testHopScoresForwardHops() {
        let h = HopEngine(seed: 1)
        h.handle(.up, isRepeat: false)
        XCTAssertEqual(h.frogRow, HopEngine.rows - 2)
        XCTAssertEqual(h.score, 10)
        simulate(h, seconds: 40)
        XCTAssertLessThan(h.lives, 3, "standing in traffic is fatal")
    }

    func testCabinetHasSixGames() {
        let a = ArcadeEngine(featured: .lander)
        XCTAssertEqual(a.boardKey, "arcade.lander")
        a.handle(.number(6), isRepeat: false)
        XCTAssertEqual(a.mini, .hop)
        XCTAssertEqual(ArcadeMini.allCases.count, 6)
    }
}
