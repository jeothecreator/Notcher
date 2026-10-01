import Foundation

public enum Suit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs

    public var isRed: Bool { self == .hearts || self == .diamonds }

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }
}

public struct Card: Hashable, Codable, Sendable, Identifiable {
    /// 0…51; suit-major.
    public let id: Int
    public var faceUp: Bool

    public init(id: Int, faceUp: Bool = false) {
        self.id = id
        self.faceUp = faceUp
    }

    public init(rank: Int, suit: Suit, faceUp: Bool = true) {
        self.init(id: suit.rawValue * 13 + rank - 1, faceUp: faceUp)
    }

    public var rank: Int { id % 13 + 1 }
    public var suit: Suit { Suit(rawValue: id / 13) ?? .spades }
    public var isRed: Bool { suit.isRed }

    public var rankLabel: String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return String(rank)
        }
    }
}

public enum Pile: Hashable, Sendable {
    case stock, waste, foundation(Int), tableau(Int)

    public var isTableau: Bool {
        if case .tableau = self { return true }
        return false
    }

    /// Column in the 7-wide layout.
    public var column: Int {
        switch self {
        case .stock: return 0
        case .waste: return 1
        case .foundation(let i): return 3 + i
        case .tableau(let i): return i
        }
    }

    static let topRow: [Pile] = [.stock, .waste, .foundation(0), .foundation(1), .foundation(2), .foundation(3)]
}

public struct SolitaireBoard: Equatable, Sendable {
    public var stock: [Card] = []
    public var waste: [Card] = []
    public var foundations: [[Card]] = Array(repeating: [], count: 4)
    public var tableau: [[Card]] = Array(repeating: [], count: 7)

    public init() {}

    public func cards(in pile: Pile) -> [Card] {
        switch pile {
        case .stock: return stock
        case .waste: return waste
        case .foundation(let i): return foundations[i]
        case .tableau(let i): return tableau[i]
        }
    }

    mutating func set(_ cards: [Card], in pile: Pile) {
        switch pile {
        case .stock: stock = cards
        case .waste: waste = cards
        case .foundation(let i): foundations[i] = cards
        case .tableau(let i): tableau[i] = cards
        }
    }

    public var isWon: Bool { foundations.allSatisfy { $0.count == 13 } }
}

/// Klondike solitaire with undo, keyboard cursor, click and drag support.
public final class SolitaireEngine: EngineBase, GameEngine {
    public struct Hold: Equatable, Sendable {
        public let from: Pile
        public let count: Int
    }

    public private(set) var board = SolitaireBoard()
    public private(set) var cursor: Pile = .tableau(0)
    /// How many face-up cards are selected at the cursor (tableau only).
    public private(set) var depth = 1
    public private(set) var held: Hold?
    public private(set) var moves = 0
    public private(set) var elapsed = 0.0
    public private(set) var won = false
    public private(set) var autoFinishing = false
    public let drawCount: Int

    private var history: [SolitaireBoard] = []
    private var rng: SeededRandom
    private var autoTimer = 0.0

    public init(seed: UInt64? = nil, drawCount: Int = 1) {
        self.rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        self.drawCount = drawCount == 3 ? 3 : 1
        super.init(boardKey: GameID.solitaire.rawValue)
        deal()
    }

    public var canUndo: Bool { !history.isEmpty }

    private func deal() {
        var deck = (0..<52).map { Card(id: $0) }
        deck.shuffle(using: &rng)
        board = SolitaireBoard()
        for col in 0..<7 {
            for row in 0...col {
                var card = deck.removeLast()
                card.faceUp = row == col
                board.tableau[col].append(card)
            }
        }
        board.stock = deck
        history = []
        moves = 0
        elapsed = 0
        won = false
        autoFinishing = false
        held = nil
        cursor = .tableau(0)
        depth = 1
        score = 0
        phase = .ready
    }

    public func restart() { deal() }

    /// Test hook.
    func load(_ b: SolitaireBoard) {
        board = b
        history = []
        held = nil
        phase = .playing
    }

    // MARK: Rules

    public func faceUpCount(_ pile: Pile) -> Int {
        board.cards(in: pile).reversed().prefix { $0.faceUp }.count
    }

