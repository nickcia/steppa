import Foundation
import SwiftData
import Testing
import PlanEngine
@testable import TrackStar

/// Integration tests for the app layer: storage, edits, adaptation and export/import,
/// each against a fresh in-memory store with a pinned "today".
@MainActor
struct AppModelTests {
    /// Monday 2 November 2026.
    static let start = LocalDate(year: 2026, month: 11, day: 2)

    static func inputs(weeks: Int = 14) -> PlanInputs {
        PlanInputs(goal: .halfMarathon, raceDate: start.adding(days: weeks * 7 + 6), startDate: start,
                   currentWeeklyMeters: 30_000, fitness: .recentRace(.init(.tenK, timeSeconds: 50 * 60)),
                   runDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday, experience: .intermediate)
    }

    static func makeModel(today: LocalDate) -> AppModel {
        AppModel(container: Persistence.makeContainer(inMemory: true), clock: { today })
    }

    static func startedModel(today: LocalDate) throws -> AppModel {
        let model = makeModel(today: today)
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(inputs()))
        return model
    }

    @Test func startsAndReloadsAPlan() throws {
        let container = Persistence.makeContainer(inMemory: true)
        let model = AppModel(container: container, clock: { Self.start })
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(Self.inputs()))
        let plan = try #require(model.plan)
        #expect(plan == (try PlanBuilder.build(Self.inputs())))
        let reopened = AppModel(container: container, clock: { Self.start })
        #expect(reopened.plan == plan)
        #expect(reopened.disclaimerAccepted)
    }

    @Test func doneWorkoutsCountAsRuns() throws {
        let model = try Self.startedModel(today: Self.start.adding(days: 7))
        let workout = try #require(model.plan?.workouts.first)
        model.setStatus(.done, for: workout)
        #expect(model.status(of: workout) == .done)
        let log = model.trainingLog
        #expect(log.runs.count == 1)
        #expect(log.runs[0].distanceMeters == workout.totalMeters)
        #expect(log.matches == [RunMatch(workoutID: workout.id, runID: log.runs[0].id)])
        model.setStatus(nil, for: workout)
        #expect(model.status(of: workout) == nil)
        #expect(model.trainingLog.runs.isEmpty)
    }

    @Test func movesAWorkoutWithinItsWeek() throws {
        let model = try Self.startedModel(today: Self.start.adding(days: 21))
        let week = try #require(model.week(containing: model.today))
        let easy = try #require(week.workouts.first { $0.kind == .easy && $0.date >= model.today })
        let restDay = try #require((0..<7).map { week.startDate.adding(days: $0) }.first { date in
            date >= model.today && model.workout(on: date) == nil
                && !week.workouts.contains { $0.kind.isHard && abs($0.date.days(until: date)) == 1 }
        })
        #expect(model.move(easy, to: restDay))
        let moved = try #require(model.plan?.workouts.first { $0.id == easy.id })
        #expect(moved.date == restDay)
        #expect(moved.movedFrom == easy.date)
        #expect(PlanValidator.validate(model.plan!).isEmpty)
    }

    @Test func refusesUnsafeMoves() throws {
        // A week with both a quality session and a long run (step-back weeks may have no session).
        let target = try #require(try PlanBuilder.build(Self.inputs()).weeks.first { week in
            week.index > 0 && week.workouts.contains { $0.kind == .tempo || $0.kind == .intervals }
                && week.workouts.contains { $0.kind == .long }
        })
        let model = try Self.startedModel(today: target.startDate)
        let week = try #require(model.week(containing: model.today))
        let session = try #require(week.workouts.first { $0.kind == .tempo || $0.kind == .intervals })
        let long = try #require(week.workouts.first { $0.kind == .long })
        let before = model.plan
        #expect(!model.move(session, to: long.date.adding(days: -1)))
        #expect(model.lastError != nil)
        #expect(model.plan == before)
    }

    @Test func reviewAdaptsAfterMissedTrainingOnce() throws {
        let today = Self.start.adding(days: 28)
        let model = try Self.startedModel(today: today)
        // Did the first two weeks, then skipped everything.
        let original = try #require(model.plan)
        for workout in original.workouts where workout.date < today {
            model.setStatus(workout.date < Self.start.adding(days: 14) ? .done : .skipped, for: workout)
        }
        #expect(model.plan == original, "ticking workouts off doesn't re-plan by itself")
        model.reviewPlan()
        let plan = try #require(model.plan)
        #expect(plan.revision >= 1)
        #expect(model.changes.count == 1)
        #expect(model.unseenChange != nil)
        #expect(PlanValidator.validate(plan).isEmpty)

        model.reviewPlan()
        #expect(model.changes.count == 1, "a second review on the same data must not change the plan again")
        model.markChangesSeen()
        #expect(model.unseenChange == nil)

        model.undo(model.changes[0])
        #expect(model.plan == original)
        #expect(model.changes.isEmpty)
    }

    @Test func changesBeforeTheyAreSeenMergeIntoOne() throws {
        let model = try Self.startedModel(today: Self.start.adding(days: 10))
        let original = model.plan
        let race = model.plan!.inputs.raceDate
        model.changeRaceDate(race.adding(days: 7))
        model.changeAvailability(runDays: [.monday, .wednesday, .friday, .sunday], longRunDay: .sunday)
        #expect(model.changes.count == 1)
        #expect(model.changes[0].reasons.count == 2)
        model.undo(model.changes[0])
        #expect(model.plan == original)
    }

    @Test func noReviewUntilTheAthleteTicksSomethingOff() throws {
        let model = try Self.startedModel(today: Self.start.adding(days: 28))
        model.reviewPlan()
        #expect(model.plan?.revision == 0)
        #expect(model.changes.isEmpty)
    }

    @Test func changingTheRaceDateReplans() throws {
        let model = try Self.startedModel(today: Self.start.adding(days: 10))
        let newDate = model.plan!.inputs.raceDate.adding(days: 14)
        model.changeRaceDate(newDate)
        #expect(model.plan?.inputs.raceDate == newDate)
        #expect(model.plan?.workouts.last?.date == newDate)
        // Nothing logged yet, so only the date change applies (no "break" cut-back).
        #expect(model.changes.first?.reasons == [.raceDateChanged(newDate)])
    }

    @Test func goalTimeAndRaces() throws {
        let model = try Self.startedModel(today: Self.start)
        model.setGoalTime(100 * 60)
        #expect(model.plan?.inputs.goalTimeSeconds == 6000.0)
        model.addRace(RaceRecord(name: "Parkrun", distance: .fiveK, date: Self.start.adding(days: 20)))
        #expect(model.races.map(\.name) == ["Parkrun"])
        model.deleteRace(model.races[0])
        #expect(model.races.isEmpty)
    }

    @Test func exportImportRoundTrip() throws {
        let model = try Self.startedModel(today: Self.start.adding(days: 8))
        let first = try #require(model.plan?.workouts.first)
        model.setStatus(.done, for: first)
        model.addRace(RaceRecord(name: "Tune-up", distance: .tenK, date: Self.start.adding(days: 40), goalSeconds: 48 * 60))
        model.setUnits(.imperial)

        let data = try model.exportBundle().encoded()
        let decoded = try ExportBundle.decode(data)

        let fresh = Self.makeModel(today: Self.start.adding(days: 8))
        fresh.importBundle(decoded)
        #expect(fresh.plan == model.plan)
        #expect(fresh.statuses == model.statuses)
        #expect(fresh.units == .imperial)
        #expect(fresh.disclaimerAccepted)
        #expect(fresh.races.map(\.name) == ["Tune-up"])
        #expect(fresh.races.first?.goalSeconds == 2880.0)
    }

    @Test func importRejectsForeignAndNewerFiles() throws {
        #expect(throws: ExportBundle.ImportError.self) { try ExportBundle.decode(Data("{\"hello\": 1}".utf8)) }
        var bundle = ExportBundle(exportedAt: .now, units: .metric, plan: nil, statuses: [:], races: [], changes: [])
        bundle.version = ExportBundle.currentVersion + 1
        let data = try bundle.encoded()
        #expect(throws: ExportBundle.ImportError.self) { try ExportBundle.decode(data) }
    }

    @Test func completionStats() throws {
        let today = Self.start.adding(days: 14)
        let model = try Self.startedModel(today: today)
        let due = model.plan!.workouts.filter { $0.date < today }
        model.setStatus(.done, for: due[0])
        model.setStatus(.skipped, for: due[1])
        let stats = CompletionStats(plan: model.plan!, statuses: model.statuses, today: today)
        #expect(stats.done == 1 && stats.skipped == 1)
        #expect(stats.due == due.count)
    }
}
