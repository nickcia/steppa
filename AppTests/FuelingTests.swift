import Testing
@testable import TrackStar
import PlanEngine

/// Fueling is only about carbs during the run: nothing under about 75 minutes, 30–60 g an hour after that, up to
/// 90 g for the longest, with a gel timetable.
@MainActor
struct FuelingTests {
    @Test func shortRunsGetNoPlan() {
        #expect(Fueling.plan(minutes: 25, isRace: true) == nil)
        #expect(Fueling.plan(minutes: 70, isRace: false) == nil)
    }

    @Test func gelsStartAtThirtyFiveMinutesAndAreEvenlySpaced() {
        // 45 g an hour is a 25 g gel about every 35 minutes (rounded to 5).
        #expect(Fueling.gelMinutes(minutes: 90, rate: 30...60) == [35, 70])
        // 75 g an hour: every 20 minutes, none in the last 10.
        #expect(Fueling.gelMinutes(minutes: 210, rate: 60...90) == [35, 55, 75, 95, 115, 135, 155, 175, 195])
        #expect(Fueling.gelMinutes(minutes: 40, rate: 30...60) == [35])
    }

    @Test func longerRunsGetMoreCarbsAnHour() throws {
        let half = try #require(Fueling.plan(minutes: 110, isRace: true))
        #expect(half.gramsPerHour == 30...60)
        #expect(half.advice.contains("trained with"))
        let marathon = try #require(Fueling.plan(minutes: 240, isRace: true))
        #expect(marathon.gramsPerHour == 60...90)
        #expect(marathon.advice.contains("glucose and fructose"))
        #expect(try #require(Fueling.plan(minutes: 100, isRace: false)).advice.contains("practise"))
    }

    @Test func onlyRunsLongEnoughGetAPlan() throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        for workout in plan.workouts {
            let fuel = Fueling.plan(for: workout)
            #expect((fuel == nil) == (workout.totalSeconds / 60 < Fueling.minimumMinutes), "\(workout.name)")
            if let fuel { #expect(fuel.gels >= 1 && fuel.gelMinutes.first == Fueling.firstGelMinute) }
        }
    }
}
