import AppKit
import NotcherCore
import SwiftUI

/// `Notcher --render-previews <folder>` renders every notch state and game to
/// PNG files (used for screenshots and visual checks in CI), then exits.
@MainActor
enum PreviewRenderer {
    static func run(into folder: URL) {
        SoundEngine.shared.suppressed = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("notcher-previews-\(UUID().uuidString)")
        let arcade = ArcadeController(store: SaveStore(folder: scratch))
        arcade.metrics = NotchMetrics(notchWidth: 186, notchHeight: 32, hasNotch: true)
        arcade.panelSize = ArcadeController.panelSize(for: arcade.metrics)
        seed(arcade)

        func shot(_ name: String) {
            if case .game = arcade.mode { arcade.previewClearToasts() }
            render(name, arcade: arcade, to: folder)
        }

        arcade.previewState(mode: .closed)
        shot("01-closed")

        arcade.previewState(mode: .launcher, hovered: .game(.stack), charging: .game(.stack))
        shot("02-launcher")

        arcade.previewState(mode: .launcher, page: .category(.action), hovered: .game(.invaders))
        shot("03-launcher-action")

        arcade.previewState(mode: .launcher, page: .category(.puzzle), hovered: .game(.gems))
        shot("04-launcher-puzzle")

        arcade.previewState(mode: .launcher, page: .category(.brain), hovered: .game(.lexi))
        shot("05-launcher-brain")

        arcade.previewState(mode: .launcher, page: .category(.idle), hovered: .page(.category(.idle)))
        shot("06-launcher-idle")

        arcade.previewState(mode: .launcher, hovered: .quit, quitArmed: true)
        shot("07-quit")

        arcade.previewState(mode: .closed, toast: Toast(symbol: "crown.fill", title: "Snake God", subtitle: "Achievement unlocked", colors: GameID.snake.style.colors))
        shot("08-toast")

        let runner = arcade.previewSession(.runner)
        if let e = runner.engine as? RunnerEngine { autopilotRunner(e, session: runner, seconds: 7.3) }
        shot("10-runner")

        let snake = arcade.previewSession(.snake)
        if let e = snake.engine as? SnakeEngine { autopilotSnake(e, session: snake, apples: 14) }
        shot("11-snake")

        let pong = arcade.previewSession(.pong)
        if let e = pong.engine as? PongEngine { autopilotPong(e, session: pong, seconds: 9.4) }
        shot("12-pong")

        let breakout = arcade.previewSession(.breakout)
        if let e = breakout.engine as? BreakoutEngine { autopilotBreakout(e, session: breakout, seconds: 14.2) }
        shot("13-breakout")

        let invaders = arcade.previewSession(.invaders, engine: InvadersEngine(seed: 7))
        if let e = invaders.engine as? InvadersEngine { autopilotInvaders(e, session: invaders, seconds: 9) }
        shot("14-invaders")

        let astro = arcade.previewSession(.astro, engine: AstroEngine(seed: 5))
        if let e = astro.engine as? AstroEngine { autopilotAstro(e, session: astro, seconds: 6) }
        shot("15-astro")

        let trails = arcade.previewSession(.trails, engine: TrailsEngine(seed: 3))
        if let e = trails.engine as? TrailsEngine { autopilotTrails(e, session: trails, seconds: 4.5) }
        shot("16-trails")

        let stack = arcade.previewSession(.stack, engine: StackEngine(seed: 11))
        if let e = stack.engine as? StackEngine { autopilotStack(e, session: stack, pieces: 30) }
        shot("17-stack")

        let twenty48 = arcade.previewSession(.twenty48)
        if let e = twenty48.engine as? Twenty48Engine {
            let moves: [GameKey] = [.left, .down, .right, .down]
            for i in 0..<140 where e.phase != .over { twenty48.press(moves[i % 4], isRepeat: false) }
            settle(twenty48, seconds: 0.5)
        }
        shot("18-2048")

        let gems = arcade.previewSession(.gems, engine: GemsEngine(seed: 21))
        if let e = gems.engine as? GemsEngine { autoplayGems(e, session: gems, moves: 6) }
        shot("19-gems")

        let sudoku = arcade.previewSession(.sudoku, engine: SudokuEngine(seed: 4, difficulty: .medium))
        if let e = sudoku.engine as? SudokuEngine { autoplaySudoku(e, session: sudoku) }
        shot("20-sudoku")

        let mines = arcade.previewSession(.mines)
        if let e = mines.engine as? MinesEngine { autoplayMines(e, session: mines) }
        shot("21-mines")

        let solitaire = arcade.previewSession(.solitaire)
        if let e = solitaire.engine as? SolitaireEngine { autoplaySolitaire(e, session: solitaire) }
        shot("22-solitaire")

        let lexi = arcade.previewSession(.lexi, engine: LexiEngine(seed: 12))
        if let e = lexi.engine as? LexiEngine { autoplayLexi(e, session: lexi, solve: false) }
        shot("23-lexi")

        let typer = arcade.previewSession(.typer, engine: TyperEngine(seed: 8))
        if let e = typer.engine as? TyperEngine { autoplayTyper(e, session: typer) }
        shot("24-typer")

        var clock = 100.0
        let reactionEngine = ReactionEngine(seed: 3, now: { clock })
        let reaction = arcade.previewSession(.reaction, engine: reactionEngine)
        for ms in [231, 198, 264, 176, 187] {
            reaction.press(.primary, isRepeat: false)
            clock += 6
            reaction.tick(1.0 / 60)
            clock += Double(ms) / 1000
            reaction.press(.primary, isRepeat: false)
        }
        shot("25-reaction")

        let four = arcade.previewSession(.four, engine: FourEngine(seed: 2))
        if let e = four.engine as? FourEngine { autoplayFour(e, session: four) }
        shot("26-four")

        let miner = arcade.previewSession(.miner)
        if let e = miner.engine as? MinerEngine {
            e.dismissOfflineBanner()
            for _ in 0..<7 { e.mine() }
            settle(miner, seconds: 0.25)
        }
        shot("27-miner")

        let farm = arcade.previewSession(.farm)
        settle(farm, seconds: 0.2)
        shot("28-farm")

        for (index, mini) in ArcadeMini.allCases.enumerated() {
            let session = arcade.previewSession(.arcade, engine: ArcadeEngine(featured: mini))
            autoplayArcade(session)
            shot("3\(index)-arcade-\(mini.rawValue)")
        }

        // A finished run with a new personal best.
        let over = arcade.previewSession(.snake)
        if let e = over.engine as? SnakeEngine {
            autopilotSnake(e, session: over, apples: 42)
            for _ in 0..<(120 * 20) where e.phase == .playing { over.tick(1.0 / 120) }
            settle(over, seconds: 0.8)
        }
        shot("40-game-over")

        let solved = arcade.previewSession(.lexi, engine: LexiEngine(seed: 30))
        if let e = solved.engine as? LexiEngine { autoplayLexi(e, session: solved, solve: true) }
        shot("41-lexi-solved")

        let daily = arcade.previewSession(arcade.daily.game, daily: true)
        settle(daily, seconds: 0.1)
        shot("42-daily-ready")

        for (i, tab) in TrophiesTab.allCases.enumerated() {
            arcade.trophiesTab = tab
            arcade.previewState(mode: .trophies)
            shot("5\(i)-trophies-\(tab.rawValue.lowercased())")
        }
        arcade.trophiesTab = .achievements

        renderShareCard(arcade, to: folder)
    }

