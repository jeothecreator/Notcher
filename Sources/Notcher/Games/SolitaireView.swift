import NotcherCore
import SwiftUI

struct SolitaireView: View {
    let session: GameSession
    let engine: SolitaireEngine
    let revision: Int

    static let card = CGSize(width: 70, height: 98)
    static let columnStride: CGFloat = 92
    static let topY: CGFloat = 12
    static let tableauY: CGFloat = 126
    static let fieldSize = CGSize(width: 680, height: 340)
    static var marginX: CGFloat { (fieldSize.width - (6 * columnStride + card.width)) / 2 }

    @State private var dragOffset: CGSize = .zero
    @State private var dragging = false
    @State private var lastTap: (id: Int, time: Date)?

    struct Placement {
        let card: Card
        let pile: Pile
        let index: Int
        let origin: CGPoint
        let z: Double
    }

    static func x(_ column: Int) -> CGFloat { marginX + CGFloat(column) * columnStride }

    static func slotOrigin(_ pile: Pile) -> CGPoint {
        switch pile {
        case .tableau(let i): return CGPoint(x: x(i), y: tableauY)
        default: return CGPoint(x: x(pile.column), y: topY)
        }
    }

    func layout() -> [Placement] {
        let b = engine.board
        var out: [Placement] = []
        for (i, card) in b.stock.enumerated() {
            let o = Self.slotOrigin(.stock)
            out.append(Placement(card: card, pile: .stock, index: i, origin: CGPoint(x: o.x - CGFloat(i / 8), y: o.y - CGFloat(i / 8)), z: Double(i)))
        }
        let fanStart = max(0, b.waste.count - (engine.drawCount == 3 ? 3 : 1))
        for (i, card) in b.waste.enumerated() {
            let o = Self.slotOrigin(.waste)
            let fan = CGFloat(max(0, i - fanStart)) * 14
            out.append(Placement(card: card, pile: .waste, index: i, origin: CGPoint(x: o.x + fan, y: o.y), z: Double(i)))
        }
        for f in 0..<4 {
            for (i, card) in b.foundations[f].enumerated() {
                out.append(Placement(card: card, pile: .foundation(f), index: i, origin: Self.slotOrigin(.foundation(f)), z: Double(i)))
            }
        }
        let available = Self.fieldSize.height - Self.tableauY - Self.card.height - 8
        for t in 0..<7 {
            let cards = b.tableau[t]
            let down = cards.filter { !$0.faceUp }.count
            let up = cards.count - down
            let downStep: CGFloat = 7
            let upStep = up > 1 ? min(22, max(9, (available - CGFloat(down) * downStep) / CGFloat(up - 1))) : 22
            var y = Self.tableauY
            for (i, card) in cards.enumerated() {
                out.append(Placement(card: card, pile: .tableau(t), index: i, origin: CGPoint(x: Self.x(t), y: y), z: 100 + Double(i)))
                y += card.faceUp ? upStep : downStep
            }
        }
        return out
    }

