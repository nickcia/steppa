import Foundation
import PlanEngine

/// How a workout's targets are shown: as pace, as heart rate, or as treadmill speed.
enum WorkoutTargetDisplay: String, CaseIterable, Identifiable, Sendable {
    case pace, heartRate, treadmill
    var id: String { rawValue }

    var name: String {
        switch self {
        case .pace: String(localized: "Pace")
        case .heartRate: String(localized: "Heart rate")
        case .treadmill: String(localized: "Treadmill")
        }
    }
}

/// Human-readable descriptions of structured workouts.
struct WorkoutDescriber {
    let format: DisplayFormat
    var display: WorkoutTargetDisplay = .pace
    /// For heart-rate targets; without zones, targets fall back to pace.
    var zones: HeartRateZones?
    var treadmillUnits: UnitSystem = .metric

    struct Line: Identifiable {
        let id = UUID()
        let title: String
        let detail: String?
        let zone: PaceZone?
        let isRecovery: Bool
    }

    enum Section: Identifiable {
        case single(Line)
        case repeated(times: Int, lines: [Line])

        var id: UUID {
            switch self {
            case .single(let line): line.id
            case .repeated(_, let lines): lines.first?.id ?? UUID()
            }
        }
    }

    func goal(_ goal: StepGoal, rep: Bool = false) -> String {
        switch goal {
        case .distance(let meters): rep ? format.repDistance(meters) : format.distance(meters)
        case .time(let seconds): DisplayFormat.shortDuration(seconds)
        }
    }

    private func line(_ step: Step, title: String? = nil, rep: Bool = false, isRecovery: Bool = false) -> Line {
        let amount = goal(step.goal, rep: rep)
        if let target = step.target {
            // A recovery with a target (custom workouts' Zone 1 jogs) reads as recovery, not "easy".
            let zoneName = isRecovery && target.zone == .easy ? String(localized: "recovery") : target.zone.name
            return Line(title: title.map { "\($0) · \(amount)" } ?? "\(amount) \(zoneName)",
                        detail: detail(target), zone: target.zone, isRecovery: isRecovery)
        }
        return Line(title: title.map { "\($0) · \(amount)" } ?? String(localized: "\(amount) jog"),
                    detail: isRecovery ? String(localized: "Easy jog or walk") : nil, zone: nil, isRecovery: isRecovery)
    }

    /// A step's target in the chosen display. Effort-based and very short steps are described by feel.
    func detail(_ target: PaceTarget) -> String {
        switch (display, target.zone) {
        case (.treadmill, .hill): return String(localized: "Set a 6–8% incline and run hard, about 5K effort")
        case (_, .hill):
            if display == .heartRate, let zones, let hr = zones.target(for: .hill) {
                return String(localized: "Hard uphill, reaching \(bpm(hr.bpm)) by the top")
            }
            return String(localized: "Hard uphill, about 5K effort")
        // Strides: a target in every view, with the feel that matters more than the number for 20 seconds.
        case (.pace, .stride): return String(localized: "\(format.paceRange(target.range)) · quick but relaxed, not a sprint")
        case (.treadmill, .stride): return String(localized: "\(speedRange(target.range)) · quick but relaxed, not a sprint")
        case (.heartRate, .stride):
            return String(localized: "Too short for heart rate to catch up: go by feel, quick but relaxed (about \(format.paceRange(target.range)))")
        case (.heartRate, _):
            guard let zones, let hr = zones.target(for: target.zone) else { return format.paceRange(target.range) }
            return "\(zoneName(hr.zones)) · \(bpm(hr.bpm))"
        case (.treadmill, _): return speedRange(target.range)
        case (.pace, _): return format.paceRange(target.range)
        }
    }

    /// A step's target as one headline number and its label, e.g. ("6:33", "easy /km"), ("114–132", "zone 2 bpm")
    /// or ("8.7", "easy km/h").
    func headline(_ target: PaceTarget) -> (value: String, label: String) {
        switch display {
        case .heartRate:
            if let zones, let hr = zones.target(for: target.zone) {
                return ("\(Int(hr.bpm.lowerBound))–\(Int(hr.bpm.upperBound))", "\(zoneName(hr.zones).lowercased()) bpm")
            }
        case .treadmill:
            return (Self.speed(target.range.mid, units: treadmillUnits), "\(target.zone.name) \(treadmillUnits.speedUnit)")
        case .pace: break
        }
        return (DisplayFormat.clock(format.paceSeconds(target.range.mid)), "\(target.zone.name) /\(format.units.distanceUnit)")
    }

    private func zoneName(_ zones: ClosedRange<Int>) -> String {
        zones.lowerBound == zones.upperBound ? String(localized: "Zone \(zones.lowerBound + 1)")
                                             : String(localized: "Zones \(zones.lowerBound + 1)–\(zones.upperBound + 1)")
    }

    private func bpm(_ range: ClosedRange<Double>) -> String {
        "\(Int(range.lowerBound))–\(Int(range.upperBound)) bpm"
    }

