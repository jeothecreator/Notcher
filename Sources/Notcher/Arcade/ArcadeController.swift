import AppKit
import NotcherCore
import Observation
import SwiftUI

enum NotchMode: Equatable {
    case closed
    case launcher
    case game(GameID)
    case trophies
    /// A ROM from the library, by id.
    case console(String)
    /// A ROM file is being dragged near the notch.
    case drop

    var isExpanded: Bool { self != .closed }

    /// Modes that hold keyboard focus and run the game loop.
    var isPlaying: Bool {
        switch self {
        case .game, .console: return true
        default: return false
        }
    }
}

/// A page of the launcher, picked in the sidebar.
enum LauncherPage: Hashable {
    case forYou
    /// The user's own ROMs.
    case library
    case category(GameCategory)

    static let all: [LauncherPage] = [.forYou, .library] + GameCategory.allCases.map { .category($0) }

    var title: String {
        switch self {
        case .forYou: return "For You"
        case .library: return "Library"
        case .category(let c): return c.title
        }
    }

    var symbol: String {
        switch self {
        case .forYou: return "sparkles"
        case .library: return "square.stack.3d.up.fill"
        case .category(let c): return c.symbol
        }
    }

    var games: [GameID] {
        switch self {
        case .forYou, .library: return []
        case .category(let c): return GameID.inCategory(c)
        }
    }
}

enum LauncherItem: Hashable {
    case game(GameID)
    case daily
    case page(LauncherPage)
    case trophies
    case settings
    case quit
    /// A ROM in the library, by id.
    case rom(String)
    /// Choose a ROM file to add.
    case addRom

    /// Only games launch on hover; pages switch after a short dwell; buttons need a click.
    var launchesOnHover: Bool {
        switch self {
        case .game, .daily, .rom: return true
        case .page, .trophies, .settings, .quit, .addRom: return false
        }
    }

    var isROM: Bool {
        if case .rom = self { return true }
        return false
    }
}

/// Keys after mapping, before they reach a game.
enum ShellKey: Equatable {
    case escape
    case game(GameKey)
    case share
    case mute
    case settings
    case console(ConsoleKey)
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
    static let earWidth: CGFloat = 46
    static let maxContent = CGSize(width: 780, height: 396)
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
    private(set) var page: LauncherPage = .forYou
    /// The quit button was clicked once; a second click within a few seconds quits.
    private(set) var quitArmed = false
    var trophiesTab: TrophiesTab = .achievements
    var save: ArcadeSave

    // ROMs (managed in ArcadeController+Library.swift)
    let library: RomLibrary
    /// Library entries, most recently played first.
    var roms: [RomEntry] = []
    /// ROMs with a saved "continue" point.
    var resumable: Set<String> = []
    var consoleSession: ConsoleSession?
    /// Last frames of each ROM, for the library tiles.
    var thumbnails: [String: CGImage] = [:]
    /// The pointer is over the notch while dragging a file.
    var dropTargeted = false
    /// Names of the files being dragged, when the drag pasteboard is readable.
    var dragNames: [String] = []
    @ObservationIgnored var libraryViewport: CGRect?
    @ObservationIgnored var modeBeforeDrop: NotchMode = .closed
    @ObservationIgnored var dropEndTask: Task<Void, Never>?

    @ObservationIgnored var itemFrames: [LauncherItem: CGRect] = [:]
    @ObservationIgnored var panelSize = CGSize(width: 876, height: 480)

    private let store: SaveStore
    @ObservationIgnored private var sessions: [String: GameSession] = [:]
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private var chargeTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?
    @ObservationIgnored private var quitTask: Task<Void, Never>?
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
    @ObservationIgnored var quitApp: () -> Void = {}
    @ObservationIgnored var shareRequested: (GameSession, RunSummary) -> Void = { _, _ in }
    @ObservationIgnored var requestOpenPanel: () -> Void = {}

