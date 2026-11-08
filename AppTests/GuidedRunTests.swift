import CoreLocation
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

@MainActor
struct GuidedRunCueTests {
    let target = PaceRange(fast: 300, slow: 320)

    @Test func paceVerdictAllowsGPSNoise() {
        #expect(GuidedTimeline.paceVerdict(current: 285, target: target) == .fast)
        #expect(GuidedTimeline.paceVerdict(current: 295, target: target) == .onPace) // within 3% of 5:00
        #expect(GuidedTimeline.paceVerdict(current: 325, target: target) == .onPace)
        #expect(GuidedTimeline.paceVerdict(current: 340, target: target) == .slow)
    }

    @Test func paceCuesNameTheTargetInTheAthletesUnits() {
        let metric = GuidedTimeline.paceCue(.fast, target: target, units: .metric)
        #expect(metric.contains("Ease off") && metric.contains("5:10") && metric.contains("kilometre"))
        let imperial = GuidedTimeline.paceCue(.slow, target: target, units: .imperial)
        #expect(imperial.contains("Pick it up") && imperial.contains("mile"))
    }

    @Test func splitCueGivesTheDistanceAndTime() {
        let cue = GuidedTimeline.splitCue(number: 2, seconds: 348, units: .metric)
        #expect(cue.contains("2") && cue.contains("5 minutes") && cue.contains("48 seconds"))
    }

    @Test func onlyPacedWorkStepsGetPaceCues() throws {
        let plan = try PlanBuilder.build(PlanInputs(goal: .halfMarathon, raceDate: LocalDate.today.adding(days: 100), startDate: .today,
                                                    currentWeeklyMeters: 30_000, fitness: .recentRace(.init(.tenK, timeSeconds: 50 * 60)),
                                                    runDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday,
                                                    experience: .intermediate))
        let describer = WorkoutDescriber(format: DisplayFormat(units: .metric))
        let tempo = try #require(plan.workouts.first { $0.kind == .tempo })
        let steps = GuidedTimeline.steps(for: tempo, describer: describer)
        #expect(steps.first { $0.role == .work }?.target != nil)
        #expect(steps.filter { $0.role != .work }.allSatisfy { $0.target == nil })
        if let hills = plan.workouts.first(where: { $0.kind == .hills }) {
            #expect(GuidedTimeline.steps(for: hills, describer: describer).filter { $0.role == .work }.allSatisfy { $0.target == nil })
        }
    }

    @Test func livePaceComesFromTheLastHalfMinute() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // 4 m/s (4:10/km) along a line, one point a second.
        let route = (0...40).map { i in
            CLLocation(coordinate: .init(latitude: 51.5 + Double(i) * 4 / 111_320, longitude: -0.12), altitude: 0,
                       horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 4,
                       timestamp: start.addingTimeInterval(Double(i)))
        }
        let pace = RunRecorder.pace(of: route, window: 30, at: start.addingTimeInterval(40))
        #expect(pace.map { abs($0 - 250) < 5 } == true)
        // Not enough running yet.
        #expect(RunRecorder.pace(of: Array(route.prefix(3)), window: 30, at: start.addingTimeInterval(3)) == nil)
    }
}
