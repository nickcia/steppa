import Foundation
import PlanEngine

/// Human-readable descriptions of structured workouts.
struct WorkoutDescriber {
    let format: DisplayFormat

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
            return Line(title: title.map { "\($0) · \(amount)" } ?? "\(amount) \(target.zone.name)",
                        detail: format.paceRange(target.range), zone: target.zone, isRecovery: isRecovery)
        }
        return Line(title: title.map { "\($0) · \(amount)" } ?? String(localized: "\(amount) jog"),
                    detail: isRecovery ? String(localized: "Easy jog or walk") : nil, zone: nil, isRecovery: isRecovery)
    }

    func sections(_ workout: Workout) -> [Section] {
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

    /// One-line summary for lists: "8 km easy", "5 × 800 m intervals", "6 km threshold".
    func summary(_ workout: Workout) -> String {
        switch workout.kind {
        case .easy, .long:
            return format.distance(workout.totalMeters)
        case .race:
            return format.distance(workout.totalMeters)
        case .tempo, .intervals, .marathonPaceLong:
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
