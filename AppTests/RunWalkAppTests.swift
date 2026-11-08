import Foundation
import Testing
import PlanEngine
import WorkoutKit
@testable import TrackStar

@MainActor
struct RunWalkAppTests {
    func newRunnerPlan() throws -> TrainingPlan {
        let draft = OnboardingDraft()
        draft.goal = .fiveK
        draft.raceDate = Calendar.current.date(byAdding: .day, value: 14 * 7, to: .now)!
        draft.experience = .beginner
        draft.startsWithRunWalk = true
        draft.weeklyDistance = 40 // ignored for new runners
        return try PlanBuilder.build(draft.inputs)
    }

    @Test func justStartingOutSkipsFitnessAndDistanceQuestions() {
        let draft = OnboardingDraft()
        draft.startsWithRunWalk = true
        draft.step = .experience
        #expect(draft.nextStep == .availability)
        draft.step = .availability
        #expect(draft.previousStep == .experience)
        #expect(draft.recommendedRunDays >= 3)
        #expect(draft.inputs.runWalkStart == draft.today && draft.inputs.currentWeeklyMeters == 0)
        #expect(draft.inputs.fitness == .estimated)
        draft.startsWithRunWalk = false
        draft.step = .experience
        #expect(draft.nextStep == .fitness)
    }

    @Test func runWalkSessionsReadAsWalkAndRun() throws {
        let plan = try newRunnerPlan()
        let session = try #require(plan.workouts.first { $0.kind == .runWalk })
        let describer = WorkoutDescriber(format: DisplayFormat(units: .metric))
        #expect(describer.summary(session).contains("run") && describer.summary(session).contains("walk"))
        guard case .single(let warmup) = describer.sections(session).first else { Issue.record("no warm-up"); return }
        #expect(warmup.title.hasPrefix("Walk"))
        let thirty = try #require(plan.workouts.last { $0.isRunWalkSession })
        #expect(describer.summary(thirty).contains("non-stop"))
    }

    @Test func watchAndGarminNameEveryStep() throws {
        let plan = try newRunnerPlan()
        let session = try #require(plan.workouts.first { $0.kind == .runWalk })
        let custom = WatchWorkoutBuilder.customWorkout(session, format: DisplayFormat(units: .metric))
        #expect(custom.blocks.first?.steps.first?.step.alert == nil)
        let text = IntervalsWorkoutBuilder.description(for: session, units: .metric)
        #expect(text.contains("- Walk 5m") && text.contains("- Run 1m") && !text.contains("Pace"))
    }

    @Test func helpAnswersBeginnerQuestions() {
        #expect(AppHelp.search("I'm a beginner and can't run for long").first?.id == "runwalk")
    }
}
