import Foundation

/// Converts race performances into a single aerobic **fitness score** and back.
///
/// The score is an "effective VO₂max" built from two equations published in the
/// exercise-science literature (Daniels & Gilbert, *Oxygen Power*, 1979):
///
/// 1. Oxygen cost of running at velocity v (m/min):
///    `VO₂ = -4.60 + 0.182258·v + 0.000104·v²`
/// 2. Fraction of VO₂max sustainable for t minutes:
///    `f(t) = 0.8 + 0.1894393·e^(-0.012778·t) + 0.2989558·e^(-0.1932605·t)`
///
/// `score = VO₂(v) / f(t)`. Everything here is computed from those equations; no lookup
/// tables are used. (The app calls this a "fitness score", not "VDOT", which is a trademark.)
public enum FitnessModel {
    /// The scores the model works with: from a walk-jog (a half marathon in about six and a half hours) to the
    /// best in the world. Results outside it are capped to it, never refused: a race time far outside is more
    /// likely a typo, so the plan says so (see `PlanWarning.unusualRaceTime`) rather than stopping the athlete.
    public static let supportedScores: ClosedRange<Double> = 8...85

    /// `score` kept within `supportedScores`.
    public static func supported(_ score: Double) -> Double {
        min(max(score, supportedScores.lowerBound), supportedScores.upperBound)
    }

    static func oxygenCost(metersPerMinute v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// Fitness score for running `distanceMeters` in `timeSeconds`.
    public static func score(distanceMeters: Double, timeSeconds: Double) -> Double {
        let minutes = timeSeconds / 60
        let velocity = distanceMeters / minutes
        return oxygenCost(metersPerMinute: velocity) / sustainableFraction(minutes: minutes)
    }

    /// Predicted race time (seconds) for a distance at a given fitness score.
    /// Solved by bisection; the score falls monotonically as time increases.
    public static func raceTimeSeconds(distanceMeters: Double, score target: Double) -> Double {
        var fast = distanceMeters / 1000 * 60      // 1:00 per km
        var slow = distanceMeters / 1000 * 60 * 20 // 20:00 per km
        for _ in 0..<80 {
            let mid = (fast + slow) / 2
            if score(distanceMeters: distanceMeters, timeSeconds: mid) > target {
                fast = mid
            } else {
                slow = mid
            }
        }
        return (fast + slow) / 2
    }

    /// Pace (s/km) at which oxygen cost equals `fraction` × score.
    public static func pace(atFraction fraction: Double, score: Double) -> Double {
        let a = 0.000104, b = 0.182258, c = -(4.60 + fraction * score)
        let velocity = (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
        return 60_000 / velocity
    }
}

/// A race result (or hard time-trial) the athlete entered.
public struct RacePerformance: Codable, Hashable, Sendable {
    public var distanceMeters: Double
    public var timeSeconds: Double
    /// When it was run, if known. Older results are trusted less.
    public var date: LocalDate?

    public init(distanceMeters: Double, timeSeconds: Double, date: LocalDate? = nil) {
        self.distanceMeters = distanceMeters
        self.timeSeconds = timeSeconds
        self.date = date
    }

    public init(_ distance: RaceDistance, timeSeconds: Double, date: LocalDate? = nil) {
        self.init(distanceMeters: distance.meters, timeSeconds: timeSeconds, date: date)
    }
}

/// Where the starting fitness comes from.
public enum FitnessSource: Codable, Hashable, Sendable {
    case recentRace(RacePerformance)
    /// No recent race: estimate conservatively from experience and current volume.
    case estimated
}

public struct FitnessEstimate: Codable, Hashable, Sendable {
    public enum Confidence: String, Codable, Sendable { case high, medium, low }

    public var score: Double
    public var confidence: Confidence

    public init(score: Double, confidence: Confidence) {
        self.score = score
        self.confidence = confidence
    }
}

public enum FitnessEstimator {
    /// Results older than this are discounted and marked medium confidence.
    static let staleAfterDays = 180
    static let staleDiscount = 0.97

    public static func estimate(
        _ source: FitnessSource,
        experience: Experience,
        weeklyMeters: Double,
        asOf today: LocalDate
    ) throws(PlanError) -> FitnessEstimate {
        switch source {
        case .recentRace(let race):
            guard (1_500...43_000).contains(race.distanceMeters), race.timeSeconds > 0 else {
                throw .invalidPerformance
            }
            // Slow results are as real as fast ones; extreme ones (likely typos) are capped, and the plan notes them.
            let score = FitnessModel.supported(FitnessModel.score(distanceMeters: race.distanceMeters,
                                                                  timeSeconds: race.timeSeconds))
            if let date = race.date, date.days(until: today) > staleAfterDays {
                return FitnessEstimate(score: score * staleDiscount, confidence: .medium)
            }
            return FitnessEstimate(score: score, confidence: .high)

        case .estimated:
            // Deliberately conservative: an underestimate means slightly easy sessions,
            // an overestimate means sessions that are too hard. The adaptive engine
            // recalibrates from real runs.
            let km = max(0, weeklyMeters / 1000)
            let score: Double = switch experience {
            case .beginner: 30 + min(km, 30) * 0.15
            case .intermediate: 36 + min(km, 60) * 0.10
            case .advanced: 42 + min(km, 100) * 0.08
            }
            return FitnessEstimate(score: score, confidence: .low)
        }
    }
}
