import Testing
@testable import PlanEngine

private let start = LocalDate(year: 2026, month: 11, day: 9)

private func inputs(weeklyKm: Double, fitness: FitnessSource = .estimated,
                    experience: Experience = .intermediate) -> PlanInputs {
    PlanInputs(goal: .halfMarathon, raceDate: start.adding(days: 12 * 7 + 6), startDate: start,
               currentWeeklyMeters: weeklyKm * 1000, fitness: fitness,
               runDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday, experience: experience)
}

/// `perWeek` runs of `km` each, in every one of the last `weeks` weeks before the start.
private func history(weeks: Int = 6, perWeek: Int = 3, km: Double, pacePerKm: Double = 360) -> [CompletedRun] {
    (0..<weeks).flatMap { week in
        (0..<perWeek).map { i in
            let date = start.adding(days: -(week * 7 + 1 + i * 2))
            return CompletedRun(id: "\(week)-\(i)", date: date, distanceMeters: km * 1000,
                                durationSeconds: km * pacePerKm)
        }
    }
}

@Suite struct HistoryCalibrationTests {
    @Test func sparseHistoryChangesNothing() {
        let given = inputs(weeklyKm: 30)
        // Runs in only 3 of the 6 weeks: probably not everything is recorded.
        let result = HistoryCalibration.calibrate(given, runs: history(weeks: 3, km: 10))
        #expect(result.volume == .notEnoughHistory(runs: 9))
        #expect(result.inputs.currentWeeklyMeters == 30_000)
    }

    @Test func agreementKeepsTheStatedVolume() {
        let result = HistoryCalibration.calibrate(inputs(weeklyKm: 30), runs: history(km: 10.5))
        guard case .confirmed(let observed) = result.volume else { Issue.record("\(result.volume)"); return }
        #expect(abs(observed - 31_500) < 1)
        #expect(result.inputs.currentWeeklyMeters == 30_000)
    }

    @Test func lowerRealVolumeIsTrusted() {
        let result = HistoryCalibration.calibrate(inputs(weeklyKm: 40), runs: history(km: 6))
        #expect(result.volume == .lowered(statedMeters: 40_000, observedMeters: 18_000))
        #expect(result.inputs.currentWeeklyMeters == 18_000)
    }

    @Test func higherRealVolumeIsUsedOnlyHalfway() {
        let result = HistoryCalibration.calibrate(inputs(weeklyKm: 20), runs: history(km: 10))
        #expect(result.volume == .raised(statedMeters: 20_000, observedMeters: 30_000, usedMeters: 25_000))
        #expect(result.inputs.currentWeeklyMeters == 25_000)
    }

    @Test func runsOnOrAfterTheStartAreIgnored() {
        let today = CompletedRun(id: "today", date: start, distanceMeters: 50_000, durationSeconds: 15_000)
        let result = HistoryCalibration.calibrate(inputs(weeklyKm: 30), runs: history(km: 10) + [today])
        #expect(result.runsConsidered == 18)
    }

    @Test func aRaceResultIsNeverReplaced() {
        let race = FitnessSource.recentRace(RacePerformance(.tenK, timeSeconds: 55 * 60))
        // 5 km at 4:00/km is far faster than that 10K, but a race result is the better guide.
        let result = HistoryCalibration.calibrate(inputs(weeklyKm: 30, fitness: race),
                                                  runs: history(km: 5, pacePerKm: 240))
        #expect(result.fitness == .raceGiven)
        #expect(result.inputs.fitness == race)
    }

    @Test func aStrongRunRaisesAnEstimate() throws {
        let given = inputs(weeklyKm: 30, experience: .beginner)
        let runs = history(km: 10, pacePerKm: 280)
        let result = HistoryCalibration.calibrate(given, runs: runs)
        guard case .fromRun(let meters, let seconds, _) = result.fitness else { Issue.record("\(result.fitness)"); return }
        #expect(meters == 10_000 && seconds == 2_800)
        let before = try FitnessEstimator.estimate(given.fitness, experience: .beginner,
                                                   weeklyMeters: given.currentWeeklyMeters, asOf: start)
        let after = try FitnessEstimator.estimate(result.inputs.fitness, experience: .beginner,
                                                  weeklyMeters: result.inputs.currentWeeklyMeters, asOf: start)
        #expect(after.score > before.score)
    }

    @Test func slowRunsKeepTheEstimate() {
        let result = HistoryCalibration.calibrate(inputs(weeklyKm: 30), runs: history(km: 8, pacePerKm: 480))
        #expect(result.fitness == .estimateKept)
        #expect(result.inputs.fitness == .estimated)
    }

    @Test func calibratedPlansStillPassTheValidator() throws {
        for weeklyKm in [10.0, 25, 50] {
            for runKm in [3.0, 8, 15] {
                for pace in [270.0, 360, 450] {
                    let result = HistoryCalibration.calibrate(inputs(weeklyKm: weeklyKm),
                                                              runs: history(km: runKm, pacePerKm: pace))
                    let plan = try PlanBuilder.build(result.inputs)
                    #expect(PlanValidator.validate(plan).isEmpty, "\(weeklyKm) km/wk, \(runKm) km runs at \(pace) s/km")
                }
            }
        }
    }
}
