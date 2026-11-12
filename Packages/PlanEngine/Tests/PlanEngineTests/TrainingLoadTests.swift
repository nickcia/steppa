import Testing
@testable import PlanEngine

struct TrainingLoadTests {
    let start = LocalDate(year: 2026, month: 9, day: 1)

    func run(_ day: Int, km: Double, pace: Double) -> CompletedRun {
        CompletedRun(id: "\(day)", date: start.adding(days: day), distanceMeters: km * 1000, durationSeconds: km * pace)
    }

    @Test func anHourAtThresholdScoresAHundred() {
        let hour = CompletedRun(id: "t", date: start, distanceMeters: 12_000, durationSeconds: 3600)  // 5:00 /km
        #expect(abs(TrainingLoad.stress(hour, thresholdSecondsPerKm: 300) - 100) < 0.001)
        let easy = CompletedRun(id: "e", date: start, distanceMeters: 10_000, durationSeconds: 3600)  // 6:00 /km
        #expect(TrainingLoad.stress(easy, thresholdSecondsPerKm: 300) < 75)
    }

    @Test func steadyTrainingBuildsFitnessAndRestBringsForm() {
        // Six weeks of an hour at threshold every day, then a week off.
        let runs = (0..<42).map { run($0, km: 12, pace: 300) }
        let training = TrainingLoad.days(runs, thresholdSecondsPerKm: 300, through: start.adding(days: 41))
        let peak = training.last!
        #expect(peak.fitness > 60 && peak.fitness < 100)
        #expect(peak.fatigue > peak.fitness)
        #expect(TrainingLoad.State(form: peak.form) == .building || TrainingLoad.State(form: peak.form) == .overreaching)

        let rested = TrainingLoad.days(runs, thresholdSecondsPerKm: 300, through: start.adding(days: 48)).last!
        #expect(rested.fatigue < rested.fitness)
        #expect(rested.form > 0)
        #expect(rested.fitness < peak.fitness)
    }

    @Test func formIsYesterdaysBalance() {
        let days = TrainingLoad.days([run(0, km: 12, pace: 300)], thresholdSecondsPerKm: 300, through: start.adding(days: 1))
        #expect(days[0].form == 0)
        #expect(abs(days[1].form - (days[0].fitness - days[0].fatigue)) < 0.0001)
    }

    @Test func noRunsMeansNoDays() {
        #expect(TrainingLoad.days([], thresholdSecondsPerKm: 300, through: start).isEmpty)
    }
}
