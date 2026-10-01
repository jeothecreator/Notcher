import AppKit
import NotcherCore
import Observation
import SwiftUI

enum NotchMode: Equatable {
    case closed
    case launcher
    case game(GameID)
    case trophies

    var isExpanded: Bool { self != .closed }
}

enum LauncherItem: Hashable {
    case game(GameID)
    case daily
    case trophies
    case settings

    /// Header buttons highlight on hover but only open on click.
    var launchesOnHover: Bool {
        switch self {
        case .game, .daily: return true
        case .trophies, .settings: return false
        }
    }
}

/// Keys after mapping, before they reach a game.
enum ShellKey: Equatable {
    case escape
    case game(GameKey)
    case share
    case mute
    case settings
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var symbol: String
    var title: String
    var subtitle: String
    var colors: [Color]
}

struct NotchMetrics: Equatable {
    /// Width of the camera housing; 0 on Macs without a notch.
    var notchWidth: CGFloat
    /// Height of the notch, or of the menu bar on Macs without one.
    var notchHeight: CGFloat
    var hasNotch: Bool

    static let fallback = NotchMetrics(notchWidth: 0, notchHeight: 26, hasNotch: false)
}

struct TickerInfo: Equatable {
    var symbol: String
    var text: String
    var colors: [Color]
}

/// The brain of Notcher: notch state machine, hover-to-launch, sessions,
/// scores, achievements and toasts.
@MainActor
@Observable
final class ArcadeController {
    static let earWidth: CGFloat = 40
    static let maxContent = CGSize(width: 720, height: 396)
    static let shadowPadding: CGFloat = 48

    private(set) var mode: NotchMode = .closed
    var metrics: NotchMetrics = .fallback
    private(set) var hovered: LauncherItem?
    private(set) var selection: LauncherItem = .game(.runner)
    private(set) var charging: LauncherItem?
    private(set) var chargeDuration: Double = 0.3
    private(set) var activeSession: GameSession?
    private(set) var toast: Toast?
    private(set) var daily: DailyChallenge
    private(set) var showTicker: Bool
    private(set) var isFocused = false
    var save: ArcadeSave

    @ObservationIgnored var itemFrames: [LauncherItem: CGRect] = [:]
    @ObservationIgnored var panelSize = CGSize(width: 816, height: 480)
    let leaderboard = LeaderboardService()

    private let store: SaveStore
    @ObservationIgnored private var sessions: [String: GameSession] = [:]
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var chargeTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var toastQueue: [Toast] = []
    @ObservationIgnored private var hoverSuppressed = false
    @ObservationIgnored private var pointerEntered = false
    @ObservationIgnored private var pendingPlaySeconds = 0.0

    // Hooks wired up by the window controller and app delegate.
    @ObservationIgnored var requestFocus: () -> Void = {}
    @ObservationIgnored var resignFocus: () -> Void = {}
    @ObservationIgnored var modeChanged: (NotchMode) -> Void = { _ in }
    @ObservationIgnored var openSettings: () -> Void = {}
    @ObservationIgnored var shareRequested: (GameSession, RunSummary) -> Void = { _, _ in }

    init(store: SaveStore) {
        self.store = store
        self.save = store.load()
        self.daily = DailyChallenge.forDate(Date())
        self.showTicker = Prefs.showTicker
    }

    // MARK: - Geometry

    var closedBaseSize: CGSize {
        let h = metrics.notchHeight
        if metrics.hasNotch {
            return CGSize(width: metrics.notchWidth + (showTicker ? Self.earWidth * 2 : 0), height: h)
        }
        return CGSize(width: showTicker ? 196 : 148, height: h)
    }

    func shapeSize(for mode: NotchMode) -> CGSize {
        let h = metrics.notchHeight
        switch mode {
        case .closed:
            let base = closedBaseSize
            if toast != nil { return CGSize(width: max(base.width + 150, 380), height: h + 44) }
            return base
        case .launcher:
            return CGSize(width: 680, height: h + 246)
        case .trophies:
            return CGSize(width: 680, height: h + 304)
        case .game(let game):
            return game == .solitaire
                ? CGSize(width: Self.maxContent.width, height: h + Self.maxContent.height)
                : CGSize(width: 700, height: h + 292)
        }
    }

