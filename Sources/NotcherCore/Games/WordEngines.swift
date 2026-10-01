import Foundation

// MARK: - Lexi

/// Guess the five-letter word in six tries.
public final class LexiEngine: EngineBase, GameEngine {
    public static let wordLength = 5
    public static let maxGuesses = 6
    /// Seconds between tiles flipping in a reveal.
    public static let flipStagger = 0.26

    public enum Mark: Int, Comparable, Sendable {
        case absent, present, correct

        public static func < (a: Mark, b: Mark) -> Bool { a.rawValue < b.rawValue }
    }

    public private(set) var answer = ""
    public private(set) var guesses: [String] = []
    public private(set) var marks: [[Mark]] = []
    public private(set) var current = ""
    /// Best known mark per letter, for the keyboard. Updated after each reveal.
    public private(set) var keyboard: [Character: Mark] = [:]
    /// Clock time each submitted row started flipping.
    public private(set) var revealedAt: [Double] = []
    public private(set) var rejectedAt: Double?
    public private(set) var message: (text: String, at: Double)?
    public private(set) var won = false

    public override var acceptsText: Bool { true }

    private let words: WordList
    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var pendingKeyboard: (marks: [Character: Mark], at: Double)?
    private var finishAt: Double?

    public init(seed: UInt64? = nil, words: WordList = .shared) {
        self.words = words
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.lexi.rawValue)
        reset()
    }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        answer = words.answers[rng.int(0...(words.answers.count - 1))]
        guesses = []
        marks = []
        current = ""
        keyboard = [:]
        revealedAt = []
        rejectedAt = nil
        message = nil
        won = false
        pendingKeyboard = nil
        finishAt = nil
        score = 0
        phase = .ready
    }

    public func restart() { reset() }

    /// Test hook.
    func setAnswer(_ word: String) {
        answer = word
    }

    public static func mark(_ guess: String, against answer: String) -> [Mark] {
        let g = Array(guess), a = Array(answer)
        var result = Array(repeating: Mark.absent, count: g.count)
        var remaining: [Character: Int] = [:]
        for i in g.indices {
            if g[i] == a[i] {
                result[i] = .correct
            } else {
                remaining[a[i], default: 0] += 1
            }
        }
        for i in g.indices where result[i] != .correct {
            if let n = remaining[g[i]], n > 0 {
                result[i] = .present
                remaining[g[i]] = n - 1
            }
        }
        return result
    }

    public var isRevealing: Bool {
        guard let last = revealedAt.last else { return false }
        return clock - last < Double(Self.wordLength) * Self.flipStagger + 0.1
    }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        if let m = message, clock - m.at > 1.6 { message = nil }
        if let pending = pendingKeyboard, clock >= pending.at {
            for (letter, mark) in pending.marks where mark > (keyboard[letter] ?? .absent) || keyboard[letter] == nil {
                keyboard[letter] = mark
            }
            pendingKeyboard = nil
        }
        if let finish = finishAt, clock >= finish {
            finishAt = nil
            phase = .over
            if won {
                score = (Self.maxGuesses + 1 - guesses.count) * 100
                emit(.record(score))
                emit(.count("lexi.wins", 1))
                emit(.maximum("lexi.best", score))
                play(.win)
            } else {
                play(.lose)
                emit(.count("lexi.losses", 1))
            }
            emit(.count("lexi.games", 1))
        }
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .over {
            if key == .confirm || key == .primary { reset() }
            return true
        }
        if phase == .paused { resume() }
        guard finishAt == nil else { return true }
        switch key {
        case .char(let c):
            guard c.isLetter, c.isASCII, current.count < Self.wordLength else { return true }
            if phase == .ready { phase = .playing }
            current.append(Character(c.lowercased()))
            play(.key)
        case .backspace:
            if !current.isEmpty {
                current.removeLast()
                play(.tick)
            }
        case .confirm:
            submit()
        default:
            return false
        }
        return true
    }

    public func submit() {
        guard !isRevealing else { return }
        guard current.count == Self.wordLength else {
            reject("Not enough letters")
            return
        }
        guard current == answer || words.isValid(current) else {
            reject("Not in word list")
            return
        }
        let m = Self.mark(current, against: answer)
        guesses.append(current)
        marks.append(m)
        revealedAt.append(clock)
        var update: [Character: Mark] = [:]
        for (c, mark) in zip(current, m) where mark > (update[c] ?? .absent) || update[c] == nil {
            update[c] = mark
        }
        let revealEnd = clock + Double(Self.wordLength) * Self.flipStagger + 0.15
        pendingKeyboard = (update, revealEnd)
        play(.reveal)
        if current == answer {
            won = true
            finishAt = revealEnd + 0.9
            message = ([ "Genius", "Magnificent", "Impressive", "Splendid", "Great", "Phew" ][guesses.count - 1], revealEnd)
        } else if guesses.count >= Self.maxGuesses {
            finishAt = revealEnd + 1.2
            message = (answer.uppercased(), revealEnd)
        }
        current = ""
    }

    private func reject(_ text: String) {
        rejectedAt = clock
        message = (text, clock)
        play(.error)
    }
}

