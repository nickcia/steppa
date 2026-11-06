import Testing
@testable import PlanEngine

private let day = LocalDate(year: 2026, month: 11, day: 10)

private func easy(_ date: LocalDate, _ meters: Double) -> Workout {
    WorkoutFactory.easy(date, meters: meters, paces: PaceTable(score: 45, goal: .tenK))
}

private func run(_ id: String, _ date: LocalDate, _ meters: Double, pace: Double = 330) -> CompletedRun {
    CompletedRun(id: id, date: date, distanceMeters: meters, durationSeconds: meters / 1000 * pace)
}

@Suite struct RunMatcherTests {
    @Test func matchesSameDayRun() {
        let matches = RunMatcher.match(workouts: [easy(day, 8_000)], runs: [run("a", day, 8_200)])
        #expect(matches == [RunMatch(workoutID: day.description, runID: "a")])
    }

    @Test func toleratesOneDayAndPrefersSameDay() {
        let workouts = [easy(day, 8_000), easy(day.adding(days: 2), 8_000)]
        let runs = [run("late", day.adding(days: 1), 8_000), run("onTime", day.adding(days: 2), 7_000)]
        let matches = RunMatcher.match(workouts: workouts, runs: runs)
        #expect(Set(matches) == [RunMatch(workoutID: day.description, runID: "late"),
                                 RunMatch(workoutID: day.adding(days: 2).description, runID: "onTime")])
    }

    @Test func ignoresShortRunsWrongDistancesAndDistantDays() {
        let workouts = [easy(day, 10_000)]
        #expect(RunMatcher.match(workouts: workouts, runs: [run("tiny", day, 800)]).isEmpty)
        #expect(RunMatcher.match(workouts: workouts, runs: [run("short", day, 4_000)]).isEmpty)
        #expect(RunMatcher.match(workouts: workouts, runs: [run("long", day, 17_000)]).isEmpty)
        #expect(RunMatcher.match(workouts: workouts, runs: [run("old", day.adding(days: -2), 10_000)]).isEmpty)
    }

    @Test func racesNeedTheRightDayAndDistance() {
        let race = WorkoutFactory.race(day, goal: .tenK, paces: PaceTable(score: 45, goal: .tenK))
        #expect(RunMatcher.match(workouts: [race], runs: [run("r", day, 10_050)]).count == 1)
        #expect(RunMatcher.match(workouts: [race], runs: [run("r", day.adding(days: 1), 10_050)]).isEmpty)
        #expect(RunMatcher.match(workouts: [race], runs: [run("r", day, 8_000)]).isEmpty)
    }

    @Test func oneToOneAndRespectsExistingMatches() {
        let workouts = [easy(day, 8_000)]
        let runs = [run("a", day, 8_000), run("b", day, 8_000)]
        #expect(RunMatcher.match(workouts: workouts, runs: runs).count == 1)
        let existing = [RunMatch(workoutID: day.description, runID: "manual")]
        #expect(RunMatcher.match(workouts: workouts, runs: runs, existing: existing).isEmpty)
    }
}

@Suite struct RacePredictorTests {
    let fitness = FitnessEstimate(score: 45, confidence: .high)

    @Test func shortRacesUseFitnessDirectly() {
        let p = RacePredictor.predict(.tenK, fitness: fitness, recentRuns: [], asOf: day)
        #expect(abs(p.seconds - FitnessModel.raceTimeSeconds(distanceMeters: 10_000, score: 45)) < 0.001)
        #expect(p.fastestSeconds < p.seconds && p.seconds < p.slowestSeconds)
    }

    @Test func marathonPenalisesLowMileage() {
        let base = FitnessModel.raceTimeSeconds(distanceMeters: RaceDistance.marathon.meters, score: 45)
        let low = RacePredictor.predict(.marathon, fitness: fitness, recentRuns: [], asOf: day)
        let highRuns = (1...42).map { run("r\($0)", day.adding(days: -$0), 10_000, pace: 400) }
        let high = RacePredictor.predict(.marathon, fitness: fitness, recentRuns: highRuns, asOf: day)
        #expect(abs(low.seconds - base * 1.08) < 1)
        #expect(abs(high.seconds - base) < 1)
    }

    @Test func strongRecentEffortRaisesPrediction() {
        let fast = run("tt", day.adding(days: -5), 5_000, pace: 220)
        let p = RacePredictor.predict(.tenK, fitness: fitness, recentRuns: [fast], asOf: day)
        #expect(p.score > 45)
        let old = run("tt", day.adding(days: -60), 5_000, pace: 220)
        #expect(RacePredictor.predict(.tenK, fitness: fitness, recentRuns: [old], asOf: day).score == 45)
    }

    @Test func lowConfidenceWidensRange() {
        let sure = RacePredictor.predict(.tenK, fitness: fitness, recentRuns: [], asOf: day)
        let unsure = RacePredictor.predict(.tenK, fitness: .init(score: 45, confidence: .low), recentRuns: [], asOf: day)
        #expect(unsure.slowestSeconds - unsure.fastestSeconds > sure.slowestSeconds - sure.fastestSeconds)
    }
}
