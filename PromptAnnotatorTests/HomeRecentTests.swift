import XCTest
@testable import PromptAnnotator

final class HomeRecentTests: XCTestCase {
    func testRecentTakesNewestFirstLimit() {
        let sessions = (0..<6).map { index -> SessionSummary in
            SessionSummary(
                id: "s\(index)",
                url: URL(fileURLWithPath: "/tmp/s\(index)"),
                started: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 3600),
                ended: nil,
                tiles: 0,
                words: index,
                model: nil,
                transcript: "t\(index)",
                preview: "t\(index)"
            )
        }
        // Library sorts newest-first; feed already sorted newest-first like load().
        let newestFirst = sessions.reversed()
        let recent = SessionLibrary.recent(Array(newestFirst), limit: 4)
        XCTAssertEqual(recent.map(\.id), ["s5", "s4", "s3", "s2"])
        XCTAssertEqual(SessionLibrary.recent([], limit: 4), [])
    }

    func testWeeklyWordCountsBucketsLastSevenDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15))!
        // today, yesterday, 8 days ago (out of window)
        let sessions = [
            summary(id: "today", dayOffset: 0, words: 10, now: now, calendar: calendar),
            summary(id: "yesterday", dayOffset: -1, words: 5, now: now, calendar: calendar),
            summary(id: "old", dayOffset: -8, words: 100, now: now, calendar: calendar),
            summary(id: "today2", dayOffset: 0, words: 3, now: now, calendar: calendar),
        ]
        let counts = SessionLibrary.weeklyWordCounts(from: sessions, now: now, calendar: calendar)
        XCTAssertEqual(counts.count, 7)
        XCTAssertEqual(counts[6], 13) // today
        XCTAssertEqual(counts[5], 5) // yesterday
        XCTAssertEqual(counts[0], 0)
        XCTAssertEqual(counts.reduce(0, +), 18)
    }

    func testRecentWhenFormatsTodayWeekdayAndOlder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15, minute: 42))!

        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 11, minute: 5))!
        XCTAssertEqual(SessionLibrary.recentWhen(today, now: now, calendar: calendar), "11:05")

        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))! // Tue
        XCTAssertEqual(SessionLibrary.recentWhen(tuesday, now: now, calendar: calendar), "Tue")

        let older = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        XCTAssertEqual(SessionLibrary.recentWhen(older, now: now, calendar: calendar), "Sep 1")
        XCTAssertEqual(SessionLibrary.recentWhen(nil, now: now, calendar: calendar), "—")
    }

    func testGetStartedCompletePersistsAndDoesNotReset() {
        let name = "PromptAnnotatorTests.homeGetStarted"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertFalse(HomeGetStartedStore.isComplete(defaults))
        HomeGetStartedStore.markComplete(defaults)
        XCTAssertTrue(HomeGetStartedStore.isComplete(defaults))
        // Re-reading must stay complete (checklist never revives).
        XCTAssertTrue(HomeGetStartedStore.isComplete(defaults))
        HomeGetStartedStore.reset(defaults)
        XCTAssertFalse(HomeGetStartedStore.isComplete(defaults))
        defaults.removePersistentDomain(forName: name)
    }

    private func summary(
        id: String,
        dayOffset: Int,
        words: Int,
        now: Date,
        calendar: Calendar
    ) -> SessionSummary {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
        let started = calendar.date(byAdding: .hour, value: 10, to: day)!
        return SessionSummary(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            started: started,
            ended: started.addingTimeInterval(60),
            tiles: words > 0 ? 1 : 0,
            words: words,
            model: nil,
            transcript: "x",
            preview: "x"
        )
    }
}
