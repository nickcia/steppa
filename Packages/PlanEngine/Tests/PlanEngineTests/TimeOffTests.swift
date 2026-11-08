import Foundation
import Testing
@testable import PlanEngine

struct TimeOffTests {
    func plan(_ timeOff: [TimeOff]) throws -> TrainingPlan {
        var inputs = sampleInputs(weeks: 16)
        inputs.timeOff = timeOff
        return try PlanBuilder.build(inputs)
    }

    var base: TrainingPlan { try! plan([]) }
    /// Monday of the plan's seventh week.
    var weekSeven: LocalDate { base.weeks[6].startDate }

    @Test func aHolidayLeavesItsDaysEmptyAndRestartsLowerAfter() throws {
        let holiday = TimeOff(reason: .vacation, start: weekSeven, end: weekSeven.adding(days: 9))
        let planned = try plan([holiday])
        #expect(planned.workouts.allSatisfy { !holiday.contains($0.date) })
        #expect(PlanValidator.validate(planned).isEmpty)
        // The week after a 10-day break restarts below where the plan was before the break.
        let back = try #require(planned.weeks.first { $0.startDate == weekSeven.adding(days: 14) })
        let before = planned.weeks[5].targetMeters
        #expect(back.targetMeters <= before * PlanAdapter.resumeShare(afterBreakOf: 10) * 1.11)
        #expect(back.targetMeters < base.weeks[8].targetMeters)
    }

    @Test func easyOnlyDaysHaveNoLongRunOrSessions() throws {
        let easy = TimeOff(reason: .vacation, mode: .easyOnly, start: weekSeven, end: weekSeven.adding(days: 6))
        let planned = try plan([easy])
        let thatWeek = planned.workouts.filter { easy.contains($0.date) }
        #expect(!thatWeek.isEmpty)
        #expect(thatWeek.allSatisfy { $0.kind == .easy && $0.totalMeters <= TimeOff.easyOnlyMaxMeters })
    }

    @Test func anInjuryWithNoEndPausesTheRestOfThePlan() throws {
        let injury = TimeOff(reason: .injury, start: weekSeven, end: nil)
        let planned = try plan([injury])
        #expect(planned.workouts.filter { $0.kind != .race && $0.date >= weekSeven }.isEmpty)
        #expect(StrengthSchedule.sessions(for: planned, perWeek: 2).allSatisfy { $0.date < weekSeven })
    }

    @Test func theFirstWeekBackFromInjuryIsEasy() throws {
        let injury = TimeOff(reason: .injury, start: weekSeven, end: weekSeven.adding(days: 4))
        let planned = try plan([injury])
        let returnDays = try #require(injury.easyReturn)
        let firstWeekBack = planned.workouts.filter { returnDays.contains($0.date) }
        #expect(!firstWeekBack.isEmpty)
        #expect(firstWeekBack.allSatisfy { $0.kind == .easy })
        #expect(firstWeekBack.allSatisfy { !$0.blocks.flatMap(\.steps).contains { $0.step.target?.zone == .stride } })
    }

    @Test func addingTimeOffReplansFromToday() throws {
        let plan = base
        let today = plan.weeks[4].startDate.adding(days: 2)
        let holiday = TimeOff(reason: .vacation, start: today.adding(days: 3), end: today.adding(days: 10))
        let revision = try PlanAdapter.adapt(plan, log: TrainingLog(), trigger: .timeOffChanged([holiday]), today: today,
                                             assessTraining: false)
        #expect(revision.reasons == [.timeOffChanged])
        #expect(revision.plan.inputs.timeOffPeriods == [holiday])
        #expect(revision.plan.workouts.allSatisfy { !holiday.contains($0.date) })
        // The past is untouched.
        #expect(revision.plan.workouts.filter { $0.date < today } == plan.workouts.filter { $0.date < today })
        // Same list again: nothing to do.
        let again = try PlanAdapter.adapt(revision.plan, log: TrainingLog(), trigger: .timeOffChanged([holiday]),
                                          today: today, assessTraining: false)
        #expect(!again.changed)
    }

    @Test func workoutsCantBeMovedOntoADayOff() throws {
        let plan = base
        let week = plan.weeks[6]
        let workout = try #require(week.workouts.first { $0.kind == .easy })
        let free = try #require((0..<7).map { week.startDate.adding(days: $0) }.first { day in
            !week.workouts.contains { $0.date == day }
        })
        var withOff = plan
        withOff.inputs.timeOff = [TimeOff(reason: .busy, start: free, end: free)]
        #expect(throws: EditError.dayOff) {
            try PlanEditor.move(workout.id, to: free, in: withOff, today: plan.inputs.startDate)
        }
    }

    @Test func plansSavedBeforeTimeOffStillLoad() throws {
        let data = try JSONEncoder().encode(base)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var inputs = try #require(json["inputs"] as? [String: Any])
        inputs.removeValue(forKey: "timeOff")
        json["inputs"] = inputs
        let decoded = try JSONDecoder().decode(TrainingPlan.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.inputs.timeOffPeriods.isEmpty)
    }
}