    var shapeSize: CGSize { shapeSize(for: mode) }

    static func panelSize(for metrics: NotchMetrics) -> CGSize {
        CGSize(
            width: maxContent.width + shadowPadding * 2,
            height: metrics.notchHeight + maxContent.height + shadowPadding
        )
    }

    /// The visible notch, in panel coordinates (origin top-left).
    var shapeRect: CGRect {
        let s = shapeSize
        return CGRect(x: (panelSize.width - s.width) / 2, y: 0, width: s.width, height: s.height)
    }

    private var hotZone: CGRect {
        let s = closedBaseSize
        return CGRect(x: (panelSize.width - s.width) / 2 - 6, y: -4, width: s.width + 12, height: s.height + 8)
    }

    // MARK: - Pointer

    func pointerMoved(_ p: CGPoint) {
        switch mode {
        case .closed:
            let hot = hotZone.contains(p)
            if hoverSuppressed {
                if !hot { hoverSuppressed = false }
                return
            }
            if hot { scheduleOpen() } else { cancelOpen() }
        case .launcher, .trophies:
            let inside = shapeRect.insetBy(dx: -10, dy: -10).contains(p)
            if inside {
                pointerEntered = true
                cancelClose()
            } else if pointerEntered {
                scheduleClose()
            }
            if mode == .launcher {
                updateHover(inside ? itemFrames.first(where: { $0.value.contains(p) })?.key : nil)
            }
        case .game:
            break
        }
    }

