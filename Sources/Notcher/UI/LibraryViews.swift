import NotcherCore
import SwiftUI

// MARK: - System marks

/// A small drawing of the console: a pad for the NES, a handheld for the Game Boys.
struct SystemGlyph: View {
    let system: ConsoleSystem
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvas in
            let colors = system.colors
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: canvas.width, y: canvas.height)
            )
            let cut = GraphicsContext.Shading.color(.black.opacity(0.55))
            switch system {
            case .nes:
                let w = canvas.width, h = canvas.height * 0.5
                let pad = CGRect(x: 0, y: (canvas.height - h) / 2, width: w, height: h)
                context.fill(Path(roundedRect: pad, cornerRadius: h * 0.22), with: shading)
                // D-pad
                let c = CGPoint(x: pad.minX + w * 0.22, y: pad.midY)
                let arm = h * 0.34, t = h * 0.13
                context.fill(Path(CGRect(x: c.x - arm, y: c.y - t, width: arm * 2, height: t * 2)), with: cut)
                context.fill(Path(CGRect(x: c.x - t, y: c.y - arm, width: t * 2, height: arm * 2)), with: cut)
                // Buttons
                let r = h * 0.15
                for x in [w * 0.70, w * 0.86] {
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: pad.midY - r, width: r * 2, height: r * 2)), with: cut)
                }
                // Select / Start
                for x in [w * 0.43, w * 0.54] {
                    context.fill(Path(roundedRect: CGRect(x: x - w * 0.04, y: pad.midY + h * 0.08, width: w * 0.08, height: h * 0.1), cornerRadius: h * 0.05), with: cut)
                }
            case .gameBoy, .gameBoyColor:
                let h = canvas.height, w = h * 0.68
                let handheld = CGRect(x: (canvas.width - w) / 2, y: 0, width: w, height: h)
                context.fill(Path(roundedRect: handheld, cornerRadius: w * 0.12), with: shading)
                // Screen
                let screen = CGRect(x: handheld.minX + w * 0.14, y: h * 0.09, width: w * 0.72, height: h * 0.38)
                context.fill(Path(roundedRect: screen, cornerRadius: w * 0.05), with: cut)
                // D-pad
                let c = CGPoint(x: handheld.minX + w * 0.30, y: h * 0.69)
                let arm = w * 0.15, t = w * 0.055
                context.fill(Path(CGRect(x: c.x - arm, y: c.y - t, width: arm * 2, height: t * 2)), with: cut)
                context.fill(Path(CGRect(x: c.x - t, y: c.y - arm, width: t * 2, height: arm * 2)), with: cut)
                // A / B
                let br = w * 0.075
                let buttons: [(CGFloat, CGFloat)] = [(0.66, 0.70), (0.80, 0.64)]
                for (x, y) in buttons {
                    let p = CGPoint(x: handheld.minX + w * x, y: h * y)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - br, y: p.y - br, width: br * 2, height: br * 2)), with: cut)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// "NES", "GB" or "GBC" on the system's colours.
struct SystemBadge: View {
    let system: ConsoleSystem

    var body: some View {
        Text(system.shortTitle)
            .font(Theme.rounded(8.5, .heavy))
            .tracking(0.6)
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(system.gradient))
    }
}

/// The last picture of a ROM, pixel-sharp.
struct RomThumbnail: View {
    let image: CGImage

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
    }
}

// MARK: - Library page

/// Hover frames of library items outside this rect are scrolled out of view.
struct LibraryViewportKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct LibraryPage: View {
    let arcade: ArcadeController

    var body: some View {
        if arcade.roms.isEmpty {
            EmptyLibraryCard(arcade: arcade, size: LauncherView.gridSize)
        } else {
            grid
        }
    }

    private var grid: some View {
        let columns = 4
        let s = LauncherView.spacing
        let tile = CGSize(
            width: ((LauncherView.gridSize.width - CGFloat(columns - 1) * s) / CGFloat(columns)).rounded(.down),
            height: ((LauncherView.gridSize.height - s) / 2).rounded(.down)
        )
        let items: [LauncherItem] = [.addRom] + arcade.roms.map { .rom($0.id) }
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min(items.count, $0 + columns)]) }
        return VerticalScroll {
            VStack(alignment: .leading, spacing: s) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: s) {
                        ForEach(row, id: \.self) { item in
                            switch item {
                            case .rom(let id):
                                if let entry = arcade.roms.first(where: { $0.id == id }) {
                                    RomTile(entry: entry, arcade: arcade, size: tile)
                                }
                            default:
                                AddRomTile(arcade: arcade, size: tile)
                            }
                        }
                    }
                }
            }
            // Room for the hover scale effect at the edges.
            .padding(4)
        }
        .frame(width: LauncherView.gridSize.width + 8, height: LauncherView.gridSize.height + 8, alignment: .topLeading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: LibraryViewportKey.self, value: proxy.frame(in: .named("panel")))
            }
        )
        .padding(-4)
    }
}