    /// Treadmill speed for a pace in seconds per kilometre, to one decimal: km/h or mph.
    static func speed(_ secondsPerKm: Double, units: UnitSystem) -> String {
        guard secondsPerKm > 0 else { return "–" }
        let kmh = 3600 / secondsPerKm
        let value = units == .metric ? kmh : kmh / 1.609344
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    /// Faster pace is the higher speed, so the range reads low to high.
    private func speedRange(_ range: PaceRange) -> String {
        "\(Self.speed(range.slow, units: treadmillUnits))–\(Self.speed(range.fast, units: treadmillUnits)) \(treadmillUnits.speedUnit)"
    }

    func sections(_ workout: Workout) -> [Section] {
        if workout.isRunWalkSession { return runWalkSections(workout) }
        var result: [Section] = []
        if let warmup = workout.warmup {
            result.append(.single(line(warmup, title: String(localized: "Warm up"))))
        }
        for block in workout.blocks {
            let lines = block.steps.map { line($0.step, rep: block.iterations > 1, isRecovery: $0.purpose == .recovery) }
            if block.iterations > 1 {
                result.append(.repeated(times: block.iterations, lines: lines))
            } else {
                result += lines.map { .single($0) }
            }
        }
        if let cooldown = workout.cooldown {
            result.append(.single(line(cooldown, title: String(localized: "Cool down"))))
        }
        return result
    }

    private func minutes(_ goal: StepGoal) -> String {
        if case .time(let seconds) = goal { return DisplayFormat.minutes(seconds) }
        return self.goal(goal)
    }

    /// Run/walk sessions are by feel: walk, run gently, walk.
    private func runWalkSections(_ workout: Workout) -> [Section] {
        func goal(_ goal: StepGoal) -> String { minutes(goal) }
        func walk(_ step: Step, _ detail: String) -> Line {
            Line(title: String(localized: "Walk · \(goal(step.goal))"), detail: detail, zone: nil, isRecovery: true)
        }
        func run(_ step: Step) -> Line {
            Line(title: String(localized: "Run · \(goal(step.goal))"), detail: String(localized: "Gently, slow enough to talk"),
                 zone: .easy, isRecovery: false)
        }
        var result: [Section] = []
        if let warmup = workout.warmup { result.append(.single(walk(warmup, String(localized: "Brisk walk to warm up")))) }
        for block in workout.blocks {
            let lines = block.steps.map { $0.purpose == .work ? run($0.step) : walk($0.step, String(localized: "Brisk walk, get your breath back")) }
            result.append(block.iterations > 1 ? .repeated(times: block.iterations, lines: lines) : .single(lines[0]))
        }
        if let cooldown = workout.cooldown { result.append(.single(walk(cooldown, String(localized: "Easy walk to cool down")))) }
        return result
    }

    /// The whole workout on a line or two, step by step: "Warm up · 2 km · 2 × 1600 m threshold · Cool down · 1.5 km",
    /// "8.4 km easy · 5 × 20 s stride". Targets are left out; the workout's page has them.
    func structureLine(_ workout: Workout) -> String {
        sections(workout).map { section in
            switch section {
            case .single(let line): line.title
            case .repeated(let times, let lines): "\(times) × " + (lines.first { !$0.isRecovery } ?? lines[0]).title
            }
        }.joined(separator: " · ")
    }

    /// One-line summary for lists: "8 km easy", "5 × 800 m intervals", "6 km threshold".
    func summary(_ workout: Workout) -> String {
        if workout.isRunWalkSession, let block = workout.blocks.first, let run = block.steps.first?.step {
            func goal(_ goal: StepGoal) -> String { minutes(goal) }
            // "8 × 1 min run, 1:30 walk", "30 min non-stop"
            if block.steps.count < 2 { return String(localized: "\(goal(run.goal)) non-stop") }
            return String(localized: "\(block.iterations) × \(goal(run.goal)) run, \(goal(block.steps[1].step.goal)) walk")
        }
        switch workout.kind {
        case .easy, .long:
            return format.distance(workout.totalMeters)
        case .runWalk:
            return DisplayFormat.shortDuration(workout.totalSeconds)
        case .race:
            return format.distance(workout.totalMeters)
        case .custom:
            // "~45 min · 7.2 km"
            return "~\(DisplayFormat.shortDuration(workout.totalSeconds)) · \(format.distance(workout.totalMeters))"
        case .tempo, .intervals, .marathonPaceLong, .hills:
            guard let block = workout.blocks.first, let work = block.steps.first(where: { $0.purpose == .work }) else {
                return format.distance(workout.totalMeters)
            }
            let zone = work.step.target?.zone.name ?? ""
            if block.iterations > 1 {
                return "\(block.iterations) × \(goal(work.step.goal, rep: true)) \(zone)"
            }
            return "\(goal(work.step.goal)) \(zone)"
        }
    }
}
