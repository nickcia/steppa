import Foundation
import Testing
@testable import PlanEngine

@Suite struct CustomWorkoutTests {
    let plan = try! PlanBuilder.build(sampleInputs())

    var template: WorkoutTemplate {
        WorkoutTemplate(name: "Saturday progression", blocks: [
            .preset(.warmup), .preset(.easy), .preset(.intervals), .preset(.cooldown),
        ])
    }

    @Test func warmupAndCooldownBecomeTheWorkoutsOwn() {
        let workout = template.workout(on: referenceToday, id: "custom-x", paces: plan.paces)
        #expect(workout.kind == .custom)
        #expect(workout.title == "Saturday progression")
        #expect(workout.warmup?.goal == .time(seconds: 600))
        #expect(workout.cooldown?.goal == .time(seconds: 600))
        #expect(workout.blocks.count == 2)
        // 5 × (3 min hard + 2 min jog).
        #expect(workout.blocks[1].iterations == 5)
        #expect(workout.blocks[1].steps.map(\.purpose) == [.work, .recovery])
        #expect(workout.totalSeconds == 600 + 1200 + 5 * 300 + 600)
    }

    @Test func zonesTakeTheAthletesPacesUnlessTheySetTheirOwn() {
        var blocks = template.blocks
        let easy = template.workout(on: referenceToday, id: "c", paces: plan.paces).blocks[0].steps[0].step
        #expect(easy.target?.range == plan.paces.easy)
        #expect(easy.target?.zone == .easy)
        blocks[1].main.customPace = PaceRange(fast: 330, slow: 340)
        let own = WorkoutTemplate(name: "x", blocks: blocks).workout(on: referenceToday, id: "c", paces: plan.paces)
        #expect(own.blocks[0].steps[0].step.target?.range == PaceRange(fast: 330, slow: 340))
        // 20 minutes at 5:35 /km is about 3.6 km.
        #expect(abs(own.blocks[0].steps[0].step.estimatedMeters - 1200 / 335 * 1000) < 1)
    }

    @Test func recoveryIsSlowerThanEasyAndOpenHasNoTarget() {
        let recovery = Effort.recovery.pace(plan.paces)!
        #expect(recovery.fast >= plan.paces.easy.slow)
        #expect(Effort.open.pace(plan.paces) == nil)
        let open = WorkoutTemplate(name: "x", blocks: [.preset(.open)]).workout(on: referenceToday, id: "c", paces: plan.paces)
        #expect(open.blocks[0].steps[0].step.target == nil)
        #expect(open.totalMeters > 0)
    }

    @Test func zonesGetFasterInOrder() {
        let mids = [Effort.recovery, .easy, .steady, .threshold, .vo2max, .speed].map { $0.pace(plan.paces)!.mid }
        #expect(mids == mids.sorted(by: >))
    }

    @Test func aCustomWorkoutTakesTheDaysPlace() throws {
        let day = try #require(plan.workouts.first { $0.date > referenceToday && $0.kind != .race }).date
        let scheduled = ScheduledWorkout(date: day, template: template)
        let merged = plan.withCustomWorkouts([scheduled])
        let onDay = merged.workouts.filter { $0.date == day }
        #expect(onDay.count == 1)
        #expect(onDay.first?.id == scheduled.workoutID)
        #expect(onDay.first?.isCustom == true)
        // Everything else is untouched, and the stored plan still has its own workout.
        #expect(merged.workouts.count == plan.workouts.count)
        #expect(plan.workouts.contains { $0.date == day && !$0.isCustom })
    }

    @Test func restDaysGainAWorkoutAndRaceDayAndDaysOutsideThePlanDont() throws {
        let runDays = Set(plan.workouts.map(\.date))
        let rest = try #require((1...14).map { referenceToday.adding(days: $0) }.first { !runDays.contains($0) })
        let merged = plan.withCustomWorkouts([
            ScheduledWorkout(date: rest, template: template),
            ScheduledWorkout(date: plan.inputs.raceDate, template: template),
            ScheduledWorkout(date: plan.inputs.raceDate.adding(days: 30), template: template),
        ])
        #expect(merged.workouts.count == plan.workouts.count + 1)
        #expect(merged.workouts.first { $0.date == plan.inputs.raceDate }?.kind == .race)
        // Still in date order within the week.
        for week in merged.weeks { #expect(week.workouts.map(\.date) == week.workouts.map(\.date).sorted()) }
    }

    @Test func templatesSurviveEncoding() throws {
        let original = template
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(WorkoutTemplate.self, from: data) == original)
        // Plans saved before custom workouts existed still decode (no title).
        let old = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(TrainingPlan.self, from: old).workouts.allSatisfy { $0.title == nil })
    }
}
