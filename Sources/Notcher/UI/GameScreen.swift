import NotcherCore
import SwiftUI

/// Header in the notch band, the playfield, and a hint footer.
struct GameScreen: View {
    let arcade: ArcadeController
    let session: GameSession

    /// Playfield size per game. Board games with many rows get a taller field.
    static func fieldSize(for game: GameID) -> CGSize {
        switch game {
        case .solitaire: return CGSize(width: 680, height: 340)
        case .stack, .sudoku, .lexi: return CGSize(width: 640, height: 300)
        default: return CGSize(width: 640, height: 240)
        }
    }

    var body: some View {
        let m = arcade.metrics
        let field = Self.fieldSize(for: session.game)
        VStack(spacing: 0) {
            header(m)
                .frame(height: m.notchHeight)
                .padding(.top, m.hasNotch ? 0 : 2)

            playfield(field)
                .padding(.top, 8)

            footer
                .frame(height: 30)
        }
        .frame(width: field.width)
    }

    // MARK: Header

    private func header(_ m: NotchMetrics) -> some View {
        let style = session.game.style
        let board = session.boardKey
        return HStack(spacing: 0) {
            HStack(spacing: 7) {
                GameGlyph(game: session.game, size: 15)
                Text(title.uppercased())
                    .font(Theme.rounded(12, .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.primary)
                if session.isDaily {
                    Chip(text: "DAILY", colors: [Color(hex: 0xFFB340), Color(hex: 0xFF375F)], foreground: .black)
                }
            }
            Spacer(minLength: m.notchWidth + 24)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if session.game.hasScores, let best = arcade.save.scores.best(board) {
                    Text("BEST \(Format.score(best, board: board))")
                        .font(Theme.mono(9.5, .bold))
                        .foregroundStyle(Theme.tertiary)
                }
                scoreView
                    .foregroundStyle(LinearGradient(colors: [.white, style.accent], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private var title: String {
        BoardInfo.title(for: session.boardKey)
    }

    @ViewBuilder private var scoreView: some View {
        switch session.game {
        case .miner:
            HStack(spacing: 4) {
                Image(systemName: "diamond.fill").font(.system(size: 10, weight: .bold))
                ScoreText(value: session.score, format: .points)
            }
        case .farm:
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill").font(.system(size: 10, weight: .bold))
                ScoreText(value: session.score, format: .points)
            }
        case .mines:
            HStack(spacing: 10) {
                if let mines = session.engine as? MinesEngine {
                    HStack(spacing: 3) {
                        Image(systemName: "flag.fill").font(.system(size: 9, weight: .bold))
                        Text("\(mines.minesLeft)").font(Theme.mono(13, .bold))
                    }
                    .opacity(0.8)
                }
                ScoreText(value: session.score, format: .duration)
            }
        case .reaction:
            if let best = (session.engine as? ReactionEngine)?.best {
                ScoreText(value: best, format: .milliseconds)
            } else {
                Text("— ms").font(Theme.mono(15, .bold))
            }
        default:
            ScoreText(value: session.score, format: session.game.scoreFormat)
        }
    }

    // MARK: Playfield

    private func playfield(_ size: CGSize) -> some View {
        let overlayActive = session.phase == .paused || (session.phase == .over && showsOverCard)
        return ZStack {
            Theme.field
            LivePlayfield(session: session, size: size, dimmed: overlayActive)

            overlay
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)
        )
        .animation(.easeOut(duration: 0.18), value: overlayActive)
    }

    private var showsOverCard: Bool {
        switch session.game {
        case .reaction, .miner, .farm: return false
        default: return true
        }
    }

    @ViewBuilder private var overlay: some View {
        switch session.phase {
        case .ready:
            if let start = startHint {
                ReadyCard(session: session, startKeys: start)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        case .paused:
            PausedCard(textInput: session.engine.acceptsText)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .over:
            if showsOverCard {
                GameOverCard(arcade: arcade, session: session)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        case .playing:
            EmptyView()
        }
    }

    /// The key that starts a run, or nil when the game shows its own intro.
    private var startHint: (keys: String, action: String)? {
        switch session.game {
        case .runner: return ("space", "to run")
        case .snake: return ("↑↓←→", "to slither")
        case .pong: return ("↑↓", "to serve")
        case .breakout: return ("space", "to launch")
        case .arcade:
            switch (session.engine as? ArcadeEngine)?.mini {
            case .dodge: return ("←→", "to start")
            case .echo: return ("space", "to start")
            default: return ("space", "to start")
            }
        case .invaders, .astro, .stack: return ("space", "to start")
        case .trails: return ("↑↓←→", "to ride")
        case .twenty48, .mines, .solitaire, .reaction, .miner, .farm, .gems, .sudoku, .lexi, .typer, .four:
            return nil
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HintRow(hints: session.game.controls)
            Spacer(minLength: 8)
            if session.phase == .playing && session.game.category != .idle && !session.engine.acceptsText {
                HintLabel(keys: "P", action: "pause")
            }
            HintLabel(keys: "esc", action: "back to work")
        }
        .padding(.horizontal, 4)
    }
}

/// The only view that observes `revision`, so per-frame redraws stay local.
struct LivePlayfield: View {
    let session: GameSession
    let size: CGSize
    let dimmed: Bool

    var body: some View {
        let revision = session.revision
        let shake = session.engine.shake
        let t = session.engine.clock
        GameContent(session: session, revision: revision, size: size)
            .blur(radius: dimmed ? 6 : 0)
            .saturation(dimmed ? 0.5 : 1)
            .offset(x: shake > 0 ? sin(t * 70) * shake * 6 : 0, y: shake > 0 ? cos(t * 55) * shake * 4 : 0)
    }
}

/// Picks the right view for the engine. `revision` forces a redraw.
struct GameContent: View {
    let session: GameSession
    let revision: Int
    let size: CGSize

    var body: some View {
        switch session.engine {
        case let e as RunnerEngine: RunnerView(engine: e, revision: revision)
        case let e as SnakeEngine: SnakeView(engine: e, revision: revision)
        case let e as PongEngine: PongView(engine: e, revision: revision)
        case let e as BreakoutEngine: BreakoutView(engine: e, revision: revision)
        case let e as Twenty48Engine: Twenty48View(session: session, engine: e, revision: revision)
        case let e as MinesEngine: MinesView(session: session, engine: e, revision: revision)
        case let e as ReactionEngine: ReactionView(engine: e, revision: revision)
        case let e as MinerEngine: MinerView(session: session, engine: e, revision: revision)
        case let e as FarmEngine: FarmView(session: session, engine: e, revision: revision)
        case let e as SolitaireEngine: SolitaireView(session: session, engine: e, revision: revision)
        case let e as ArcadeEngine: ArcadeView(session: session, engine: e, revision: revision)
        case let e as InvadersEngine: InvadersView(engine: e, revision: revision)
        case let e as AstroEngine: AstroView(engine: e, revision: revision)
        case let e as TrailsEngine: TrailsView(engine: e, revision: revision)
        case let e as StackEngine: StackView(engine: e, revision: revision)
        case let e as GemsEngine: GemsView(session: session, engine: e, revision: revision)
        case let e as SudokuEngine: SudokuView(session: session, engine: e, revision: revision)
        case let e as LexiEngine: LexiView(session: session, engine: e, revision: revision)
        case let e as TyperEngine: TyperView(engine: e, revision: revision)
        case let e as FourEngine: FourView(session: session, engine: e, revision: revision)
        default: Color.clear
        }
    }
}

// MARK: - Overlays

struct ReadyCard: View {
    let session: GameSession
    let startKeys: (keys: String, action: String)

    var body: some View {
        let style = session.game.style
        VStack(spacing: 10) {
            if let arcade = session.engine as? ArcadeEngine, !session.boardKey.isEmpty {
                ArcadeMiniPicker(session: session, engine: arcade)
                Text(arcade.mini.tagline)
                    .font(Theme.rounded(11.5, .medium))
                    .foregroundStyle(Theme.secondary)
            } else {
                GameGlyph(game: session.game, size: 30)
                    .shadow(color: style.accent.opacity(0.6), radius: 10)
                Text(session.game.title)
                    .font(Theme.rounded(20, .heavy))
                    .foregroundStyle(Theme.primary)
                Text(session.isDaily ? (session.daily?.goal ?? "") : session.game.tagline)
                    .font(Theme.rounded(11.5, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 5) {
                Text("Press").foregroundStyle(Theme.secondary)
                Keycap(label: startKeys.keys, highlighted: true)
                Text(startKeys.action).foregroundStyle(Theme.secondary)
            }
            .font(Theme.rounded(11, .semibold))
            .padding(.top, 4)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
        )
    }
}

/// The final score, counting up when the card appears.
struct CountUpScore: View {
    let value: Int
    let format: ScoreFormat
    @State private var shown: Double = 0
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        CountingText(value: previewRendering ? Double(value) : shown, format: format)
            .onAppear {
                shown = 0
                withAnimation(.easeOut(duration: 0.75)) { shown = Double(value) }
            }
    }
}

private struct CountingText: View, Animatable {
    var value: Double
    let format: ScoreFormat

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Format.score(Int(value.rounded()), format: format))
            .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
    }
}

struct PausedCard: View {
    /// Letters type in word games, so R isn't a shortcut there.
    var textInput = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text("Paused")
                .font(Theme.rounded(18, .heavy))
                .foregroundStyle(Theme.primary)
            HStack(spacing: 14) {
                HintLabel(keys: textInput ? "any key" : "space", action: "resume")
                if !textInput { HintLabel(keys: "R", action: "restart") }
                HintLabel(keys: "esc", action: "back to work")
            }
        }
        .padding(22)
    }
}

struct GameOverCard: View {
    let arcade: ArcadeController
    let session: GameSession

    var body: some View {
        let style = boardStyle(session.boardKey)
        let summary = session.summary
        VStack(spacing: 6) {
            if let cabinet = session.engine as? ArcadeEngine {
                ArcadeMiniPicker(session: session, engine: cabinet)
                    .padding(.bottom, 8)
            }
            headline(summary, colors: style.colors)

            if let summary {
                CountUpScore(value: summary.record.value, format: BoardInfo.format(for: summary.board))
                    .foregroundStyle(LinearGradient(colors: [.white, style.colors[0]], startPoint: .top, endPoint: .bottom))
                    .shadow(color: style.colors[0].opacity(0.4), radius: 14)
                Text(detail(summary))
                    .font(Theme.rounded(11, .semibold))
                    .foregroundStyle(Theme.secondary)
            } else {
                Text(Format.score(session.score, format: session.game.scoreFormat))
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.primary.opacity(0.7))
            }

            HStack(spacing: 14) {
                HintLabel(keys: "space", action: "play again")
                if summary != nil { HintLabel(keys: "S", action: "share") }
                HintLabel(keys: "esc", action: "back to work")
            }
            .padding(.top, 8)
        }
        .padding(22)
    }

    @ViewBuilder
    private func headline(_ summary: RunSummary?, colors: [Color]) -> some View {
        if let met = summary?.dailyMet {
            Chip(text: met ? "DAILY CHALLENGE COMPLETE" : "DAILY · \(session.daily?.goal.uppercased() ?? "")",
                 colors: met ? [Color(hex: 0xFFB340), Color(hex: 0xFF375F)] : [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                 foreground: met ? .black : .white)
        } else if summary?.record.isPersonalBest == true && summary?.record.previousBest != nil {
            Chip(text: "NEW PERSONAL BEST", colors: colors, foreground: .black)
        } else {
            Text(overTitle)
                .font(Theme.rounded(11, .heavy))
                .tracking(2)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var overTitle: String {
        switch session.engine {
        case let mines as MinesEngine: return mines.won ? "FIELD CLEARED" : "BOOM"
        case is SolitaireEngine: return "SOLVED"
        case is PongEngine: return "MATCH OVER"
        case let sudoku as SudokuEngine: return sudoku.won ? "SOLVED" : "GAME OVER"
        case let lexi as LexiEngine: return lexi.won ? "SOLVED IN \(lexi.guesses.count)" : "THE WORD WAS \(lexi.answer.uppercased())"
        case is TyperEngine: return "TIME"
        case is FourEngine: return "THE AI WINS"
        case is StackEngine: return "TOPPED OUT"
        case is GemsEngine: return "OUT OF MOVES"
        case is InvadersEngine: return "INVADED"
        default: return "GAME OVER"
        }
    }

    private func detail(_ summary: RunSummary) -> String {
        var parts: [String] = []
        if let extra = gameDetail { parts.append(extra) }
        if let previous = summary.record.previousBest {
            parts.append(summary.record.isPersonalBest
                ? "Previous best \(Format.score(previous, board: summary.board))"
                : "Best \(Format.score(previous, board: summary.board))")
        } else {
            parts.append("First record")
        }
        return parts.joined(separator: " · ")
    }

    /// One line of what happened in the run.
    private var gameDetail: String? {
        switch session.engine {
        case let e as TyperEngine:
            return "\(e.accuracy)% accuracy · \(e.results.filter { $0 }.count) words"
        case let e as StackEngine:
            return "\(e.lines) lines · level \(e.level)"
        case let e as SudokuEngine:
            return "\(e.difficulty.title) · \(e.mistakes == 0 ? "no mistakes" : "\(e.mistakes) mistake\(e.mistakes == 1 ? "" : "s")")"
        case let e as FourEngine:
            return "Reached level \(e.level) · \(e.wins) win\(e.wins == 1 ? "" : "s")"
        case let e as InvadersEngine:
            return "Wave \(e.wave)"
        case let e as AstroEngine:
            return "Wave \(e.wave)"
        case let e as TrailsEngine:
            return "Round \(e.round)"
        case let e as SnakeEngine:
            return "Length \(e.body.count)"
        case let e as BreakoutEngine:
            return "Level \(e.level)"
        default:
            return nil
        }
    }
}
