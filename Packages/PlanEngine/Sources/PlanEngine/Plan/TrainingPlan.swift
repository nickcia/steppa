public enum Phase: String, Codable, Sendable, CaseIterable {
    /// Aerobic foundation: mostly easy running, gentle volume growth.
    case base
    /// Volume keeps growing; regular quality sessions.
    case build
    /// Race-specific work at the highest volume.
    case peak
    /// Volume drops so the athlete arrives at the race fresh.
    case taper
}

public struct PlanWeek: Codable, Hashable, Sendable {
    public var index: Int
    /// Monday of this week.
    public var startDate: LocalDate
    public var phase: Phase
    public var isStepBack: Bool
    /// Nominal full-week volume. Partial weeks (plan start, race week) schedule
    /// proportionally less; the safety rules are checked against this number.
    public var targetMeters: Double
    public var workouts: [Workout]

    /// Planned training distance, excluding the race itself.
    public var trainingMeters: Double {
        workouts.filter { $0.kind != .race }.reduce(0) { $0 + $1.totalMeters }
    }

    public var plannedMeters: Double { workouts.reduce(0) { $0 + $1.totalMeters } }
}

public enum PlanWarning: Codable, Hashable, Sendable {
    /// Less time than recommended for this distance; the plan is compressed.
    case shortPlan(weeks: Int, recommendedWeeks: Int)
    /// Current volume is below what this race distance usually needs.
    case lowStartingVolume(recommendedMeters: Double)
    /// Available days can't hold the target volume safely, so some weeks are lighter.
    case volumeLimitedByAvailability
    /// The goal time needs noticeably more fitness than the athlete currently shows.
    case ambitiousGoal(predictedSeconds: Double)
    /// Fewer run days than this goal usually needs (e.g. a 3-hour marathon on two days a week).
    case fewRunDays(recommended: Int)
    /// No race result was given, so paces are an estimate until real runs come in.
    case estimatedFitness
}

public struct TrainingPlan: Codable, Hashable, Sendable {
    public var engineVersion: Int
    public var inputs: PlanInputs
    public var fitness: FitnessEstimate
    public var paces: PaceTable
    public var weeks: [PlanWeek]
    public var warnings: [PlanWarning]
    /// 0 for a freshly built plan; incremented on every adaptation.
    public var revision: Int = 0
    /// Last time the fitness score changed. Only runs after this date count as new evidence.
    public var fitnessUpdatedOn: LocalDate?
    /// Date of the last adaptation. Workouts before it are history: they were checked when planned
    /// and are not re-checked against the current inputs (e.g. they may sit on old run days).
    public var revisedOn: LocalDate?

    public var workouts: [Workout] { weeks.flatMap(\.workouts) }

    /// Predicted finish time for the goal race at current fitness.
    public var predictedRaceSeconds: Double {
        FitnessModel.raceTimeSeconds(distanceMeters: inputs.goal.meters, score: fitness.score)
    }
}
