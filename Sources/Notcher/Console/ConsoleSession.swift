import AppKit
import NotcherCore
import Observation

/// Keys a console understands, after mapping.
enum ConsoleKey: Equatable {
    case button(ConsoleButtons)
    /// Hold to run at 4× speed.
    case fastForward
    case pause
    case quickSave
    case quickLoad
    case reset
}

/// One ROM running in the notch: pacing, input, the picture, battery saves
/// and the "continue where you left off" state.
@MainActor
@Observable
final class ConsoleSession {
    private(set) var entry: RomEntry
    private(set) var paused = false
    private(set) var fastForward = false
    private(set) var quickSaveDate: Date?
    /// Picked up from a saved spot and waiting for a button to continue.
    private(set) var resumed = false
    /// Last thing that happened, shown briefly over the picture.
    private(set) var flash: Flash?
    /// Buttons held right now, from the keyboard and any controller.
    private(set) var held: ConsoleButtons = []

    struct Flash: Equatable {
        let id = UUID()
        var symbol: String
        var text: String
    }

    let runner: ConsoleRunner
    private let library: RomLibrary
    @ObservationIgnored private(set) var image: CGImage?
    @ObservationIgnored weak var display: ConsoleDisplayView?
    @ObservationIgnored private var keyboard: ConsoleButtons = []
    @ObservationIgnored private var pacer = FramePacer()
    @ObservationIgnored private var unsavedSeconds = 0.0
    @ObservationIgnored private var batteryClock = 0.0
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var palette: GameBoyPalette?
    @ObservationIgnored var gamepad: @MainActor () -> ConsoleButtons = { GamepadInput.shared.buttons }

    var system: ConsoleSystem { entry.system }

    init(entry: RomEntry, library: RomLibrary, resume: Bool) throws {
        let rom = try library.romData(entry)
        let emulator = try EmulatorFactory.make(rom: rom)
        if let save = library.battery(entry) {
            emulator.loadBatteryRAM(save)
        }
        var didResume = false
        if resume, let state = library.resumeState(entry) {
            didResume = (try? emulator.loadState(state)) != nil
        }
        self.entry = entry
        self.library = library
        runner = ConsoleRunner(emulator: emulator)
        resumed = didResume
        quickSaveDate = library.quickStateDate(entry)
        applyPalette()
        if didResume, let data = library.thumbnail(entry) {
            // The last picture you saw, until the first new frame arrives.
            image = FrameImage.load(data)
        } else {
            image = runner.snapshot()
        }
    }

    // MARK: Running

    /// Advances the console for one display refresh.
    func tick(_ dt: Double) {
        guard !paused else { return }
        unsavedSeconds += dt
        var frames = pacer.frames(for: dt, rate: runner.frameRate)
        if fastForward { frames = max(frames, 1) * 4 }
        guard frames > 0 else { return }
        let buttons = keyboard.union(gamepad())
        if buttons != held { held = buttons }
        runner.run(frames: frames, buttons: buttons, audio: !fastForward) { [weak self] image in
            self?.show(image)
        }
        batteryClock += dt
        if batteryClock >= 3 {
            batteryClock = 0
            saveBatteryIfNeeded()
        }
    }

    private func show(_ image: CGImage?) {
        guard let image else { return }
        self.image = image
        display?.show(image)
    }

    func press(_ key: ConsoleKey, isRepeat: Bool) {
        switch key {
        case .button(let b):
            // While paused, Start or A only resumes; the game doesn't see the press.
            if paused {
                if (b == .start || b == .a) && !isRepeat { resume() }
                return
            }
            keyboard.insert(b)
        case .fastForward:
            if !fastForward && !paused {
                fastForward = true
                ConsoleAudio.shared.flush()
            }
        case .pause:
            guard !isRepeat else { return }
            if paused { resume() } else { pause() }
        case .quickSave:
            guard !isRepeat else { return }
            quickSave()
        case .quickLoad:
            guard !isRepeat else { return }
            quickLoad()
        case .reset:
            guard !isRepeat else { return }
            reset()
        }
    }

    func release(_ key: ConsoleKey) {
        switch key {
        case .button(let b): keyboard.remove(b)
        case .fastForward: fastForward = false
        default: break
        }
    }

    func releaseAll() {
        keyboard = []
        held = []
        fastForward = false
    }

    func pause() {
        guard !paused else { return }
        paused = true
        releaseAll()
    }

    func resume() {
        guard paused else { return }
        paused = false
        resumed = false
        pacer.reset()
    }

    // MARK: States

    func quickSave() {
        let state = runner.sync { $0.saveState() }
        library.writeQuickState(state, for: entry)
        quickSaveDate = Date()
        showFlash("square.and.arrow.down.fill", "Saved")
    }

    func quickLoad() {
        guard let state = library.quickState(entry) else {
            showFlash("exclamationmark.circle.fill", "No quick save yet — ⌘S makes one")
            return
        }
        do {
            try runner.sync { try $0.loadState(state) }
            if let picture = runner.snapshot() { show(picture) }
            showFlash("arrow.counterclockwise", "Loaded")
        } catch {
            showFlash("exclamationmark.triangle.fill", "That save couldn't be loaded")
        }
    }

    func reset() {
        runner.sync { $0.reset() }
        paused = false
        resumed = false
        pacer.reset()
        showFlash("power", "Reset")
    }

    private func showFlash(_ symbol: String, _ text: String) {
        flash = Flash(symbol: symbol, text: text)
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }

    // MARK: Persistence

    func applyPalette() {
        let wanted = Prefs.gbPalette
        guard runner.system == .gameBoy, wanted != palette else { return }
        palette = wanted
        runner.sync { emulator in
            if let gameBoy = emulator as? GameBoy {
                gameBoy.monochromePalette = wanted.colors
            }
        }
    }

    private func saveBatteryIfNeeded() {
        let data: [UInt8]? = runner.sync { emulator in
            guard emulator.batteryDirty, let ram = emulator.batteryRAM else { return nil }
            emulator.markBatterySaved()
            return ram
        }
        if let data { library.writeBattery(data, for: entry) }
    }

    /// Writes everything needed to pick up here later. Returns the play time
    /// since the last call.
    @discardableResult
    func suspend() -> Double {
        releaseAll()
        saveBatteryIfNeeded()
        if Prefs.resumeROMs {
            let state = runner.sync { $0.saveState() }
            library.writeResumeState(state, for: entry)
        }
        if let picture = runner.snapshot(), let png = FrameImage.png(picture) {
            library.writeThumbnail(png, for: entry)
        }
        let seconds = unsavedSeconds
        unsavedSeconds = 0
        pacer.reset()
        return seconds
    }

    func rename(_ updated: RomEntry) {
        entry = updated
    }
}

/// Draws console frames straight into a layer, outside SwiftUI's diffing.
final class ConsoleDisplayView: NSView {
    private var current: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .linear
        layer?.contentsGravity = .resize
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.contents = current
    }

    func show(_ image: CGImage?) {
        current = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }

    // Clicks fall through to SwiftUI.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