    /// The cards that would be picked up from `pile`.
    func available(from pile: Pile, count: Int) -> [Card]? {
        let cards = board.cards(in: pile)
        guard count >= 1, cards.count >= count else { return nil }
        switch pile {
        case .stock:
            return nil
        case .waste, .foundation:
            return count == 1 ? [cards[cards.count - 1]] : nil
        case .tableau:
            let run = Array(cards.suffix(count))
            return run.allSatisfy(\.faceUp) ? run : nil
        }
    }

    public func canDrop(_ cards: [Card], on pile: Pile) -> Bool {
        guard let first = cards.first else { return false }
        switch pile {
        case .foundation(let i):
            guard cards.count == 1 else { return false }
            guard let top = board.foundations[i].last else { return first.rank == 1 }
            return top.suit == first.suit && top.rank + 1 == first.rank
        case .tableau(let i):
            guard let top = board.tableau[i].last else { return first.rank == 13 }
            return top.faceUp && top.isRed != first.isRed && top.rank == first.rank + 1
        case .stock, .waste:
            return false
        }
    }

    /// Moves `count` cards from one pile to another if the rules allow it.
    @discardableResult
    public func move(from: Pile, count: Int, to: Pile) -> Bool {
        guard from != to, let cards = available(from: from, count: count), canDrop(cards, on: to) else {
            return false
        }
        history.append(board)
        if history.count > 200 { history.removeFirst() }
        var source = board.cards(in: from)
        source.removeLast(count)
        if case .tableau = from, let last = source.last, !last.faceUp {
            source[source.count - 1].faceUp = true
        }
        board.set(source, in: from)
        board.set(board.cards(in: to) + cards, in: to)
        didMove()
        if case .foundation = to {
            play(.place)
            emit(.count("solitaire.foundation", 1))
        } else {
            play(.card)
        }
        checkWin()
        return true
    }

    private func didMove() {
        moves += 1
        if phase == .ready { phase = .playing }
    }

    public func draw() {
        guard phase != .over else { return }
        held = nil
        if board.stock.isEmpty {
            guard !board.waste.isEmpty else {
                play(.error)
                return
            }
            history.append(board)
            board.stock = board.waste.reversed().map { var c = $0; c.faceUp = false; return c }
            board.waste = []
            play(.slide)
        } else {
            history.append(board)
            for _ in 0..<min(drawCount, board.stock.count) {
                var card = board.stock.removeLast()
                card.faceUp = true
                board.waste.append(card)
            }
            play(.card)
        }
        didMove()
    }

    /// Sends the top card (or run) somewhere useful: foundations first.
    @discardableResult
    public func smartMove(from pile: Pile, count: Int = 1) -> Bool {
        held = nil
        if count == 1 {
            for f in 0..<4 where move(from: pile, count: 1, to: .foundation(f)) { return true }
        }
        guard available(from: pile, count: count) != nil else {
            play(.error)
            return false
        }
        // Prefer building on cards over using empty columns.
        let targets = (0..<7).map { Pile.tableau($0) }.filter { $0 != pile }
        let sorted = targets.filter { !board.cards(in: $0).isEmpty } + targets.filter { board.cards(in: $0).isEmpty }
        for t in sorted {
            // Don't shuffle a king from one empty column to another.
            if board.cards(in: t).isEmpty, case .tableau = pile, board.cards(in: pile).count == count { continue }
            if move(from: pile, count: count, to: t) { return true }
        }
        play(.error)
        return false
    }

    public func undo() {
        guard let previous = history.popLast() else {
            play(.error)
            return
        }
        board = previous
        held = nil
        autoFinishing = false
        moves += 1
        play(.slide)
    }

    private func checkWin() {
        if board.isWon {
            won = true
            autoFinishing = false
            phase = .over
            score = Int(elapsed * 1000)
            play(.win)
            emit(.record(score))
            emit(.count("solitaire.wins", 1))
            emit(.minimum("solitaire.time", score))
            return
        }
        if !autoFinishing && board.stock.isEmpty && board.waste.isEmpty
            && board.tableau.allSatisfy({ $0.allSatisfy(\.faceUp) }) {
            autoFinishing = true
            autoTimer = 0.25
        }
    }

    private func autoFinishStep() {
        // Lowest card that can go up next.
        var best: (pile: Pile, rank: Int)?
        for i in 0..<7 {
            guard let top = board.tableau[i].last else { continue }
            if (0..<4).contains(where: { canDrop([top], on: .foundation($0)) }), top.rank < (best?.rank ?? 99) {
                best = (.tableau(i), top.rank)
            }
        }
        guard let source = best?.pile else {
            autoFinishing = false
            return
        }
        for f in 0..<4 where move(from: source, count: 1, to: .foundation(f)) { break }
    }

