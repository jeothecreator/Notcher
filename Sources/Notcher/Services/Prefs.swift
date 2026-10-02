import Carbon.HIToolbox
import Foundation
import NotcherCore

enum HoverLaunch: String, CaseIterable, Identifiable {
    case fast, relaxed, click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast — 0.3 s"
        case .relaxed: return "Relaxed — 0.6 s"
        case .click: return "Click to launch"
        }
    }

    var delay: Double? {
        switch self {
        case .fast: return 0.3
        case .relaxed: return 0.6
        case .click: return nil
        }
    }
}

enum OpenDelay: String, CaseIterable, Identifiable {
    case instant, short, long

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instant: return "Instantly"
        case .short: return "After a short pause"
        case .long: return "After a longer pause"
        }
    }

    var seconds: Double {
        switch self {
        case .instant: return 0.06
        case .short: return 0.25
        case .long: return 0.6
        }
    }
}

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case controlOptionCommandG, optionCommandG, controlOptionN, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionCommandG: return "⌃⌥⌘G"
        case .optionCommandG: return "⌥⌘G"
        case .controlOptionN: return "⌃⌥N"
        case .off: return "Off"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .controlOptionCommandG, .optionCommandG: return UInt32(kVK_ANSI_G)
        case .controlOptionN: return UInt32(kVK_ANSI_N)
        case .off: return nil
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionCommandG: return UInt32(controlKey | optionKey | cmdKey)
        case .optionCommandG: return UInt32(optionKey | cmdKey)
        case .controlOptionN: return UInt32(controlKey | optionKey)
        case .off: return 0
        }
    }
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case automatic, main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Built-in display with notch"
        case .main: return "Main display"
        }
    }
}

/// Shades for original Game Boy games.
enum GameBoyPalette: String, CaseIterable, Identifiable {
    case classic, pocket

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic green"
        case .pocket: return "Pocket grey"
        }
    }

    var colors: [UInt32] {
        switch self {
        case .classic: return GameBoy.greenPalette
        case .pocket: return GameBoy.grayPalette
        }
    }
}

/// How console pictures are drawn.
enum ScreenFilter: String, CaseIterable, Identifiable {
    case authentic, sharp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .authentic: return "Authentic (scanlines, LCD grid)"
        case .sharp: return "Sharp pixels"
        }
    }
}

/// UserDefaults-backed preferences. Views bind with @AppStorage using the
/// same keys; everything else reads through here.
enum Prefs {
    enum Key {
        static let hoverLaunch = "hoverLaunch"
        static let openDelay = "openDelay"
        static let showTicker = "showTicker"
        static let sound = "soundEnabled"
        static let volume = "soundVolume"
        static let haptics = "haptics"
        static let hotkey = "hotkey"
        static let menuBarIcon = "showMenuBarIcon"
        static let drawThree = "solitaireDrawThree"
        static let display = "display"
        static let sudokuDifficulty = "sudokuDifficulty"
        static let onboarded = "onboarded"
        /// The version that last ran, to greet people after an update.
        static let lastVersion = "lastVersion"
        static let gbPalette = "gameBoyPalette"
        static let screenFilter = "screenFilter"
        static let resumeROMs = "resumeROMs"
    }

    static var defaults: UserDefaults { .standard }

    static func register() {
        defaults.register(defaults: [
            Key.hoverLaunch: HoverLaunch.fast.rawValue,
            Key.openDelay: OpenDelay.instant.rawValue,
            Key.showTicker: true,
            Key.sound: true,
            Key.volume: 0.5,
            Key.haptics: true,
            Key.hotkey: HotkeyPreset.controlOptionCommandG.rawValue,
            Key.menuBarIcon: true,
            Key.drawThree: false,
            Key.display: DisplayChoice.automatic.rawValue,
            Key.sudokuDifficulty: SudokuEngine.Difficulty.medium.rawValue,
            Key.onboarded: false,
            Key.gbPalette: GameBoyPalette.classic.rawValue,
            Key.screenFilter: ScreenFilter.authentic.rawValue,
            Key.resumeROMs: true,
        ])
    }

    static var hoverLaunch: HoverLaunch {
        HoverLaunch(rawValue: defaults.string(forKey: Key.hoverLaunch) ?? "") ?? .fast
    }

    static var openDelay: OpenDelay {
        OpenDelay(rawValue: defaults.string(forKey: Key.openDelay) ?? "") ?? .instant
    }

    static var showTicker: Bool { defaults.bool(forKey: Key.showTicker) }
    static var soundEnabled: Bool { defaults.bool(forKey: Key.sound) }
    static var volume: Double { defaults.double(forKey: Key.volume) }
    static var haptics: Bool { defaults.bool(forKey: Key.haptics) }
    static var showMenuBarIcon: Bool { defaults.bool(forKey: Key.menuBarIcon) }
    static var drawThree: Bool { defaults.bool(forKey: Key.drawThree) }

    static var hotkey: HotkeyPreset {
        HotkeyPreset(rawValue: defaults.string(forKey: Key.hotkey) ?? "") ?? .controlOptionCommandG
    }

    static var display: DisplayChoice {
        DisplayChoice(rawValue: defaults.string(forKey: Key.display) ?? "") ?? .automatic
    }

    /// The last Sudoku difficulty played, so the next puzzle starts there.
    static var sudokuDifficulty: SudokuEngine.Difficulty {
        get { SudokuEngine.Difficulty(rawValue: defaults.integer(forKey: Key.sudokuDifficulty)) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.sudokuDifficulty) }
    }

    static var gbPalette: GameBoyPalette {
        GameBoyPalette(rawValue: defaults.string(forKey: Key.gbPalette) ?? "") ?? .classic
    }

    static var screenFilter: ScreenFilter {
        ScreenFilter(rawValue: defaults.string(forKey: Key.screenFilter) ?? "") ?? .authentic
    }

    /// Reopening a ROM continues exactly where you pressed Esc.
    static var resumeROMs: Bool { defaults.bool(forKey: Key.resumeROMs) }

    static func toggleSound() {
        defaults.set(!soundEnabled, forKey: Key.sound)
    }
}
