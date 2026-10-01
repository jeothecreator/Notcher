import Foundation

public struct PlayerStats: Codable, Equatable, Sendable {
    /// Runs actually started (first key press in a game).
    public var gamesPlayed = 0
    /// Times a game was opened from the launcher.
    public var gameLaunches = 0
    public var escExits = 0
    public var playSeconds: Double = 0
    public var counters: [String: Int] = [:]
    public var maxima: [String: Int] = [:]
    public var minima: [String: Int] = [:]
    /// Runs per game id.
    public var plays: [String: Int] = [:]
    /// Day keys of completed daily challenges.
    public var dailyCompleted: [String] = []

    public init() {}

    public func counter(_ key: String) -> Int { counters[key] ?? 0 }
    public func maximum(_ key: String) -> Int { maxima[key] ?? 0 }
    public func minimum(_ key: String) -> Int? { minima[key] }

    public mutating func apply(_ event: GameEvent) {
        switch event {
        case .count(let key, let amount):
            counters[key, default: 0] += amount
        case .maximum(let key, let value):
            maxima[key] = max(maxima[key] ?? value, value)
        case .minimum(let key, let value):
            minima[key] = min(minima[key] ?? value, value)
        case .sound, .record, .shake:
            break
        }
    }

    /// Generic score stats so achievements can target any board.
    public mutating func noteScore(_ value: Int, board: String) {
        switch BoardInfo.order(for: board) {
        case .higherIsBetter: apply(.maximum("score.\(board)", value))
        case .lowerIsBetter: apply(.minimum("score.\(board)", value))
        }
    }

    public mutating func markDaily(_ dayKey: String) {
        if !dailyCompleted.contains(dayKey) {
            dailyCompleted.append(dayKey)
        }
    }

    /// Consecutive days (ending today or yesterday) with a completed challenge.
    public func dailyStreak(today: Date, calendar: Calendar = .current) -> Int {
        let done = Set(dailyCompleted)
        var streak = 0
        var day = today
        if !done.contains(DayKey.key(for: day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while done.contains(DayKey.key(for: day, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    enum CodingKeys: String, CodingKey {
        case gamesPlayed, gameLaunches, escExits, playSeconds, counters, maxima, minima, plays, dailyCompleted
    }

    // Tolerant decoding: new fields never invalidate an old save.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gamesPlayed = try c.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        gameLaunches = try c.decodeIfPresent(Int.self, forKey: .gameLaunches) ?? 0
        escExits = try c.decodeIfPresent(Int.self, forKey: .escExits) ?? 0
        playSeconds = try c.decodeIfPresent(Double.self, forKey: .playSeconds) ?? 0
        counters = try c.decodeIfPresent([String: Int].self, forKey: .counters) ?? [:]
        maxima = try c.decodeIfPresent([String: Int].self, forKey: .maxima) ?? [:]
        minima = try c.decodeIfPresent([String: Int].self, forKey: .minima) ?? [:]
        plays = try c.decodeIfPresent([String: Int].self, forKey: .plays) ?? [:]
        dailyCompleted = try c.decodeIfPresent([String].self, forKey: .dailyCompleted) ?? []
    }
}

public struct PlayerProfile: Codable, Equatable, Sendable {
    /// Anonymous, e.g. `PLAYER-7X42`.
    public var id: String
    public var nickname: String?

    public init(id: String, nickname: String? = nil) {
        self.id = id
        self.nickname = nickname
    }

    public var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    public static func generate<R: RandomNumberGenerator>(using rng: inout R) -> PlayerProfile {
        // No 0/O or 1/I so IDs read cleanly.
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        let tag = String((0..<4).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
        return PlayerProfile(id: "PLAYER-\(tag)")
    }

    public static func generate() -> PlayerProfile {
        var rng = SystemRandomNumberGenerator()
        return generate(using: &rng)
    }
}

/// Everything Notcher persists, in one Codable document.
public struct ArcadeSave: Codable, Equatable, Sendable {
    public var version = 1
    public var profile: PlayerProfile
    public var scores = ScoreBook()
    public var stats = PlayerStats()
    /// Achievement id → unlock date.
    public var achievements: [String: Date] = [:]
    public var miner: MinerState?
    public var farm: FarmState?

    public init(profile: PlayerProfile = .generate()) {
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case version, profile, scores, stats, achievements, miner, farm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        profile = try c.decodeIfPresent(PlayerProfile.self, forKey: .profile) ?? .generate()
        scores = (try? c.decodeIfPresent(ScoreBook.self, forKey: .scores)) ?? ScoreBook()
        stats = (try? c.decodeIfPresent(PlayerStats.self, forKey: .stats)) ?? PlayerStats()
        achievements = (try? c.decodeIfPresent([String: Date].self, forKey: .achievements)) ?? [:]
        miner = try? c.decodeIfPresent(MinerState.self, forKey: .miner)
        farm = try? c.decodeIfPresent(FarmState.self, forKey: .farm)
    }

    public static func decode(_ data: Data) throws -> ArcadeSave {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(ArcadeSave.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