struct RomTile: View {
    let entry: RomEntry
    let arcade: ArcadeController
    let size: CGSize
    @State private var charge: CGFloat = 0
    @Environment(\.previewRendering) private var previewRendering

    private var item: LauncherItem { .rom(entry.id) }
    private var isHovered: Bool { arcade.hovered == item }
    private var isSelected: Bool { arcade.isFocused && arcade.selection == item && arcade.hovered == nil }
    private var isCharging: Bool { arcade.charging == item }

    var body: some View {
        let system = entry.system
        let active = isHovered || isSelected
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button {
            arcade.activate(item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                shape.fill(Color(hex: 0x111116))
                if let thumb = arcade.thumbnails[entry.id] {
                    RomThumbnail(image: thumb)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .opacity(active ? 1 : 0.78)
                } else {
                    shape.fill(LinearGradient(
                        colors: [system.accent.opacity(active ? 0.3 : 0.16), system.colors[1].opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    SystemGlyph(system: system, size: 64)
                        .opacity(active ? 0.3 : 0.16)
                        .rotationEffect(.degrees(-12))
                        .offset(x: size.width - 52, y: -size.height + 56)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        SystemBadge(system: system)
                        Spacer(minLength: 0)
                        if arcade.resumable.contains(entry.id) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Theme.primary)
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                                .help("Continues where you left off")
                        }
                    }
                    Spacer(minLength: 0)
                    Text(entry.title)
                        .font(Theme.rounded(12.5, .heavy))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                    Text(arcade.romStatus(entry))
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(active ? AnyShapeStyle(system.accent) : AnyShapeStyle(Theme.secondary))
                        .lineLimit(1)
                }
                .padding(9)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(active ? system.accent.opacity(0.65) : Theme.stroke, lineWidth: active ? 1 : 0.75))
            .overlay(
                shape
                    .trim(from: 0, to: previewRendering && isCharging ? 0.62 : charge)
                    .stroke(system.gradient, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .shadow(color: system.accent.opacity(0.8), radius: 4)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.04 : 1)
        .shadow(color: system.accent.opacity(active ? 0.35 : 0), radius: 14, y: 4)
        .animation(Theme.snappy, value: active)
        .hoverItem(item)
        .contextMenu {
            Button("Play") { arcade.playROM(entry.id) }
            if arcade.resumable.contains(entry.id) {
                Button("Start Over") { arcade.restartROM(entry.id) }
            }
            Button("Show in Finder") { arcade.revealROM(entry.id) }
            Divider()
            Button("Remove from Library", role: .destructive) { arcade.removeROM(entry.id) }
        }
        .onChange(of: isCharging) { _, charging in
            if charging {
                charge = 0
                withAnimation(.linear(duration: arcade.chargeDuration)) { charge = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { charge = 0 }
            }
        }
    }
}

/// The first library slot: click to pick files.
struct AddRomTile: View {
    let arcade: ArcadeController
    let size: CGSize

    var body: some View {
        let active = arcade.hovered == .addRom || (arcade.isFocused && arcade.hovered == nil && arcade.selection == .addRom)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button {
            arcade.activate(.addRom)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(active ? AnyShapeStyle(LauncherPage.library.colors[0]) : AnyShapeStyle(Theme.secondary))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(active ? 0.1 : 0.06)))
                Text("Add ROM")
                    .font(Theme.rounded(11.5, .bold))
                    .foregroundStyle(Theme.primary)
                Text("or drop one on the notch")
                    .font(Theme.rounded(9.5, .medium))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(width: size.width, height: size.height)
            .background(shape.fill(Color.white.opacity(active ? 0.05 : 0.02)))
            .overlay(shape.strokeBorder(Color.white.opacity(active ? 0.35 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.03 : 1)
        .animation(Theme.snappy, value: active)
        .hoverItem(.addRom)
    }
}

/// The whole library page when there are no ROMs yet.
struct EmptyLibraryCard: View {
    let arcade: ArcadeController
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let colors = LauncherPage.library.colors
        HStack(spacing: 22) {
            CartridgeFan(size: 112)
                .frame(width: 150)
            VStack(alignment: .leading, spacing: 6) {
                Text("Bring your own games")
                    .font(Theme.rounded(18, .heavy))
                    .foregroundStyle(Theme.primary)
                Text("Drag a NES, Game Boy or Game Boy Color ROM onto the notch, or a zip with one inside. It joins your library and starts right away. Battery saves and your last spot are kept automatically.")
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach([".nes", ".gb", ".gbc", ".zip"], id: \.self) { ext in
                        Text(ext)
                            .font(Theme.mono(9.5, .bold))
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    Spacer(minLength: 8)
                    ChooseFileButton(arcade: arcade)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: size.width, height: size.height)
        .background(shape.fill(LinearGradient(colors: [colors[0].opacity(0.08), colors[1].opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
    }
}

struct ChooseFileButton: View {
    let arcade: ArcadeController

    var body: some View {
        let active = arcade.hovered == .addRom || (arcade.isFocused && arcade.hovered == nil && arcade.selection == .addRom)
        let colors = LauncherPage.library.colors
        Button {
            arcade.activate(.addRom)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Choose File…")
                    .font(Theme.rounded(11, .bold))
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)))
            .shadow(color: colors[1].opacity(active ? 0.6 : 0.25), radius: active ? 10 : 5)
            .scaleEffect(active ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverItem(.addRom)
        .animation(Theme.snappy, value: active)
    }
}

/// Three cartridges fanned out, one per system.
struct CartridgeFan: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            card(.gameBoy).rotationEffect(.degrees(-14)).offset(x: -size * 0.32, y: size * 0.04)
            card(.nes).rotationEffect(.degrees(12)).offset(x: size * 0.32, y: size * 0.05)
            card(.gameBoyColor).offset(y: -size * 0.04)
        }
        .frame(width: size * 1.3, height: size)
    }

    private func card(_ system: ConsoleSystem) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
        return ZStack {
            shape.fill(Color(hex: 0x1A1A20))
            shape.fill(LinearGradient(colors: [system.accent.opacity(0.28), system.colors[1].opacity(0.08)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: size * 0.05) {
                SystemGlyph(system: system, size: size * 0.32)
                SystemBadge(system: system)
            }
        }
        .frame(width: size * 0.56, height: size * 0.72)
        .overlay(shape.strokeBorder(system.accent.opacity(0.35), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }
}

// MARK: - For You

/// Two tiles wide on the For You page: your last ROM, or how to add one.
struct LibraryCard: View {
    let arcade: ArcadeController
    let size: CGSize
    @State var charge: CGFloat = 0
    @Environment(\.previewRendering) private var previewRendering

    private var entry: RomEntry? { arcade.continueROM ?? arcade.roms.first }
    private var item: LauncherItem {
        if let entry { return .rom(entry.id) }
        return .addRom
    }
    private var active: Bool {
        arcade.hovered == item || (arcade.isFocused && arcade.hovered == nil && arcade.selection == item)
    }
    private var isCharging: Bool { arcade.charging == item }

    var body: some View {
        let colors = entry?.system.colors ?? LauncherPage.library.colors
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button {
            arcade.activate(item)
        } label: {
            ZStack(alignment: .topLeading) {
                shape.fill(Color(hex: 0x111116))
                shape.fill(LinearGradient(
                    colors: [colors[0].opacity(active ? 0.24 : 0.12), colors[1].opacity(active ? 0.12 : 0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                if let entry {
                    continueContent(entry)
                } else {
                    promoContent
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: colors.map { $0.opacity(active ? 0.7 : 0.25) }, startPoint: .leading, endPoint: .trailing), lineWidth: 1))
            .overlay(
                shape
                    .trim(from: 0, to: previewRendering && isCharging ? 0.62 : charge)
                    .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.02 : 1)
        .shadow(color: colors[1].opacity(active ? 0.3 : 0), radius: 14, y: 4)
        .animation(Theme.snappy, value: active)
        .hoverItem(item)
        .onChange(of: isCharging) { _, charging in
            if charging {
                charge = 0
                withAnimation(.linear(duration: arcade.chargeDuration)) { charge = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { charge = 0 }
            }
        }
    }

    private func continueContent(_ entry: RomEntry) -> some View {
        let screen = FrameImage.layout(for: entry.system)
        let thumbHeight = size.height - 20
        let thumbWidth = thumbHeight * CGFloat(screen.width) / CGFloat(screen.visibleHeight)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.lastPlayedAt == nil ? "READY TO PLAY" : "CONTINUE")
                    .font(Theme.rounded(8.5, .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiary)
                Text(entry.title)
                    .font(Theme.rounded(14.5, .heavy))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    SystemBadge(system: entry.system)
                    Text(arcade.romStatus(entry))
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(arcade.roms.count == 1 ? "1 game in your library" : "\(arcade.roms.count) games in your library")
                    .font(Theme.mono(9, .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 12)
            Spacer(minLength: 0)
            Group {
                if let thumb = arcade.thumbnails[entry.id] {
                    RomThumbnail(image: thumb)
                } else {
                    ZStack {
                        Color.black
                        SystemGlyph(system: entry.system, size: thumbHeight * 0.5)
                    }
                }
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
    }

    private var promoContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR GAMES")
                    .font(Theme.rounded(8.5, .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiary)
                Text("Play your own ROMs")
                    .font(Theme.rounded(14.5, .heavy))
                    .foregroundStyle(Theme.primary)
                Text("Drag a NES or Game Boy ROM onto the notch, or click to choose one.")
                    .font(Theme.rounded(10.5, .medium))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            CartridgeFan(size: 62)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
    }
}
