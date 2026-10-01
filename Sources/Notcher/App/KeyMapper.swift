import AppKit
import Carbon.HIToolbox
import NotcherCore

enum KeyMapper {
    /// - Parameter textMode: the active game takes typed letters, so plain
    ///   letter keys become `.char` instead of shortcuts.
    static func map(_ event: NSEvent, textMode: Bool = false) -> ShellKey? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = mods.contains(.command)

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
}
