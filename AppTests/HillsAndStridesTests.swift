import Foundation
import Testing
import WorkoutKit
import PlanEngine
@testable import Steppa

@MainActor
struct HillsAndStridesTests {
    let plan = try! PlanBuilder.build(AppModelTests.inputs(weeks: 16))

    var hills: Workout { plan.workouts.first { $0.kind == .hills }! }
    var strides: Workout { plan.workouts.first { $0.kind == .easy && $0.blocks.count > 1 }! }

    @Test func planHasBoth() {
        #expect(plan.workouts.contains { $0.kind == .hills })
        #expect(plan.workouts.contains { $0.kind == .easy && $0.blocks.count > 1 })
    }

    @Test func describedByFeelNotPace() {
        let describer = WorkoutDescriber(format: DisplayFormat(units: .metric))
        func details(_ workout: Workout) -> [String] {
            describer.sections(workout).flatMap { section -> [WorkoutDescriber.Line] in
                switch section {
                case .single(let line): [line]
                case .repeated(_, let lines): lines
                }
            }.compactMap(\.detail)
        }
        #expect(details(hills).contains("Hard uphill, about 5K effort"))
        #expect(details(strides).contains("Quick but relaxed, not a sprint"))
        #expect(describer.summary(hills).contains("uphill"))
    }

    @Test func intervalsTextHasNoPaceForEffortSteps() {
        let hillText = IntervalsWorkoutBuilder.description(for: hills, units: .metric)
        #expect(hillText.contains("- Uphill hard 1m") || hillText.contains("- Uphill hard 90s"))
        let strideText = IntervalsWorkoutBuilder.description(for: strides, units: .metric)
        #expect(strideText.contains("- Stride 20s"))
        // The easy part keeps its pace range.
        #expect(strideText.contains("/km Pace"))
    }

    @Test func watchHasNoPaceAlertOnHillsOrStrides() {
        for workout in [hills, strides] {
            let custom = WatchWorkoutBuilder.customWorkout(workout, format: DisplayFormat(units: .metric))
            for block in custom.blocks {
                for step in block.steps where step.purpose == .work {
                    let isEffort = workout.kind == .hills || block.iterations > 1
                    if isEffort { #expect(step.step.alert == nil) }
                }
            }
        }
    }
}
