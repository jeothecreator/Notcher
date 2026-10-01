import AppKit
import Carbon.HIToolbox
import NotcherCore

enum KeyMapper {
    static func map(_ event: NSEvent) -> ShellKey? {
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
        switch c {
        case "a": return .game(.auto)
        case "s": return .share
        case "f": return .game(.flag)
        case "r": return .game(.restart)
        case "u": return .game(.undo)
        case "d": return .game(.cycle)
        case "p": return .game(.pause)
        case "m": return .mute
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return .game(.number(Int(String(c)) ?? 1))
        default: return nil
        }
    }
}
