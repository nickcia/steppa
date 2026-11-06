import Foundation

/// Day of the week, ISO-8601 numbering (Monday = 1 … Sunday = 7).
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Days going forward from `self` to `other`, in 0...6.
    public func daysForward(to other: Weekday) -> Int {
        ((other.rawValue - rawValue) % 7 + 7) % 7
    }

    /// Shortest distance around the repeating weekly cycle, in 0...3.
    /// Used to keep hard sessions apart across week boundaries (e.g. Sunday → Monday).
    public func circularDistance(to other: Weekday) -> Int {
        let forward = daysForward(to: other)
        return min(forward, 7 - forward)
    }

    public var next: Weekday { Weekday(rawValue: rawValue % 7 + 1)! }
}

/// A calendar date with no time or time zone. Training is planned per day, so using a plain
/// date avoids the classic "workout moved to yesterday after a time-zone change" bugs.
///
/// Encodes as an ISO-8601 string, e.g. `"2026-11-06"`.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        precondition(LocalDate.isValid(year: year, month: month, day: day),
                     "Invalid date \(year)-\(month)-\(day)")
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. Returns nil for anything else.
    public init?(iso string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              LocalDate.isValid(year: y, month: m, day: d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Creates a date from a count of days since 1970-01-01.
    /// Uses Howard Hinnant's public-domain `civil_from_days` algorithm.
    public init(daysSinceEpoch: Int) {
        let z = daysSinceEpoch + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    /// Days since 1970-01-01 (Hinnant's `days_from_civil`).
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public func adding(days: Int) -> LocalDate { LocalDate(daysSinceEpoch: daysSinceEpoch + days) }

    /// Signed number of days from `self` to `other`.
    public func days(until other: LocalDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

    public var weekday: Weekday {
        // 1970-01-01 was a Thursday.
        Weekday(rawValue: ((daysSinceEpoch + 3) % 7 + 7) % 7 + 1)!
    }

    /// The Monday on or before this date.
    public var startOfWeek: LocalDate { adding(days: -(weekday.rawValue - 1)) }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    // MARK: Foundation bridging

    /// The calendar day that `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Midnight at the start of this day in `calendar`'s time zone.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Helpers

    static func isLeapYear(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func isValid(year: Int, month: Int, day: Int) -> Bool {
        (1...12).contains(month) && day >= 1 && day <= daysInMonth(year: year, month: month)
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = LocalDate(iso: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD, got \(string)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
