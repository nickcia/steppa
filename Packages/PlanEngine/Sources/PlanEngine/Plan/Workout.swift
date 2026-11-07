public enum WorkoutKind: String, Codable, Sendable, CaseIterable {
    case easy
    case long
    /// Threshold work: cruise intervals or a continuous tempo run.
    case tempo
    /// VO₂max intervals.
    case intervals
    /// Long run finishing at marathon pace.
    case marathonPaceLong
    case race
    /// Uphill repeats run by effort: strength and power with less pounding than flat speedwork.
    case hills

    /// Hard days must never fall on consecutive dates.
    public var isHard: Bool { self != .easy }
}

public enum StepGoal: Codable, Hashable, Sendable {
    case distance(meters: Double)
    case time(seconds: Double)
}

public struct PaceTarget: Codable, Hashable, Sendable {
    public var zone: PaceZone
    public var range: PaceRange
}

/// One step of a structured workout. Mirrors WorkoutKit's `WorkoutStep`
/// so the app can map it one-to-one onto the watch.
public struct Step: Codable, Hashable, Sendable {
    public var goal: StepGoal
    /// nil = no pace alert (e.g. a recovery jog).
    public var target: PaceTarget?
    /// Planned distance, estimated from the target pace for time-based steps.
    public var estimatedMeters: Double
    /// Planned duration, estimated from the target pace for distance-based steps.
    public var estimatedSeconds: Double
}

public enum IntervalPurpose: String, Codable, Sendable { case work, recovery }

public struct IntervalStep: Codable, Hashable, Sendable {
    public var purpose: IntervalPurpose
    public var step: Step
}

/// A group of steps repeated `iterations` times (WorkoutKit's `IntervalBlock`).
public struct IntervalBlock: Codable, Hashable, Sendable {
    public var iterations: Int
    public var steps: [IntervalStep]
}

/// A planned session. The shape (optional warm-up, blocks, optional cool-down) matches
/// WorkoutKit's `CustomWorkout`. Rest days are simply days with no workout.
public struct Workout: Codable, Hashable, Sendable, Identifiable {
    /// Unique within a plan. The date it was planned for, plus a revision suffix if an adaptation made it.
    public var id: String
    public var date: LocalDate
    /// Set when the athlete moved this workout; the date it was originally planned for.
    public var movedFrom: LocalDate?
    public var kind: WorkoutKind
    public var warmup: Step?
    public var blocks: [IntervalBlock]
    public var cooldown: Step?

    public init(date: LocalDate, kind: WorkoutKind, warmup: Step? = nil, blocks: [IntervalBlock], cooldown: Step? = nil) {
        self.id = date.description
        self.date = date
        self.movedFrom = nil
        self.kind = kind
        self.warmup = warmup
        self.blocks = blocks
        self.cooldown = cooldown
    }

    /// Every step in order, with blocks expanded by their iteration count.
    public var expandedSteps: [Step] {
        var steps: [Step] = []
        if let warmup { steps.append(warmup) }
        for block in blocks {
            for _ in 0..<block.iterations { steps.append(contentsOf: block.steps.map(\.step)) }
        }
        if let cooldown { steps.append(cooldown) }
        return steps
    }

    public var totalMeters: Double { expandedSteps.reduce(0) { $0 + $1.estimatedMeters } }
    public var totalSeconds: Double { expandedSteps.reduce(0) { $0 + $1.estimatedSeconds } }

    /// Distance run at threshold pace or faster (the "hard" part of the 80/20 split).
    public var highIntensityMeters: Double {
        blocks.reduce(0) { sum, block in
            sum + Double(block.iterations) * block.steps.reduce(0) { inner, interval in
                guard interval.purpose == .work, let zone = interval.step.target?.zone, zone.isHighIntensity else {
                    return inner
                }
                return inner + interval.step.estimatedMeters
            }
        }
    }
}
