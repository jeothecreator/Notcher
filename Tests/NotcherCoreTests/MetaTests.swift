import XCTest
@testable import NotcherCore

final class FormatTests: XCTestCase {
    func testGrouped() {
        XCTAssertEqual(Format.grouped(0), "0")
        XCTAssertEqual(Format.grouped(999), "999")
        XCTAssertEqual(Format.grouped(1_240), "1,240")
        XCTAssertEqual(Format.grouped(24_821), "24,821")
        XCTAssertEqual(Format.grouped(1_000_000), "1,000,000")
        XCTAssertEqual(Format.grouped(-4_500), "-4,500")
    }

    func testCompact() {
        XCTAssertEqual(Format.compact(950), "950")
        XCTAssertEqual(Format.compact(9_999), "9,999")
        XCTAssertEqual(Format.compact(14_820), "14.8K")
        XCTAssertEqual(Format.compact(20_000), "20K")
        XCTAssertEqual(Format.compact(2_300_000), "2.3M")
        XCTAssertEqual(Format.compact(125_000), "125K")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(ms: 0), "0:00.0")
        XCTAssertEqual(Format.duration(ms: 83_450), "1:23.4")
        XCTAssertEqual(Format.score(142, format: .milliseconds), "142 ms")
    }
}

final class RandomTests: XCTestCase {
    func testDeterministic() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = SeededRandom(seed: 7)
        for _ in 0..<1000 {
            let u = c.unit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
            let i = c.int(3...5)
            XCTAssertTrue((3...5).contains(i))
        }
    }

    func testCircleHit() {
        let box = Box(x: 0, y: 0, w: 10, h: 10)
        XCTAssertNil(box.circleHit(center: Vec2(20, 5), radius: 3))
        XCTAssertEqual(box.circleHit(center: Vec2(12, 5), radius: 3), Vec2(1, 0))
        XCTAssertEqual(box.circleHit(center: Vec2(5, -2), radius: 3), Vec2(0, -1))
    }
}

final class ScoreBookTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testHigherIsBetter() {
        var book = ScoreBook()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let first = book.record(100, board: "runner", at: now, calendar: calendar)
        XCTAssertTrue(first.isPersonalBest)
        XCTAssertNil(first.previousBest)
        XCTAssertEqual(first.rankToday, 1)

        let second = book.record(50, board: "runner", at: now.addingTimeInterval(10), calendar: calendar)
        XCTAssertFalse(second.isPersonalBest)
        XCTAssertEqual(second.rankToday, 2)

        let third = book.record(300, board: "runner", at: now.addingTimeInterval(20), calendar: calendar)
        XCTAssertTrue(third.isPersonalBest)
        XCTAssertEqual(third.previousBest, 100)
        XCTAssertEqual(third.rankToday, 1)
        XCTAssertEqual(book.best("runner"), 300)
        XCTAssertEqual(book.top("runner", period: .today, now: now, calendar: calendar).map(\.value), [300, 100, 50])
    }

    func testLowerIsBetter() {
        var book = ScoreBook()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        book.record(240, board: "reaction", at: now, calendar: calendar)
        let r = book.record(180, board: "reaction", at: now.addingTimeInterval(1), calendar: calendar)
        XCTAssertTrue(r.isPersonalBest)
        XCTAssertEqual(book.best("reaction"), 180)
        let slower = book.record(400, board: "reaction", at: now.addingTimeInterval(2), calendar: calendar)
        XCTAssertFalse(slower.isPersonalBest)
        XCTAssertEqual(slower.rankToday, 3)
    }

    func testPeriods() {
        var book = ScoreBook()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        book.record(10, board: "snake", at: now.addingTimeInterval(-86_400 * 3), calendar: calendar)
        book.record(20, board: "snake", at: now.addingTimeInterval(-86_400 * 10), calendar: calendar)
        book.record(5, board: "snake", at: now, calendar: calendar)
        XCTAssertEqual(book.top("snake", period: .today, now: now, calendar: calendar).map(\.value), [5])
        XCTAssertEqual(book.top("snake", period: .week, now: now, calendar: calendar).map(\.value), [10, 5])
        XCTAssertEqual(book.top("snake", period: .allTime, now: now, calendar: calendar).map(\.value), [20, 10, 5])
    }

    func testPruningKeepsBest() {
        var book = ScoreBook()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<300 {
            book.record(i, board: "pong", at: start.addingTimeInterval(Double(i) * 3600), calendar: calendar)
        }
        XCTAssertLessThanOrEqual(book.runs("pong"), 300)
        XCTAssertEqual(book.best("pong"), 299)
    }
}

final class StatsAndAchievementTests: XCTestCase {
    func testApplyEvents() {
        var stats = PlayerStats()
        stats.apply(.count("snake.apples", 3))
        stats.apply(.count("snake.apples", 2))
        stats.apply(.maximum("snake.length", 12))
        stats.apply(.maximum("snake.length", 8))
        stats.apply(.minimum("reaction.ms", 300))
        stats.apply(.minimum("reaction.ms", 220))
        XCTAssertEqual(stats.counter("snake.apples"), 5)
        XCTAssertEqual(stats.maximum("snake.length"), 12)
        XCTAssertEqual(stats.minimum("reaction.ms"), 220)
    }

