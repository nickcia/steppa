import Foundation
import Testing
import PlanEngine
@testable import TrackStar

/// The workout chart: one bar per step, in order, taller for harder.
@MainActor
struct WorkoutShapeTests {
    let plan = try! PlanBuilder.build(AppModelTests.inputs())

    @Test func intervalsAreTallBarsWithLowRecoveriesBetween() throws {
        let workout = try #require(plan.workouts.first { $0.kind == .intervals })
        let bars = WorkoutShapeView.bars(workout)
        let reps = workout.blocks.first { $0.iterations > 1 }?.iterations ?? 1
        // Warm-up, each rep with its recovery, cool-down.
        #expect(bars.count == workout.expandedSteps.count)
        #expect(bars.filter { $0.zone == .interval }.count == reps)
        let warmup = try #require(bars.first)
        let rep = try #require(bars.first { $0.zone == .interval })
        let recovery = try #require(bars.first { $0.isRecovery })
        #expect(rep.intensity > warmup.intensity)
        #expect(recovery.intensity < warmup.intensity)
    }

    @Test func harderZonesAreTaller() {
        let order: [PaceZone?] = [nil, .easy, .marathon, .threshold, .interval, .repetition]
        let heights = order.map(WorkoutShapeView.intensity)
        #expect(heights == heights.sorted())
    }

    @Test func runWalkShowsWalksLowAndRunsHigher() throws {
        var inputs = AppModelTests.inputs()
        inputs.runWalkStart = inputs.startDate
        let session = try #require(try PlanBuilder.build(inputs).workouts.first { $0.isRunWalkSession })
        let bars = WorkoutShapeView.bars(session)
        #expect(bars.first?.intensity == bars.last?.intensity)
        #expect(Set(bars.map(\.intensity)).count == 2)
        #expect(bars[1].intensity > bars[0].intensity)
    }

    @Test func customWorkoutsDrawTheirBlocks() {
        let template = WorkoutTemplate(name: "x", blocks: [.preset(.warmup), .preset(.tempo), .preset(.strides), .preset(.cooldown)])
        let bars = WorkoutShapeView.bars(template.workout(on: AppModelTests.start, id: "c", paces: plan.paces))
        // Warm-up, tempo, 4 × (stride + jog), cool-down.
        #expect(bars.count == 1 + 1 + 8 + 1)
        #expect(bars[1].zone == .threshold)
        #expect(bars[2].intensity == 1)
    }
}
