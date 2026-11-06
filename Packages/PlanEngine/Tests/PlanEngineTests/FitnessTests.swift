import Testing
@testable import PlanEngine

/// Formats s/km as m:ss for readable failure messages.
func paceString(_ secondsPerKm: Double) -> String {
    let s = Int(secondsPerKm.rounded())
    return "\(s / 60):\(s % 60 < 10 ? "0" : "")\(s % 60)"
}

@Suite struct FitnessTests {
    @Test func scoreForA20Minute5K() {
        let score = FitnessModel.score(distanceMeters: 5_000, timeSeconds: 20 * 60)
        #expect(abs(score - 49.8) < 0.2)
    }

    @Test func raceTimeInvertsScore() {
        for distance in RaceDistance.allCases {
            for score in stride(from: 25.0, through: 80.0, by: 5.0) {
                let time = FitnessModel.raceTimeSeconds(distanceMeters: distance.meters, score: score)
                let back = FitnessModel.score(distanceMeters: distance.meters, timeSeconds: time)
                #expect(abs(back - score) < 0.001, "\(distance) score \(score)")
            }
        }
    }

    /// Equivalent performances should match well-known coaching rules of thumb
    /// (a ~20:00 5K runner is roughly a 1:32 half and a 3:10 marathon runner).
    @Test func equivalentRaceTimesAreRealistic() {
        let score = FitnessModel.score(distanceMeters: 5_000, timeSeconds: 20 * 60)
        let tenK = FitnessModel.raceTimeSeconds(distanceMeters: 10_000, score: score)
        let half = FitnessModel.raceTimeSeconds(distanceMeters: RaceDistance.halfMarathon.meters, score: score)
        let marathon = FitnessModel.raceTimeSeconds(distanceMeters: RaceDistance.marathon.meters, score: score)
        #expect((41 * 60...42 * 60 + 30).contains(Int(tenK)))
        #expect((91 * 60...93 * 60).contains(Int(half)))
        #expect((189 * 60...193 * 60).contains(Int(marathon)))
    }

    @Test func trainingPacesFor20Minute5K() {
        let score = FitnessModel.score(distanceMeters: 5_000, timeSeconds: 20 * 60)
        let paces = PaceTable(score: score, goal: .fiveK)
        // Easy: roughly 5:05–5:40 /km.
        #expect((295...315).contains(paces.easy.fast), "\(paceString(paces.easy.fast))")
        #expect((325...345).contains(paces.easy.slow), "\(paceString(paces.easy.slow))")
        // Threshold ~4:15, interval ~3:55, repetition ~3:42, marathon ~4:31, race = 4:00.
        #expect(abs(paces.threshold.mid - 256) < 6, "\(paceString(paces.threshold.mid))")
        #expect(abs(paces.interval.mid - 235) < 6, "\(paceString(paces.interval.mid))")
        #expect(abs(paces.repetition.mid - 222) < 6, "\(paceString(paces.repetition.mid))")
        #expect(abs(paces.marathon.mid - 271) < 6, "\(paceString(paces.marathon.mid))")
        #expect(abs(paces.race.mid - 240) < 1, "\(paceString(paces.race.mid))")
    }

    @Test func pacesAreOrderedForEveryScore() {
        for score in stride(from: 25.0, through: 80.0, by: 2.5) {
            let p = PaceTable(score: score, goal: .halfMarathon)
            #expect(p.repetition.mid < p.interval.mid)
            #expect(p.interval.mid < p.threshold.mid)
            #expect(p.threshold.mid < p.marathon.mid)
            #expect(p.marathon.mid < p.easy.fast)
            for zone in PaceZone.allCases {
                #expect(p.range(for: zone).fast < p.range(for: zone).slow)
            }
        }
    }

    @Test func estimatorRejectsImplausibleRaces() {
        let today = LocalDate(year: 2026, month: 11, day: 6)
        #expect(throws: PlanError.invalidPerformance) {
            try FitnessEstimator.estimate(.recentRace(.init(.fiveK, timeSeconds: 8 * 60)),
                                          experience: .advanced, weeklyMeters: 50_000, asOf: today)
        }
        #expect(throws: PlanError.invalidPerformance) {
            try FitnessEstimator.estimate(.recentRace(.init(distanceMeters: 400, timeSeconds: 90)),
                                          experience: .advanced, weeklyMeters: 50_000, asOf: today)
        }
    }

    @Test func staleRacesAreDiscounted() throws {
        let today = LocalDate(year: 2026, month: 11, day: 6)
        let fresh = try FitnessEstimator.estimate(
            .recentRace(.init(.tenK, timeSeconds: 45 * 60, date: today.adding(days: -30))),
            experience: .intermediate, weeklyMeters: 30_000, asOf: today)
        let stale = try FitnessEstimator.estimate(
            .recentRace(.init(.tenK, timeSeconds: 45 * 60, date: today.adding(days: -400))),
            experience: .intermediate, weeklyMeters: 30_000, asOf: today)
        #expect(fresh.confidence == .high)
        #expect(stale.confidence == .medium)
        #expect(stale.score < fresh.score)
    }

    @Test func estimatedFitnessIsConservative() throws {
        let today = LocalDate(year: 2026, month: 11, day: 6)
        for experience in Experience.allCases {
            let e = try FitnessEstimator.estimate(.estimated, experience: experience, weeklyMeters: 200_000, asOf: today)
            #expect(e.confidence == .low)
            #expect(e.score <= 50)
        }
    }
}
