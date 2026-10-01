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
            render(name, arcade: arcade, to: folder)
        }

        arcade.previewState(mode: .closed)
        shot("01-closed")

        arcade.previewState(mode: .launcher, hovered: .game(.snake), charging: .game(.snake))
        shot("02-launcher")

        arcade.previewState(mode: .closed, toast: Toast(symbol: "crown.fill", title: "Snake God", subtitle: "Achievement unlocked", colors: GameID.snake.style.colors))
        shot("03-toast")

        // Runner mid-jump
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

        let twenty48 = arcade.previewSession(.twenty48)
        if let e = twenty48.engine as? Twenty48Engine {
            let moves: [GameKey] = [.left, .down, .right, .down]
            for i in 0..<140 where e.phase != .over { twenty48.press(moves[i % 4], isRepeat: false) }
            settle(twenty48, seconds: 0.5)
        }
        shot("14-2048")

        let mines = arcade.previewSession(.mines)
        if let e = mines.engine as? MinesEngine { autoplayMines(e, session: mines) }
        shot("15-mines")

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
        shot("16-reaction")

        let miner = arcade.previewSession(.miner)
        if let e = miner.engine as? MinerEngine {
            e.dismissOfflineBanner()
            for _ in 0..<7 { e.mine() }
            settle(miner, seconds: 0.25)
        }
        shot("17-miner")

        let farm = arcade.previewSession(.farm)
        settle(farm, seconds: 0.2)
        shot("18-farm")

        let solitaire = arcade.previewSession(.solitaire)
        if let e = solitaire.engine as? SolitaireEngine { autoplaySolitaire(e, session: solitaire) }
        shot("19-solitaire")

        for (index, mini) in ArcadeMini.allCases.enumerated() {
            let session = arcade.previewSession(.arcade, engine: ArcadeEngine(featured: mini))
            autoplayArcade(session)
            shot("2\(index)-arcade-\(mini.rawValue)")
        }

        // A finished run with a new personal best.
        let over = arcade.previewSession(.snake)
        if let e = over.engine as? SnakeEngine {
            autopilotSnake(e, session: over, apples: 42)
            // Then stop steering and let it hit the wall.
            for _ in 0..<(120 * 20) where e.phase == .playing { over.tick(1.0 / 120) }
            settle(over, seconds: 0.8)
        }
        shot("30-game-over")

        let daily = arcade.previewSession(arcade.daily.game, daily: true)
        settle(daily, seconds: 0.1)
        shot("31-daily-ready")

        arcade.previewState(mode: .trophies)
        shot("40-trophies")

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
        write(card, scale: 1, to: folder.appendingPathComponent("50-share-card.png"))
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
        ]
        for (board, value, days) in runs {
            save.scores.record(value, board: board, at: now.addingTimeInterval(days * 86_400 - 3_600))
            save.stats.noteScore(value, board: board)
        }
        save.stats.gamesPlayed = 86
        save.stats.gameLaunches = 112
        save.stats.escExits = 71
        save.stats.playSeconds = 5_420
        save.stats.plays = ["runner": 31, "snake": 18, "pong": 6, "breakout": 9, "twenty48": 7, "reaction": 12, "solitaire": 3]
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
        default:
            break
        }
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
