import NotcherCore
import SwiftUI

/// A ROM running in the notch, laid out like a handheld: the picture in a
/// bezel, the D-pad on the left and the face buttons on the right. Both
/// light up as you press, on the keyboard or a controller.
struct ConsoleScreen: View {
    let arcade: ArcadeController
    let session: ConsoleSession
    @AppStorage(Prefs.Key.screenFilter) private var filter = ScreenFilter.authentic.rawValue

    static let sideWidth: CGFloat = 150
    static let gap: CGFloat = 20
    static let bezel: CGFloat = 5
    static let footerHeight: CGFloat = 30

    /// NES pictures are shown at 1.5× (256×224 after the usual overscan
    /// crop), Game Boy pictures at 2×.
    static func screenSize(for system: ConsoleSystem) -> CGSize {
        let layout = FrameImage.layout(for: system)
        let scale: CGFloat = system == .nes ? 1.5 : 2
        return CGSize(width: CGFloat(layout.width) * scale, height: CGFloat(layout.visibleHeight) * scale)
    }

    /// Everything below the notch band.
    static func contentSize(for system: ConsoleSystem) -> CGSize {
        let screen = screenSize(for: system)
        return CGSize(
            width: screen.width + bezel * 2 + (sideWidth + gap) * 2 + 40,
            height: 8 + screen.height + bezel * 2 + 8 + footerHeight
        )
    }

