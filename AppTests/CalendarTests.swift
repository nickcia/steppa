import Foundation
import Testing
import PlanEngine
@testable import TrackStar

@MainActor
struct CalendarEventTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }()

    func workout(_ kind: WorkoutKind) throws -> Workout {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        return try #require(plan.workouts.first { $0.kind == kind && $0.blocks.contains { $0.iterations > 1 } }
                            ?? plan.workouts.first { $0.kind == kind })
    }

    @Test func eventIsAtTheReminderTimeAndLastsTheWorkout() throws {
        let session = try workout(.intervals)
        let event = CalendarEventContent.make(for: session, format: DisplayFormat(units: .metric), minutes: 7 * 60 + 30,
                                              calendar: calendar)
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.start)
        #expect(start.year == session.date.year && start.month == session.date.month && start.day == session.date.day)
        #expect(start.hour == 7 && start.minute == 30)
        let minutes = event.end.timeIntervalSince(event.start) / 60
        #expect(minutes >= session.totalSeconds / 60 && minutes < session.totalSeconds / 60 + 5)
        #expect(Int(minutes) % 5 == 0)
    }

    @Test func notesListTheStepsAndThePurpose() throws {
        let session = try workout(.intervals)
        let event = CalendarEventContent.make(for: session, format: DisplayFormat(units: .metric), minutes: 420,
                                              calendar: calendar)
        #expect(event.title.hasPrefix(WorkoutKind.intervals.name))
        let block = try #require(session.blocks.first { $0.iterations > 1 })
        #expect(event.notes.contains("\(block.iterations) ×"))
        #expect(event.notes.contains("/km"))
        #expect(event.notes.hasSuffix(WorkoutKind.intervals.purpose))
    }

    @Test func keyRoundTripsThroughTheURLAndChangesWithTheWorkout() throws {
        let session = try workout(.easy)
        let format = DisplayFormat(units: .metric)
        let event = CalendarEventContent.make(for: session, format: format, minutes: 420, calendar: calendar)
        #expect(CalendarEventContent.key(from: event.url) == event.key)
        #expect(CalendarEventContent.key(from: URL(string: "https://example.com")) == nil)
        #expect(CalendarEventContent.make(for: session, format: format, minutes: 420, calendar: calendar) == event)
        #expect(CalendarEventContent.make(for: session, format: format, minutes: 480, calendar: calendar).key != event.key)
        #expect(CalendarEventContent.make(for: session, format: DisplayFormat(units: .imperial), minutes: 420,
                                          calendar: calendar).key != event.key)
    }

    @Test func diffAddsMissingAndRemovesStaleAndDuplicates() {
        func content(_ key: String) -> CalendarEventContent {
            CalendarEventContent(title: key, notes: "", start: .now, end: .now, key: key)
        }
        let diff = CalendarEventContent.diff(
            wanted: [content("a-1"), content("b-2")],
            existing: [(id: "1", key: "a-1"), (id: "2", key: "b-1"), (id: "3", key: nil), (id: "4", key: "a-1")])
        #expect(diff.add.map(\.key) == ["b-2"])
        // Event 3 has no key: someone added it by hand, so it stays.
        #expect(diff.remove.sorted() == ["2", "4"])
    }
}

struct RenameCompatibilityTests {
    @Test func calendarEventsFromBeforeTheRenameAreStillRecognised() {
        #expect(CalendarEventContent.key(from: URL(string: "trackstar-workout:abc-1")) == "abc-1")
        #expect(CalendarEventContent.key(from: URL(string: "steppa-workout:abc-1")) == "abc-1")
        #expect(CalendarEventContent.key(from: URL(string: "https://example.com")) == nil)
    }
}