// MARK: - Typer

/// A 30-second typing test.
public final class TyperEngine: EngineBase, GameEngine {
    public static let duration = 30.0

    public private(set) var words: [String] = []
    public private(set) var index = 0
    public private(set) var typed = ""
    /// Per finished word: was it typed exactly?
    public private(set) var results: [Bool] = []
    public private(set) var correctChars = 0
    public private(set) var keystrokes = 0
    public private(set) var mistakes = 0
    public private(set) var elapsed = 0.0
    public private(set) var lastMistakeAt: Double?
    /// WPM samples, one per second, for the result graph.
    public private(set) var samples: [Int] = []

    public override var acceptsText: Bool { true }

    private let source: [String]
    private let fixedSeed: UInt64?
    private var rng: SeededRandom
    private var sampleTimer = 0.0

    public init(seed: UInt64? = nil, words: WordList = .shared) {
        source = words.typingWords
        fixedSeed = seed
        rng = SeededRandom(seed: seed ?? SeededRandom.randomSeed())
        super.init(boardKey: GameID.typer.rawValue)
        reset()
    }

    public var timeLeft: Double { max(0, Self.duration - elapsed) }

    public var wpm: Int {
        let minutes = max(elapsed, 1) / 60
        return Int((Double(correctChars) / 5 / minutes).rounded())
    }

    public var accuracy: Int {
        guard keystrokes > 0 else { return 100 }
        return Int((Double(keystrokes - mistakes) / Double(keystrokes) * 100).rounded())
    }

    public var currentWord: String { words[index] }

    /// True while what has been typed so far matches the current word.
    public var onTrack: Bool { currentWord.hasPrefix(typed) }

    private func reset() {
        rng = SeededRandom(seed: fixedSeed ?? SeededRandom.randomSeed())
        words = (0..<240).map { _ in source[rng.int(0...(source.count - 1))] }
        index = 0
        typed = ""
        results = []
        correctChars = 0
        keystrokes = 0
        mistakes = 0
        elapsed = 0
        samples = []
        sampleTimer = 0
        lastMistakeAt = nil
        score = 0
        phase = .ready
    }

    public func restart() { reset() }

    public func tick(_ dt: Double, input: InputState) {
        advanceClock(dt)
        guard phase == .playing else { return }
        elapsed += dt
        sampleTimer += dt
        if sampleTimer >= 1 {
            sampleTimer -= 1
            samples.append(wpm)
        }
        score = wpm
        if elapsed >= Self.duration { finish() }
    }

    @discardableResult
    public func handle(_ key: GameKey, isRepeat: Bool) -> Bool {
        if phase == .over {
            if key == .confirm || key == .primary { reset() }
            return true
        }
        if phase == .paused { resume() }
        switch key {
        case .char(let c):
            guard c.isLetter || c == "'" else { return true }
            if phase == .ready { phase = .playing }
            typed.append(Character(c.lowercased()))
            keystrokes += 1
            if !onTrack {
                mistakes += 1
                lastMistakeAt = clock
                play(.error)
            } else {
                play(.key)
            }
        case .backspace:
            if !typed.isEmpty { typed.removeLast() }
        case .primary, .confirm:
            guard phase == .playing, !typed.isEmpty else { return true }
            let ok = typed == currentWord
            results.append(ok)
            if ok { correctChars += currentWord.count + 1 }
            keystrokes += 1
            index += 1
            typed = ""
            play(ok ? .tick : .error)
        default:
            return false
        }
        return true
    }

    private func finish() {
        phase = .over
        score = wpm
        play(.win)
        emit(.record(score))
        emit(.maximum("typer.wpm", score))
        emit(.count("typer.tests", 1))
        if accuracy == 100 && results.count >= 10 { emit(.count("typer.perfect", 1)) }
    }
}