    var body: some View {
        _ = revision
        let placements = layout()
        let held = engine.held
        let heldCards: Set<Int> = {
            guard let h = held else { return [] }
            return Set(engine.board.cards(in: h.from).suffix(h.count).map(\.id))
        }()

        return ZStack(alignment: .topLeading) {
            RadialGradient(colors: [Color(hex: 0x1E1D3A), Color(hex: 0x0B0B14)], center: .center, startRadius: 20, endRadius: 420)

            slots
            statusBar

            ForEach(placements, id: \.card.id) { p in
                let isHeld = heldCards.contains(p.card.id)
                let lift: CGFloat = isHeld && !dragging ? -5 : 0
                CardView(card: p.card, highlighted: isHeld)
                    .frame(width: Self.card.width, height: Self.card.height)
                    .shadow(color: .black.opacity(isHeld ? 0.6 : 0.35), radius: isHeld ? 10 : 3, y: isHeld ? 6 : 1.5)
                    .position(x: p.origin.x + Self.card.width / 2, y: p.origin.y + Self.card.height / 2 + lift)
                    .offset(isHeld && dragging ? dragOffset : .zero)
                    .zIndex(isHeld && dragging ? 1000 + p.z : p.z)
                    .gesture(cardGesture(p))
            }

            cursorHighlight(placements)
                .zIndex(2000)
                .allowsHitTesting(false)
        }
        .frame(width: Self.fieldSize.width, height: Self.fieldSize.height)
        .coordinateSpace(.named("table"))
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: engine.moves)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: held)
    }

    // MARK: Slots

    private var slots: some View {
        ZStack(alignment: .topLeading) {
            slot(.stock, symbol: engine.board.stock.isEmpty && !engine.board.waste.isEmpty ? "arrow.counterclockwise" : nil)
            slot(.waste, symbol: nil)
            ForEach(0..<4, id: \.self) { f in slot(.foundation(f), symbol: nil, label: "A") }
            ForEach(0..<7, id: \.self) { t in slot(.tableau(t), symbol: nil, label: "K") }
        }
    }

    private func slot(_ pile: Pile, symbol: String?, label: String? = nil) -> some View {
        let o = Self.slotOrigin(pile)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.025)))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))
            } else if let label {
                Text(label)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.08))
            }
        }
        .frame(width: Self.card.width, height: Self.card.height)
        .contentShape(Rectangle())
        .position(x: o.x + Self.card.width / 2, y: o.y + Self.card.height / 2)
        .onTapGesture { engine.tap(pile, index: nil) }
    }

    private var statusBar: some View {
        VStack(spacing: 4) {
            Text("\(engine.moves) MOVES")
                .font(Theme.mono(9.5, .heavy))
                .foregroundStyle(Theme.secondary)
            Text("DRAW \(engine.drawCount)")
                .font(Theme.rounded(8.5, .heavy))
                .tracking(1)
                .foregroundStyle(Theme.tertiary)
            if engine.canUndo {
                HStack(spacing: 3) {
                    Keycap(label: "U")
                    Text("undo").font(Theme.rounded(9, .medium)).foregroundStyle(Theme.tertiary)
                }
                .padding(.top, 4)
            }
        }
        .frame(width: Self.card.width + 10)
        .position(x: Self.x(2) + Self.card.width / 2, y: Self.topY + Self.card.height / 2)
    }

    // MARK: Cursor

    @ViewBuilder
    private func cursorHighlight(_ placements: [Placement]) -> some View {
        if engine.phase != .over {
            let pile = engine.cursor
            let inPile = placements.filter { $0.pile == pile }
            let rect: CGRect = {
                let o = Self.slotOrigin(pile)
                guard let last = inPile.max(by: { $0.index < $1.index }) else {
                    return CGRect(origin: o, size: Self.card)
                }
                if pile.isTableau {
                    let depth = engine.held?.from == pile ? engine.held!.count : engine.depth
                    let firstIndex = max(0, inPile.count - depth)
                    let first = inPile.first { $0.index == firstIndex } ?? last
                    return CGRect(x: first.origin.x, y: first.origin.y, width: Self.card.width, height: last.origin.y + Self.card.height - first.origin.y)
                }
                return CGRect(origin: last.origin, size: Self.card)
            }()
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(GameID.solitaire.style.gradient, lineWidth: 2.2)
                .shadow(color: GameID.solitaire.style.accent.opacity(0.8), radius: 6)
                .frame(width: rect.width + 6, height: rect.height + 6)
                .position(x: rect.midX, y: rect.midY)
                .animation(.spring(response: 0.22, dampingFraction: 0.85), value: rect)
        }
    }

    // MARK: Gestures

    private func cardGesture(_ p: Placement) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("table"))
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if !dragging && distance > 4 && p.card.faceUp && p.pile != .stock {
                    if engine.beginDrag(p.pile, index: p.index) {
                        dragging = true
                    }
                }
                if dragging { dragOffset = value.translation }
            }
            .onEnded { value in
                if dragging {
                    let target = Self.pile(at: value.location)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        engine.endDrag(on: target)
                        dragging = false
                        dragOffset = .zero
                    }
                } else {
                    tap(p)
                }
            }
    }

    private func tap(_ p: Placement) {
        let now = Date()
        if let last = lastTap, last.id == p.card.id, now.timeIntervalSince(last.time) < 0.35, p.pile != .stock {
            lastTap = nil
            engine.doubleTap(p.pile, index: p.index)
            return
        }
        lastTap = (p.card.id, now)
        engine.tap(p.pile, index: p.card.faceUp ? p.index : nil)
    }

    static func pile(at point: CGPoint) -> Pile? {
        let column = Int(((point.x - marginX + (columnStride - card.width) / 2) / columnStride).rounded(.down))
        guard (0..<7).contains(column) else { return nil }
        if point.y < tableauY - 4 {
            switch column {
            case 0: return .stock
            case 1: return .waste
            case 2: return nil
            default: return .foundation(column - 3)
            }
        }
        return .tableau(column)
    }
}

struct CardView: View {
    let card: Card
    var highlighted = false

    static let red = Color(hex: 0xE0364F)
    static let black = Color(hex: 0x1F1F2A)

    var body: some View {
        if card.faceUp {
            face
        } else {
            back
        }
    }

    private var face: some View {
        let color = card.isRed ? Self.red : Self.black
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFFFF), Color(hex: 0xEDEDF3)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(highlighted ? GameID.solitaire.style.accent : Color.black.opacity(0.12), lineWidth: highlighted ? 2 : 0.75)
            VStack(alignment: .leading, spacing: -2) {
                Text(card.rankLabel)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Text(card.suit.symbol)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(color)
            .padding(.leading, 6)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if card.rank > 10 {
                court(color)
            } else {
                Text(card.suit.symbol)
                    .font(.system(size: card.rank == 1 ? 38 : 30, weight: .bold))
                    .foregroundStyle(color.opacity(card.rank == 1 ? 1 : 0.85))
                    .shadow(color: card.rank == 1 ? color.opacity(0.35) : .clear, radius: 6, y: 2)
                    .offset(y: 8)
            }
        }
    }

    /// Jack, queen and king get a framed portrait panel.
    private func court(_ color: Color) -> some View {
        let symbol: String
        switch card.rank {
        case 13: symbol = "crown.fill"
        case 12: symbol = "crown"
        default: symbol = "shield.lefthalf.filled"
        }
        let tint = card.isRed ? [Color(hex: 0xFFE6EB), Color(hex: 0xFFC7D2)] : [Color(hex: 0xE9EBF7), Color(hex: 0xC9CFEA)]
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: tint, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(color.opacity(0.3), lineWidth: 0.75)
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(card.suit.symbol)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.top, 38)
        .padding(.bottom, 7)
    }

    private var back: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x6E6CF0), Color(hex: 0x2C2A7A)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, size in
                var lines = Path()
                var x = -size.height
                while x < size.width {
                    lines.move(to: CGPoint(x: x, y: size.height))
                    lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 7
                }
                ctx.stroke(lines, with: .color(.white.opacity(0.07)), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                .padding(5)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}
