import Foundation
import Testing

@testable import WordCore

/// The Daily Deal has no TS counterpart to be a parity fixture for, so these
/// are the spec: the day boundary, the seed, and the streak rule.

// MARK: - Civil calendar

@Suite("DailyDeal: calendar arithmetic")
struct DailyDealCalendar {
    @Test("agrees with known epoch landmarks")
    func agreesWithKnownEpochLandmarks() {
        #expect(daysFromCivil(year: 1970, month: 1, day: 1) == 0)
        #expect(dailyDateString(day: 0) == "1970-01-01")
        #expect(dailyDateString(day: 19_000) == "2022-01-08")
    }

    @Test("round-trips every day across a long span, leap years included")
    func roundTripsEveryDayAcrossALongSpan() {
        // ~55 years, so 1900/2000/2100-style century rules all get exercised.
        for day in stride(from: -25_000, through: 55_000, by: 7) {
            let civil = civilFromDays(day)
            #expect(daysFromCivil(year: civil.year, month: civil.month, day: civil.day) == day)
        }
    }

    @Test("handles leap day and the day either side of it")
    func handlesLeapDay() {
        let leap = daysFromCivil(year: 2024, month: 2, day: 29)
        #expect(dailyDateString(day: leap) == "2024-02-29")
        #expect(dailyDateString(day: leap - 1) == "2024-02-28")
        #expect(dailyDateString(day: leap + 1) == "2024-03-01")
        // 2100 is not a leap year, unlike 2000.
        #expect(dailyDateString(day: daysFromCivil(year: 2100, month: 2, day: 28) + 1) == "2100-03-01")
        #expect(dailyDateString(day: daysFromCivil(year: 2000, month: 2, day: 28) + 1) == "2000-02-29")
    }

    @Test("pads months and days to two digits")
    func padsMonthsAndDays() {
        #expect(dailyDateString(day: daysFromCivil(year: 2026, month: 8, day: 4)) == "2026-08-04")
        #expect(dailyDateString(day: daysFromCivil(year: 2026, month: 12, day: 31)) == "2026-12-31")
    }
}

// MARK: - The day boundary

@Suite("DailyDeal: the day boundary")
struct DailyDealBoundary {
    /// An instant at a given UTC wall clock, built without a DateFormatter.
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let days = daysFromCivil(year: y, month: m, day: d)
        return Date(
            timeIntervalSince1970: Double(days) * 86_400 + Double(hour) * 3_600
                + Double(minute) * 60)
    }

    @Test("flips at the configured reset hour, not UTC midnight")
    func flipsAtTheConfiguredResetHour() {
        let reset = DailyRules.resetHourUTC
        let justBefore = dailyDeal(at: utc(2026, 8, 24, reset - 1, 59))
        let atReset = dailyDeal(at: utc(2026, 8, 24, reset))
        #expect(
            justBefore.date == "2026-08-23",
            "the UTC hours before the reset still belong to yesterday's puzzle")
        #expect(atReset.date == "2026-08-24")
        #expect(atReset.day == justBefore.day + 1)
        // And the reset is genuinely not UTC midnight.
        #expect(dailyDeal(at: utc(2026, 8, 24, 0)).date == "2026-08-23")
    }

    @Test("every instant inside a day maps to the same deal")
    func everyInstantInsideADayMapsToTheSameDeal() {
        let reset = DailyRules.resetHourUTC
        let deal = dailyDeal(at: utc(2026, 8, 24, reset))
        for minute in stride(from: 0, to: 24 * 60, by: 17) {
            let at = utc(2026, 8, 24, reset).addingTimeInterval(Double(minute) * 60)
            #expect(dailyDeal(at: at) == deal)
        }
        // One second past the window is tomorrow.
        #expect(dailyDeal(at: deal.closesAt).date == "2026-08-25")
    }

    @Test("opensAt and closesAt bracket the day exactly")
    func opensAtAndClosesAtBracketTheDay() {
        let deal = dailyDeal(at: utc(2026, 8, 24, 12))
        #expect(deal.closesAt.timeIntervalSince(deal.opensAt) == 86_400)
        #expect(dailyDayNumber(at: deal.opensAt) == deal.day)
        #expect(dailyDayNumber(at: deal.closesAt.addingTimeInterval(-1)) == deal.day)
        #expect(dailyDayNumber(at: deal.opensAt.addingTimeInterval(-1)) == deal.day - 1)
    }

    @Test("floors rather than truncating, so pre-epoch instants don't skip a day")
    func floorsRatherThanTruncating() {
        // Truncation toward zero would map both sides of the epoch to day 0.
        let justBeforeEpochReset = Date(timeIntervalSince1970: -1)
        #expect(dailyDayNumber(at: justBeforeEpochReset) == -1)
        #expect(dailyDayNumber(at: Date(timeIntervalSince1970: 0)) == -1)
    }
}

