import Foundation
import Testing
@testable import PlanEngine

struct RunWalkTests {
    func inputs(weeks: Int = 16, goal: RaceDistance = .fiveK,
                runDays: Set<Weekday> = [.tuesday, .thursday, .sunday]) -> PlanInputs {
        var inputs = sampleInputs(goal: goal, weeks: weeks, current: 0, fitness: .estimated, runDays: runDays,
                                  longRunDay: .sunday, experience: .beginner)
        inputs.runWalkStart = inputs.startDate
        return inputs
    }

    @Test func newRunnersStartWithRunWalkAndBuildToThirtyMinutes() throws {
        let plan = try PlanBuilder.build(inputs())
        #expect(PlanValidator.validate(plan).isEmpty, "\(PlanValidator.validate(plan))")
        let first = try #require(plan.workouts.first)
        #expect(first.kind == .runWalk)
        #expect(first.warmup?.target == nil && first.blocks[0].steps.count == 2)
        // The run/walk weeks end with 30 minutes non-stop, then the normal plan takes over.
        let thirty = try #require(plan.workouts.last { $0.isRunWalkSession })
        #expect(thirty.kind == .easy && thirty.blocks[0].steps[0].step.estimatedSeconds == 30 * 60)
        let after = plan.workouts.filter { $0.date > thirty.date && $0.kind != .race }
        #expect(!after.isEmpty && after.allSatisfy { !$0.isRunWalkSession })
        // Running time never shrinks from one week to the next.
        let running = plan.weeks.prefix(RunWalk.stages.count).compactMap { week in
            week.workouts.first.map { $0.blocks.reduce(0) { $0 + Double($1.iterations) * $1.steps[0].step.estimatedSeconds } }
        }
        #expect(running == running.sorted())
    }

    @Test func threeSpreadOutSessionsAWeekWithNoHardDays() throws {
        let plan = try PlanBuilder.build(inputs(runDays: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday]))
        for week in plan.weeks.prefix(RunWalk.stages.count) where week.startDate >= plan.inputs.startDate.startOfWeek.adding(days: 7) {
            #expect(week.workouts.count == RunWalk.sessionsPerWeek)
            let dates = week.workouts.map(\.date)
            #expect(zip(dates, dates.dropFirst()).allSatisfy { $0.days(until: $1) >= 2 })
            #expect(week.workouts.allSatisfy { !$0.kind.isHard })
        }
    }

    @Test func aShortRunUpCompressesTheStagesAndWarns() throws {
        let plan = try PlanBuilder.build(inputs(weeks: 5))
        #expect(PlanValidator.validate(plan).isEmpty, "\(PlanValidator.validate(plan))")
        #expect(plan.warnings.contains { if case .shortPlan = $0 { true } else { false } })
        // Still ends at 30 minutes non-stop before race week.
        let raceWeek = plan.inputs.raceDate.startOfWeek
        let last = try #require(plan.workouts.last { $0.date < raceWeek })
        #expect(last.kind == .easy && last.blocks[0].steps[0].step.estimatedSeconds == 30 * 60)
    }

    @Test func weeksOffDontMoveTheStageOn() throws {
        var withBreak = inputs()
        let third = withBreak.startDate.startOfWeek.adding(days: 14)
        withBreak.timeOff = [TimeOff(reason: .illness, start: third, end: third.adding(days: 6))]
        let plan = try PlanBuilder.build(withBreak)
        #expect(PlanValidator.validate(plan).isEmpty, "\(PlanValidator.validate(plan))")
        // The week after the break repeats the stage before it rather than skipping ahead.
        #expect(RunWalk.stage(for: third.adding(days: 7), inputs: withBreak) == RunWalk.stage(for: third, inputs: withBreak))
    }

    @Test func aLongerGoalAlsoWorks() throws {
        let plan = try PlanBuilder.build(inputs(weeks: 24, goal: .tenK))
        #expect(PlanValidator.validate(plan).isEmpty, "\(PlanValidator.validate(plan))")
        #expect(plan.workouts.contains { $0.kind == .tempo || $0.kind == .intervals || $0.kind == .hills })
        #expect(!plan.warnings.contains { if case .lowStartingVolume = $0 { true } else { false } })
    }

    @Test func replanningMidWeekKeepsThreeSessions() throws {
        let plan = try PlanBuilder.build(inputs())
        let week = plan.weeks[3]
        let today = try #require(week.workouts.first).date.adding(days: 1)
        let revision = try PlanAdapter.adapt(plan, log: TrainingLog(), trigger: .availabilityChanged(
            runDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday), today: today, assessTraining: false)
        #expect(PlanValidator.validate(revision.plan).isEmpty, "\(PlanValidator.validate(revision.plan))")
        let thatWeek = revision.plan.weeks.first { $0.startDate == week.startDate }
        #expect(thatWeek?.workouts.count == RunWalk.sessionsPerWeek)
    }

    @Test func everyoneElseIsUnchanged() throws {
        #expect(RunWalk.stage(for: referenceToday.startOfWeek, inputs: sampleInputs()) == nil)
    }
}
