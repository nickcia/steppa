import Foundation

/// How hard a block is run. Paces come from the athlete's fitness (the same table the plan uses), so "Zone 2" is
/// their own easy pace and follows their fitness as it changes, unless they set a pace of their own.
public enum Effort: String, Codable, Sendable, CaseIterable {
    /// Zone 1: slower than easy. Jogs between intervals, very easy days.
    case recovery
    /// Zone 2: conversational.
    case easy
    /// Zone 3: marathon pace.
    case steady
    /// Zone 4: comfortably hard, about an hour's effort.
    case threshold
    /// Zone 5: hard 2–5 minute efforts.
    case vo2max
    /// Faster than 5K pace: short reps and strides.
    case speed
    /// Predicted pace for the goal race.
    case racePace
    /// No pace target: run by feel, or walk.
    case open

    /// 1–5 for the five training zones; nil for the rest.
    public var zoneNumber: Int? {
        switch self {
        case .recovery: 1
        case .easy: 2
        case .steady: 3
        case .threshold: 4
        case .vo2max: 5
        case .speed, .racePace, .open: nil
        }
    }

    /// The plan's pace zone this effort sits in (for intensity, watch alerts and colours).
    public var paceZone: PaceZone? {
        switch self {
        case .recovery, .easy: .easy
        case .steady: .marathon
        case .threshold: .threshold
        case .vo2max: .interval
        case .speed: .repetition
        case .racePace: .race
        case .open: nil
        }
    }

    /// The pace band for this effort from the athlete's paces.
    public func pace(_ paces: PaceTable) -> PaceRange? {
        switch self {
        // Recovery jogs: from the slow end of easy to about 10% slower.
        case .recovery: PaceRange(fast: paces.easy.slow, slow: paces.easy.slow * 1.10)
        case .open: nil
        default: paceZone.map { paces.range(for: $0) }
        }
    }
}

/// One stretch of running at one effort, for a time or a distance.
public struct BlockPart: Codable, Hashable, Sendable {
    public var effort: Effort
    public var length: StepGoal
    /// The athlete's own pace band. nil uses the effort's pace from their fitness.
    public var customPace: PaceRange?

    public init(effort: Effort, length: StepGoal, customPace: PaceRange? = nil) {
        self.effort = effort
        self.length = length
        self.customPace = customPace
    }

    /// The pace to run: the athlete's own, else the effort's.
    public func pace(_ paces: PaceTable) -> PaceRange? {
        effort == .open ? nil : (customPace ?? effort.pace(paces))
    }

    public func step(_ paces: PaceTable) -> Step {
        let target = pace(paces)
        // Distance and time are estimated at the middle of the band; with no target, at a gentle easy pace.
        let secondsPerKm = target?.mid ?? paces.easy.slow
        let zone = effort.paceZone ?? .easy
        let paceTarget = target.map { PaceTarget(zone: zone, range: $0) }
        switch length {
        case .distance(let meters):
            return Step(goal: length, target: paceTarget, estimatedMeters: meters, estimatedSeconds: meters / 1000 * secondsPerKm)
        case .time(let seconds):
            return Step(goal: length, target: paceTarget, estimatedMeters: seconds / secondsPerKm * 1000, estimatedSeconds: seconds)
        }
    }
}

/// One block of a custom workout: a warm-up, a steady run, a set of repeats or a cool-down.
public struct WorkoutBlock: Codable, Hashable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case warmup, run, repeats, cooldown
    }

    public var id: UUID
    public var role: Role
    /// The block itself, or for repeats, the hard part of each one.
    public var main: BlockPart
    /// How many times a set of repeats runs (1 for other blocks).
    public var repeats: Int
    /// The easy part between repeats; nil for none.
    public var recovery: BlockPart?

    public init(id: UUID = UUID(), role: Role, main: BlockPart, repeats: Int = 1, recovery: BlockPart? = nil) {
        self.id = id
        self.role = role
        self.main = main
        self.repeats = repeats
        self.recovery = recovery
    }

    /// Starting points for the "add a block" buttons, with everyday lengths the athlete can then change.
    public enum Preset: String, CaseIterable, Sendable {
        case warmup, easy, steady, tempo, intervals, strides, cooldown, recovery, racePace, open
    }

    public static func preset(_ preset: Preset) -> WorkoutBlock {
        switch preset {
        case .warmup: WorkoutBlock(role: .warmup, main: BlockPart(effort: .easy, length: .time(seconds: 10 * 60)))
        case .easy: WorkoutBlock(role: .run, main: BlockPart(effort: .easy, length: .time(seconds: 20 * 60)))
        case .steady: WorkoutBlock(role: .run, main: BlockPart(effort: .steady, length: .time(seconds: 15 * 60)))
        case .tempo: WorkoutBlock(role: .run, main: BlockPart(effort: .threshold, length: .time(seconds: 20 * 60)))
        case .intervals:
            WorkoutBlock(role: .repeats, main: BlockPart(effort: .vo2max, length: .time(seconds: 3 * 60)), repeats: 5,
                         recovery: BlockPart(effort: .recovery, length: .time(seconds: 2 * 60)))
        case .strides:
            WorkoutBlock(role: .repeats, main: BlockPart(effort: .speed, length: .time(seconds: 20)), repeats: 4,
                         recovery: BlockPart(effort: .recovery, length: .time(seconds: 60)))
        case .cooldown: WorkoutBlock(role: .cooldown, main: BlockPart(effort: .easy, length: .time(seconds: 10 * 60)))
        case .recovery: WorkoutBlock(role: .run, main: BlockPart(effort: .recovery, length: .time(seconds: 10 * 60)))
        case .racePace: WorkoutBlock(role: .run, main: BlockPart(effort: .racePace, length: .distance(meters: 2_000)))
        case .open: WorkoutBlock(role: .run, main: BlockPart(effort: .open, length: .time(seconds: 10 * 60)))
        }
    }
}

