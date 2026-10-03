import AppKit
import NotcherCore
import SwiftUI

/// `Notcher --render-appstore <folder>` renders the Mac App Store screenshots:
/// 2880 × 1800 JPEGs, one of the sizes App Store Connect accepts. Only the
/// built-in demo cartridges appear in them. AppStore/README.md says where they go.
@MainActor
enum AppStoreShots {
    static func run(into folder: URL) {
        SoundEngine.shared.suppressed = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let arcade = PreviewRenderer.makeArcade()

        func shot(_ name: String, _ title: String, _ subtitle: String, _ wallpaper: AppStoreShot.Wallpaper) {
            if arcade.mode.isPlaying { arcade.previewClearToasts() }
            let view = AppStoreShot(arcade: arcade, title: title, subtitle: subtitle, wallpaper: wallpaper)
            PreviewRenderer.write(view, scale: 2, to: folder.appendingPathComponent("\(name).jpg"))
        }

        arcade.previewState(mode: .drop, dropTargeted: true, dragNames: ["Night Flight (Notcher Demo).nes"])
        shot("2-drop", "Drop a game on the notch.",
             "Notcher opens up, adds it to your library and starts it right away.", .lagoon)

        arcade.installDemos()
        arcade.previewClearToasts()
        let ids = Dictionary(uniqueKeysWithValues: arcade.roms.map { ($0.system, $0.id) })
        func flight(right: Int) -> [(frames: Int, buttons: ConsoleButtons)] {
            [(frames: 70, buttons: []), (frames: right, buttons: [.right]), (frames: 8, buttons: [.right, .a])]
        }
        if let id = ids[.gameBoyColor] {
            arcade.previewConsole(id, script: flight(right: 30), held: [.right, .a])
            shot("1-console", "A game console in your notch.",
                 "Drag in a retro game you own and play it right under the camera.", .dusk)
            arcade.previewFinishConsole(seconds: 2_940)
        }
        if let id = ids[.gameBoy] {
            arcade.previewConsole(id, script: flight(right: 24), held: [.right])
            arcade.previewFinishConsole(seconds: 1_260)
        }
        if let id = ids[.nes] {
            arcade.previewConsole(id, script: flight(right: 40), held: [.right, .a])
            arcade.previewFinishConsole(seconds: 4_380)
            arcade.previewClearToasts()
            arcade.previewState(mode: .launcher, page: .library, hovered: .rom(id))
            shot("3-library", "Every game, right where you left off.",
                 "Esc saves your spot. Battery saves are kept. Play with the keyboard or a controller.", .ember)
        }

        arcade.previewState(mode: .launcher, hovered: .game(.stack))
        shot("4-games", "20 games built in, too.",
             "Falling blocks, invaders, word puzzles, sudoku, solitaire, idle farms and more.", .forest)

        let stack = arcade.previewSession(.stack, engine: StackEngine(seed: 11))
        if let e = stack.engine as? StackEngine { PreviewRenderer.autopilotStack(e, session: stack, pieces: 30) }
        shot("5-back-to-work", "Esc. Back to work.",
             "Made for the half-minute gaps in your day: a build, a download, a render.", .sunset)
    }
}

/// One App Store screenshot: the top of a Mac screen with the notch open,
/// zoomed in so it reads at store sizes, and a caption underneath.
struct AppStoreShot: View {
    enum Wallpaper {
        case dusk, lagoon, ember, forest, sunset

        var colors: [Color] {
            switch self {
            case .dusk: return [Color(hex: 0x1B2B5E), Color(hex: 0x3C1F5C), Color(hex: 0x0E1230)]
            case .lagoon: return [Color(hex: 0x0E3F4F), Color(hex: 0x15306B), Color(hex: 0x081425)]
            case .ember: return [Color(hex: 0x4A1E3A), Color(hex: 0x2A1A5E), Color(hex: 0x120A24)]
            case .forest: return [Color(hex: 0x0E3A2E), Color(hex: 0x163B5C), Color(hex: 0x07141C)]
            case .sunset: return [Color(hex: 0x5C2A1B), Color(hex: 0x5C1F4A), Color(hex: 0x1A0E24)]
            }
        }

        var glows: (Color, Color) {
            switch self {
            case .dusk: return (Color(hex: 0xFF6FB5), Color(hex: 0x4FB8FF))
            case .lagoon: return (Color(hex: 0x3FE0C5), Color(hex: 0x6A7BFF))
            case .ember: return (Color(hex: 0xFF8A5B), Color(hex: 0xB86BFF))
            case .forest: return (Color(hex: 0x5BFF9E), Color(hex: 0x3FA9FF))
            case .sunset: return (Color(hex: 0xFFC15B), Color(hex: 0xFF5B8A))
            }
        }
    }

    let arcade: ArcadeController
    let title: String
    let subtitle: String
    let wallpaper: Wallpaper

    static let size = CGSize(width: 1440, height: 900)
    static let zoom: CGFloat = 1.4

    var body: some View {
        let panel = arcade.panelSize
        let screenWidth = Self.size.width / Self.zoom
        // Where the open notch ends; the caption is centered in the space below.
        let notchBottom = arcade.shapeRect.maxY * Self.zoom
        ZStack(alignment: .top) {
            LinearGradient(colors: wallpaper.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(wallpaper.glows.0.opacity(0.35)).frame(width: 700).blur(radius: 150).offset(x: -460, y: 420)
            Circle().fill(wallpaper.glows.1.opacity(0.3)).frame(width: 620).blur(radius: 140).offset(x: 470, y: 200)

            ZStack(alignment: .top) {
                menuBar
                NotchRootView(arcade: arcade)
                    .frame(width: panel.width, height: panel.height)
            }
            .frame(width: screenWidth, height: panel.height, alignment: .top)
            .scaleEffect(Self.zoom, anchor: .top)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top)

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 62, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
            .frame(width: 1180)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, notchBottom)
            .padding(.bottom, 40)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.previewRendering, true)
        .environment(\.colorScheme, .dark)
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Finder").bold()
            // Only the menus that end before the open notch, so none peek out cut in half.
            ForEach(["File", "Edit", "View"], id: \.self) { Text($0) }
            Spacer()
            ForEach(["wifi", "battery.75percent", "magnifyingglass"], id: \.self) { Image(systemName: $0) }
            Text("Wed 1 Oct  9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 18)
        .frame(height: arcade.metrics.notchHeight)
        .background(Color.black.opacity(0.28))
    }
}
