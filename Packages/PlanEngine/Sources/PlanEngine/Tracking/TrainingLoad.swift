import Foundation

/// Fitness, fatigue and form from the runs themselves (the impulse–response model of Banister, 1975, in the
/// widely used form: fitness is a 42-day exponentially weighted average of daily training load, fatigue a 7-day
/// one, and form is yesterday's fitness minus yesterday's fatigue).
///
/// A run's load is a running stress score: hours × intensity² × 100, where intensity is the run's speed as a share
/// of threshold speed. An hour at threshold pace scores 100; an hour easy, about 55–65. Pace alone can't see hills,
/// heat or how the athlete felt, so these are a guide to the trend, not a measurement.
public enum TrainingLoad {
    public static let fitnessDays = 42.0
    public static let fatigueDays = 7.0

    public struct Day: Hashable, Sendable {
        public var date: LocalDate
        /// That day's total stress score.
        public var load: Double
        public var fitness: Double
        public var fatigue: Double
        /// Fitness minus fatigue, as of the start of the day: positive is fresh, negative is carrying fatigue.
        public var form: Double
    }

    /// How fresh or tired the athlete is, from form.
    public enum State: String, Sendable {
        /// Very negative form: more load than the body is absorbing.
        case overreaching
        /// Moderately negative: the normal state in a training block.
        case building
        case balanced
        /// Positive: tapered or rested, ready to race.
        case fresh
        /// Well rested for a while: fitness is starting to drop.
        case detraining

        public init(form: Double) {
            self = switch form {
            case ..<(-30): .overreaching
            case ..<(-10): .building
            case ..<5: .balanced
            case ..<25: .fresh
            default: .detraining
            }
        }
    }

    /// Stress score for one run. Intensity is capped so a GPS glitch or a mismeasured short run can't dominate.
    public static func stress(_ run: CompletedRun, thresholdSecondsPerKm: Double) -> Double {
        guard run.durationSeconds > 0, run.distanceMeters > 0, thresholdSecondsPerKm > 0 else { return 0 }
        let intensity = min(thresholdSecondsPerKm / run.paceSecondsPerKm, 1.15)
        return run.durationSeconds / 3600 * intensity * intensity * 100
    }

    /// Every day from the first run to `today`, oldest first. Empty without runs.
    public static func days(_ runs: [CompletedRun], thresholdSecondsPerKm: Double, through today: LocalDate) -> [Day] {
        guard let first = runs.map(\.date).min(), first <= today else { return [] }
        var loadByDay: [LocalDate: Double] = [:]
        for run in runs where run.date <= today {
            loadByDay[run.date, default: 0] += stress(run, thresholdSecondsPerKm: thresholdSecondsPerKm)
        }
        var fitness = 0.0, fatigue = 0.0
        var result: [Day] = []
        var date = first
        while date <= today {
            let load = loadByDay[date] ?? 0
            let form = fitness - fatigue
            fitness += (load - fitness) / fitnessDays
            fatigue += (load - fatigue) / fatigueDays
            result.append(Day(date: date, load: load, fitness: fitness, fatigue: fatigue, form: form))
            date = date.adding(days: 1)
        }
        return result
    }
}
