public enum PaceZone: String, Codable, Sendable, CaseIterable {
    /// Conversational running: easy days, long runs, warm-ups, recoveries.
    case easy
    /// Current marathon race pace.
    case marathon
    /// Comfortably hard, sustainable for about an hour ("tempo").
    case threshold
    /// Hard efforts of 2–5 minutes that develop VO₂max.
    case interval
    /// Short, fast repetitions for speed and economy.
    case repetition
    /// Predicted race pace for the goal distance.
    case race
    /// Strides: ~20 s accelerations to a fast but relaxed pace, after an easy run. Too short to tire you, so
    /// they don't count towards the high-intensity limit (Daniels treats them as part of easy running).
    case stride
    /// Hard uphill efforts. Pace means little on a hill, so this is run by effort (about 5K effort); the
    /// range only estimates distance, and watch exports leave the pace target out.
    case hill

    /// Sessions at these paces count towards the weekly high-intensity limit.
    public var isHighIntensity: Bool {
        switch self {
        case .threshold, .interval, .repetition, .hill: true
        case .easy, .marathon, .race, .stride: false
        }
    }

    /// Run by feel rather than to a pace target.
    public var isEffortBased: Bool { self == .hill }
}

/// A pace band in seconds per kilometre. `fast` is the smaller number.
public struct PaceRange: Codable, Hashable, Sendable {
    public var fast: Double
    public var slow: Double

    public init(fast: Double, slow: Double) {
        self.fast = fast
        self.slow = slow
    }

    /// A band of ±`tolerance` (fraction) around `center`.
    init(center: Double, tolerance: Double) {
        self.init(fast: center * (1 - tolerance), slow: center * (1 + tolerance))
    }

    public var mid: Double { (fast + slow) / 2 }
}

/// Training paces derived from a fitness score.
public struct PaceTable: Codable, Hashable, Sendable {
    public let score: Double
    public let goal: RaceDistance
    public let easy: PaceRange
    public let marathon: PaceRange
    public let threshold: PaceRange
    public let interval: PaceRange
    public let repetition: PaceRange
    public let race: PaceRange

    /// Fractions of the fitness score used for each zone. Chosen to match widely used
    /// coaching guidance; they are tuning values, not taken from any proprietary table.
    enum Intensity {
        static let easyFast = 0.70
        static let easySlow = 0.62
        static let threshold = 0.88
        static let interval = 0.975
        static let repetition = 1.05
        static let tolerance = 0.02
        static let raceTolerance = 0.015
    }

    public init(score: Double, goal: RaceDistance) {
        self.score = score
        self.goal = goal
        easy = PaceRange(fast: FitnessModel.pace(atFraction: Intensity.easyFast, score: score),
                         slow: FitnessModel.pace(atFraction: Intensity.easySlow, score: score))
        let marathonPace = FitnessModel.raceTimeSeconds(distanceMeters: RaceDistance.marathon.meters, score: score)
            / (RaceDistance.marathon.meters / 1000)
        marathon = PaceRange(center: marathonPace, tolerance: Intensity.tolerance)
        threshold = PaceRange(center: FitnessModel.pace(atFraction: Intensity.threshold, score: score),
                              tolerance: Intensity.tolerance)
        interval = PaceRange(center: FitnessModel.pace(atFraction: Intensity.interval, score: score),
                             tolerance: Intensity.tolerance)
        repetition = PaceRange(center: FitnessModel.pace(atFraction: Intensity.repetition, score: score),
                               tolerance: Intensity.tolerance)
        let racePace = FitnessModel.raceTimeSeconds(distanceMeters: goal.meters, score: score) / (goal.meters / 1000)
        race = PaceRange(center: racePace, tolerance: Intensity.raceTolerance)
    }

    public func range(for zone: PaceZone) -> PaceRange {
        switch zone {
        case .easy: easy
        case .marathon: marathon
        case .threshold: threshold
        case .interval: interval
        case .repetition, .stride: repetition
        case .race: race
        // Climbing at interval effort covers ground 12–18% slower than on the flat.
        case .hill: PaceRange(fast: interval.fast * 1.12, slow: interval.slow * 1.18)
        }
    }
}
