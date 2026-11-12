import CryptoKit
import Foundation
import PlanEngine

// Garmin Connect, through TrackStar's server. Planned workouts go to the athlete's Garmin Connect calendar (and on to
// their watch) in TrackStar's own simple format; the server turns them into Garmin's. Runs recorded on a Garmin come
// back the other way: Garmin sends them to the server, which keeps them until this iPhone collects them. On the
// iPhone they're kept in a file of their own (not in iCloud), tick off workouts and show in run analysis like a run
// from Apple Health, always credited "Garmin [device]". They're never given to the coach.

/// One planned workout in TrackStar's format for the server.
nonisolated struct GarminPlanWorkout: Encodable, Hashable, Sendable {
    /// "trackstar-<workout id>-<content hash>": changes whenever the workout does, so the server replaces it.
    var key: String
    var date: String
    var name: String
    var description: String
    var steps: [GarminPlanStep]
}

nonisolated indirect enum GarminPlanStep: Encodable, Hashable, Sendable {
    enum Intensity: String, Encodable, Sendable { case warmup, active, recovery, cooldown, rest }

    case step(intensity: Intensity, goal: StepGoal, pace: PaceRange?, note: String?)
    case repeated(times: Int, steps: [GarminPlanStep])

    private enum Keys: String, CodingKey { case kind, intensity, duration, pace, note, times, steps }
    private struct Duration: Encodable { var type: String; var value: Double }
    private struct Pace: Encodable { var fast: Double; var slow: Double }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .step(let intensity, let goal, let pace, let note):
            try container.encode("step", forKey: .kind)
            try container.encode(intensity, forKey: .intensity)
            switch goal {
            case .time(let seconds): try container.encode(Duration(type: "time", value: seconds.rounded()), forKey: .duration)
            case .distance(let meters): try container.encode(Duration(type: "distance", value: meters.rounded()), forKey: .duration)
            }
            if let pace { try container.encode(Pace(fast: pace.fast, slow: pace.slow), forKey: .pace) }
            if let note { try container.encode(note, forKey: .note) }
        case .repeated(let times, let steps):
            try container.encode("repeat", forKey: .kind)
            try container.encode(times, forKey: .times)
            try container.encode(steps, forKey: .steps)
        }
    }
}

/// Turns plan workouts into the server's format. Pure, so it's unit-tested.
enum GarminWorkoutBuilder {
    nonisolated static let keyPrefix = "trackstar-"
    /// The server keeps two weeks on the calendar; a day more covers time zones.
    nonisolated static let daysAhead = 15

    static func workouts(_ workouts: [Workout], from today: LocalDate, format: DisplayFormat) -> [GarminPlanWorkout] {
        workouts.filter { $0.date >= today && today.days(until: $0.date) <= daysAhead }.map { workout(for: $0, format: format) }
    }

