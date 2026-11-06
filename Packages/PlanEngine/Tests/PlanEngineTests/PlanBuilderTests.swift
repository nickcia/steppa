import Foundation
import Testing
@testable import PlanEngine

/// Friday 6 November 2026.
let referenceToday = LocalDate(year: 2026, month: 11, day: 6)

func sampleInputs(
    goal: RaceDistance = .halfMarathon,
    weeks: Int = 14,
    current: Double = 30_000,
    fitness: FitnessSource = .recentRace(.init(.tenK, timeSeconds: 50 * 60)),
    runDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday],
    longRunDay: Weekday = .sunday,
    experience: Experience = .intermediate,
    goalTime: Double? = nil
) -> PlanInputs {
    PlanInputs(goal: goal, raceDate: referenceToday.adding(days: weeks * 7 + 2), startDate: referenceToday,
               currentWeeklyMeters: current, fitness: fitness, runDays: runDays, longRunDay: longRunDay,
               experience: experience, goalTimeSeconds: goalTime)
}

@Suite struct PlanBuilderTests {
    @Test func typicalHalfMarathonPlan() throws {
        let plan = try PlanBuilder.build(sampleInputs())
        #expect(PlanValidator.validate(plan).isEmpty, "\(PlanValidator.validate(plan))")

        // Phases appear in order and the plan ends in a two-week taper.
        let phases = plan.weeks.map(\.phase)
        #expect(phases == phases.sorted { Phase.allCases.firstIndex(of: $0)! < Phase.allCases.firstIndex(of: $1)! })
        #expect(phases.suffix(2) == [.taper, .taper])
        #expect(phases.contains(.base) && phases.contains(.build) && phases.contains(.peak))

        // Ends with the race on race day.
        #expect(plan.workouts.last?.kind == .race)
        #expect(plan.workouts.last?.date == plan.inputs.raceDate)

        // Nothing before the start date (a Friday, so week 0 is partial).
        #expect(plan.workouts.allSatisfy { $0.date >= referenceToday })
        #expect(plan.weeks[0].startDate == LocalDate(year: 2026, month: 11, day: 2))

        // Includes step-back weeks, quality sessions and long runs.
        #expect(plan.weeks.contains { $0.isStepBack })
        let kinds = Set(plan.workouts.map(\.kind))
        #expect(kinds.isSuperset(of: [.easy, .long, .tempo, .intervals, .race]))

        // Volume grows from the starting point and peaks above it.
        let peak = plan.weeks.map(\.targetMeters).max()!
        #expect(peak > 30_000)
        #expect(peak <= PlanRules.peakMeters(.halfMarathon, .intermediate, currentMeters: 30_000))
    }

    @Test func marathonPeakIncludesMarathonPaceLongRuns() throws {
        let plan = try PlanBuilder.build(sampleInputs(goal: .marathon, weeks: 18, current: 45_000))
        #expect(PlanValidator.validate(plan).isEmpty)
        #expect(plan.workouts.contains { $0.kind == .marathonPaceLong })
        #expect(plan.weeks.suffix(3).allSatisfy { $0.phase == .taper })
    }

    @Test func beginnersGetGentlerPlans() throws {
        let plan = try PlanBuilder.build(sampleInputs(goal: .fiveK, weeks: 10, current: 10_000,
                                                      fitness: .estimated, runDays: [.monday, .wednesday, .saturday],
                                                      longRunDay: .saturday, experience: .beginner))
        #expect(PlanValidator.validate(plan).isEmpty)
        #expect(plan.weeks.filter { $0.phase == .base }.allSatisfy { week in
            week.workouts.allSatisfy { $0.kind == .easy || $0.kind == .long }
        })
        // Step back after every two loading weeks.
        let loadingFlags = plan.weeks.filter { $0.phase != .taper }.map(\.isStepBack)
        #expect(Array(loadingFlags.prefix(6)) == [false, false, true, false, false, true])
        #expect(plan.warnings.contains(.estimatedFitness))
    }

    @Test func pacesComeFromCurrentFitnessNotGoal() throws {
        let realistic = try PlanBuilder.build(sampleInputs())
        let ambitious = try PlanBuilder.build(sampleInputs(goalTime: 80 * 60))
        #expect(realistic.paces == ambitious.paces)
        #expect(ambitious.warnings.contains { if case .ambitiousGoal = $0 { true } else { false } })
        #expect(!realistic.warnings.contains { if case .ambitiousGoal = $0 { true } else { false } })
    }

    @Test func shortPlansWarnAndStillTaper() throws {
        let plan = try PlanBuilder.build(sampleInputs(goal: .marathon, weeks: 5, current: 50_000))
        #expect(PlanValidator.validate(plan).isEmpty)
        #expect(plan.warnings.contains(.shortPlan(weeks: 6, recommendedWeeks: 16)))
        #expect(plan.weeks.last?.phase == .taper)
    }

    @Test func lowVolumeWarning() throws {
        let plan = try PlanBuilder.build(sampleInputs(goal: .marathon, weeks: 20, current: 10_000))
        #expect(plan.warnings.contains(.lowStartingVolume(recommendedMeters: 25_000)))
        #expect(plan.weeks[0].targetMeters == 10_000)
    }

    @Test func invalidInputsThrow() {
        var inputs = sampleInputs()
        inputs.raceDate = inputs.startDate
        #expect(throws: PlanError.raceNotAfterStart) { try PlanBuilder.build(inputs) }

        inputs = sampleInputs(runDays: [.sunday])
        #expect(throws: PlanError.tooFewRunDays) { try PlanBuilder.build(inputs) }

        inputs = sampleInputs(longRunDay: .monday)
        #expect(throws: PlanError.longRunDayNotARunDay) { try PlanBuilder.build(inputs) }

        inputs = sampleInputs(current: -1)
        #expect(throws: PlanError.invalidWeeklyVolume) { try PlanBuilder.build(inputs) }
    }

    @Test func deterministicAndCodable() throws {
        let a = try PlanBuilder.build(sampleInputs())
        let b = try PlanBuilder.build(sampleInputs())
        #expect(a == b)
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(TrainingPlan.self, from: data) == a)
    }

    @Test func intervalSessionStructure() throws {
        let plan = try PlanBuilder.build(sampleInputs(goal: .fiveK, weeks: 12, current: 35_000))
        let session = try #require(plan.workouts.first { $0.kind == .intervals })
        #expect(session.warmup?.target?.zone == .easy)
        #expect(session.cooldown != nil)
        let block = try #require(session.blocks.first)
        #expect(block.iterations >= 3)
        #expect(block.steps.map(\.purpose) == [.work, .recovery])
        #expect(block.steps[0].step.target?.zone == .interval)
        #expect(block.steps[1].step.target == nil)
    }

    @Test func raceEarlyInWeekStillHasQuietDays() throws {
        // Race on a Monday, long runs on Sunday: the Sunday before must not be a long run.
        var inputs = sampleInputs(goal: .halfMarathon, weeks: 12)
        inputs.raceDate = LocalDate(year: 2027, month: 2, day: 1)
        #expect(inputs.raceDate.weekday == .monday)
        let plan = try PlanBuilder.build(inputs)
        #expect(PlanValidator.validate(plan).isEmpty, "\(PlanValidator.validate(plan))")
        let dayBefore = plan.workouts.first { $0.date == inputs.raceDate.adding(days: -1) }
        #expect(dayBefore.map { $0.kind == .easy && $0.totalMeters <= 4_000 } ?? true)
    }
}