    func testUnlocking() {
        var stats = PlayerStats()
        XCTAssertTrue(AchievementCatalog.newlyUnlocked(stats: stats, unlocked: []).isEmpty)
        stats.apply(.count("runner.runs", 1))
        stats.noteScore(150, board: "runner")
        stats.apply(.minimum("reaction.ms", 240))
        let ids = Set(AchievementCatalog.newlyUnlocked(stats: stats, unlocked: []).map(\.id))
        XCTAssertEqual(ids, ["runner.first", "runner.100", "reaction.250"])
        let again = AchievementCatalog.newlyUnlocked(stats: stats, unlocked: ids)
        XCTAssertTrue(again.isEmpty)
    }

    func testUniqueIDs() {
        let ids = AchievementCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testDailyStreak() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        var stats = PlayerStats()
        for back in [1, 2, 3, 5] {
            stats.markDaily(DayKey.key(for: today.addingTimeInterval(-86_400 * Double(back)), calendar: cal))
        }
        XCTAssertEqual(stats.dailyStreak(today: today, calendar: cal), 3)
        stats.markDaily(DayKey.key(for: today, calendar: cal))
        XCTAssertEqual(stats.dailyStreak(today: today, calendar: cal), 4)
    }

    func testRecentGames() {
        var stats = PlayerStats()
        for game in [GameID.snake, .runner, .snake, .lexi] { stats.noteLaunch(game) }
        XCTAssertEqual(stats.recentGames, [.lexi, .snake, .runner])
        for game in GameID.allCases { stats.noteLaunch(game) }
        XCTAssertEqual(stats.recent.count, 8)
        XCTAssertEqual(stats.recentGames.first, GameID.allCases.last)
    }

    func testProfileID() {
        var rng = SeededRandom(seed: 1)
        let p = PlayerProfile.generate(using: &rng)
        XCTAssertTrue(p.id.hasPrefix("PLAYER-"))
        XCTAssertEqual(p.id.count, 11)
        XCTAssertEqual(p.displayName, p.id)
        XCTAssertEqual(PlayerProfile(id: "PLAYER-AAAA", nickname: "  neonfox ").displayName, "neonfox")
    }
}

final class DailyChallengeTests: XCTestCase {
    func testStableAndVaried() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let a = DailyChallenge.forDate(day, calendar: cal)
        let b = DailyChallenge.forDate(day.addingTimeInterval(60), calendar: cal)
        XCTAssertEqual(a, b)
        var games = Set<GameID>()
        for i in 0..<7 {
            games.insert(DailyChallenge.forDate(day.addingTimeInterval(86_400 * Double(i)), calendar: cal).game)
        }
        XCTAssertEqual(games.count, 7)
    }

    func testIsMet() {
        let runner = DailyChallenge(dayKey: "x", game: .runner, target: 3000, seed: 1)
        XCTAssertTrue(runner.isMet(by: 3000))
        XCTAssertFalse(runner.isMet(by: 2999))
        let reaction = DailyChallenge(dayKey: "x", game: .reaction, target: 260, seed: 1)
        XCTAssertTrue(reaction.isMet(by: 200))
        XCTAssertFalse(reaction.isMet(by: 300))
        XCTAssertEqual(DailyChallenge(dayKey: "x", game: .mines, target: 150_000, seed: 1).goal, "Clear the field in 2:30")
    }
}

final class SaveTests: XCTestCase {
    func testRoundTrip() throws {
        var save = ArcadeSave(profile: PlayerProfile(id: "PLAYER-TEST"))
        save.scores.record(1234, board: "runner")
        save.stats.apply(.count("snake.apples", 4))
        save.achievements["runner.first"] = Date(timeIntervalSince1970: 1_000)
        save.miner = MinerState(now: Date(timeIntervalSince1970: 2_000))
        save.farm = FarmState()
        let data = try save.encoded()
        let back = try ArcadeSave.decode(data)
        XCTAssertEqual(back.profile.id, "PLAYER-TEST")
        XCTAssertEqual(back.scores.best("runner"), 1234)
        XCTAssertEqual(back.stats.counter("snake.apples"), 4)
        XCTAssertEqual(back.achievements["runner.first"], Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(back.miner?.lastUpdate, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(back.farm?.unlocked, 4)
    }

    func testTolerantDecoding() throws {
        let save = try ArcadeSave.decode(Data("{}".utf8))
        XCTAssertTrue(save.profile.id.hasPrefix("PLAYER-"))
        XCTAssertEqual(save.stats.gamesPlayed, 0)
        let partial = try ArcadeSave.decode(Data(#"{"profile":{"id":"PLAYER-ABCD"},"stats":{"escExits":7}}"#.utf8))
        XCTAssertEqual(partial.profile.id, "PLAYER-ABCD")
        XCTAssertEqual(partial.stats.escExits, 7)
    }
}

final class CatalogTests: XCTestCase {
    func testTwentyGames() {
        XCTAssertEqual(GameID.allCases.count, 20)
        XCTAssertEqual(Set(GameID.allCases.map(\.title)).count, 20)
        for category in GameCategory.allCases {
            XCTAssertFalse(GameID.inCategory(category).isEmpty)
        }
        XCTAssertEqual(BoardInfo.title(for: "arcade.flap"), "Arcade · Flap")
        XCTAssertEqual(BoardInfo.order(for: "mines"), .lowerIsBetter)
    }

    func testFeaturedArcadeRotates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let minis = (0..<6).map { ArcadeMini.featured(on: day.addingTimeInterval(86_400 * Double($0)), calendar: cal) }
        XCTAssertEqual(Set(minis).count, 6)
    }
}