    var body: some View {
        let m = arcade.metrics
        let screen = Self.screenSize(for: session.system)
        VStack(spacing: 0) {
            header(m)
                .frame(height: m.notchHeight)
                .padding(.top, m.hasNotch ? 0 : 2)
            HStack(spacing: Self.gap) {
                DPadPanel(session: session)
                    .frame(width: Self.sideWidth, height: screen.height)
                picture(screen)
                FaceButtonPanel(arcade: arcade, session: session)
                    .frame(width: Self.sideWidth, height: screen.height)
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            footer
                .frame(height: Self.footerHeight, alignment: .top)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Header

    private func header(_ m: NotchMetrics) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                SystemBadge(system: session.system)
                Text(session.entry.title.uppercased())
                    .font(Theme.rounded(12, .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: m.notchWidth + 24)
            HStack(spacing: 8) {
                if session.fastForward {
                    Chip(text: "FAST ×4", colors: session.system.colors, foreground: .black)
                }
                if session.entry.hasBattery {
                    Image(systemName: "memorychip.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                        .help("This cartridge saves to battery; Notcher keeps it for you")
                }
                Text(session.system.title.uppercased())
                    .font(Theme.rounded(9.5, .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: Picture

    private func picture(_ size: CGSize) -> some View {
        let system = session.system
        return ZStack {
            Color.black
            ConsoleDisplay(session: session)
            if filter == ScreenFilter.authentic.rawValue {
                ScreenFilterOverlay(system: system)
            }
            // A faint sheen, like glass over the screen.
            LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
            overlay
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(Self.bezel)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: 0x0D0D11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                )
        )
        .shadow(color: system.accent.opacity(0.22), radius: 22)
        .animation(.easeOut(duration: 0.18), value: session.paused)
        .animation(Theme.snappy, value: session.flash)
    }

    @ViewBuilder private var overlay: some View {
        if session.paused {
            ZStack {
                Color.black.opacity(0.62)
                ConsolePausedCard(session: session)
            }
            .transition(.opacity)
        }
        if let flash = session.flash {
            HStack(spacing: 6) {
                Image(systemName: flash.symbol)
                    .font(.system(size: 10.5, weight: .bold))
                Text(flash.text)
                    .font(Theme.rounded(11, .bold))
            }
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(flash.id)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HintLabel(keys: "P", action: "pause")
            HintLabel(keys: "hold tab", action: "fast-forward")
            HintLabel(keys: "⌘S", action: "save")
            HintLabel(keys: "⌘L", action: "load")
            HintLabel(keys: "⌘R", action: "reset")
            Spacer(minLength: 8)
            HintLabel(keys: "esc", action: "back to work")
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

/// The picture itself: a layer fed straight from the emulator, or a plain
/// image when rendering previews.
struct ConsoleDisplay: View {
    let session: ConsoleSession
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        if previewRendering {
            if let image = session.image {
                RomThumbnail(image: image)
            } else {
                Color.black
            }
        } else {
            ConsoleLayer(session: session)
        }
    }
}

private struct ConsoleLayer: NSViewRepresentable {
    let session: ConsoleSession

    func makeNSView(context: Context) -> ConsoleDisplayView {
        let view = ConsoleDisplayView(frame: .zero)
        view.show(session.image)
        session.display = view
        return view
    }

    func updateNSView(_ view: ConsoleDisplayView, context: Context) {
        if session.display !== view {
            session.display = view
            view.show(session.image)
        }
    }
}

/// Scanlines for the NES, the pixel grid of an LCD for the Game Boys.
struct ScreenFilterOverlay: View {
    let system: ConsoleSystem

    var body: some View {
        let layout = FrameImage.layout(for: system)
        Canvas { context, size in
            let rows = layout.visibleHeight
            let cols = layout.width
            let ph = size.height / CGFloat(rows)
            let pw = size.width / CGFloat(cols)
            var path = Path()
            switch system {
            case .nes:
                for r in 0..<rows {
                    path.addRect(CGRect(x: 0, y: CGFloat(r) * ph + ph * 0.64, width: size.width, height: ph * 0.36))
                }
                context.fill(path, with: .color(.black.opacity(0.2)))
            case .gameBoy, .gameBoyColor:
                for r in 1..<rows {
                    path.addRect(CGRect(x: 0, y: CGFloat(r) * ph - 0.25, width: size.width, height: 0.5))
                }
                for c in 1..<cols {
                    path.addRect(CGRect(x: CGFloat(c) * pw - 0.25, y: 0, width: 0.5, height: size.height))
                }
                context.fill(path, with: .color(.black.opacity(0.14)))
            }
        }
        .overlay(
            RadialGradient(colors: [.clear, .black.opacity(0.22)], center: .center, startRadius: 120, endRadius: 300)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Side panels

/// D-pad and Select, lit while held.
struct DPadPanel: View {
    let session: ConsoleSession
    @Environment(\.previewRendering) private var previewRendering

    var body: some View {
        let held = session.held
        let colors = session.system.colors
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            DPad(held: held, colors: colors)
                .frame(width: 92, height: 92)
            Text("arrows or WASD")
                .font(Theme.rounded(9.5, .semibold))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 10)
            ConsolePill(title: "SELECT", key: "⌫", lit: held.contains(.select), colors: colors)
                .padding(.top, 18)
            Spacer(minLength: 0)
            controllerStatus
        }
    }

    private var controllerStatus: some View {
        let name = previewRendering ? nil : GamepadInput.shared.connectedName
        return HStack(spacing: 5) {
            Image(systemName: name == nil ? "keyboard" : "gamecontroller.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(name ?? "Keyboard")
                .font(Theme.rounded(9.5, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(name == nil ? Theme.tertiary : Theme.secondary)
        .help(name == nil ? "Connect a controller to play with it" : "Controller connected")
    }
}

struct DPad: View {
    let held: ConsoleButtons
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width
            let arm = s / 3
            ZStack {
                Group {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).frame(width: arm, height: s)
                    RoundedRectangle(cornerRadius: 7, style: .continuous).frame(width: s, height: arm)
                }
                .foregroundStyle(Color(hex: 0x1D1D24))
                Circle().fill(Color.black.opacity(0.35)).frame(width: arm * 0.45)
                arrow(.up, "arrowtriangle.up.fill", x: 0, y: -arm)
                arrow(.down, "arrowtriangle.down.fill", x: 0, y: arm)
                arrow(.left, "arrowtriangle.left.fill", x: -arm, y: 0)
                arrow(.right, "arrowtriangle.right.fill", x: arm, y: 0)
            }
            .frame(width: s, height: s)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
    }

    private func arrow(_ button: ConsoleButtons, _ symbol: String, x: CGFloat, y: CGFloat) -> some View {
        let lit = held.contains(button)
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(lit ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.04)))
                .padding(3)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(lit ? Color.black.opacity(0.8) : Theme.secondary)
        }
        .frame(width: 30, height: 30)
        .shadow(color: lit ? colors[0].opacity(0.8) : .clear, radius: 6)
        .offset(x: x, y: y)
        .animation(.easeOut(duration: 0.06), value: lit)
    }
}

/// A and B, Start, and quick save / load.
struct FaceButtonPanel: View {
    let arcade: ArcadeController
    let session: ConsoleSession

    var body: some View {
        let held = session.held
        let colors = session.system.colors
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                FaceButton(label: "B", key: "Z", lit: held.contains(.b), colors: colors)
                    .offset(x: -24, y: 13)
                FaceButton(label: "A", key: "X", lit: held.contains(.a), colors: colors)
                    .offset(x: 24, y: -13)
            }
            .frame(width: 120, height: 92)
            ConsolePill(title: "START", key: "⏎", lit: held.contains(.start), colors: colors)
                .padding(.top, 18)
            Spacer(minLength: 0)
            QuickSaveRow(session: session)
        }
    }
}

struct FaceButton: View {
    let label: String
    let key: String
    let lit: Bool
    let colors: [Color]

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(Theme.rounded(15, .heavy))
                .foregroundStyle(lit ? Color.black.opacity(0.8) : Theme.primary)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(lit ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color(hex: 0x24242C)))
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(lit ? 0.3 : 0.08), lineWidth: 0.75))
                .shadow(color: lit ? colors[0].opacity(0.8) : .black.opacity(0.5), radius: lit ? 8 : 3, y: lit ? 0 : 2)
                .scaleEffect(lit ? 0.94 : 1)
            Keycap(label: key)
        }
        .animation(.easeOut(duration: 0.06), value: lit)
    }
}

struct ConsolePill: View {
    let title: String
    let key: String
    let lit: Bool
    let colors: [Color]

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Theme.rounded(8.5, .heavy))
                .tracking(0.8)
                .foregroundStyle(lit ? Color.black.opacity(0.8) : Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(lit ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color(hex: 0x24242C)))
                )
                .shadow(color: lit ? colors[0].opacity(0.7) : .clear, radius: 6)
            Keycap(label: key)
        }
        .animation(.easeOut(duration: 0.06), value: lit)
    }
}