    static func workout(for workout: Workout, format: DisplayFormat) -> GarminPlanWorkout {
        let describer = WorkoutDescriber(format: format)
        let name = "\(workout.name) · \(describer.summary(workout))"
        let description = String(localized: "Planned with TrackStar")
        let steps = steps(for: workout, format: format)
        let content = (try? JSONEncoder.sortedKeys.encode(steps)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        let digest = SHA256.hash(data: Data("\(workout.date)|\(name)|\(content)".utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return GarminPlanWorkout(key: "\(keyPrefix)\(workout.id)-\(hash)", date: workout.date.description,
                                 name: name, description: description, steps: steps)
    }

    /// `format`: rounds paces to the nearest 5 s in the athlete's units, matching what the app shows.
    static func steps(for workout: Workout, format: DisplayFormat? = nil) -> [GarminPlanStep] {
        let runWalk = workout.isRunWalkSession
        var steps: [GarminPlanStep] = []
        if let warmup = workout.warmup {
            steps.append(step(warmup, intensity: .warmup, note: runWalk ? String(localized: "Walk") : nil, format: format))
        }
        for block in workout.blocks {
            let inner = block.steps.map { interval -> GarminPlanStep in
                if runWalk {
                    return interval.purpose == .work
                        ? step(interval.step, intensity: .active, note: String(localized: "Run"), pace: false)
                        : step(interval.step, intensity: .recovery, note: String(localized: "Walk"), pace: false)
                }
                return step(interval.step, intensity: interval.purpose == .work ? .active : .recovery, format: format)
            }
            if block.iterations > 1 {
                steps.append(.repeated(times: block.iterations, steps: inner))
            } else {
                steps += inner
            }
        }
        if let cooldown = workout.cooldown {
            steps.append(step(cooldown, intensity: .cooldown, note: runWalk ? String(localized: "Walk") : nil, format: format))
        }
        return steps
    }

    /// Hill and stride steps are by effort, so they get a name instead of a pace alert.
    static func step(_ step: Step, intensity: GarminPlanStep.Intensity, note: String? = nil, pace: Bool = true,
                     format: DisplayFormat? = nil) -> GarminPlanStep {
        switch step.target?.zone {
        case .hill?: return .step(intensity: intensity, goal: step.goal, pace: nil, note: String(localized: "Uphill hard"))
        case .stride?: return .step(intensity: intensity, goal: step.goal, pace: nil, note: String(localized: "Stride"))
        default:
            let range = step.target.map { format?.rounded($0.range) ?? $0.range }
            return .step(intensity: intensity, goal: step.goal, pace: pace ? range : nil, note: note)
        }
    }
}

private extension JSONEncoder {
    nonisolated static var sortedKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// A run recorded on a Garmin device, as the server passes it on.
nonisolated struct GarminRun: Codable, Hashable, Sendable, Identifiable {
    /// Garmin's summary ID.
    var id: String
    /// Start, in seconds since 1970 (UTC).
    var start: Double?
    /// Seconds to add to `start` for the local time where the run was.
    var offset: Double?
    var duration: Double?
    var distance: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var averageCadence: Double?
    var elevationGain: Double?
    /// The device model, e.g. "Forerunner 265".
    var device: String?
    var name: String?
    var manual: Bool?
    /// Every ~5 s: time (s since 1970), heart rate, speed m/s, distance m, steps/min, watts, elevation m.
    /// -1 (-9999 for elevation) means not recorded.
    var samples: [[Double]]?

    var runID: String { "garmin-\(id)" }

    var startDate: Date? { start.map { Date(timeIntervalSince1970: $0) } }

    /// The day it was run, where it was run.
    var date: LocalDate? {
        guard let start else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return LocalDate(Date(timeIntervalSince1970: start + (offset ?? 0)), calendar: calendar)
    }

    var interval: DateInterval? {
        guard let startDate else { return nil }
        return DateInterval(start: startDate, duration: max(0, duration ?? 0))
    }

    var completedRun: CompletedRun? {
        guard let date, let distance, distance >= RunMatcher.minimumRunMeters, let duration, duration > 0 else { return nil }
        return CompletedRun(id: runID, date: date, distanceMeters: distance, durationSeconds: duration, start: startDate)
    }

    /// "Garmin Forerunner 265", or just "Garmin" when the model isn't known (Garmin's attribution rule).
    var attribution: String {
        let model = (device ?? "").trimmingCharacters(in: .whitespaces)
        if model.isEmpty || model.lowercased() == "unknown" { return "Garmin" }
        return model.lowercased().hasPrefix("garmin") ? model : "Garmin \(model)"
    }

    /// The samples as a series for run analysis (time from the start).
    var series: RunSeries? {
        guard let start, let samples, !samples.isEmpty else { return nil }
        var series = RunSeries()
        for sample in samples where sample.count >= 7 {
            let t = sample[0] - start
            if sample[1] > 0 { series.heartRate.append(.init(t, sample[1])) }
            if sample[3] >= 0 { series.distance.append(.init(t, sample[3])) }
            if sample[4] > 0 { series.cadence.append(.init(t, sample[4])) }
            if sample[5] >= 0 { series.power.append(.init(t, sample[5])) }
            if sample[6] > -9000 { series.altitude.append(.init(t, sample[6])) }
        }
        // Garmin reports running cadence per foot on some devices; double it when it looks that way.
        let sorted = series.cadence.map(\.v).sorted()
        if !sorted.isEmpty, sorted[sorted.count / 2] < 120 {
            series.cadence = series.cadence.map { .init($0.t, $0.v * 2) }
        }
        if series.power.allSatisfy({ $0.v == 0 }) { series.power = [] }
        return series.isEmpty ? nil : series.downsampled()
    }
}

/// Garmin runs on this iPhone: one file in Application Support, never synced to iCloud. Deleted when Garmin is
/// disconnected.
nonisolated struct GarminRunStore: Sendable {
    var file: URL = URL.applicationSupportDirectory.appending(path: "garmin/runs.json")
    /// Plenty for the plan and its history; the oldest go first.
    static let limit = 500

    func load() -> [GarminRun] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([GarminRun].self, from: data)) ?? []
    }

    /// Adds or replaces runs (Garmin sends an updated copy if the athlete edits a run).
    @discardableResult
    func add(_ runs: [GarminRun]) -> [GarminRun] {
        var byID = Dictionary(load().map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for run in runs { byID[run.id] = run }
        let kept = byID.values.sorted { ($0.start ?? 0) < ($1.start ?? 0) }.suffix(Self.limit)
        save(Array(kept))
        return Array(kept)
    }

    func clear() { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    private func save(_ runs: [GarminRun]) {
        var directory = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        try? JSONEncoder().encode(runs).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

nonisolated enum GarminConnectError: LocalizedError, Equatable {
    /// The athlete chose not to allow TrackStar on Garmin's page.
    case declined
    /// The sign-in took too long, or was started twice.
    case expired
    case failed

    var errorDescription: String? {
        switch self {
        case .declined: String(localized: "Garmin Connect wasn't connected, because access wasn't allowed. You can try again any time.")
        case .expired: String(localized: "Connecting to Garmin Connect took too long. Please try again.")
        case .failed: String(localized: "Connecting to Garmin Connect didn't finish. Please try again.")
        }
    }
}
