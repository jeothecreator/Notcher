import NotcherCore
import SwiftUI

enum Theme {
    static let background = Color.black
    static let surface = Color.white.opacity(0.055)
    static let surfaceHover = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.08)
    static let primary = Color.white.opacity(0.95)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
    static let field = Color(hex: 0x0A0A0D)
    static let dailyColors = [Color(hex: 0xFFB340), Color(hex: 0xFF375F)]

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.8)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Visual identity of a game: glyph and a two-stop accent gradient.
struct GameStyle {
    let symbol: String?
    let colors: [Color]

    var accent: Color { colors[0] }
    var deep: Color { colors[colors.count - 1] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension GameID {
    var style: GameStyle {
        switch self {
        case .runner: return GameStyle(symbol: "figure.run", colors: [Color(hex: 0xFFB340), Color(hex: 0xFF5E3A)])
        case .snake: return GameStyle(symbol: nil, colors: [Color(hex: 0xB4F05A), Color(hex: 0x2FD49A)])
        case .pong: return GameStyle(symbol: nil, colors: [Color(hex: 0x6AD4FF), Color(hex: 0x3478F6)])
        case .breakout: return GameStyle(symbol: nil, colors: [Color(hex: 0xFF7AD0), Color(hex: 0xA35BFF)])
        case .twenty48: return GameStyle(symbol: nil, colors: [Color(hex: 0xFFE07A), Color(hex: 0xFF9F0A)])
        case .mines: return GameStyle(symbol: nil, colors: [Color(hex: 0xFF8A80), Color(hex: 0xE5484D)])
        case .reaction: return GameStyle(symbol: "bolt.fill", colors: [Color(hex: 0xF4FF7A), Color(hex: 0x34C759)])
        case .miner: return GameStyle(symbol: "diamond.fill", colors: [Color(hex: 0xFFE3A3), Color(hex: 0xD08C2E)])
        case .farm: return GameStyle(symbol: "leaf.fill", colors: [Color(hex: 0x9BEA7C), Color(hex: 0x2E9E5B)])
        case .solitaire: return GameStyle(symbol: "suit.spade.fill", colors: [Color(hex: 0xA9A7FF), Color(hex: 0x5E5CE6)])
        case .arcade: return GameStyle(symbol: "gamecontroller.fill", colors: [Color(hex: 0xFF8AC2), Color(hex: 0x8B5CFF)])
        case .invaders: return GameStyle(symbol: nil, colors: [Color(hex: 0x7CFFCB), Color(hex: 0x14B8A6)])
        case .astro: return GameStyle(symbol: nil, colors: [Color(hex: 0xE6E9FF), Color(hex: 0x7C83FF)])
        case .trails: return GameStyle(symbol: nil, colors: [Color(hex: 0x3DF5FF), Color(hex: 0xFF3DCB)])
        case .stack: return GameStyle(symbol: nil, colors: [Color(hex: 0x60A5FA), Color(hex: 0x7C3AED)])
        case .gems: return GameStyle(symbol: nil, colors: [Color(hex: 0x6EF7B5), Color(hex: 0x0EA371)])
        case .sudoku: return GameStyle(symbol: nil, colors: [Color(hex: 0x67E8F9), Color(hex: 0x0891B2)])
        case .lexi: return GameStyle(symbol: nil, colors: [Color(hex: 0xB7F77A), Color(hex: 0xE8B931)])
        case .typer: return GameStyle(symbol: "keyboard.fill", colors: [Color(hex: 0xF0ABFC), Color(hex: 0xA855F7)])
        case .four: return GameStyle(symbol: nil, colors: [Color(hex: 0xFFD93D), Color(hex: 0xFF5F6D)])
        }
    }
}

extension ArcadeMini {
    var colors: [Color] {
        switch self {
        case .flap: return [Color(hex: 0xFFE07A), Color(hex: 0xFF8A3D)]
        case .dodge: return [Color(hex: 0x8AF2FF), Color(hex: 0x5865F2)]
        case .bullseye: return [Color(hex: 0xFF8A80), Color(hex: 0xFF2D78)]
        case .echo: return [Color(hex: 0xC9A7FF), Color(hex: 0x30D5C8)]
        case .lander: return [Color(hex: 0xE5E7EB), Color(hex: 0x60A5FA)]
        case .hop: return [Color(hex: 0xB9F99D), Color(hex: 0x16A34A)]
        }
    }

    var symbol: String {
        switch self {
        case .flap: return "bird.fill"
        case .dodge: return "sparkles"
        case .bullseye: return "scope"
        case .echo: return "waveform"
        case .lander: return "moon.fill"
        case .hop: return "hare.fill"
        }
    }
}

extension GameCategory {
    var colors: [Color] {
        switch self {
        case .action: return [Color(hex: 0xFFB340), Color(hex: 0xFF5E3A)]
        case .puzzle: return [Color(hex: 0x7AD7FF), Color(hex: 0x6366F1)]
        case .brain: return [Color(hex: 0xF0ABFC), Color(hex: 0xA855F7)]
        case .idle: return [Color(hex: 0x9BEA7C), Color(hex: 0x2E9E5B)]
        }
    }
}

extension LauncherPage {
    var colors: [Color] {
        switch self {
        case .forYou: return GameID.arcade.style.colors
        case .category(let c): return c.colors
        }
    }
}

/// Style for any score key.
func boardStyle(_ board: String) -> (symbol: String?, colors: [Color], game: GameID?) {
    if let game = GameID(rawValue: board) {
        return (game.style.symbol, game.style.colors, game)
    }
    if board.hasPrefix("arcade."), let mini = ArcadeMini(rawValue: String(board.dropFirst(7))) {
        return (mini.symbol, mini.colors, nil)
    }
    return ("gamecontroller.fill", GameID.arcade.style.colors, nil)
}
