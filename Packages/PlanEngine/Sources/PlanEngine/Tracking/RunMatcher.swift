import Foundation

/// A finished run, summarised from Apple Health (or any other source).
public struct CompletedRun: Codable, Hashable, Sendable, Identifiable {
    /// Stable source identifier, e.g. the HealthKit workout UUID.
    public var id: String
    public var date: LocalDate
    public var distanceMeters: Double
    public var durationSeconds: Double

    public init(id: String, date: LocalDate, distanceMeters: Double, durationSeconds: Double) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }

    public var paceSecondsPerKm: Double { durationSeconds / distanceMeters * 1000 }
}

public struct RunMatch: Codable, Hashable, Sendable {
    public var workoutID: String
    public var runID: String

    public init(workoutID: String, runID: String) {
        self.workoutID = workoutID
        self.runID = runID
    }
}

/// What the athlete actually did: every run, plus which planned workout each one fulfilled.
public struct TrainingLog: Codable, Hashable, Sendable {
    public var runs: [CompletedRun]
    public var matches: [RunMatch]

    public init(runs: [CompletedRun] = [], matches: [RunMatch] = []) {
        self.runs = runs
        self.matches = matches
    }

    func run(forWorkout id: String) -> CompletedRun? {
        guard let match = matches.first(where: { $0.workoutID == id }) else { return nil }
        return runs.first { $0.id == match.runID }
    }
}

/// Pairs completed runs with planned workouts by date and distance.
public enum RunMatcher {
    /// Shorter runs (a jog to the shop, a GPS glitch) are never matched.
    public static let minimumRunMeters = 1_000.0
    /// A run may be logged up to this many days either side of the planned date.
    public static let dayTolerance = 1
    public static let distanceRatio: ClosedRange<Double> = 0.5...1.6
    public static let raceDistanceRatio: ClosedRange<Double> = 0.9...1.15

    /// Returns new matches only. Workouts and runs in `existing` are left alone, so a manual
    /// match or unmatch in the app is never overridden.
    public static func match(workouts: [Workout], runs: [CompletedRun], existing: [RunMatch] = []) -> [RunMatch] {
        let usedWorkouts = Set(existing.map(\.workoutID))
        let usedRuns = Set(existing.map(\.runID))

        struct Candidate { let workout: Workout; let run: CompletedRun; let score: Double }
        var candidates: [Candidate] = []
        for workout in workouts where !usedWorkouts.contains(workout.id) {
            let planned = workout.totalMeters
            guard planned > 0 else { continue }
            for run in runs where !usedRuns.contains(run.id) && run.distanceMeters >= minimumRunMeters {
                let dayGap = abs(workout.date.days(until: run.date))
                let ratio = run.distanceMeters / planned
                let isRace = workout.kind == .race
                guard dayGap <= (isRace ? 0 : dayTolerance),
                      (isRace ? raceDistanceRatio : distanceRatio).contains(ratio) else { continue }
                // Same day beats a close distance; then closer distance wins.
                candidates.append(Candidate(workout: workout, run: run, score: Double(dayGap) + abs(log(ratio))))
            }
        }

        candidates.sort {
            $0.score != $1.score ? $0.score < $1.score
                : ($0.workout.date != $1.workout.date ? $0.workout.date < $1.workout.date : $0.run.id < $1.run.id)
        }
        var takenWorkouts = Set<String>(), takenRuns = Set<String>()
        var result: [RunMatch] = []
        for c in candidates where !takenWorkouts.contains(c.workout.id) && !takenRuns.contains(c.run.id) {
            takenWorkouts.insert(c.workout.id)
            takenRuns.insert(c.run.id)
            result.append(RunMatch(workoutID: c.workout.id, runID: c.run.id))
        }
        return result.sorted { $0.workoutID < $1.workoutID }
    }
}
