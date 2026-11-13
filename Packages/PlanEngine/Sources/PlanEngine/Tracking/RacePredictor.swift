public struct RacePrediction: Codable, Hashable, Sendable {
    public var seconds: Double
    /// Plausible range given how confident we are in the fitness score.
    public var fastestSeconds: Double
    public var slowestSeconds: Double
    /// The fitness score the prediction is based on.
    public var score: Double
}

/// Predicts race times from current fitness and recent training.
public enum RacePredictor {
    /// How far back to look for strong efforts and training volume.
    public static let lookbackDays = 42

    /// The best effort in recent runs, as a fitness score.
    ///
    /// Any run is at most an all-out effort, so its score is a *lower bound* on fitness.
    /// Runs under 3 km are ignored: GPS error makes their pace unreliable.
    public static func bestRecentScore(_ runs: [CompletedRun], asOf today: LocalDate) -> Double? {
        runs
            .filter {
                let age = $0.date.days(until: today)
                return age >= 0 && age <= lookbackDays && (3_000...43_000).contains($0.distanceMeters)
                    && $0.durationSeconds > 0
            }
            .map { FitnessModel.score(distanceMeters: $0.distanceMeters, timeSeconds: $0.durationSeconds) }
            .filter { FitnessModel.supportedScores.contains($0) }
            .max()
    }

    /// Average weekly distance over the lookback window.
    public static func recentWeeklyMeters(_ runs: [CompletedRun], asOf today: LocalDate) -> Double {
        let total = runs.filter {
            let age = $0.date.days(until: today)
            return age >= 1 && age <= lookbackDays
        }.reduce(0) { $0 + $1.distanceMeters }
        return total / (Double(lookbackDays) / 7)
    }

    /// Long races need endurance as well as speed: equivalent-performance formulas are optimistic
    /// for low-mileage runners, so add a modest penalty below these weekly volumes.
    static func endurancePenalty(_ distance: RaceDistance, weeklyMeters: Double) -> Double {
        let km = weeklyMeters / 1000
        switch distance {
        case .marathon: return min(max((60 - km) / 60, 0), 1) * 0.08
        case .halfMarathon: return min(max((40 - km) / 40, 0), 1) * 0.04
        case .fiveK, .tenK: return 0
        }
    }

    public static func predict(
        _ distance: RaceDistance,
        fitness: FitnessEstimate,
        recentRuns: [CompletedRun],
        asOf today: LocalDate
    ) -> RacePrediction {
        let score = max(fitness.score, bestRecentScore(recentRuns, asOf: today) ?? 0)
        let base = FitnessModel.raceTimeSeconds(distanceMeters: distance.meters, score: score)
        let seconds = base * (1 + endurancePenalty(distance, weeklyMeters: recentWeeklyMeters(recentRuns, asOf: today)))
        let spread: Double = switch fitness.confidence {
        case .high: 0.02
        case .medium: 0.035
        case .low: 0.06
        }
        return RacePrediction(seconds: seconds, fastestSeconds: seconds * (1 - spread),
                              slowestSeconds: seconds * (1 + spread), score: score)
    }
}