    init(store: SaveStore, libraryFolder: URL? = nil) {
        self.store = store
        self.save = store.load()
        self.daily = DailyChallenge.forDate(Date())
        self.showTicker = Prefs.showTicker
        self.library = RomLibrary(folder: libraryFolder ?? store.folder.appendingPathComponent("Library", isDirectory: true))
        reloadLibrary()
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
            return CGSize(width: 780, height: h + 276)
        case .trophies:
            return CGSize(width: 780, height: h + 300)
        case .game(let game):
            let field = GameScreen.fieldSize(for: game)
            return CGSize(width: field.width + (field.width >= 680 ? 40 : 60), height: h + field.height + 54)
        case .console(let id):
            let system = consoleSession?.system ?? library.entry(id)?.system ?? .nes
            let content = ConsoleScreen.contentSize(for: system)
            return CGSize(width: content.width, height: h + content.height)
        case .drop:
            return CGSize(width: 560, height: h + 176)
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
                updateHover(inside ? item(at: p) : nil)
            }
        case .game, .console, .drop:
            break
        }
    }

    /// The launcher item under the pointer. Library tiles scrolled out of
    /// view still report frames, so those only count inside the viewport.
    private func item(at p: CGPoint) -> LauncherItem? {
        itemFrames.first { item, frame in
            guard frame.contains(p) else { return false }
            if page == .library, item.isROM || item == .addRom, let viewport = libraryViewport {
                return viewport.contains(p)
            }
            return true
        }?.key
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

    func cancelOpen() {
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

    func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func updateHover(_ item: LauncherItem?) {
        guard item != hovered else { return }
        hovered = item
        cancelCharge()
        pageTask?.cancel()
        pageTask = nil
        guard let item else { return }
        selection = item
        SoundEngine.shared.play(.tick)
        if case .page(let target) = item, target != page {
            // A short dwell so sweeping across the sidebar doesn't flip every page.
            pageTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self, !Task.isCancelled, self.hovered == item else { return }
                self.show(target)
            }
            return
        }
        guard item.launchesOnHover, let delay = Prefs.hoverLaunch.delay else { return }
        chargeDuration = delay
        charging = item
        chargeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.charging == item, self.mode == .launcher else { return }
            self.activate(item)
        }
    }

    func cancelCharge() {
        chargeTask?.cancel()
        chargeTask = nil
        charging = nil
    }

    // MARK: - Mode changes

    func setMode(_ newMode: NotchMode) {
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
        if focus { selection = firstItem(on: page) }
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
        disarmQuit()
        setMode(.trophies)
    }

    /// Switches the launcher page.
    func show(_ newPage: LauncherPage) {
        guard newPage != page else { return }
        withAnimation(Theme.snappy) { page = newPage }
        SoundEngine.shared.play(.select)
    }

    /// Back to the plain notch. Pauses any game.
    func close() {
        cancelOpen()
        cancelClose()
        cancelCharge()
        disarmQuit()
        pageTask?.cancel()
        pageTask = nil
        hovered = nil
        if case .game = mode {
            activeSession?.pause()
            flushPlayTime()
        }
        if case .console = mode {
            suspendConsole()
        }
        dropTargeted = false
        persistIdleGames()
        setMode(.closed)
        resignFocus()
    }

    func escape() {
        switch mode {
        case .closed:
            return
        case .game, .console:
            save.stats.escExits += 1
            checkAchievements()
            persist()
        case .launcher, .trophies, .drop:
            break
        }
        hoverSuppressed = true
        close()
    }

    /// The panel gained or lost keyboard focus.
    func focusChanged(_ focused: Bool) {
        isFocused = focused
        if !focused, mode.isPlaying {
            // Clicked somewhere else: that's "back to work" too.
            hoverSuppressed = true
            close()
        }
    }

    func activate(_ item: LauncherItem) {
        switch item {
        case .game(let game): launch(game)
        case .daily: launch(daily.game, daily: true)
        case .page(let p):
            selection = item
            show(p)
        case .trophies: showTrophies()
        case .settings:
            close()
            openSettings()
        case .quit:
            if quitArmed {
                quitApp()
            } else {
                armQuit()
            }
        case .rom(let id):
            playROM(id)
        case .addRom:
            requestOpenPanel()
        }
    }

    // MARK: - Quit

    private func armQuit() {
        withAnimation(Theme.snappy) { quitArmed = true }
        SoundEngine.shared.play(.select)
        quitTask?.cancel()
        quitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.disarmQuit()
        }
    }

    func disarmQuit() {
        quitTask?.cancel()
        quitTask = nil
        if quitArmed {
            withAnimation(Theme.snappy) { quitArmed = false }
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
        save.stats.noteLaunch(game)
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
        case .invaders: engine = InvadersEngine(seed: seed)
        case .astro: engine = AstroEngine(seed: seed)
        case .trails: engine = TrailsEngine(seed: seed)
        case .stack: engine = StackEngine(seed: seed)
        case .gems: engine = GemsEngine(seed: seed)
        case .sudoku: engine = SudokuEngine(seed: seed, difficulty: daily == nil ? Prefs.sudokuDifficulty : .medium)
        case .lexi: engine = LexiEngine(seed: seed)
        case .typer: engine = TyperEngine(seed: seed)
        case .four: engine = FourEngine(seed: seed)
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
        if case .console = mode {
            consoleSession?.tick(dt)
            return
        }
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
        if let sudoku = session.engine as? SudokuEngine, !session.isDaily {
            Prefs.sudokuDifficulty = sudoku.difficulty
        }
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
        case .share, .game, .console:
            break
        }

        switch mode {
        case .closed, .drop:
            return false
        case .console:
            guard let session = consoleSession else { return false }
            if case .console(let k) = key {
                session.press(k, isRepeat: isRepeat)
                return true
            }
            return false
        case .trophies:
            if case .game(let k) = key, k == .left || k == .confirm {
                open(focus: true)
                return true
            }
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

    func keyUp(_ key: ConsoleKey) {
        consoleSession?.release(key)
    }

    /// True while a ROM is running, so keys map to console buttons.
    var wantsConsoleInput: Bool {
        if case .console = mode { return true }
        return false
    }

    /// True while the active game takes typed letters, so P, M and S type instead.
    var wantsTextInput: Bool {
        guard case .game = mode, let session = activeSession else { return false }
        return session.engine.acceptsText && session.phase != .over
    }

    /// The first thing to select on a page.
    func firstItem(on page: LauncherPage) -> LauncherItem {
        switch page {
        case .forYou: return .daily
        case .library: return roms.first.map { .rom($0.id) } ?? .addRom
        case .category: return page.games.first.map { .game($0) } ?? .page(page)
        }
    }

    private func launcherKey(_ key: GameKey) -> Bool {
        switch key {
        case .primary, .confirm:
            activate(selection)
            return true
        case .cycle:
            let pages = LauncherPage.all
            let next = pages[((pages.firstIndex(of: page) ?? 0) + 1) % pages.count]
            show(next)
            if case .page = selection { selection = .page(next) } else { selection = firstItem(on: next) }
            return true
        case .left, .right, .up, .down:
            guard let next = Self.neighbour(of: selection, toward: key, in: itemFrames) else {
                if itemFrames[selection] == nil { selection = firstItem(on: page) }
                return true
            }
            cancelCharge()
            disarmQuit()
            selection = next
            if case .page(let p) = next { show(p) }
            SoundEngine.shared.play(.tick)
            return true
        default:
            return false
        }
    }

    /// Spatial keyboard navigation: the closest item in the direction of the arrow.
    static func neighbour(of item: LauncherItem, toward key: GameKey, in frames: [LauncherItem: CGRect]) -> LauncherItem? {
        guard let from = frames[item] else { return nil }
        var best: (item: LauncherItem, cost: CGFloat)?
        for (candidate, rect) in frames where candidate != item {
            let dx = rect.midX - from.midX
            let dy = rect.midY - from.midY
            let along: CGFloat, across: CGFloat
            switch key {
            case .left: along = -dx; across = abs(dy)
            case .right: along = dx; across = abs(dy)
            case .up: along = -dy; across = abs(dx)
            case .down: along = dy; across = abs(dx)
            default: return nil
            }
            // Overlapping rows or columns count as aligned.
            let overlap: Bool
            switch key {
            case .left, .right: overlap = rect.maxY > from.minY + 2 && rect.minY < from.maxY - 2
            default: overlap = rect.maxX > from.minX + 2 && rect.minX < from.maxX - 2
            }
            guard along > 4 else { continue }
            let cost = along + (overlap ? 0 : across * 2.5 + 40)
            if best == nil || cost < best!.cost { best = (candidate, cost) }
        }
        return best?.item
    }

    // MARK: - Achievements & toasts

    func checkAchievements() {
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

    /// Six games for the For You page: recent ones first, then new games you haven't tried.
    var forYouGames: [GameID] {
        var picks: [GameID] = []
        func add(_ game: GameID) {
            if picks.count < 6 && !picks.contains(game) { picks.append(game) }
        }
        for game in save.stats.recentGames.prefix(3) { add(game) }
        let curated: [GameID] = [.stack, .lexi, .invaders, .gems, .four, .astro, .sudoku, .typer, .trails]
        for game in curated where save.stats.plays[game.rawValue] == nil { add(game) }
        for game in [GameID.runner, .snake, .twenty48, .breakout, .solitaire, .miner] + curated { add(game) }
        return picks
    }

    /// Unplayed new games get a badge.
    func isUnplayedNew(_ game: GameID) -> Bool {
        game.isNew && save.stats.plays[game.rawValue] == nil
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
                return TickerInfo(symbol: "leaf.fill", text: "\(ready)", colors: GameID.farm.style.colors)
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
        // A ROM closed with Esc was already saved; only one still on screen needs it.
        if case .console = mode { suspendConsole() }
        flushPlayTime()
        persistIdleGames()
        store.saveNow(save)
    }

    func reloadPrefs() {
        consoleSession?.applyPalette()
        ConsoleAudio.shared.setVolume(Prefs.volume, muted: !Prefs.soundEnabled)
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

    func previewState(mode: NotchMode, page: LauncherPage = .forYou, hovered: LauncherItem? = nil, charging: LauncherItem? = nil, focused: Bool = false, toast: Toast? = nil, quitArmed: Bool = false, dropTargeted: Bool = false, dragNames: [String] = []) {
        self.mode = mode
        self.dropTargeted = dropTargeted
        self.dragNames = dragNames
        self.page = page
        self.quitArmed = quitArmed
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

    /// Drops toasts raised while an autopilot played, so game shots stay clean.
    func previewClearToasts() {
        toastTask?.cancel()
        toastTask = nil
        toastQueue.removeAll()
        toast = nil
    }

    func isPaused(_ game: GameID) -> Bool {
        sessions[game.rawValue]?.phase == .paused
    }

    /// Clears the session for a game so its next launch starts fresh (e.g. after changing Solitaire's draw mode).
    func discardSession(_ game: GameID) {
        sessions[game.rawValue] = nil
    }
}
