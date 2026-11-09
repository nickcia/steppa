import Foundation
import SwiftData
import Testing
import PlanEngine
@testable import TrackStar

/// Custom workouts in the app: saving, putting them on days, and staying out of the plan the engine adapts.
@MainActor
struct CustomWorkoutAppTests {
    let template = WorkoutTemplate(name: "Progression", blocks: [.preset(.warmup), .preset(.tempo), .preset(.cooldown)])

    func model() throws -> AppModel {
        try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 7))
    }

    @Test func addingReplacesThePlannedRunAndRemovingBringsItBack() throws {
        let model = try model()
        let planned = try #require(model.plan?.workouts.first { $0.date > model.today && $0.kind == .easy })
        let added = try #require(model.addWorkout(template, on: planned.date))
        #expect(added.isCustom)
        #expect(added.name == "Progression")
        #expect(model.workout(on: planned.date)?.id == added.id)
        #expect(model.plannedWorkout(on: planned.date)?.id == planned.id)
        model.removeWorkout(added)
        #expect(model.workout(on: planned.date)?.id == planned.id)
    }

    @Test func oneCustomWorkoutADay() throws {
        let model = try model()
        let day = model.today.adding(days: 2)
        model.addWorkout(template, on: day)
        model.addWorkout(WorkoutTemplate(name: "Second", blocks: [.preset(.easy)]), on: day)
        #expect(model.scheduledWorkouts.count == 1)
        #expect(model.workout(on: day)?.name == "Second")
    }

    @Test func notInThePastNorOnOrAfterRaceDay() throws {
        let model = try model()
        let race = try #require(model.plan?.inputs.raceDate)
        #expect(model.addWorkout(template, on: model.today.adding(days: -1)) == nil)
        #expect(model.addWorkout(template, on: race) == nil)
        #expect(model.addWorkout(template, on: race.adding(days: -1)) != nil)
    }

    @Test func savedWorkoutsAreKeptAndEditedApartFromDays() throws {
        let model = try model()
        model.saveWorkout(template)
        let day = model.today.adding(days: 3)
        let added = try #require(model.addWorkout(template, on: day))
        var changed = template
        changed.name = "Changed"
        model.saveWorkout(changed)
        #expect(model.savedWorkouts.map(\.name) == ["Changed"])
        // The day keeps its own copy.
        #expect(model.workout(on: day)?.name == "Progression")
        model.updateWorkout(added, to: changed)
        #expect(model.workout(on: day)?.name == "Changed")
        model.deleteSavedWorkout(changed)
        #expect(model.savedWorkouts.isEmpty)
        #expect(model.workout(on: day)?.isCustom == true)
    }

    @Test func movingACustomWorkout() throws {
        let model = try model()
        let from = model.today.adding(days: 1)
        let added = try #require(model.addWorkout(template, on: from))
        #expect(model.move(added, to: from.adding(days: 1)))
        #expect(model.workout(on: from.adding(days: 1))?.isCustom == true)
        #expect(model.workout(on: from)?.isCustom != true)
    }

    @Test func theStoredPlanNeverHoldsCustomWorkouts() throws {
        let model = try model()
        model.addWorkout(template, on: model.today.adding(days: 1))
        // Edits to the plan itself go through the engine and keep the custom workout on top.
        model.setGoalTime(6000)
        #expect(model.plan?.inputs.goalTimeSeconds == 6000.0)
        #expect(model.plan?.workouts.contains { $0.isCustom } == true)
        let bundle = model.exportBundle()
        #expect(bundle.plan?.workouts.contains { $0.isCustom } == false)
        #expect(bundle.scheduledWorkouts?.count == 1)
    }

    @Test func doneCustomWorkoutsCountAsRuns() throws {
        let model = try model()
        let day = model.today.adding(days: 1)
        let added = try #require(model.addWorkout(template, on: day))
        model.setStatus(.done, for: added)
        #expect(model.trainingLog.matches.contains { $0.workoutID == added.id })
    }

    @Test func exportAndImportKeepCustomWorkouts() throws {
        let model = try model()
        model.saveWorkout(template)
        model.addWorkout(template, on: model.today.adding(days: 2))
        let data = try model.exportBundle().encoded()
        let other = AppModelTests.makeModel(today: model.today)
        other.importBundle(try ExportBundle.decode(data))
        #expect(other.savedWorkouts == model.savedWorkouts)
        #expect(other.scheduledWorkouts == model.scheduledWorkouts)
        #expect(other.workout(on: model.today.adding(days: 2))?.isCustom == true)
    }

    @Test func oldExportsWithoutCustomWorkoutsStillImport() throws {
        let model = try model()
        var bundle = model.exportBundle()
        bundle.savedWorkouts = nil
        bundle.scheduledWorkouts = nil
        let other = AppModelTests.makeModel(today: model.today)
        other.importBundle(try ExportBundle.decode(try bundle.encoded()))
        #expect(other.plan != nil)
        #expect(other.savedWorkouts.isEmpty)
    }
}
