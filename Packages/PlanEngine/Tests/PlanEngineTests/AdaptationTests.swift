import Testing
@testable import PlanEngine

/// How a simulated athlete follows the plan.
struct Behaviour {
    /// Returns the share of the planned distance run for a workout (0 = skipped).
    var completion: (Workout) -> Double = { _ in 1 }
    /// Actual time ÷ planned time. Below 1 is faster.
    var paceFactor: Double = 1
}

/// Simulates runs for every workout before `today`, then matches them.
func simulateLog(_ plan: TrainingPlan, until today: LocalDate, _ behaviour: Behaviour,
                 into log: TrainingLog = TrainingLog()) -> TrainingLog {
    var log = log
    let known = Set(log.runs.map(\.id))
    for workout in plan.workouts where workout.date < today && workout.kind != .race {
        let id = "run-\(workout.date)"
        let share = behaviour.completion(workout)
        guard share > 0, !known.contains(id) else { continue }
        log.runs.append(CompletedRun(id: id, date: workout.date, distanceMeters: workout.totalMeters * share,
                                     durationSeconds: workout.totalSeconds * share * behaviour.paceFactor))
    }
    log.matches += RunMatcher.match(workouts: plan.workouts, runs: log.runs, existing: log.matches)
    return log
}

/// Checks invariants every adaptation must keep.
func expectSoundRevision(_ old: TrainingPlan, _ new: TrainingPlan, today: LocalDate,
                         sourceLocation: SourceLocation = #_sourceLocation) {
    let violations = PlanValidator.validate(new)
    #expect(violations.isEmpty, "\(violations.prefix(5))", sourceLocation: sourceLocation)
    let oldPast = old.workouts.filter { $0.date < today }
    let newPast = new.workouts.filter { $0.date < today }
    #expect(oldPast == newPast, "history changed", sourceLocation: sourceLocation)
    let ids = new.workouts.map(\.id)
    #expect(Set(ids).count == ids.count, "duplicate workout IDs", sourceLocation: sourceLocation)
}

@Suite struct PlanAdapterTests {
    let plan = try! PlanBuilder.build(sampleInputs(weeks: 16))
    var today: LocalDate { referenceToday.adding(days: 31) }

    @Test func onTrackReviewChangesNothing() throws {
        let log = simulateLog(plan, until: today, Behaviour())
        let revision = try PlanAdapter.adapt(plan, log: log, trigger: .review, today: today)
        #expect(!revision.changed)
        #expect(revision.plan == plan)
    }

    @Test func missedTrainingLowersVolumeWithoutCatchingUp() throws {
        // Skips every easy run over the last two weeks.
        let skipEasy = Behaviour(completion: { $0.kind == .easy && $0.date >= today.adding(days: -14) ? 0 : 1 })
        let log = simulateLog(plan, until: today, skipEasy)
        let revision = try PlanAdapter.adapt(plan, log: log, trigger: .review, today: today)
        #expect(revision.reasons.contains { if case .missedTraining = $0 { true } else { false } })
        expectSoundRevision(plan, revision.plan, today: today)

        let futureOld = plan.weeks.filter { $0.startDate > today }.map(\.targetMeters)
        let futureNew = revision.plan.weeks.filter { $0.startDate > today }.map(\.targetMeters)
        #expect(futureNew.count == futureOld.count)
        #expect(zip(futureNew, futureOld).allSatisfy { $0 <= $1 + 1 })
        #expect(futureNew.first! < futureOld.first!)

        // Reviewing again on the same data doesn't lower it a second time.
        let again = try PlanAdapter.adapt(revision.plan, log: log, trigger: .review, today: today)
        #expect(!again.changed)
        let tomorrow = try PlanAdapter.adapt(revision.plan, log: log, trigger: .review, today: today.adding(days: 1))
        #expect(!tomorrow.reasons.contains { if case .missedTraining = $0 { true } else { false } })
    }

    @Test func breakReducesVolumeByLength() throws {
        let tenDaysOff = Behaviour(completion: { $0.date >= today.adding(days: -10) ? 0 : 1 })
        let log = simulateLog(plan, until: today, tenDaysOff)
        let revision = try PlanAdapter.adapt(plan, log: log, trigger: .review, today: today)
        #expect(revision.reasons.contains { if case .returningFromBreak(let d) = $0 { d >= 10 } else { false } })
        expectSoundRevision(plan, revision.plan, today: today)
        let progression = Periodisation.Progression.after(plan.weeks.filter { $0.startDate <= today })!
        let nextWeek = revision.plan.weeks.first { $0.startDate > today }!
        #expect(nextWeek.targetMeters <= PlanRules.nextLoadingVolume(after: progression.lastLoadingMeters * 0.8, .intermediate) + 1)
    }

    @Test func fasterSessionsRaiseFitnessOnceAndGently() throws {
        let log = simulateLog(plan, until: today, Behaviour(paceFactor: 0.9))
        let revision = try PlanAdapter.adapt(plan, log: log, trigger: .review, today: today)
        let improved = revision.reasons.contains { if case .fitnessImproved = $0 { true } else { false } }
        #expect(improved)
        #expect(revision.plan.fitness.score > plan.fitness.score)
        #expect(revision.plan.fitness.score <= plan.fitness.score * 1.03 + 0.001)
        #expect(revision.plan.paces.threshold.mid < plan.paces.threshold.mid)
        expectSoundRevision(plan, revision.plan, today: today)

        // Same evidence again: no further change.
        let again = try PlanAdapter.adapt(revision.plan, log: log, trigger: .review, today: today.adding(days: 1))
        #expect(!again.changed)
    }

