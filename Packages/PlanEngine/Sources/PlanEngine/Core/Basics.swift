/// Units used throughout the engine: distances in **metres**, durations in **seconds**,
/// paces in **seconds per kilometre**. Conversion to miles is a display concern for the app.

public enum RaceDistance: String, Codable, Sendable, CaseIterable {
    case fiveK, tenK, halfMarathon, marathon

    public var meters: Double {
        switch self {
        case .fiveK: 5_000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        }
    }
}

public enum Experience: String, Codable, Sendable, CaseIterable {
    /// New to running or to structured training.
    case beginner
    /// Runs regularly and has done some races.
    case intermediate
    /// Trains consistently with structured sessions.
    case advanced
}

/// Rounds a distance to the nearest 500 m.
func roundTo500(_ meters: Double) -> Double { (meters / 500).rounded() * 500 }

/// Rounds a distance down to a multiple of 500 m.
func floorTo500(_ meters: Double) -> Double { (meters / 500).rounded(.down) * 500 }