// MARK: - The seed

@Suite("DailyDeal: the seed")
struct DailyDealSeed {
    @Test("is stable for a day and different across days")
    func isStableForADayAndDifferentAcrossDays() {
        let today = dailyDeal(day: 20_000)
        #expect(dailyDeal(day: 20_000).seed == today.seed)
        #expect(dailyDeal(day: 20_001).seed != today.seed)
    }

    @Test("is salted, so the date alone doesn't give it away")
    func isSaltedSoTheDateAloneDoesNotGiveItAway() {
        let deal = dailyDeal(day: 20_000)
        #expect(deal.seed.contains(deal.date))
        #expect(deal.seed != "daily/\(deal.date)")
        #expect(deal.seed.hasPrefix(DailyRules.seedSalt))
    }

    @Test("deals identical letters to every player on the same day")
    func dealsIdenticalLettersToEveryPlayer() {
        let deal = dailyDeal(day: 20_240)
        let mine = TileStream(seed: deal.seed).next(DailyRules.tileCount)
        let yours = TileStream(seed: deal.seed).next(DailyRules.tileCount)
        #expect(mine == yours)
        #expect(mine.count == DailyRules.tileCount)
        #expect(mine.allSatisfy { $0.count == 1 })
    }

    @Test("deals different letters tomorrow")
    func dealsDifferentLettersTomorrow() {
        let today = TileStream(seed: dailyDeal(day: 20_240).seed).next(DailyRules.tileCount)
        let tomorrow = TileStream(seed: dailyDeal(day: 20_241).seed).next(DailyRules.tileCount)
        #expect(today != tomorrow)
    }
}

// MARK: - Streaks

@Suite("DailyDeal: streaks")
struct DailyDealStreaks {
    @Test("counts consecutive days ending today")
    func countsConsecutiveDaysEndingToday() {
        #expect(dailyStreak(playedDays: [100, 99, 98], today: 100) == 3)
    }

    @Test("survives today not being played yet")
    func survivesTodayNotBeingPlayedYet() {
        // The day isn't over — a run ending yesterday is still alive.
        #expect(dailyStreak(playedDays: [99, 98, 97], today: 100) == 3)
    }

    @Test("breaks after a whole day missed")
    func breaksAfterAWholeDayMissed() {
        #expect(dailyStreak(playedDays: [98, 97, 96], today: 100) == 0)
    }

    @Test("ignores gaps further back and days in the future")
    func ignoresGapsFurtherBackAndFutureDays() {
        #expect(dailyStreak(playedDays: [100, 99, 97, 96], today: 100) == 2)
        #expect(dailyStreak(playedDays: [100, 101, 102], today: 100) == 1)
    }

    @Test("is zero with nothing played")
    func isZeroWithNothingPlayed() {
        #expect(dailyStreak(playedDays: [], today: 100) == 0)
    }

    @Test("is a set union away from being device-mergeable")
    func isASetUnionAwayFromBeingDeviceMergeable() {
        // The shape §9.1's iCloud merge needs: two devices' histories combine
        // by union, and the streak falls out of the combined set.
        let phone: Set<Int> = [100, 98]
        let pad: Set<Int> = [99, 97]
        #expect(dailyStreak(playedDays: phone, today: 100) == 1)
        #expect(dailyStreak(playedDays: phone.union(pad), today: 100) == 4)
    }
}

@Suite("DailyDeal: display labels")
struct DailyDealLabels {
    @Test("names the month and day without a formatter")
    func namesTheMonthAndDay() {
        let deal = dailyDeal(day: daysFromCivil(year: 2026, month: 8, day: 4))
        #expect(deal.monthLabel == "Aug")
        #expect(deal.dayOfMonthLabel == "4")
        let newYear = dailyDeal(day: daysFromCivil(year: 2027, month: 1, day: 31))
        #expect(newYear.monthLabel == "Jan")
        #expect(newYear.dayOfMonthLabel == "31")
    }

    @Test("covers every month")
    func coversEveryMonth() {
        let names = (1...12).map {
            dailyDeal(day: daysFromCivil(year: 2026, month: $0, day: 15)).monthLabel
        }
        #expect(names == ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
    }
}
