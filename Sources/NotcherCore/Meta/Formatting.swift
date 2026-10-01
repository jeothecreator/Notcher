import Foundation

public enum DayKey {
    /// `2026-10-01` in the given calendar's time zone.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Days since 2024-01-01 in the calendar's time zone. Stable across launches.
    public static func dayNumber(for date: Date, calendar: Calendar = .current) -> Int {
        var epoch = DateComponents()
        epoch.year = 2024
        epoch.month = 1
        epoch.day = 1
        guard let start = calendar.date(from: epoch) else { return 0 }
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

public enum Format {
    /// 1240 → "1,240"
    public static func grouped(_ value: Int) -> String {
        let negative = value < 0
        var digits = String(abs(value))
        var out = ""
        while digits.count > 3 {
            out = "," + String(digits.suffix(3)) + out
            digits.removeLast(3)
        }
        return (negative ? "-" : "") + digits + out
    }

    /// 14_820 → "14.8K", 2_300_000 → "2.3M". Values under 10k stay grouped.
    public static func compact(_ value: Double) -> String {
        let v = abs(value)
        let sign = value < 0 ? "-" : ""
        func trimmed(_ x: Double, _ suffix: String) -> String {
            let rounded = (x * 10 + 1e-7).rounded(.down) / 10
            if rounded >= 100 || rounded == rounded.rounded(.down) {
                return sign + String(Int(rounded)) + suffix
            }
            return sign + String(format: "%.1f", rounded) + suffix
        }
        switch v {
        case ..<10_000: return sign + grouped(Int(v.rounded(.down)))
        case ..<1_000_000: return trimmed(v / 1_000, "K")
        case ..<1_000_000_000: return trimmed(v / 1_000_000, "M")
        case ..<1_000_000_000_000: return trimmed(v / 1_000_000_000, "B")
        default: return trimmed(v / 1_000_000_000_000, "T")
        }
    }

    /// Milliseconds → "1:23.4"
    public static func duration(ms: Int) -> String {
        let tenths = max(0, ms) / 100
        let minutes = tenths / 600
        let seconds = (tenths / 10) % 60
        return String(format: "%d:%02d.%d", minutes, seconds, tenths % 10)
    }

    /// Seconds → "2h 14m" / "14m" / "42s"
    public static func playTime(seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }

    public static func score(_ value: Int, format: ScoreFormat) -> String {
        switch format {
        case .points: return grouped(value)
        case .milliseconds: return "\(value) ms"
        case .duration: return duration(ms: value)
        }
    }

    public static func score(_ value: Int, board: String) -> String {
        score(value, format: BoardInfo.format(for: board))
    }
}
