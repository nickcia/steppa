import Foundation
import HealthKit
import Testing
import WorkoutKit
import PlanEngine
@testable import TrackStar

/// Stands in for Apple Health.
final class FakeRunSource: RunSource {
    var runs: [CompletedRun]
    var accessRequested = false

    init(runs: [CompletedRun]) { self.runs = runs }

    var isAvailable: Bool { true }
    func requestAccess() async throws { accessRequested = true }
    func runs(since: LocalDate) async throws -> [CompletedRun] { runs.filter { $0.date >= since } }
    var series: [String: RunSeries] = [:]
    func series(forRun id: String) async throws -> RunSeries? { series[id] }
    var ageInYears: Int?
    func age() -> Int? { ageInYears }
}

@MainActor
struct HealthIntegrationTests {
    static func run(for workout: PlanEngine.Workout, id: String, scale: Double = 1) -> CompletedRun {
        CompletedRun(id: id, date: workout.date, distanceMeters: workout.totalMeters * scale,
                     durationSeconds: workout.totalSeconds * scale)
    }

    func model(today: LocalDate, runs: (TrainingPlan) -> [CompletedRun]) throws -> (AppModel, FakeRunSource) {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let source = FakeRunSource(runs: runs(plan))
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { today }, runSource: source)
        model.acceptDisclaimer()
        model.start(plan)
        return (model, source)
    }

    @Test func healthRunsTickOffWorkouts() async throws {
        let (model, source) = try model(today: AppModelTests.start.adding(days: 9)) { plan in
            Array(plan.workouts.prefix(2)).enumerated().map { Self.run(for: $1, id: "hk\($0)", scale: 1.04) }
        }
        let first = try #require(model.plan?.workouts.first)
        #expect(model.status(of: first) == nil)

        await model.connectHealth()
        #expect(source.accessRequested)
        #expect(model.healthConnected)
        #expect(model.status(of: first) == .done)
        #expect(model.healthRun(for: first)?.id == "hk0")
        #expect(model.trainingLog.matches.count == 2)

        // Ticking off a workout that Health already covers doesn't count it twice.
        model.setStatus(.done, for: first)
        #expect(model.trainingLog.runs.count == 2)
    }

    @Test func skippedWorkoutsAreNotMatched() async throws {
        let (model, _) = try model(today: AppModelTests.start.adding(days: 9)) { plan in
            [Self.run(for: plan.workouts[0], id: "hk0")]
        }
        let first = try #require(model.plan?.workouts.first)
        model.setStatus(.skipped, for: first)
        await model.connectHealth()
        #expect(model.status(of: first) == .skipped)
        #expect(model.healthRun(for: first) == nil)
    }

    @Test func healthRunsAloneAreEnoughToAdapt() async throws {
        // Ran the first week (recorded in Health), nothing since; never ticked anything by hand.
        let today = AppModelTests.start.adding(days: 28)
        let (model, _) = try model(today: today) { plan in
            plan.workouts.filter { $0.date < AppModelTests.start.adding(days: 7) }.enumerated()
                .map { Self.run(for: $1, id: "hk\($0)") }
        }
        #expect(!model.hasTrainingRecord)
        await model.connectHealth()
        #expect(model.hasTrainingRecord)
        #expect(model.changes.count == 1)
        #expect(model.plan?.revision == 1)
        #expect(PlanValidator.validate(model.plan!).isEmpty)
    }
}

@MainActor
struct WatchWorkoutBuilderTests {
    let plan = try! PlanBuilder.build(AppModelTests.inputs())
    let format = DisplayFormat(units: .metric)

    @Test func intervalSessionMapsStepByStep() throws {
        let session = try #require(plan.workouts.first { $0.kind == .intervals })
        let custom = WatchWorkoutBuilder.customWorkout(session, format: format)
        #expect(custom.activity == .running)
        #expect(custom.location == .outdoor)
        #expect(custom.warmup?.goal == .distance(session.warmup!.estimatedMeters, .meters))
        #expect(custom.warmup?.alert == nil)
        #expect(custom.blocks.count == session.blocks.count)

        let block = try #require(custom.blocks.first)
        let source = session.blocks[0]
        #expect(block.iterations == source.iterations)
        #expect(block.steps.map(\.purpose) == [.work, .recovery])

        let work = block.steps[0].step
        #expect(work.goal == .distance(source.steps[0].step.estimatedMeters, .meters))
        let alert = try #require(work.alert as? SpeedRangeAlert)
        let range = source.steps[0].step.target!.range
        #expect(abs(alert.target.lowerBound.converted(to: .metersPerSecond).value - 1000 / range.slow) < 0.0001)
        #expect(abs(alert.target.upperBound.converted(to: .metersPerSecond).value - 1000 / range.fast) < 0.0001)

        let recovery = block.steps[1].step
        guard case .time(let seconds, .seconds) = recovery.goal else {
            Issue.record("recovery should be time-based")
            return
        }
        #expect(seconds > 0)
        #expect(recovery.alert == nil)
    }

    @Test func idsAreStableAndChangeWithTheWorkout() throws {
        let workout = try #require(plan.workouts.first)
        #expect(WatchWorkoutBuilder.stableID(for: workout) == WatchWorkoutBuilder.stableID(for: workout))
        var moved = workout
        moved.date = workout.date.adding(days: 1)
        #expect(WatchWorkoutBuilder.stableID(for: moved) != WatchWorkoutBuilder.stableID(for: workout))
        let ids = Set(plan.workouts.map(WatchWorkoutBuilder.stableID(for:)))
        #expect(ids.count == plan.workouts.count)
    }

    @Test func startTimeUsesTheWorkoutDay() {
        let c = WatchWorkoutBuilder.startComponents(for: LocalDate(year: 2026, month: 11, day: 7), minutes: 6 * 60 + 30)
        #expect(c == DateComponents(year: 2026, month: 11, day: 7, hour: 6, minute: 30))
    }

    @Test func everyWorkoutInAPlanConverts() {
        for workout in plan.workouts {
            let custom = WatchWorkoutBuilder.customWorkout(workout, format: format)
            #expect(!custom.blocks.isEmpty)
            #expect(CustomWorkout.supportsActivity(.running))
        }
    }
}
