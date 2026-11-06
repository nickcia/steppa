import Foundation
import Testing
@testable import PlanEngine

@Suite struct LocalDateTests {
    @Test func knownWeekdays() {
        #expect(LocalDate(year: 1970, month: 1, day: 1).weekday == .thursday)
        #expect(LocalDate(year: 2026, month: 11, day: 6).weekday == .friday)
        #expect(LocalDate(year: 2000, month: 2, day: 29).weekday == .tuesday)
        #expect(LocalDate(year: 1969, month: 12, day: 31).weekday == .wednesday)
    }

    @Test func epochRoundTripAcrossCenturies() {
        for days in stride(from: -200_000, through: 200_000, by: 37) {
            #expect(LocalDate(daysSinceEpoch: days).daysSinceEpoch == days)
        }
    }

    @Test func arithmeticAcrossMonthAndLeapYear() {
        let d = LocalDate(year: 2028, month: 2, day: 28)
        #expect(d.adding(days: 1) == LocalDate(year: 2028, month: 2, day: 29))
        #expect(d.adding(days: 2) == LocalDate(year: 2028, month: 3, day: 1))
        #expect(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1) == LocalDate(year: 2027, month: 1, day: 1))
        #expect(d.days(until: LocalDate(year: 2029, month: 2, day: 28)) == 366)
    }

    @Test func startOfWeekIsMonday() {
        let friday = LocalDate(year: 2026, month: 11, day: 6)
        #expect(friday.startOfWeek == LocalDate(year: 2026, month: 11, day: 2))
        let monday = LocalDate(year: 2026, month: 11, day: 2)
        #expect(monday.startOfWeek == monday)
        let sunday = LocalDate(year: 2026, month: 11, day: 8)
        #expect(sunday.startOfWeek == monday)
    }

    @Test func isoParsingAndCodable() throws {
        #expect(LocalDate(iso: "2026-11-06") == LocalDate(year: 2026, month: 11, day: 6))
        #expect(LocalDate(iso: "2026-02-30") == nil)
        #expect(LocalDate(iso: "2026-11") == nil)
        #expect(LocalDate(year: 987, month: 3, day: 4).description == "0987-03-04")

        let data = try JSONEncoder().encode([LocalDate(year: 2026, month: 11, day: 6)])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-11-06\"]")
        let decoded = try JSONDecoder().decode([LocalDate].self, from: data)
        #expect(decoded == [LocalDate(year: 2026, month: 11, day: 6)])
    }

    @Test func weekdayCircularDistance() {
        #expect(Weekday.sunday.circularDistance(to: .monday) == 1)
        #expect(Weekday.monday.circularDistance(to: .thursday) == 3)
        #expect(Weekday.monday.circularDistance(to: .friday) == 3)
        #expect(Weekday.saturday.circularDistance(to: .tuesday) == 3)
        #expect(Weekday.sunday.next == .monday)
    }

    @Test func foundationBridging() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let date = LocalDate(year: 2026, month: 11, day: 6)
        #expect(LocalDate(date.date(in: calendar), calendar: calendar) == date)
    }
}