    // MARK: Rendering

    static func render(_ name: String, arcade: ArcadeController, to folder: URL) {
        let panel = arcade.panelSize
        let stage = PreviewStage(arcade: arcade, panel: panel)
            .frame(width: 1100, height: panel.height + 24)
            .environment(\.previewRendering, true)
            .environment(\.colorScheme, .dark)
        write(stage, scale: 2, to: folder.appendingPathComponent("\(name).png"))
    }

    static func renderShareCard(_ arcade: ArcadeController, to folder: URL) {
        let card = ShareCardView(board: "runner", value: 18_420, isBest: true, player: arcade.save.profile.displayName, daily: false)
        write(card, scale: 1, to: folder.appendingPathComponent("60-share-card.png"))
    }

    static func write<V: View>(_ view: V, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else {
            print("preview: failed to render \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("preview: wrote \(url.lastPathComponent)")
    }

    // MARK: Seed data

    static func seed(_ arcade: ArcadeController) {
        let now = Date()
        let cal = Calendar.current
        var save = ArcadeSave(profile: PlayerProfile(id: "PLAYER-7X42", nickname: "neonfox"))
        let runs: [(String, Int, Double)] = [
            ("runner", 8_820, -3), ("runner", 4_210, 0), ("runner", 3_120, 0), ("runner", 1_980, 0),
            ("snake", 380, 0), ("snake", 240, -1), ("pong", 27, -2), ("breakout", 2_340, 0),
            ("twenty48", 12_840, -1), ("mines", 48_200, -2), ("reaction", 172, 0), ("reaction", 214, -1),
            ("solitaire", 151_000, -4), ("arcade.flap", 23, 0), ("arcade.dodge", 640, -1), ("arcade.echo", 9, -2),
            ("stack", 18_400, 0), ("stack", 9_250, -1), ("lexi", 400, 0), ("lexi", 300, -1), ("typer", 74, -1),
            ("arcade.lander", 410, -2),
        ]
        for (board, value, days) in runs {
            save.scores.record(value, board: board, at: now.addingTimeInterval(days * 86_400 - 3_600))
            save.stats.noteScore(value, board: board)
        }
        save.stats.gamesPlayed = 86
        save.stats.gameLaunches = 112
        save.stats.escExits = 71
        save.stats.playSeconds = 5_420
        save.stats.plays = ["runner": 31, "snake": 18, "pong": 6, "breakout": 9, "twenty48": 7, "reaction": 12, "solitaire": 3, "stack": 14, "lexi": 9, "typer": 4]
        for game in [GameID.runner, .lexi, .snake, .twenty48, .stack] { save.stats.noteLaunch(game) }
        for back in 1...2 {
            if let day = cal.date(byAdding: .day, value: -back, to: now) {
                save.stats.markDaily(DayKey.key(for: day))
            }
        }
        for id in ["runner.first", "runner.100", "snake.hungry", "pong.win", "reaction.250", "reaction.180", "general.speedrunner", "mines.win", "2048.512"] {
            save.achievements[id] = now
        }
        var miner = MinerState(now: now)
        miner.coins = 14_820
        miner.lifetime = 52_300
        miner.pickaxe = 9
        miner.workers = 4
        miner.speed = 3
        miner.storage = 2
        miner.hits = 7
        save.miner = miner
        var farm = FarmState()
        farm.coins = 640
        farm.unlocked = 6
        let crops: [(Crop, Double)] = [(.wheat, 40), (.carrot, 70), (.tomato, 60), (.pumpkin, 300), (.starfruit, 2_900), (.carrot, 5)]
        for (i, entry) in crops.enumerated() {
            farm.plots[i] = FarmPlot(crop: entry.0, plantedAt: now.addingTimeInterval(-entry.1))
        }
        save.farm = farm
        // Anything the seed data already earns counts as unlocked, so no toasts fire mid-shot.
        for achievement in AchievementCatalog.newlyUnlocked(stats: save.stats, unlocked: Set(save.achievements.keys)) {
            save.achievements[achievement.id] = now
        }
        arcade.save = save
    }

    // MARK: Autopilots

    static func settle(_ session: GameSession, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { session.tick(1.0 / 120) }
    }

    static func autopilotRunner(_ e: RunnerEngine, session: GameSession, seconds: Double) {
        session.press(.primary, isRepeat: false)
        session.release(.primary)
        for _ in 0..<Int(seconds * 120) {
            guard e.phase == .playing else { break }
            let p = e.player
            let ahead = e.obstacles.first { $0.box.maxX > p.x - 2 && $0.box.minX - (p.x + 22) < e.speed * 0.2 }
            if let o = ahead, o.kind == .drone {
                session.input.press(.down)
            } else {
                session.input.release(.down)
                if let o = ahead, o.kind != .drone, p.onGround {
                    session.press(.primary, isRepeat: false)
                } else if p.vy > 0 {
                    session.release(.primary)
                }
            }
            session.tick(1.0 / 120)
        }
    }

    static func autopilotSnake(_ e: SnakeEngine, session: GameSession, apples: Int) {
        session.press(.right, isRepeat: false)
        var frames = 0
        var lastSteps = -1
        while e.phase == .playing && e.apples < apples && frames < 120 * 90 {
            // Decide once per grid step, right after the snake moved.
            let stepID = e.body.count * 10_000 + e.body[0].x * 100 + e.body[0].y
            if stepID != lastSteps {
                lastSteps = stepID
                if let pick = bestDirection(e), pick != e.direction {
                    session.press(GameKey.from(pick), isRepeat: false)
                }
            }
            session.tick(1.0 / 120)
            frames += 1
        }
        // Stop between two cells for a smooth frame.
        for _ in 0..<6 where e.phase == .playing { session.tick(1.0 / 120) }
    }

    /// Greedy toward the apple, but never into a pocket smaller than the snake.
    static func bestDirection(_ e: SnakeEngine) -> Direction? {
        let head = e.body[0]
        let a = e.arena
        let blocked = Set(e.body.dropLast())
        func inside(_ p: GridPoint) -> Bool { p.x >= a.minX && p.x <= a.maxX && p.y >= a.minY && p.y <= a.maxY }
        func space(from start: GridPoint) -> Int {
            var seen: Set<GridPoint> = [start]
            var queue = [start]
            var i = 0
            while i < queue.count && seen.count < 400 {
                let p = queue[i]
                i += 1
                for d in Direction.allCases {
                    let n = GridPoint(p.x + d.delta.x, p.y + d.delta.y)
                    if inside(n) && !blocked.contains(n) && !seen.contains(n) {
                        seen.insert(n)
                        queue.append(n)
                    }
                }
            }
            return seen.count
        }
        var best: (Direction, Int, Int)?
        for d in Direction.allCases where d != e.direction.opposite {
            let n = GridPoint(head.x + d.delta.x, head.y + d.delta.y)
            guard inside(n), !blocked.contains(n) else { continue }
            let room = space(from: n)
            let distance = abs(n.x - e.apple.x) + abs(n.y - e.apple.y)
            let roomy = room >= e.body.count + 4 ? 1 : 0
            if let b = best {
                let bRoomy = b.1 >= e.body.count + 4 ? 1 : 0
                if roomy > bRoomy || (roomy == bRoomy && (roomy == 1 ? distance < b.2 : room > b.1)) {
                    best = (d, room, distance)
                }
            } else {
                best = (d, room, distance)
            }
        }
        return best?.0
    }

    static func autopilotPong(_ e: PongEngine, session: GameSession, seconds: Double) {
        session.press(.up, isRepeat: false)
        for _ in 0..<Int(seconds * 120) {
            guard e.phase == .playing else { break }
            let target = e.ballVelocity.x < 0 ? e.ball.y : PongEngine.height / 2
            if target < e.player.y - 8 {
                session.input.press(.up)
                session.input.release(.down)
            } else if target > e.player.y + 8 {
                session.input.press(.down)
                session.input.release(.up)
            } else {
                session.input.release(.up)
                session.input.release(.down)
            }
            session.tick(1.0 / 120)
        }
    }

    static func autopilotBreakout(_ e: BreakoutEngine, session: GameSession, seconds: Double) {
        session.press(.primary, isRepeat: false)
        for _ in 0..<Int(seconds * 120) {
            guard e.phase == .playing else { break }
            if e.balls.contains(where: \.stuck) { session.press(.primary, isRepeat: false) }
            let target = e.balls.max { $0.position.y < $1.position.y }?.position.x ?? BreakoutEngine.width / 2
            if target < e.paddleX - 10 {
                session.input.press(.left)
                session.input.release(.right)
            } else if target > e.paddleX + 10 {
                session.input.press(.right)
                session.input.release(.left)
            } else {
                session.input.release(.left)
                session.input.release(.right)
            }
            session.tick(1.0 / 120)
        }
    }

    static func autoplayMines(_ e: MinesEngine, session: GameSession) {
        e.setCursor(9, 4)
        session.press(.confirm, isRepeat: false)
        var flagged = 0
        for y in 0..<MinesEngine.rows {
            for x in 0..<MinesEngine.columns {
                let cell = e.cell(x, y)
                guard cell.state == .hidden else { continue }
                if cell.isMine, flagged < 5, x > 3, x < 16 {
                    e.toggleFlag(x, y)
                    flagged += 1
                } else if !cell.isMine, (x + y) % 5 == 0, x > 2, x < 17 {
                    e.reveal(x, y)
                }
            }
        }
        e.setCursor(12, 3)
        settle(session, seconds: 1.2)
    }

    static func autoplaySolitaire(_ e: SolitaireEngine, session: GameSession) {
        for _ in 0..<60 {
            var moved = false
            for t in 0..<7 where !moved {
                for f in 0..<4 where !moved {
                    moved = e.move(from: .tableau(t), count: 1, to: .foundation(f))
                }
            }
            for f in 0..<4 where !moved {
                moved = e.move(from: .waste, count: 1, to: .foundation(f))
            }
            for t in 0..<7 where !moved {
                moved = e.move(from: .waste, count: 1, to: .tableau(t))
            }
            for from in 0..<7 where !moved {
                let run = e.faceUpCount(.tableau(from))
                guard run > 0, run < e.board.tableau[from].count || e.board.tableau[from].first?.rank != 13 else { continue }
                for to in 0..<7 where !moved && to != from {
                    moved = e.move(from: .tableau(from), count: run, to: .tableau(to))
                }
            }
            if !moved { e.draw() }
        }
        e.handle(.right, isRepeat: false)
        e.handle(.right, isRepeat: false)
        settle(session, seconds: 2)
    }

    static func autoplayArcade(_ session: GameSession) {
        guard let cabinet = session.engine as? ArcadeEngine else { return }
        switch cabinet.current {
        case let flap as FlapEngine:
            session.press(.primary, isRepeat: false)
            for _ in 0..<(120 * 6) where flap.phase == .playing {
                let next = flap.pipes.first { $0.x + FlapEngine.pipeWidth > FlapEngine.birdX - 10 }
                let target = next?.gapY ?? FlapEngine.height / 2
                if flap.birdY > target + 20 && flap.velocity > 0 { session.press(.primary, isRepeat: false) }
                session.tick(1.0 / 120)
            }
        case let dodge as DodgeEngine:
            session.press(.primary, isRepeat: false)
            for _ in 0..<(120 * 9) where dodge.phase == .playing {
                let threat = dodge.rocks.filter { !$0.isGem && $0.position.y > 120 }.min { abs($0.position.x - dodge.playerX) < abs($1.position.x - dodge.playerX) }
                session.input.release(.left)
                session.input.release(.right)
                if let threat, abs(threat.position.x - dodge.playerX) < 40 {
                    session.input.press(threat.position.x > dodge.playerX ? .left : .right)
                }
                session.tick(1.0 / 120)
            }
        case let bullseye as BullseyeEngine:
            session.press(.primary, isRepeat: false)
            for _ in 0..<5 {
                var guardCount = 0
                while abs(bullseye.needle - bullseye.zoneCenter) > bullseye.zoneWidth * 0.1 && guardCount < 4_000 {
                    session.tick(1.0 / 240)
                    guardCount += 1
                }
                session.press(.primary, isRepeat: false)
            }
            for _ in 0..<40 { session.tick(1.0 / 120) }
        case let echo as EchoEngine:
            session.press(.primary, isRepeat: false)
            for _ in 0..<4 {
                var guardCount = 0
                while echo.stage != .input && guardCount < 2_000 {
                    session.tick(1.0 / 120)
                    guardCount += 1
                }
                for pad in echo.sequence {
                    session.press([GameKey.up, .right, .down, .left][pad], isRepeat: false)
                }
            }
            for _ in 0..<70 { session.tick(1.0 / 120) }
        case let lander as LanderEngine:
            session.press(.up, isRepeat: false)
            session.release(.up)
            for _ in 0..<(120 * 3) where lander.phase == .playing {
                // Hover-ish: burn when falling fast, drift toward the nearest pad.
                session.input.release(.up)
                session.input.release(.left)
                session.input.release(.right)
                if lander.velocity.y > 14 { session.input.press(.up) }
                if let pad = lander.pads.min(by: { abs(($0.x0 + $0.x1) / 2 - lander.position.x) < abs(($1.x0 + $1.x1) / 2 - lander.position.x) }) {
                    let dx = (pad.x0 + pad.x1) / 2 - lander.position.x
                    let wantAngle = max(-0.3, min(0.3, dx * 0.004 - lander.velocity.x * 0.01))
                    if lander.angle < wantAngle - 0.03 { session.input.press(.right) } else if lander.angle > wantAngle + 0.03 { session.input.press(.left) }
                }
                session.tick(1.0 / 120)
            }
            session.input.clear()
        case let hop as HopEngine:
            session.press(.primary, isRepeat: false)
            var hops = 0
            for _ in 0..<(120 * 8) where hop.phase == .playing && hop.deathAt == nil && hops < 5 {
                // Hop up only when the lane ahead stays clear for a moment.
                let row = hop.frogRow - 1
                let lane = hop.lanes[row]
                let clear = lane.movers.allSatisfy { m in
                    let ahead = m.x + lane.speed * 0.25
                    return hop.frogX + 14 < min(m.x, ahead) - 4 || hop.frogX - 14 > max(m.x, ahead) + m.width + 4
                }
                if clear {
                    session.press(.up, isRepeat: false)
                    hops += 1
                    for _ in 0..<20 { session.tick(1.0 / 120) }
                }
                session.tick(1.0 / 120)
            }
            for _ in 0..<6 { session.tick(1.0 / 120) }
        default:
            break
        }
    }
}

extension PreviewRenderer {
    static func autopilotInvaders(_ e: InvadersEngine, session: GameSession, seconds: Double) {
        session.press(.primary, isRepeat: false)
        session.release(.primary)
        var fire = 0.0
        for frame in 0..<Int(seconds * 120) {
            guard e.phase == .playing else { break }
            // Chase the lowest alien in the nearest column.
            let targets = e.aliens.filter(\.alive).map { e.alienBox($0) }
            let target = targets.min { abs($0.midX - e.playerX) < abs($1.midX - e.playerX) }?.midX ?? InvadersEngine.width / 2
            session.input.release(.left)
            session.input.release(.right)
            if target < e.playerX - 4 { session.input.press(.left) } else if target > e.playerX + 4 { session.input.press(.right) }
            fire += 1.0 / 120
            if fire > 0.32 {
                fire = 0
                session.press(.primary, isRepeat: false)
                session.release(.primary)
            }
            session.tick(1.0 / 120)
            if frame % 240 == 0 { session.input.clear() }
        }
        session.input.clear()
    }

    static func autopilotAstro(_ e: AstroEngine, session: GameSession, seconds: Double) {
        session.press(.primary, isRepeat: false)
        session.release(.primary)
        var fire = 0.0
        let frames = Int(seconds * 120)
        for frame in 0..<frames {
            guard e.phase == .playing else { break }
            session.input.release(.left)
            session.input.release(.right)
            session.input.release(.up)
            if let rock = e.rocks.min(by: { distance(e.ship.position, $0.position) < distance(e.ship.position, $1.position) }) {
                let want = atan2(rock.position.y - e.ship.position.y, rock.position.x - e.ship.position.x)
                var diff = want - e.ship.angle
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                if diff > 0.08 { session.input.press(.right) } else if diff < -0.08 { session.input.press(.left) }
                fire += 1.0 / 120
                if abs(diff) < 0.2 && fire > 0.25 {
                    fire = 0
                    session.press(.primary, isRepeat: false)
                    session.release(.primary)
                }
            }
            // Thrust near the end so the flame shows.
            if frame > frames - 50 { session.input.press(.up) }
            session.tick(1.0 / 120)
        }
    }

    static func distance(_ a: Vec2, _ b: Vec2) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    static func autopilotTrails(_ e: TrailsEngine, session: GameSession, seconds: Double) {
        session.press(.up, isRepeat: false)
        session.release(.up)
        var lastHead: GridPoint?
        for _ in 0..<Int(seconds * 120) {
            guard e.phase == .playing, let me = e.bikes.first, me.alive else { break }
            if me.head != lastHead {
                lastHead = me.head
                var blocked = Set<GridPoint>()
                for bike in e.bikes { blocked.formUnion(bike.path) }
                func free(_ p: GridPoint) -> Bool {
                    p.x >= 0 && p.y >= 0 && p.x < TrailsEngine.columns && p.y < TrailsEngine.rows && !blocked.contains(p)
                }
                func room(_ start: GridPoint) -> Int {
                    guard free(start) else { return -1 }
                    var seen: Set<GridPoint> = [start]
                    var queue = [start]
                    var i = 0
                    while i < queue.count && seen.count < 300 {
                        let p = queue[i]
                        i += 1
                        for d in Direction.allCases {
                            let n = GridPoint(p.x + d.delta.x, p.y + d.delta.y)
                            if free(n) && !seen.contains(n) {
                                seen.insert(n)
                                queue.append(n)
                            }
                        }
                    }
                    return seen.count
                }
                let options = Direction.allCases.filter { $0 != me.direction.opposite }
                let scored = options.map { d -> (Direction, Int) in
                    let n = GridPoint(me.head.x + d.delta.x, me.head.y + d.delta.y)
                    // Prefer going straight when it's just as roomy, for clean lines.
                    return (d, room(n) * 4 + (d == me.direction ? 2 : 0))
                }
                if let best = scored.max(by: { $0.1 < $1.1 }), best.0 != me.direction {
                    session.press(GameKey.from(best.0), isRepeat: false)
                    session.release(GameKey.from(best.0))
                }
            }
            session.tick(1.0 / 120)
        }
    }

    static func autopilotStack(_ e: StackEngine, session: GameSession, pieces: Int) {
        session.press(.primary, isRepeat: false)
        session.release(.primary)
        settle(session, seconds: 0.1)
        let cols = StackEngine.columns, rows = StackEngine.totalRows
        for _ in 0..<pieces {
            guard e.phase == .playing, let piece = e.current else { break }
            var board = e.board.map { $0.map { $0 != nil } }
            var best: (rotation: Int, x: Int, score: Double)?
            for rotation in 0..<4 {
                let shape = piece.kind.cells(rotation: rotation)
                let minX = shape.map(\.x).min() ?? 0, maxX = shape.map(\.x).max() ?? 0
                for x in (-minX)..<(cols - maxX) {
                    var y = 0
                    func fits(_ y: Int) -> Bool {
                        shape.allSatisfy { c in
                            let cx = c.x + x, cy = c.y + y
                            return cx >= 0 && cx < cols && cy < rows && (cy < 0 || !board[cy][cx])
                        }
                    }
                    guard fits(0) else { continue }
                    while fits(y + 1) { y += 1 }
                    for c in shape { board[c.y + y][c.x + x] = true }
                    let score = evaluate(board)
                    for c in shape { board[c.y + y][c.x + x] = false }
                    if best == nil || score > best!.score { best = (rotation, x, score) }
                }
            }
            guard let plan = best else { break }
            for _ in 0..<plan.rotation {
                session.press(.up, isRepeat: false)
                session.release(.up)
            }
            // The piece's x is the box origin; shift until it matches the plan.
            var guardCount = 0
            while let current = e.current, current.x != plan.x, guardCount < 12 {
                let key: GameKey = current.x > plan.x ? .left : .right
                session.press(key, isRepeat: false)
                session.release(key)
                guardCount += 1
            }
            session.press(.primary, isRepeat: false)
            session.release(.primary)
            settle(session, seconds: 0.4)
        }
        // Let the next piece drop a little so the ghost shows.
        settle(session, seconds: 0.6)
    }

    static func evaluate(_ full: [[Bool]]) -> Double {
        // Clear completed lines first, the way the engine will.
        let cols = full.first?.count ?? 0
        let kept = full.filter { !$0.allSatisfy { $0 } }
        let lines = full.count - kept.count
        let board = Array(repeating: Array(repeating: false, count: cols), count: lines) + kept
        let rows = board.count
        var heights = Array(repeating: 0, count: cols)
        var holes = 0
        for x in 0..<cols {
            var seen = false
            for y in 0..<rows {
                if board[y][x] {
                    if !seen { heights[x] = rows - y; seen = true }
                } else if seen {
                    holes += 1
                }
            }
        }
        let bumpiness = zip(heights, heights.dropFirst()).map { abs($0 - $1) }.reduce(0, +)
        return -0.51 * Double(heights.reduce(0, +)) + 0.76 * Double(lines) - 0.36 * Double(holes) - 0.18 * Double(bumpiness)
    }

    static func autoplayGems(_ e: GemsEngine, session: GameSession, moves: Int) {
        for _ in 0..<moves {
            guard e.phase != .over, let move = e.findMove() else { break }
            e.select(move.0)
            e.select(move.1)
            var guardCount = 0
            repeat {
                session.tick(1.0 / 120)
                guardCount += 1
            } while e.isBusy && guardCount < 120 * 6
        }
        if let move = e.findMove() { e.select(move.0) }
        settle(session, seconds: 0.2)
    }

    static func autoplaySudoku(_ e: SudokuEngine, session: GameSession) {
        var filled = 0
        for i in 0..<81 where !e.isGiven(i) && (i * 7) % 3 != 0 {
            e.select(i % 9, i / 9)
            session.press(.number(e.solution[i]), isRepeat: false)
            filled += 1
            if filled > 22 { break }
            session.tick(1.0 / 60)
        }
        // A few pencil marks.
        session.press(.flag, isRepeat: false)
        var noted = 0
        for i in 0..<81 where e.value(i) == 0 && noted < 3 {
            e.select(i % 9, i / 9)
            for n in [e.solution[i], (e.solution[i] % 9) + 1] { session.press(.number(n), isRepeat: false) }
            noted += 1
        }
        session.press(.flag, isRepeat: false)
        settle(session, seconds: 34)
        if let i = (0..<81).first(where: { !e.isGiven($0) && e.value($0) != 0 }) { e.select(i % 9, i / 9) }
        settle(session, seconds: 1.2)
    }

    static func typeWord(_ word: String, into session: GameSession) {
        for c in word {
            session.press(.char(c), isRepeat: false)
            session.release(.char(c))
            session.tick(1.0 / 60)
        }
    }

    static func autoplayLexi(_ e: LexiEngine, session: GameSession, solve: Bool) {
        let answer = Array(e.answer)
        // Guesses that share letters with the answer, for a colourful board.
        func overlap(_ word: String) -> Int {
            LexiEngine.mark(word, against: e.answer).map { $0 == .correct ? 3 : ($0 == .present ? 1 : 0) }.reduce(0, +)
        }
        let pool = WordList.shared.answers.filter { $0 != e.answer }
        let first = pool.filter { overlap($0) <= 2 }.max { overlap($0) < overlap($1) } ?? pool[0]
        let second = pool.filter { $0 != first && overlap($0) >= 4 && overlap($0) < 9 }.first ?? pool[1]
        for guess in [first, second] {
            typeWord(guess, into: session)
            session.press(.confirm, isRepeat: false)
            settle(session, seconds: 2)
        }
        if solve {
            typeWord(e.answer, into: session)
            session.press(.confirm, isRepeat: false)
            settle(session, seconds: 4.5)
        } else {
            typeWord(String(answer.prefix(2)) + "r", into: session)
            settle(session, seconds: 0.2)
        }
    }

    static func autoplayTyper(_ e: TyperEngine, session: GameSession) {
        for w in 0..<15 {
            var word = e.currentWord
            if w == 5 { word = String(word.dropLast()) + "q" }
            for c in word {
                session.press(.char(c), isRepeat: false)
                for _ in 0..<15 { session.tick(1.0 / 120) }
            }
            session.press(.primary, isRepeat: false)
            for _ in 0..<10 { session.tick(1.0 / 120) }
        }
        for c in e.currentWord.prefix(2) {
            session.press(.char(c), isRepeat: false)
            for _ in 0..<12 { session.tick(1.0 / 120) }
        }
    }

    /// Four in a row for `owner` anywhere on a 7×6 board.
    static func fourWins(_ b: [Int], _ owner: Int) -> Bool {
        let cols = FourEngine.columns, rows = FourEngine.rows
        for r in 0..<rows {
            for c in 0..<cols {
                for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                    let cells = (0..<4).map { (c + dc * $0, r + dr * $0) }
                    if cells.allSatisfy({ $0.0 >= 0 && $0.0 < cols && $0.1 >= 0 && $0.1 < rows && b[$0.1 * cols + $0.0] == owner }) { return true }
                }
            }
        }
        return false
    }

    /// Win if possible, block if needed, otherwise play near the centre.
    static func fourPick(_ e: FourEngine, preferring order: [Int]) -> Int {
        for owner in [1, 2] {
            for c in 0..<FourEngine.columns {
                guard let r = e.landingRow(c) else { continue }
                var b = e.board
                b[r * FourEngine.columns + c] = owner
                if fourWins(b, owner) { return c }
            }
        }
        return order.first { e.landingRow($0) != nil } ?? 3
    }

    static func autoplayFour(_ e: FourEngine, session: GameSession) {
        for preferred in [[3], [2, 4], [4, 2], [5, 1], [1, 5]] {
            guard e.phase != .over, e.result == nil else { break }
            let column = fourPick(e, preferring: preferred + [3, 2, 4, 1, 5, 0, 6])
            e.choose(column: column)
            session.press(.primary, isRepeat: false)
            var guardCount = 0
            repeat {
                session.tick(1.0 / 120)
                guardCount += 1
            } while (e.turn != .player || e.drop != nil) && e.result == nil && guardCount < 120 * 4
        }
        e.choose(column: 5)
        settle(session, seconds: 0.3)
    }
}

private extension GameKey {
    static func from(_ d: Direction) -> GameKey {
        switch d {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

/// A slice of desktop with a menu bar, with the notch panel on top.
struct PreviewStage: View {
    let arcade: ArcadeController
    let panel: CGSize

    var body: some View {
        let h = arcade.metrics.notchHeight
        ZStack(alignment: .top) {
            // Wallpaper
            LinearGradient(colors: [Color(hex: 0x1B2B5E), Color(hex: 0x3C1F5C), Color(hex: 0x0E1230)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(hex: 0xFF6FB5).opacity(0.35)).frame(width: 520).blur(radius: 120).offset(x: -320, y: 240)
            Circle().fill(Color(hex: 0x4FB8FF).opacity(0.3)).frame(width: 460).blur(radius: 110).offset(x: 340, y: 120)

            // Menu bar
            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                Text("Code").bold()
                ForEach(["File", "Edit", "Selection", "View", "Go"], id: \.self) { Text($0) }
                Spacer()
                ForEach(["wifi", "battery.75percent", "magnifyingglass"], id: \.self) { Image(systemName: $0) }
                Text("Wed 1 Oct  9:41")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 18)
            .frame(height: h)
            .background(Color.black.opacity(0.28))

            NotchRootView(arcade: arcade)
                .frame(width: panel.width, height: panel.height)
        }
        .clipped()
    }
}
