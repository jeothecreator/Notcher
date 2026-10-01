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
        }
    }

    var symbol: String {
        switch self {
        case .flap: return "bird.fill"
        case .dodge: return "sparkles"
        case .bullseye: return "scope"
        case .echo: return "waveform"
        }
    }
}

/// Style for any leaderboard key.
func boardStyle(_ board: String) -> (symbol: String?, colors: [Color], game: GameID?) {
    if let game = GameID(rawValue: board) {
        return (game.style.symbol, game.style.colors, game)
    }
    if board.hasPrefix("arcade."), let mini = ArcadeMini(rawValue: String(board.dropFirst(7))) {
        return (mini.symbol, mini.colors, nil)
    }
    return ("gamecontroller.fill", GameID.arcade.style.colors, nil)
}