    @Test func slowerSessionsLowerFitness() throws {
        let log = simulateLog(plan, until: today, Behaviour(paceFactor: 1.12))
        let revision = try PlanAdapter.adapt(plan, log: log, trigger: .review, today: today)
        #expect(revision.plan.fitness.score < plan.fitness.score)
        #expect(revision.plan.fitness.score >= plan.fitness.score * 0.97 - 0.001)
        expectSoundRevision(plan, revision.plan, today: today)
    }

    @Test func raceDateMovesLaterAndEarlier() throws {
        let log = simulateLog(plan, until: today, Behaviour())
        let later = try PlanAdapter.adapt(plan, log: log, trigger: .raceDateChanged(plan.inputs.raceDate.adding(days: 21)), today: today)
        expectSoundRevision(plan, later.plan, today: today)
        #expect(later.plan.weeks.count == plan.weeks.count + 3)
        #expect(later.plan.workouts.last?.date == plan.inputs.raceDate.adding(days: 21))

        let earlier = try PlanAdapter.adapt(plan, log: log, trigger: .raceDateChanged(today.adding(days: 12)), today: today)
        expectSoundRevision(plan, earlier.plan, today: today)
        #expect(earlier.plan.workouts.last?.date == today.adding(days: 12))
        #expect(earlier.plan.weeks.last?.phase == .taper)

        let thisWeek = try PlanAdapter.adapt(plan, log: log, trigger: .raceDateChanged(today.adding(days: 2)), today: today)
        expectSoundRevision(plan, thisWeek.plan, today: today)
    }

    @Test func availabilityChangeMovesFutureWorkouts() throws {
        let log = simulateLog(plan, until: today, Behaviour())
        let newDays: Set<Weekday> = [.monday, .wednesday, .friday, .saturday]
        let revision = try PlanAdapter.adapt(plan, log: log,
                                             trigger: .availabilityChanged(runDays: newDays, longRunDay: .saturday),
                                             today: today)
        expectSoundRevision(plan, revision.plan, today: today)
        let future = revision.plan.workouts.filter { $0.date >= today && $0.kind != .race }
        #expect(future.allSatisfy { newDays.contains($0.date.weekday) })
        #expect(future.filter { $0.kind == .long }.allSatisfy { $0.date.weekday == .saturday })
    }

    @Test func newRaceResultResetsFitness() throws {
        let result = RacePerformance(.tenK, timeSeconds: 44 * 60, date: today.adding(days: -1))
        let revision = try PlanAdapter.adapt(plan, log: TrainingLog(), trigger: .newRaceResult(result), today: today)
        let expected = FitnessModel.score(distanceMeters: 10_000, timeSeconds: 44 * 60)
        #expect(abs(revision.plan.fitness.score - expected) < 0.001)
        #expect(revision.plan.fitnessUpdatedOn == today)
    }

    @Test func invalidRequestsThrow() {
        #expect(throws: PlanError.raceNotAfterStart) {
            try PlanAdapter.adapt(plan, log: TrainingLog(), trigger: .raceDateChanged(today), today: today)
        }
        #expect(throws: PlanError.planFinished) {
            try PlanAdapter.adapt(plan, log: TrainingLog(), trigger: .review, today: plan.inputs.raceDate)
        }
        #expect(throws: PlanError.longRunDayNotARunDay) {
            try PlanAdapter.adapt(plan, log: TrainingLog(),
                                  trigger: .availabilityChanged(runDays: [.monday, .tuesday], longRunDay: .sunday), today: today)
        }
    }
}

@Suite struct PlanEditorTests {
    let plan = try! PlanBuilder.build(sampleInputs(weeks: 16))
    // A full Monday-to-Sunday week well into the plan.
    var week: PlanWeek { plan.weeks[4] }
    var today: LocalDate { week.startDate }

    @Test func swapsWithAnotherWorkout() throws {
        let workouts = week.workouts
        let first = workouts[0], second = workouts[1]
        let edited = try PlanEditor.move(first.id, to: second.date, in: plan, today: today)
        let moved = edited.workouts.first { $0.id == first.id }!
        let swapped = edited.workouts.first { $0.id == second.id }!
        #expect(moved.date == second.date && moved.movedFrom == first.date)
        #expect(swapped.date == first.date && swapped.movedFrom == second.date)
    }

    @Test func movingToARestDayIsAllowed() throws {
        let easyRun = try #require(week.workouts.first { $0.kind == .easy })
        let restDay = try #require((0..<7).map { week.startDate.adding(days: $0) }.first { date in
            !week.workouts.contains { $0.date == date }
                && !week.workouts.contains { $0.kind.isHard && abs($0.date.days(until: date)) == 1 }
        })
        let edited = try PlanEditor.move(easyRun.id, to: restDay, in: plan, today: today)
        #expect(PlanValidator.validate(edited).isEmpty)
    }

    @Test func refusesUnsafeOrInvalidMoves() throws {
        let long = try #require(week.workouts.first { $0.kind == .long })
        let session = try #require(week.workouts.first { $0.kind == .tempo || $0.kind == .intervals })
        #expect(throws: EditError.breaksRule(.consecutiveHardDays)) {
            try PlanEditor.move(session.id, to: long.date.adding(days: -1), in: plan, today: today)
        }
        #expect(throws: EditError.differentWeek) {
            try PlanEditor.move(session.id, to: session.date.adding(days: 7), in: plan, today: today)
        }
        #expect(throws: EditError.dateInPast) {
            try PlanEditor.move(session.id, to: session.date, in: plan, today: session.date.adding(days: 1))
        }
        let race = plan.workouts.last!
        #expect(throws: EditError.cannotMoveRace) {
            try PlanEditor.move(race.id, to: race.date.adding(days: -1), in: plan, today: today)
        }
    }
}