struct QuickSaveRow: View {
    let session: ConsoleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                SmallActionButton(symbol: "square.and.arrow.down.fill", title: "Save") { session.quickSave() }
                SmallActionButton(symbol: "arrow.counterclockwise", title: "Load") { session.quickLoad() }
            }
            Text(caption)
                .font(Theme.rounded(9.5, .semibold))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
        }
    }

    private var caption: String {
        guard let date = session.quickSaveDate else { return "No quick save yet" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Quick save · just now" }
        return "Quick save · " + Format.playTime(seconds: seconds) + " ago"
    }
}

struct SmallActionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(Theme.rounded(10, .bold))
            }
            .foregroundStyle(hovering ? Theme.primary : Theme.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(hovering ? Theme.surfaceHover : Theme.surface))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ConsolePausedCard: View {
    let session: ConsoleSession

    var body: some View {
        let resumed = session.resumed
        VStack(spacing: 9) {
            Image(systemName: resumed ? "bookmark.fill" : "pause.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(resumed ? AnyShapeStyle(session.system.gradient) : AnyShapeStyle(Theme.primary))
            Text(resumed ? "Continue where you left off" : "Paused")
                .font(Theme.rounded(17, .heavy))
                .foregroundStyle(Theme.primary)
            if resumed, let played = session.entry.lastPlayedAt {
                Text("Last played " + played.formatted(.relative(presentation: .named)))
                    .font(Theme.rounded(11, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 12) {
                HintLabel(keys: "⏎", action: resumed ? "continue" : "resume")
                HintLabel(keys: "⌘R", action: resumed ? "start over" : "reset")
            }
            .padding(.top, 4)
        }
        .padding(20)
    }
}