    // MARK: Engine

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        guard phase == .playing else { return }
        elapsed += dt
        score = Int(elapsed * 1000)
        if autoFinishing {
            autoTimer -= dt
            if autoTimer <= 0 {
                autoTimer = 0.07
                autoFinishStep()
            }
        }
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .paused {
            resume()
            return true
        }
        if phase == .over {
            if key == .primary || key == .confirm || key == .restart {
                if !isRepeat { deal() }
                return true
            }
            return false
        }
        switch key {
        case .left: moveCursor(-1)
        case .right: moveCursor(1)
        case .up: cursorUp()
        case .down: cursorDown()
        case .primary, .confirm:
            if !isRepeat { activate() }
        case .cycle:
            draw()
        case .auto:
            smartMove(from: cursor, count: cursor.isTableau ? depth : 1)
        case .undo:
            undo()
        case .restart:
            deal()
        default:
            return false
        }
        return true
    }

    private func moveCursor(_ step: Int) {
        if case .tableau(let i) = cursor {
            cursor = .tableau((i + step + 7) % 7)
            depth = 1
        } else {
            let row = Pile.topRow
            let i = row.firstIndex(of: cursor) ?? 0
            cursor = row[(i + step + row.count) % row.count]
        }
        play(.tick)
    }

    private func cursorUp() {
        if case .tableau(let i) = cursor {
            if held == nil && depth < faceUpCount(cursor) {
                depth += 1
            } else {
                let col = i
                cursor = col <= 1 ? (col == 0 ? .stock : .waste) : (col == 2 ? .waste : .foundation(col - 3))
                depth = 1
            }
            play(.tick)
        }
    }

    private func cursorDown() {
        if case .tableau = cursor {
            if depth > 1 {
                depth -= 1
                play(.tick)
            }
            return
        }
        cursor = .tableau(cursor.column)
        depth = 1
        play(.tick)
    }

    /// Enter: pick up at the cursor, or drop what is held.
    private func activate() {
        if let h = held {
            if h.from == cursor {
                held = nil
                play(.tick)
            } else if move(from: h.from, count: h.count, to: cursor) {
                held = nil
                depth = 1
            } else {
                play(.error)
            }
            return
        }
        if cursor == .stock {
            draw()
            return
        }
        let count = cursor.isTableau ? depth : 1
        if available(from: cursor, count: count) != nil {
            held = Hold(from: cursor, count: count)
            play(.select)
        } else {
            play(.error)
        }
    }

    // MARK: Mouse

    /// Click on a pile; `index` is the card index within the pile (tableau).
    public func tap(_ pile: Pile, index: Int?) {
        guard phase != .over else { return }
        if let h = held {
            held = nil
            if h.from != pile, !move(from: h.from, count: h.count, to: pile) {
                play(.error)
            }
            cursor = pile
            depth = 1
            return
        }
        cursor = pile
        if pile == .stock {
            draw()
            return
        }
        let cards = board.cards(in: pile)
        let count = pile.isTableau ? cards.count - (index ?? cards.count - 1) : 1
        depth = max(1, count)
        if available(from: pile, count: count) != nil {
            held = Hold(from: pile, count: count)
            play(.select)
        }
    }

    public func doubleTap(_ pile: Pile, index: Int?) {
        guard phase != .over, pile != .stock else { return }
        held = nil
        let cards = board.cards(in: pile)
        let count = pile.isTableau ? cards.count - (index ?? cards.count - 1) : 1
        smartMove(from: pile, count: max(1, count))
    }

    /// Start dragging from a card. Returns false if the card can't be dragged.
    @discardableResult
    public func beginDrag(_ pile: Pile, index: Int) -> Bool {
        guard phase != .over else { return false }
        let count = board.cards(in: pile).count - index
        guard available(from: pile, count: count) != nil else { return false }
        held = Hold(from: pile, count: count)
        cursor = pile
        return true
    }

    public func endDrag(on pile: Pile?) {
        guard let h = held else { return }
        held = nil
        guard let pile, pile != h.from else { return }
        if move(from: h.from, count: h.count, to: pile) {
            cursor = pile
            depth = 1
        } else {
            play(.error)
        }
    }

    public func cancelHold() {
        held = nil
    }
}
