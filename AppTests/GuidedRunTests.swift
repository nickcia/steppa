import Foundation
import Testing
import PlanEngine
@testable import TrackStar

@MainActor
struct GuidedRunTests {
    let describer = WorkoutDescriber(format: DisplayFormat(units: .metric))

    func runWalkSession() throws -> Workout {
        var inputs = PlanInputs(goal: .fiveK, raceDate: LocalDate.today.adding(days: 98), startDate: .today,
                                currentWeeklyMeters: 0, fitness: .estimated, runDays: [.tuesday, .thursday, .sunday],
                                longRunDay: .sunday, experience: .beginner)
        inputs.runWalkStart = inputs.startDate
        let plan = try PlanBuilder.build(inputs)
        return try #require(plan.workouts.first { $0.kind == .runWalk })
    }

    @Test func runWalkBecomesWalkRunWalkSteps() throws {
        let steps = GuidedTimeline.steps(for: try runWalkSession(), describer: describer)
        // 5-minute walk, 8 × (1 min run, 1:30 walk), 5-minute walk.
        #expect(steps.count == 18)
        #expect(steps.first?.role == .walk && steps.first?.seconds == 300)
        #expect(steps[1].role == .run && steps[1].seconds == 60 && steps[1].rep?.index == 1 && steps[1].rep?.count == 8)
        #expect(steps[2].role == .walk && steps[2].seconds == 90)
        #expect(steps.last?.role == .walk)
        #expect(steps.allSatisfy { $0.meters == nil })
    }

    @Test func cuesSayWhatToDo() throws {
        let steps = GuidedTimeline.steps(for: try runWalkSession(), describer: describer)
        #expect(GuidedTimeline.startCue(steps, index: 0).contains("warm up"))
        #expect(GuidedTimeline.startCue(steps, index: 1).hasPrefix("Run for 1"))
        // The last run says so.
        #expect(GuidedTimeline.startCue(steps, index: 15).hasPrefix("Last one"))
        #expect(GuidedTimeline.startCue(steps, index: 17).contains("cool down"))
        // A heads-up ten seconds before the warm-up walk ends; nothing mid-way through a 1-minute run.
        let warmupCues = GuidedTimeline.midCues(steps, index: 0)
        #expect(warmupCues.contains { $0.at == 290 && $0.text.contains("run") })
        #expect(GuidedTimeline.midCues(steps, index: 1).count == 1)
    }

    @Test func distanceStepsKeepTheirDistanceAndAnEstimate() throws {
        let plan = try PlanBuilder.build(sampleInputs())
        let tempo = try #require(plan.workouts.first { $0.kind == .tempo })
        let steps = GuidedTimeline.steps(for: tempo, describer: describer)
        #expect(steps.first?.role == .warmup)
        #expect(steps.last?.role == .cooldown)
        let work = try #require(steps.first { $0.role == .work })
        #expect(work.title == "Threshold")
        if case .distance(let meters) = try #require(tempo.blocks.first?.steps.first?.step.goal) {
            #expect(work.meters == meters)
        }
        #expect(work.seconds > 0)
        // Distance steps don't get time-based mid cues (the time is only an estimate).
        #expect(GuidedTimeline.midCues(steps, index: steps.firstIndex(of: work)!).isEmpty)
    }

    @Test func spokenAmountsReadNaturally() {
        #expect(GuidedTimeline.spokenDuration(90).contains("1 minute"))
        #expect(GuidedTimeline.spokenDuration(90).contains("30 seconds"))
    }
}

/// Same inputs as the engine's tests use.
private func sampleInputs() -> PlanInputs {
    PlanInputs(goal: .halfMarathon, raceDate: LocalDate.today.adding(days: 14 * 7 + 2), startDate: .today,
               currentWeeklyMeters: 30_000, fitness: .recentRace(.init(.tenK, timeSeconds: 50 * 60)),
               runDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday, experience: .intermediate)
}
