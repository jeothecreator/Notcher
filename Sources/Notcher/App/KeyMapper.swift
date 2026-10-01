import AppKit
import Carbon.HIToolbox
import NotcherCore

enum KeyMapper {
    /// - Parameter textMode: the active game takes typed letters, so plain
    ///   letter keys become `.char` instead of shortcuts.
    /// - Parameter console: a ROM is running, so keys become console buttons.
    static func map(_ event: NSEvent, textMode: Bool = false, console: Bool = false) -> ShellKey? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = mods.contains(.command)
        if console { return mapConsole(event, command: command) }

        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_LeftArrow: return .game(.left)
        case kVK_RightArrow: return .game(.right)
        case kVK_UpArrow: return .game(.up)
        case kVK_DownArrow: return .game(.down)
        case kVK_Space: return .game(.primary)
        case kVK_Return, kVK_ANSI_KeypadEnter: return .game(.confirm)
        case kVK_Tab: return .game(.cycle)
        case kVK_Delete, kVK_ForwardDelete: return command ? nil : .game(.backspace)
        default: break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(), let c = chars.first else { return nil }
        if command {
            switch c {
            case "z": return .game(.undo)
            case ",": return .settings
            case "w", ".": return .escape
            default: return nil
            }
        }
        if let digit = c.wholeNumberValue, c.isASCII {
            return .game(.number(digit))
        }
        if textMode {
            return c.isLetter || c == "'" ? .game(.char(c)) : nil
        }
        switch c {
        case "a": return .game(.auto)
        case "s": return .share
        case "f", "n": return .game(.flag)
        case "r": return .game(.restart)
        case "u": return .game(.undo)
        case "d", "c": return .game(.cycle)
        case "p": return .game(.pause)
        case "m": return .mute
        default: return nil
        }
    }

    /// Console layout, as in most emulators: arrows or WASD move, X/K/Space
    /// is A, Z/J is B, Return is Start, Backspace is Select, hold Tab to fast-forward.
    static func mapConsole(_ event: NSEvent, command: Bool) -> ShellKey? {
        if command {
            switch event.charactersIgnoringModifiers?.lowercased().first {
            case "s": return .console(.quickSave)
            case "l": return .console(.quickLoad)
            case "r": return .console(.reset)
            case ",": return .settings
            case "w", ".": return .escape
            default: return nil
            }
        }
        switch Int(event.keyCode) {
        case kVK_Escape: return .escape
        case kVK_LeftArrow, kVK_ANSI_A: return .console(.button(.left))
        case kVK_RightArrow, kVK_ANSI_D: return .console(.button(.right))
        case kVK_UpArrow, kVK_ANSI_W: return .console(.button(.up))
        case kVK_DownArrow, kVK_ANSI_S: return .console(.button(.down))
        case kVK_ANSI_X, kVK_ANSI_K, kVK_Space: return .console(.button(.a))
        case kVK_ANSI_Z, kVK_ANSI_J: return .console(.button(.b))
        case kVK_Return, kVK_ANSI_KeypadEnter: return .console(.button(.start))
        case kVK_Delete, kVK_RightShift, kVK_ANSI_C: return .console(.button(.select))
        case kVK_Tab: return .console(.fastForward)
        case kVK_ANSI_P: return .console(.pause)
        case kVK_ANSI_M: return .mute
        default: return nil
        }
    }
}