/// A workout the athlete builds from blocks, saved to reuse on any day.
public struct WorkoutTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var blocks: [WorkoutBlock]

    public init(id: UUID = UUID(), name: String, blocks: [WorkoutBlock]) {
        self.id = id
        self.name = name
        self.blocks = blocks
    }

    /// The template as a workout on a date, with targets from the athlete's paces. A warm-up at the start and a
    /// cool-down at the end become the workout's warm-up and cool-down (as on the watch); every other block, in
    /// order, becomes a block of its own.
    public func workout(on date: LocalDate, id: String, paces: PaceTable) -> Workout {
        var blocks = self.blocks
        let warmup = blocks.first?.role == .warmup ? blocks.removeFirst().main.step(paces) : nil
        let cooldown = blocks.last?.role == .cooldown ? blocks.removeLast().main.step(paces) : nil
        let intervals = blocks.map { block -> IntervalBlock in
            var steps = [IntervalStep(purpose: block.role == .run || block.role == .repeats ? .work : .recovery,
                                      step: block.main.step(paces))]
            if block.role == .repeats, let recovery = block.recovery {
                steps.append(IntervalStep(purpose: .recovery, step: recovery.step(paces)))
            }
            return IntervalBlock(iterations: block.role == .repeats ? max(1, block.repeats) : 1, steps: steps)
        }
        var workout = Workout(date: date, kind: .custom, warmup: warmup, blocks: intervals, cooldown: cooldown)
        workout.id = id
        workout.title = name
        return workout
    }
}

/// A custom workout put on a day.
public struct ScheduledWorkout: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: LocalDate
    public var template: WorkoutTemplate

    public init(id: UUID = UUID(), date: LocalDate, template: WorkoutTemplate) {
        self.id = id
        self.date = date
        self.template = template
    }

    /// Prefix of the workout IDs of custom workouts, so they never clash with planned ones.
    public static let idPrefix = "custom-"
    public var workoutID: String { Self.idPrefix + id.uuidString }
}

extension Workout {
    /// Built by the athlete rather than the plan.
    public var isCustom: Bool { id.hasPrefix(ScheduledWorkout.idPrefix) }
}

extension TrainingPlan {
    /// The plan with the athlete's own workouts in it. A custom workout takes the place of whatever the plan had on
    /// that day (race day excepted); days outside the plan are left out. The plan itself is unchanged, so removing
    /// a custom workout brings the planned one back.
    public func withCustomWorkouts(_ scheduled: [ScheduledWorkout]) -> TrainingPlan {
        guard !scheduled.isEmpty else { return self }
        var merged = self
        for (index, week) in weeks.enumerated() {
            let end = week.startDate.adding(days: 7)
            let here = scheduled.filter { $0.date >= week.startDate && $0.date < end && $0.date != inputs.raceDate }
            guard !here.isEmpty else { continue }
            let days = Set(here.map(\.date))
            var workouts = week.workouts.filter { !days.contains($0.date) }
            // At most one custom workout a day: the newest wins.
            var seen = Set<LocalDate>()
            for item in here.reversed() where seen.insert(item.date).inserted {
                workouts.append(item.template.workout(on: item.date, id: item.workoutID, paces: paces))
            }
            merged.weeks[index].workouts = workouts.sorted { $0.date < $1.date }
        }
        return merged
    }
}
