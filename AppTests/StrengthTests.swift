import Foundation
import Testing
import PlanEngine
@testable import Steppa

@MainActor
struct StrengthTests {
    @Test func offByDefaultThenScheduledAndTracked() throws {
        let model = try AppModelTests.startedModel(today: AppModelTests.start)
        #expect(model.strengthSessions.isEmpty)

        model.setStrength(enabled: true, perWeek: 1)
        let sessions = model.strengthSessions
        #expect(!sessions.isEmpty)
        let first = try #require(sessions.first)
        #expect(model.strengthSession(on: first.date) == first)

        model.setStrengthDone(true, for: first)
        #expect(model.isStrengthDone(first))
        // Strength doesn't count as a run in the plan's training log.
        #expect(model.trainingLog.runs.isEmpty)
        model.setStrengthDone(false, for: first)
        #expect(!model.isStrengthDone(first))
    }

    @Test func routinesAndCalendarEvent() throws {
        for level in [StrengthSchedule.Level.foundation, .maintenance, .light] {
            let routine = StrengthRoutine.for(level)
            #expect(!routine.exercises.isEmpty)
            #expect(routine.text.contains(routine.exercises[0].name))
        }
        let model = try AppModelTests.startedModel(today: AppModelTests.start)
        model.setStrength(enabled: true)
        let session = try #require(model.strengthSessions.first)
        let event = model.calendarEvent(for: session)
        #expect(event.title == StrengthRoutine.for(session.level).title)
        #expect(event.key.hasPrefix(session.id))
        #expect(event.end.timeIntervalSince(event.start) == Double(StrengthRoutine.for(session.level).minutes * 60))
    }
}
