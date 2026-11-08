import Foundation
import PlanEngine

/// One step of a guided run, flattened from a workout (repeats expanded), with what to show and say.
struct GuidedStep: Hashable, Sendable {
    enum Role: Sendable { case walk, run, warmup, work, recovery, cooldown }

    var role: Role
    /// "Run", "Walk", "Threshold", "Recovery"…
    var title: String
    /// Target or feel: "Gently, slow enough to talk", "5:10–5:20 /km".
    var detail: String
    /// Planned length. For distance steps this is the estimate, used when there's no GPS.
    var seconds: Double
    /// Set for distance steps: the step ends after this distance when GPS is available.
    var meters: Double?
    /// "3 of 8" within a repeat, nil outside one.
    var rep: (index: Int, count: Int)?
    /// Hex colour for the step.
    var tint: UInt32

    static func == (a: GuidedStep, b: GuidedStep) -> Bool {
        a.role == b.role && a.title == b.title && a.detail == b.detail && a.seconds == b.seconds && a.meters == b.meters
            && a.rep?.index == b.rep?.index && a.rep?.count == b.rep?.count
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(seconds)
        hasher.combine(rep?.index)
    }

    /// "Walk 1:30", "Threshold 1.6 km" (for "Next:").
    func short(_ format: DisplayFormat) -> String {
        "\(title) \(meters.map { format.distance($0) } ?? DisplayFormat.minutes(seconds))"
    }
}

/// Builds the steps of a guided run and decides what to say when.
enum GuidedTimeline {
    static func steps(for workout: Workout, describer: WorkoutDescriber) -> [GuidedStep] {
        let runWalk = workout.isRunWalkSession
        let walkTint: UInt32 = 0xB8B8B8
        func amount(_ step: Step) -> (seconds: Double, meters: Double?) {
            switch step.goal {
            case .time(let seconds): (seconds, nil)
            case .distance(let meters): (step.estimatedSeconds, meters)
            }
        }
        func make(_ step: Step, role: GuidedStep.Role, rep: (Int, Int)? = nil) -> GuidedStep {
            let (seconds, meters) = amount(step)
            switch role {
            case .walk:
                return GuidedStep(role: .walk, title: String(localized: "Walk"),
                                  detail: String(localized: "Brisk walk"), seconds: seconds, meters: meters, rep: rep, tint: walkTint)
            case .run:
                return GuidedStep(role: .run, title: String(localized: "Run"),
                                  detail: String(localized: "Gently, slow enough to talk"), seconds: seconds, meters: meters,
                                  rep: rep, tint: 0x4FC9B4)
            case .warmup, .cooldown:
                return GuidedStep(role: role, title: role == .warmup ? String(localized: "Warm up") : String(localized: "Cool down"),
                                  detail: step.target.map { describer.detail($0) } ?? String(localized: "Easy jog"),
                                  seconds: seconds, meters: meters, rep: rep, tint: 0x5CCB6A)
            case .recovery:
                return GuidedStep(role: .recovery, title: String(localized: "Recover"),
                                  detail: step.target.map { describer.detail($0) } ?? String(localized: "Easy jog or walk"),
                                  seconds: seconds, meters: meters, rep: rep, tint: walkTint)
            case .work:
                let zone = step.target?.zone
                return GuidedStep(role: .work, title: zone.map { $0.name.capitalized } ?? String(localized: "Run"),
                                  detail: step.target.map { describer.detail($0) } ?? String(localized: "Steady"),
                                  seconds: seconds, meters: meters, rep: rep, tint: tint(for: workout.kind, zone: zone))
            }
        }

        var steps: [GuidedStep] = []
        if let warmup = workout.warmup { steps.append(make(warmup, role: runWalk ? .walk : .warmup)) }
        for block in workout.blocks {
            for i in 0..<block.iterations {
                for interval in block.steps {
                    let role: GuidedStep.Role = switch (runWalk, interval.purpose) {
                    case (true, .work): .run
                    case (true, .recovery): .walk
                    case (false, .work): .work
                    case (false, .recovery): .recovery
                    }
                    steps.append(make(interval.step, role: role, rep: block.iterations > 1 ? (i + 1, block.iterations) : nil))
                }
            }
        }
        if let cooldown = workout.cooldown { steps.append(make(cooldown, role: runWalk ? .walk : .cooldown)) }
        return steps
    }

    private static func tint(for kind: WorkoutKind, zone: PaceZone?) -> UInt32 {
        switch zone {
        case .threshold?: 0xF5B13D
        case .interval?, .repetition?: 0xF26D6D
        case .marathon?: 0x9A78F0
        case .hill?: 0xD98A55
        case .stride?: 0xF26D6D
        case .race?: 0xEC5D93
        default: kind == .long ? 0x5B8DEF : 0x5CCB6A
        }
    }

    // MARK: What to say

    /// Said as a step starts: "Run for 1 minute." "Walk for 1 minute, 30 seconds." "Last one: run for 1 minute."
    static func startCue(_ steps: [GuidedStep], index: Int) -> String {
        let step = steps[index]
        let amount = step.meters.map(spokenDistance) ?? spokenDuration(step.seconds)
        let lastRep = step.rep.map { $0.index == $0.count } ?? false
        let isFinalHardRep = lastRep && (step.role == .run || step.role == .work)
        let what: String = switch step.role {
        case .run: String(localized: "Run for \(amount).")
        case .walk where index == 0: String(localized: "Walk for \(amount) to warm up.")
        case .walk where index == steps.count - 1: String(localized: "Walk for \(amount) to cool down.")
        case .walk: String(localized: "Walk for \(amount).")
        case .warmup: String(localized: "Warm up, \(amount) easy.")
        case .cooldown: String(localized: "Cool down, \(amount) easy.")
        case .recovery: String(localized: "Recover, \(amount).")
        case .work: String(localized: "\(step.title), \(amount).")
        }
        if index == 0 { return String(localized: "Let's go. \(what)") }
        return isFinalHardRep && (step.rep?.count ?? 0) > 1 ? String(localized: "Last one. \(what)") : what
    }

    /// Cues during a step, by seconds into it: halfway on long steps, and a heads-up ten seconds before the next.
    static func midCues(_ steps: [GuidedStep], index: Int) -> [(at: Double, text: String)] {
        let step = steps[index]
        var cues: [(Double, String)] = []
        if step.seconds >= 6 * 60, step.meters == nil { cues.append((step.seconds / 2, String(localized: "Halfway."))) }
        if step.seconds >= 45, step.meters == nil, index + 1 < steps.count {
            let next = steps[index + 1]
            cues.append((step.seconds - 10, String(localized: "Ten seconds, then \(next.title.lowercased()).")))
        }
        return cues
    }

    static let finishCue = String(localized: "That's it, workout complete. Great job.")

    static func spokenDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        return formatter.string(from: seconds.rounded()) ?? "\(Int(seconds)) seconds"
    }

    static func spokenDistance(_ meters: Double) -> String {
        let usesMiles = Locale.current.measurementSystem == .us
        let measurement = usesMiles ? Measurement(value: meters / 1609.344, unit: UnitLength.miles)
                                    : Measurement(value: meters / 1000, unit: UnitLength.kilometers)
        if !usesMiles, meters < 1000 { return Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .wide)) }
        return measurement.formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }
}
