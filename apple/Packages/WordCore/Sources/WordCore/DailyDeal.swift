import Foundation

/// The Daily Deal: one puzzle a day, the same letters for everybody.
///
/// New on Apple platforms — there is no `src/game/daily.ts` to port (plan
/// §8.2). It exists because the pieces were already here: `TileStream` grows a
/// deal off its own *hidden* board rather than the player's, so the same seed
/// yields the same letters no matter what anyone does with them. Solo's own
/// deal path can't do this — it grows tiles off the live board
/// (`extendPuzzle(board:…)`), which diverges from everyone else's on the first
/// move. So the Daily Deal is battle's deal plumbing under a solo-style
/// ruleset.
///
/// Everything here is pure arithmetic over an instant, so it tests on Linux
/// with the rest of `WordCore` and a test can name any day it likes.

// MARK: - The rules (decision points, plan §16.3)

/// The knobs the plan leaves open, in one place and deliberately so — each is
/// a product decision that wants playtesting, not a value to sprinkle through
/// the code.
public enum DailyRules {
    /// When the puzzle flips, as an hour offset into the UTC day.
    ///
    /// **This has to agree with the Game Center recurring leaderboard's
    /// occurrence boundary when phase 3's submission lands** — a recurring
    /// leaderboard restarts on an absolute schedule, so a seed derived from
    /// anything else (the player's *local* date, say, Wordle-style) would let
    /// two people play different puzzles into the same occurrence.
    ///
    /// 08:00 UTC = midnight US Pacific, 3am Eastern, 9am Central European:
    /// overnight for North America and breakfast for Europe. UTC midnight —
    /// the obvious choice — would flip the puzzle mid-afternoon in the US.
    public static let resetHourUTC = 8

    /// Tiles in the day's deal. A fixed deal rather than a timed run: the
    /// score should say how well you used the letters, not how fast you type,
    /// which is what makes the day's boards comparable.
    public static let tileCount = 30

    /// One go per day. In-progress games still survive process death — the
    /// save/restore path treats a daily like any other game — so this stops a
    /// player *restarting* for a better score, not resuming an interrupted one.
    public static let attemptsPerDay = 1

    /// Mixed into the seed so the day's letters aren't derivable from the date
    /// alone (plan §8.4). This is a speed bump, not a lock: it lives in the
    /// binary and anyone determined can read it out. The plan accepts residual
    /// client trust for v1 and says so.
    static let seedSalt = "nana-daily-1f4a9c"
}

// MARK: - The day

/// Which daily puzzle is live, and the seed that deals it.
public struct DailyDeal: Equatable {
    /// Days since 1970-01-01 on the reset grid — the streak key, and the
    /// leaderboard occurrence index when phase 3 needs one.
    public let day: Int
    /// The day's label, `YYYY-MM-DD`. Also the storage key for a result.
    public let date: String
    /// What `TileStream(seed:)` is opened with.
    public let seed: String
    public let opensAt: Date
    public let closesAt: Date

    /// Short month name, e.g. `AUG`. Built from the day number rather than a
    /// `DateFormatter` for the same reason `date` is: no locale, no time zone,
    /// same answer everywhere. The app's copy is English throughout.
    public var monthLabel: String {
        let months = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        return months[civilFromDays(day).month - 1]
    }

    /// How the day is written to the player — `Aug 24`. `date` stays the
    /// machine form: it's a storage key and a seed ingredient.
    public var shortLabel: String { "\(monthLabel) \(dayOfMonthLabel)" }

    /// Day of the month, unpadded — `4`, not `04`.
    public var dayOfMonthLabel: String { "\(civilFromDays(day).day)" }

    public init(day: Int, date: String, seed: String, opensAt: Date, closesAt: Date) {
        self.day = day
        self.date = date
        self.seed = seed
        self.opensAt = opensAt
        self.closesAt = closesAt
    }
}

/// The puzzle live at `now`.
public func dailyDeal(at now: Date) -> DailyDeal {
    let day = dailyDayNumber(at: now)
    return dailyDeal(day: day)
}

/// The puzzle for a given day number — the form the widget and a rollover
/// check want, since both reason about days rather than instants.
public func dailyDeal(day: Int) -> DailyDeal {
    let date = dailyDateString(day: day)
    let opens = Double(day) * 86_400 + Double(DailyRules.resetHourUTC) * 3_600
    return DailyDeal(
        day: day,
        date: date,
        seed: "\(DailyRules.seedSalt)/daily/\(date)",
        opensAt: Date(timeIntervalSince1970: opens),
        closesAt: Date(timeIntervalSince1970: opens + 86_400))
}

/// Days since the epoch on the reset grid. Floor division, so instants before
/// 1970 (and the hours before the first reset) still land on the day that
/// contains them rather than rounding toward zero.
public func dailyDayNumber(at now: Date) -> Int {
    let shifted = now.timeIntervalSince1970 - Double(DailyRules.resetHourUTC) * 3_600
    return Int((shifted / 86_400).rounded(.down))
}

/// `YYYY-MM-DD` for a day number, computed rather than formatted: a
/// `DateFormatter` would drag in a locale and a time zone, and this string is
/// a storage key and a seed ingredient, not display text.
public func dailyDateString(day: Int) -> String {
    let civil = civilFromDays(day)
    let month = civil.month < 10 ? "0\(civil.month)" : "\(civil.month)"
    let dayOfMonth = civil.day < 10 ? "0\(civil.day)" : "\(civil.day)"
    return "\(civil.year)-\(month)-\(dayOfMonth)"
}

// MARK: - Streaks

/// How many days in a row end at today.
///
/// Today not being played yet doesn't break a streak — you have until the
/// puzzle flips — so a run ending yesterday still counts. This is the shape
/// §9.1's iCloud merge needs: it takes the *set* of days played, because
/// merging two devices' histories is a set union and nothing more.
public func dailyStreak(playedDays: Set<Int>, today: Int) -> Int {
    var cursor: Int
    if playedDays.contains(today) {
        cursor = today
    } else if playedDays.contains(today - 1) {
        cursor = today - 1
    } else {
        return 0
    }
    var length = 0
    while playedDays.contains(cursor) {
        length += 1
        cursor -= 1
    }
    return length
}

// MARK: - Civil calendar arithmetic

/// Days-since-epoch → proleptic Gregorian year/month/day (Howard Hinnant's
/// `civil_from_days`). Pure integer maths, valid far past any date this game
/// will see, and identical on every platform.
func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    // Shift the epoch to 0000-03-01 so leap days land at the end of the cycle.
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra =
        (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let year = yearOfEra + era * 400
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPrime = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
    let month = monthPrime < 10 ? monthPrime + 3 : monthPrime - 9
    return (year + (month <= 2 ? 1 : 0), month, day)
}

/// The inverse, so tests can name a date instead of a magic number.
func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let y = year - (month <= 2 ? 1 : 0)
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let monthPrime = month > 2 ? month - 3 : month + 9
    let dayOfYear = (153 * monthPrime + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}
