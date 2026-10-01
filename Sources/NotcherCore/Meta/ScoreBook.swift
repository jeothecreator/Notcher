import Foundation

public struct ScoreEntry: Codable, Equatable, Sendable {
    public var value: Int
    public var date: Date
    public var daily: Bool

    public init(value: Int, date: Date, daily: Bool = false) {
        self.value = value
        self.date = date
        self.daily = daily
    }
}

public enum LeaderboardPeriod: String, CaseIterable, Sendable {
    case today, week, allTime

    public var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .allTime: return "All Time"
        }
    }
}

public struct RecordResult: Equatable, Sendable {
    public var value: Int
    public var isPersonalBest: Bool
    public var previousBest: Int?
    /// 1-based rank among today's runs.
    public var rankToday: Int
    public var runsToday: Int
}

/// Local score history for every board.
public struct ScoreBook: Codable, Equatable, Sendable {
    public var boards: [String: [ScoreEntry]] = [:]

    public init() {}

    static func better(_ a: Int, _ b: Int, _ order: ScoreOrder) -> Bool {
        order == .higherIsBetter ? a > b : a < b
    }

    public func best(_ board: String) -> Int? {
        let order = BoardInfo.order(for: board)
        return boards[board]?.map(\.value).min { Self.better($0, $1, order) }
    }

    public func runs(_ board: String) -> Int { boards[board]?.count ?? 0 }

    @discardableResult
    public mutating func record(_ value: Int, board: String, daily: Bool = false, at date: Date = Date(), calendar: Calendar = .current) -> RecordResult {
        let order = BoardInfo.order(for: board)
        let previous = best(board)
        var list = boards[board] ?? []
        list.append(ScoreEntry(value: value, date: date, daily: daily))
        boards[board] = Self.pruned(list, order: order, now: date, calendar: calendar)

        let today = top(board, period: .today, now: date, calendar: calendar, limit: .max)
        let rank = (today.firstIndex { $0.value == value && $0.date == date } ?? (today.count - 1)) + 1
        let isBest = previous.map { Self.better(value, $0, order) } ?? true
        return RecordResult(value: value, isPersonalBest: isBest, previousBest: previous, rankToday: rank, runsToday: today.count)
    }

    /// Keeps the 60 best runs ever plus everything from the last 8 days.
    static func pruned(_ list: [ScoreEntry], order: ScoreOrder, now: Date, calendar: Calendar) -> [ScoreEntry] {
        guard list.count > 120 else { return list }
        let cutoff = calendar.date(byAdding: .day, value: -8, to: now) ?? now
        let ranked = Self.sorted(list, order)
        let keep = Set(ranked.prefix(60).map { "\($0.value)-\($0.date.timeIntervalSince1970)" })
        return list.filter { $0.date >= cutoff || keep.contains("\($0.value)-\($0.date.timeIntervalSince1970)") }
    }

    static func sorted(_ list: [ScoreEntry], _ order: ScoreOrder) -> [ScoreEntry] {
        list.sorted { a, b in
            if a.value != b.value { return better(a.value, b.value, order) }
            return a.date < b.date
        }
    }

    public func top(_ board: String, period: LeaderboardPeriod, now: Date = Date(), calendar: Calendar = .current, limit: Int = 10) -> [ScoreEntry] {
        let list = boards[board] ?? []
        let filtered: [ScoreEntry]
        switch period {
        case .today:
            filtered = list.filter { calendar.isDate($0.date, inSameDayAs: now) }
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            filtered = list.filter { $0.date >= start }
        case .allTime:
            filtered = list
        }
        return Array(Self.sorted(filtered, BoardInfo.order(for: board)).prefix(limit))
    }

    public func bestDaily(_ board: String, on date: Date, calendar: Calendar = .current) -> Int? {
        let order = BoardInfo.order(for: board)
        return boards[board]?
            .filter { $0.daily && calendar.isDate($0.date, inSameDayAs: date) }
            .map(\.value)
            .min { Self.better($0, $1, order) }
    }
}
