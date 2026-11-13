/// Checks what the athlete told us during onboarding against the runs their phone already knows about
/// (e.g. from Apple Health), before the first plan is built.
///
/// The rules lean towards safety: a lower real-world volume is trusted straight away (starting too high is
/// how injuries happen), a higher one only halfway, and nothing changes unless the history looks complete
/// enough to rely on. See docs/PLAN-RULES.md, "Checking your answers against your runs".
public enum HistoryCalibration {
    /// Full weeks before the plan starts that are looked at.
    public static let lookbackWeeks = 6
    /// The history must have at least this many runs, spread over at least `minimumWeeksWithRuns` weeks.
    /// Fewer usually means some runs aren't recorded, and the stated volume is the better guide.
    public static let minimumRuns = 6
    public static let minimumWeeksWithRuns = 4
    /// Differences smaller than this are treated as agreement.
    public static let tolerance = 0.15

    public enum VolumeCheck: Codable, Hashable, Sendable {
        /// Too few runs to judge; the stated volume is used as given.
        case notEnoughHistory(runs: Int)
        /// The runs agree with what the athlete said.
        case confirmed(observedMeters: Double)
        /// The runs show less than stated, so the plan starts from what was actually run.
        case lowered(statedMeters: Double, observedMeters: Double)
        /// The runs show more than stated; the plan starts halfway between, to stay cautious.
        case raised(statedMeters: Double, observedMeters: Double, usedMeters: Double)
    }

    public enum FitnessCheck: Codable, Hashable, Sendable {
        /// A race result was given; it's a better guide than training runs.
        case raceGiven
        /// No run in the history beats the conservative estimate.
        case estimateKept
        /// A recent run shows more fitness than the estimate. Any run is at most an all-out effort, so its
        /// score is a lower bound: using it can't make sessions harder than the athlete has already run.
        case fromRun(distanceMeters: Double, timeSeconds: Double, date: LocalDate)
    }

    public struct Result: Codable, Hashable, Sendable {
        public var inputs: PlanInputs
        public var volume: VolumeCheck
        public var fitness: FitnessCheck
        public var runsConsidered: Int
    }

    public static func calibrate(_ inputs: PlanInputs, runs: [CompletedRun]) -> Result {
        let start = inputs.startDate
        let window = runs.filter {
            let age = $0.date.days(until: start)
            return age >= 1 && age <= lookbackWeeks * 7 && $0.distanceMeters > 0
        }
        var calibrated = inputs

        // Volume.
        let weeksWithRuns = Set(window.map { ($0.date.days(until: start) - 1) / 7 }).count
        let volume: VolumeCheck
        if window.count < minimumRuns || weeksWithRuns < minimumWeeksWithRuns {
            volume = .notEnoughHistory(runs: window.count)
        } else {
            let stated = inputs.currentWeeklyMeters
            let observed = window.reduce(0) { $0 + $1.distanceMeters } / Double(lookbackWeeks)
            if observed < stated * (1 - tolerance) {
                calibrated.currentWeeklyMeters = rounded(observed)
                volume = .lowered(statedMeters: stated, observedMeters: observed)
            } else if observed > stated * (1 + tolerance) {
                let used = rounded((stated + observed) / 2)
                calibrated.currentWeeklyMeters = used
                volume = .raised(statedMeters: stated, observedMeters: observed, usedMeters: used)
            } else {
                volume = .confirmed(observedMeters: observed)
            }
        }

        // Fitness, only when there's no race result to go on.
        let fitness: FitnessCheck
        switch inputs.fitness {
        case .recentRace:
            fitness = .raceGiven
        case .estimated:
            let estimate = try? FitnessEstimator.estimate(.estimated, experience: calibrated.experience,
                                                          weeklyMeters: calibrated.currentWeeklyMeters, asOf: start)
            let best = window
                .filter { (3_000...43_000).contains($0.distanceMeters) && $0.durationSeconds > 0 }
                .map { (run: $0, score: FitnessModel.score(distanceMeters: $0.distanceMeters, timeSeconds: $0.durationSeconds)) }
                .filter { FitnessModel.supportedScores.contains($0.score) }
                .max { $0.score < $1.score }
            if let best, let estimate, best.score > estimate.score {
                calibrated.fitness = .recentRace(RacePerformance(distanceMeters: best.run.distanceMeters,
                                                                 timeSeconds: best.run.durationSeconds,
                                                                 date: best.run.date))
                fitness = .fromRun(distanceMeters: best.run.distanceMeters, timeSeconds: best.run.durationSeconds,
                                   date: best.run.date)
            } else {
                fitness = .estimateKept
            }
        }

        return Result(inputs: calibrated, volume: volume, fitness: fitness, runsConsidered: window.count)
    }

    /// To the nearest 500 m, so the plan doesn't start from a falsely precise number.
    private static func rounded(_ meters: Double) -> Double {
        (meters / 500).rounded() * 500
    }
}
