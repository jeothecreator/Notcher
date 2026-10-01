import AppKit
import NotcherCore
import SwiftUI

/// Renders a score card image and offers it to the system share sheet.
@MainActor
enum ShareService {
    static func share(session: GameSession, summary: RunSummary, profile: PlayerProfile, shapeRect: CGRect, in view: NSView) {
        let card = ShareCardView(board: summary.board, value: summary.record.value, isBest: summary.record.isPersonalBest, player: profile.displayName, daily: summary.dailyMet == true)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])

        var items: [Any] = [image]
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let name = "Notcher-\(summary.board.replacingOccurrences(of: ".", with: "-"))-\(summary.record.value).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if (try? png.write(to: url)) != nil { items = [url] }
        }

        let picker = NSSharingServicePicker(items: items)
        let y = view.isFlipped ? shapeRect.maxY - 40 : view.bounds.height - shapeRect.maxY + 40
        let anchor = NSRect(x: shapeRect.midX - 1, y: y, width: 2, height: 2)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}

/// The 1200×675 image people post.
struct ShareCardView: View {
    let board: String
    let value: Int
    let isBest: Bool
    let player: String
    let daily: Bool

    var body: some View {
        let style = boardStyle(board)
        ZStack {
            Color.black
            RadialGradient(colors: [style.colors[0].opacity(0.45), .clear], center: .top, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [style.colors[style.colors.count - 1].opacity(0.35), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 380)

            VStack(spacing: 0) {
                // A little notch at the top, like the real thing.
                NotchShape(topRadius: 10, bottomRadius: 18)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 220, height: 34)
                    .overlay(
                        HStack(spacing: 7) {
                            Image(systemName: "gamecontroller.fill")
                            Text("NOTCHER").tracking(3)
                        }
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                    )

                Spacer()

                Group {
                    if let game = style.game {
                        GameGlyph(game: game, size: 64)
                    } else if let symbol = style.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .padding(.bottom, 14)

                Text(BoardInfo.title(for: board).uppercased())
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Color.white.opacity(0.85))

                Text(Format.score(value, board: board))
                    .font(.system(size: 120, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(LinearGradient(colors: [.white, style.colors[0]], startPoint: .top, endPoint: .bottom))
                    .padding(.top, 2)

                HStack(spacing: 10) {
                    if isBest { Chip(text: "PERSONAL BEST", colors: style.colors, foreground: .black) }
                    if daily { Chip(text: "DAILY CHALLENGE ✓", colors: [Color(hex: 0xFFB340), Color(hex: 0xFF375F)], foreground: .black) }
                }
                .scaleEffect(1.6)
                .padding(.top, 8)

                Spacer()

                HStack {
                    Text(player)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Spacer()
                    Text("Can you beat me?")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .padding(.horizontal, 56)
                .padding(.bottom, 40)
            }
        }
        .frame(width: 1200, height: 675)
        .environment(\.colorScheme, .dark)
    }
}
