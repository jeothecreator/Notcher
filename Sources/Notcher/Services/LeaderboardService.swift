import Foundation
import NotcherCore

struct RemoteScore: Identifiable, Equatable, Decodable {
    var id: String { "\(player_id)-\(value)" }
    let player_id: String
    let name: String
    let value: Int
}

/// Optional global leaderboards backed by a Supabase (PostgREST) table.
/// See `Backend/supabase.sql`. Without a configured server everything stays local.
@MainActor
final class LeaderboardService {
    private var baseURL: URL? {
        let raw = (Prefs.defaults.string(forKey: Prefs.Key.leaderboardURL) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }

    private var apiKey: String {
        (Prefs.defaults.string(forKey: Prefs.Key.leaderboardKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool { baseURL != nil && !apiKey.isEmpty }

    private func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard let base = baseURL, !apiKey.isEmpty,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    func submit(board: String, value: Int, profile: PlayerProfile) {
        guard var req = request("rest/v1/scores") else { return }
        req.httpMethod = "POST"
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "board": board,
            "player_id": profile.id,
            "name": profile.displayName,
            "value": value,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Best score per player for a board.
    func top(board: String, period: LeaderboardPeriod, limit: Int = 10) async -> [RemoteScore]? {
        let ascending = BoardInfo.order(for: board) == .lowerIsBetter
        var query = [
            URLQueryItem(name: "board", value: "eq.\(board)"),
            URLQueryItem(name: "select", value: "player_id,name,value"),
            URLQueryItem(name: "order", value: "value.\(ascending ? "asc" : "desc")"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        if let since = Self.start(of: period) {
            query.append(URLQueryItem(name: "created_at", value: "gte.\(ISO8601DateFormatter().string(from: since))"))
        }
        guard let req = request("rest/v1/scores", query: query) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let rows = try JSONDecoder().decode([RemoteScore].self, from: data)
            var seen = Set<String>()
            var best: [RemoteScore] = []
            for row in rows where !seen.contains(row.player_id) {
                seen.insert(row.player_id)
                best.append(row)
                if best.count == limit { break }
            }
            return best
        } catch {
            return nil
        }
    }

    static func start(of period: LeaderboardPeriod) -> Date? {
        let cal = Calendar.current
        switch period {
        case .today: return cal.startOfDay(for: Date())
        case .week: return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))
        case .allTime: return nil
        }
    }
}