    private func scheduleOpen() {
        guard openTask == nil else { return }
        let delay = Prefs.openDelay.seconds
        openTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.openTask = nil
            if self.mode == .closed { self.open(focus: false) }
        }
    }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self, !Task.isCancelled else { return }
            self.closeTask = nil
            if self.mode == .launcher || self.mode == .trophies { self.close() }
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func updateHover(_ item: LauncherItem?) {
        guard item != hovered else { return }
        hovered = item
        cancelCharge()
        guard let item else { return }
        selection = item
        SoundEngine.shared.play(.tick)
        guard item.launchesOnHover, let delay = Prefs.hoverLaunch.delay else { return }
        chargeDuration = delay
        charging = item
        chargeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.charging == item, self.mode == .launcher else { return }
            self.activate(item)
        }
    }

    private func cancelCharge() {
        chargeTask?.cancel()
        chargeTask = nil
        charging = nil
    }

    // MARK: - Mode changes

    private func setMode(_ newMode: NotchMode) {
        guard newMode != mode else { return }
        withAnimation(Theme.spring) {
            mode = newMode
        }
        modeChanged(newMode)
    }

    func open(focus: Bool) {
        cancelOpen()
        cancelClose()
        refreshDaily()
        pointerEntered = !focus
        hovered = nil
        setMode(.launcher)
        if focus { requestFocus() }
    }

    func toggleFromHotkey() {
        if mode == .closed {
            open(focus: true)
        } else {
            escape()
        }
    }

    func showTrophies() {
        cancelCharge()
        setMode(.trophies)
    }

    /// Back to the plain notch. Pauses any game.
    func close() {
        cancelOpen()
        cancelClose()
        cancelCharge()
        hovered = nil
        if case .game = mode {
            activeSession?.pause()
            flushPlayTime()
        }
        persistIdleGames()
        setMode(.closed)
        resignFocus()
    }

    func escape() {
        switch mode {
        case .closed:
            return
        case .game:
            save.stats.escExits += 1
            checkAchievements()
            persist()
        case .launcher, .trophies:
            break
        }
        hoverSuppressed = true
        close()
    }

    /// The panel gained or lost keyboard focus.
    func focusChanged(_ focused: Bool) {
        isFocused = focused
        if !focused, case .game = mode {
            // Clicked somewhere else: that's "back to work" too.
            hoverSuppressed = true
            close()
        }
    }

    func activate(_ item: LauncherItem) {
        switch item {
        case .game(let game): launch(game)
        case .daily: launch(daily.game, daily: true)
        case .trophies: showTrophies()
        case .settings:
            close()
            openSettings()
        }
    }

    // MARK: - Games

    func launch(_ game: GameID, daily isDaily: Bool = false) {
        cancelOpen()
        cancelClose()
        cancelCharge()
        refreshDaily()
        let key = isDaily ? "daily-\(daily.dayKey)" : game.rawValue
        let session: GameSession
        if let existing = sessions[key] {
            session = existing
        } else {
            session = makeSession(game, daily: isDaily ? daily : nil)
            sessions[key] = session
        }
        if session.phase == .over { session.restart() }
        activeSession = session
        save.stats.gameLaunches += 1
        if game.category == .idle {
            save.stats.plays[game.rawValue, default: 0] += 1
        }
        setMode(.game(game))
        requestFocus()
        SoundEngine.shared.play(.launch)
        if Prefs.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        checkAchievements()
        persist()
    }

    private func makeSession(_ game: GameID, daily: DailyChallenge?) -> GameSession {
        let seed = daily?.seed
        let engine: GameEngine
        switch game {
        case .runner: engine = RunnerEngine(seed: seed)
        case .snake: engine = SnakeEngine(seed: seed)
        case .pong: engine = PongEngine(seed: seed)
        case .breakout: engine = BreakoutEngine(seed: seed)
        case .twenty48: engine = Twenty48Engine(seed: seed)
        case .mines: engine = MinesEngine(seed: seed)
        case .reaction: engine = ReactionEngine(seed: seed)
        case .solitaire: engine = SolitaireEngine(seed: seed, drawCount: Prefs.drawThree ? 3 : 1)
        case .arcade: engine = ArcadeEngine(featured: ArcadeMini.featured(on: Date()))
        case .miner:
            let miner = MinerEngine(state: save.miner ?? MinerState())
            miner.onPersist = { [weak self] state in
                self?.save.miner = state
                self?.persist()
            }
            engine = miner
        case .farm:
            let farm = FarmEngine(state: save.farm ?? FarmState())
            farm.onPersist = { [weak self] state in
                self?.save.farm = state
                self?.persist()
            }
            engine = farm
        }
        let session = GameSession(game: game, engine: engine, daily: daily)
        session.onEvents = { [weak self] session, events in
            self?.handle(events, from: session)
        }
        session.onPhaseChange = { [weak self] session, old, new in
            self?.phaseChanged(session, from: old, to: new)
        }
        return session
    }

    func frame(_ dt: Double) {
        guard let session = activeSession, case .game = mode else { return }
        session.tick(dt)
        if session.phase == .playing {
            pendingPlaySeconds += dt
            if pendingPlaySeconds >= 10 { flushPlayTime() }
        }
    }

    private func flushPlayTime() {
        guard pendingPlaySeconds > 0 else { return }
        save.stats.playSeconds += pendingPlaySeconds
        pendingPlaySeconds = 0
        checkAchievements()
        persist()
    }

    private func persistIdleGames() {
        for session in sessions.values {
            if let miner = session.engine as? MinerEngine { miner.persist() }
            if let farm = session.engine as? FarmEngine { farm.persist() }
        }
    }

    private func phaseChanged(_ session: GameSession, from old: GamePhase, to new: GamePhase) {
        if new == .playing && (old == .ready || old == .over) {
            save.stats.gamesPlayed += 1
            save.stats.plays[session.game.rawValue, default: 0] += 1
            checkAchievements()
            persist()
        }
    }

    private func handle(_ events: [GameEvent], from session: GameSession) {
        var statsChanged = false
        for event in events {
            switch event {
            case .sound(let cue):
                SoundEngine.shared.play(cue)
            case .count, .maximum, .minimum:
                save.stats.apply(event)
                statsChanged = true
            case .record(let value):
                record(value, from: session)
            case .shake:
                break
            }
        }
        if statsChanged {
            checkAchievements()
            persist()
        }
    }

    private func record(_ value: Int, from session: GameSession) {
        let board = session.engine.boardKey
        let result = save.scores.record(value, board: board, daily: session.isDaily)
        save.stats.noteScore(value, board: board)
        var dailyMet: Bool?
        if let challenge = session.daily {
            let met = challenge.isMet(by: value)
            dailyMet = met
            if met && !save.stats.dailyCompleted.contains(challenge.dayKey) {
                save.stats.markDaily(challenge.dayKey)
                showToast(Toast(
                    symbol: "flame.fill", title: "Daily challenge complete",
                    subtitle: "\(challenge.game.title) · \(challenge.goal)", colors: [Color(hex: 0xFFB340), Color(hex: 0xFF375F)]
                ))
                SoundEngine.shared.play(.win)
            }
        }
        session.summary = RunSummary(board: board, record: result, dailyMet: dailyMet)
        if result.isPersonalBest && result.previousBest != nil && session.game != .reaction {
            SoundEngine.shared.play(.levelUp)
        }
        leaderboard.submit(board: board, value: value, profile: save.profile)
        checkAchievements()
        persist()
    }

    // MARK: - Keys

    @discardableResult
    func keyDown(_ key: ShellKey, isRepeat: Bool) -> Bool {
        switch key {
        case .escape:
            escape()
            return true
        case .mute:
            Prefs.toggleSound()
            showToast(Toast(
                symbol: Prefs.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                title: Prefs.soundEnabled ? "Sound on" : "Sound off", subtitle: "Press M to toggle",
                colors: [Color.white, Color.white.opacity(0.6)]
            ))
            return true
        case .settings:
            close()
            openSettings()
            return true
        case .share, .game:
            break
        }

        switch mode {
        case .closed, .trophies:
            return false
        case .launcher:
            if case .game(let k) = key { return launcherKey(k) }
            return false
        case .game:
            guard let session = activeSession else { return false }
            if key == .share {
                if session.phase == .over, let summary = session.summary {
                    shareRequested(session, summary)
                }
                return true
            }
            guard case .game(let k) = key else { return false }
            if k == .pause {
                if session.phase == .playing { session.pause() } else if session.phase == .paused { session.press(.primary, isRepeat: false) }
                return true
            }
            return session.press(k, isRepeat: isRepeat)
        }
    }

    func keyUp(_ key: GameKey) {
        activeSession?.release(key)
    }

    static let launcherRows: [[LauncherItem]] = [
        [.trophies, .settings],
        [.game(.runner), .game(.snake), .game(.pong), .game(.breakout), .game(.twenty48), .game(.mines), .game(.reaction)],
        [.game(.miner), .game(.farm), .game(.solitaire), .game(.arcade), .daily],
    ]

    private func launcherKey(_ key: GameKey) -> Bool {
        let rows = Self.launcherRows
        var r = rows.firstIndex { $0.contains(selection) } ?? 1
        var c = rows[r].firstIndex(of: selection) ?? 0
        switch key {
        case .left: c = (c - 1 + rows[r].count) % rows[r].count
        case .right: c = (c + 1) % rows[r].count
        case .up, .down:
            let fraction = Double(c) / Double(max(1, rows[r].count - 1))
            r = key == .up ? max(0, r - 1) : min(rows.count - 1, r + 1)
            c = Int((fraction * Double(rows[r].count - 1)).rounded())
        case .primary, .confirm:
            activate(selection)
            return true
        default:
            return false
        }
        cancelCharge()
        selection = rows[r][c]
        SoundEngine.shared.play(.tick)
        return true
    }

    // MARK: - Achievements & toasts

    private func checkAchievements() {
        let fresh = AchievementCatalog.newlyUnlocked(stats: save.stats, unlocked: Set(save.achievements.keys))
        guard !fresh.isEmpty else { return }
        for achievement in fresh {
            save.achievements[achievement.id] = Date()
            showToast(Toast(
                symbol: achievement.symbol, title: achievement.title, subtitle: "Achievement unlocked",
                colors: achievement.game?.style.colors ?? [Color(hex: 0xFFE07A), Color(hex: 0xFF9F0A)]
            ))
        }
        SoundEngine.shared.play(.bonus)
    }

    func showToast(_ toast: Toast) {
        toastQueue.append(toast)
        if self.toast == nil && toastTask == nil { nextToast() }
    }

    private func nextToast() {
        guard !toastQueue.isEmpty else {
            toastTask = nil
            withAnimation(Theme.spring) { toast = nil }
            modeChanged(mode)
            return
        }
        let next = toastQueue.removeFirst()
        withAnimation(Theme.spring) { toast = next }
        modeChanged(mode)
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.nextToast()
        }
    }

    // MARK: - Ticker & daily

    func refreshDaily() {
        let today = DailyChallenge.forDate(Date())
        if today.dayKey != daily.dayKey { daily = today }
    }

    var dailyBest: Int? {
        save.scores.bestDaily(daily.game.rawValue, on: Date())
    }

    var dailyDone: Bool {
        save.stats.dailyCompleted.contains(daily.dayKey)
    }

    var minerState: MinerState? {
        (sessions[GameID.miner.rawValue]?.engine as? MinerEngine)?.state ?? save.miner
    }

    var farmState: FarmState? {
        (sessions[GameID.farm.rawValue]?.engine as? FarmEngine)?.state ?? save.farm
    }

    /// The live stat beside the notch.
    func ticker(at date: Date) -> TickerInfo {
        if let farm = farmState {
            let ready = farm.readyCount(at: date)
            if ready > 0 {
                return TickerInfo(symbol: "leaf.fill", text: "\(ready) ready", colors: GameID.farm.style.colors)
            }
        }
        if let miner = minerState, miner.workers > 0 {
            return TickerInfo(symbol: "diamond.fill", text: Format.compact(MinerEngine.projectedCoins(miner, at: date)), colors: GameID.miner.style.colors)
        }
        let streak = save.stats.dailyStreak(today: date)
        if streak > 0 {
            return TickerInfo(symbol: "flame.fill", text: "\(streak)", colors: [Color(hex: 0xFFB340), Color(hex: 0xFF5E3A)])
        }
        if let best = save.scores.best(GameID.runner.rawValue) {
            return TickerInfo(symbol: "trophy.fill", text: Format.compact(Double(best)), colors: GameID.runner.style.colors)
        }
        return TickerInfo(symbol: "sparkles", text: "Play", colors: GameID.arcade.style.colors)
    }

    // MARK: - Persistence & prefs

    func persist() {
        store.scheduleSave { [weak self] in self?.save ?? ArcadeSave() }
    }

    func prepareForQuit() {
        flushPlayTime()
        persistIdleGames()
        store.saveNow(save)
    }

    func reloadPrefs() {
        let ticker = Prefs.showTicker
        if ticker != showTicker {
            withAnimation(Theme.spring) { showTicker = ticker }
            modeChanged(mode)
        }
    }

    func setNickname(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save.profile.nickname = trimmed.isEmpty ? nil : String(trimmed.prefix(16))
        persist()
    }

    func resetProgress() {
        if mode != .closed { close() }
        sessions.removeAll()
        activeSession = nil
        save = store.reset()
    }

    // MARK: - Preview rendering hooks

    func previewState(mode: NotchMode, hovered: LauncherItem? = nil, charging: LauncherItem? = nil, focused: Bool = false, toast: Toast? = nil) {
        self.mode = mode
        self.hovered = hovered
        self.charging = charging
        self.isFocused = focused
        self.toast = toast
        if let hovered { selection = hovered }
    }

    /// Builds a session the way `launch` would, without focus, sound or stats side effects.
    @discardableResult
    func previewSession(_ game: GameID, daily isDaily: Bool = false, engine: GameEngine? = nil) -> GameSession {
        let session: GameSession
        if let engine {
            session = GameSession(game: game, engine: engine, daily: isDaily ? daily : nil)
            session.onEvents = { [weak self] session, events in self?.handle(events, from: session) }
            session.onPhaseChange = { [weak self] session, old, new in self?.phaseChanged(session, from: old, to: new) }
        } else {
            session = makeSession(game, daily: isDaily ? daily : nil)
        }
        sessions[isDaily ? "daily-\(daily.dayKey)" : game.rawValue] = session
        activeSession = session
        mode = .game(game)
        toast = nil
        toastQueue.removeAll()
        return session
    }

    func isPaused(_ game: GameID) -> Bool {
        sessions[game.rawValue]?.phase == .paused
    }

    /// Clears the session for a game so its next launch starts fresh (e.g. after changing Solitaire's draw mode).
    func discardSession(_ game: GameID) {
        sessions[game.rawValue] = nil
    }
}
