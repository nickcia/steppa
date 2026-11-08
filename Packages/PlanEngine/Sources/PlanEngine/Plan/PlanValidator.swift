public struct PlanViolation: Hashable, Sendable, CustomStringConvertible {
    public enum Rule: String, Sendable {
        case volumeIncrease
        case missingStepBack
        case overTarget
        case longRunTooLong
        case consecutiveHardDays
        case scheduling
        case intensityTooHigh
        case hardBeforeRace
        case invalidStep
    }

    public var rule: Rule
    public var date: LocalDate?
    public var detail: String

    public var description: String { "[\(rule.rawValue)] \(date.map { "\($0): " } ?? "")\(detail)" }
}

/// Independent safety check for any plan, generated or adapted.
///
/// The builder is designed to satisfy these rules; the validator proves it. Tests run it across
/// thousands of input combinations, and the app can run it before saving a plan as a last guard.
public enum PlanValidator {
    public static func validate(_ plan: TrainingPlan) -> [PlanViolation] {
        var violations: [PlanViolation] = []
        func fail(_ rule: PlanViolation.Rule, _ date: LocalDate?, _ detail: String) {
            violations.append(PlanViolation(rule: rule, date: date, detail: detail))
        }
        let inputs = plan.inputs
        let km = { (m: Double) in "\((m / 100).rounded() / 10) km" }

        // Volume progression and step-back weeks (checked on nominal weekly targets).
        var lastLoading: Double?
        var loadingRun = 0
        let maxLoadingRun = PlanRules.loadingWeeksBeforeStepBack(inputs.experience)
        for week in plan.weeks {
            // Run/walk weeks come before the plan's volume progression starts.
            if RunWalk.stage(for: week.startDate, inputs: inputs) != nil {
                lastLoading = nil
                loadingRun = 0
                continue
            }
            // A week mostly lost to time off (a holiday, injury…) is rest, not a loading week.
            let daysOff = (0..<7).filter { plan.inputs.isUnavailable(week.startDate.adding(days: $0)) }.count
            if daysOff > 0, week.trainingMeters < week.targetMeters * 0.5 {
                loadingRun = 0
                continue
            }
            if week.phase == .taper || week.isStepBack {
                if let last = lastLoading, week.targetMeters > last + 1 {
                    fail(.volumeIncrease, week.startDate, "\(week.phase) week above last loading week")
                }
                if week.isStepBack { loadingRun = 0 }
                continue
            }
            if let last = lastLoading, week.targetMeters > PlanRules.maximumAllowedVolume(after: last) + 1 {
                fail(.volumeIncrease, week.startDate, "\(km(last)) → \(km(week.targetMeters))")
            }
            lastLoading = week.targetMeters
            loadingRun += 1
            if loadingRun > maxLoadingRun {
                fail(.missingStepBack, week.startDate, "\(loadingRun) loading weeks in a row")
            }
        }

        // Per-week checks.
        for week in plan.weeks {
            let training = week.workouts.filter { $0.kind != .race }
            let trainingMeters = week.trainingMeters
            if trainingMeters > week.targetMeters * 1.05 + 500 {
                fail(.overTarget, week.startDate, "planned \(km(trainingMeters)), target \(km(week.targetMeters))")
            }
            // History isn't re-checked: in a week re-planned part-way through, only the re-planned part counts.
            // (Cutting the rest of a week after missed runs raises its hard share without adding hard work.)
            let planned = training.filter { workout in plan.revisedOn.map { workout.date >= $0 } ?? true }
            let plannedMeters = planned.reduce(0) { $0 + $1.totalMeters }
            let hard = planned.reduce(0) { $0 + $1.highIntensityMeters }
            if hard > plannedMeters * PlanRules.maxHighIntensityShare + 1 {
                fail(.intensityTooHigh, week.startDate, "\(km(hard)) of \(km(plannedMeters)) at threshold or faster")
            }
            let weekEnd = week.startDate.adding(days: 6)
            for workout in week.workouts where workout.date < week.startDate || workout.date > weekEnd {
                fail(.scheduling, workout.date, "workout outside its week")
            }
            for workout in training where workout.kind == .long || workout.kind == .marathonPaceLong {
                let meters = workout.totalMeters
                if meters > PlanRules.longRunCapMeters(inputs.goal, inputs.experience) + 1 {
                    fail(.longRunTooLong, workout.date, "\(km(meters)) over distance cap")
                }
                if workout.totalSeconds > PlanRules.longRunCapSeconds(inputs.goal, inputs.experience) + 180 {
                    fail(.longRunTooLong, workout.date, "\(Int(workout.totalSeconds / 60)) min over time cap")
                }
                let isHistory = plan.revisedOn.map { workout.date < $0 } ?? false
                if training.count >= 3, meters > trainingMeters * 0.5 + 1, !isHistory {
                    fail(.longRunTooLong, workout.date, "\(km(meters)) is over half the week")
                }
            }
        }

        // Whole-plan scheduling checks.
        let workouts = plan.workouts.sorted { $0.date < $1.date }
        let races = workouts.filter { $0.kind == .race }
        if races.count != 1 || races.first?.date != inputs.raceDate || workouts.last?.kind != .race {
            fail(.scheduling, inputs.raceDate, "plan must end with exactly one race on race day")
        }
        let quietStart = inputs.raceDate.adding(days: -PlanRules.raceTaperQuietDays)
        for (i, workout) in workouts.enumerated() {
            if workout.date < inputs.startDate || workout.date > inputs.raceDate {
                fail(.scheduling, workout.date, "outside the plan dates")
            }
            // History (before the last revision) and workouts the athlete moved may be on any day.
            let isHistory = plan.revisedOn.map { workout.date < $0 } ?? false
            if workout.kind != .race, workout.movedFrom == nil, !isHistory,
               !inputs.runDays.contains(workout.date.weekday) {
                fail(.scheduling, workout.date, "\(workout.date.weekday) is not a run day")
            }
            if i > 0 {
                let previous = workouts[i - 1]
                if previous.date == workout.date {
                    fail(.scheduling, workout.date, "two workouts on one day")
                } else if previous.date.days(until: workout.date) == 1, previous.kind.isHard, workout.kind.isHard,
                          !isHistory {
                    fail(.consecutiveHardDays, workout.date, "\(previous.kind) then \(workout.kind)")
                }
            }
            if workout.kind.isHard, workout.kind != .race, workout.date >= quietStart, !isHistory {
                fail(.hardBeforeRace, workout.date, "\(workout.kind) in the last days before the race")
            }
            for step in workout.expandedSteps {
                let validTarget = step.target.map { $0.range.fast > 0 && $0.range.fast < $0.range.slow } ?? true
                if step.estimatedMeters <= 0 || step.estimatedSeconds <= 0 || !validTarget {
                    fail(.invalidStep, workout.date, "invalid step in \(workout.kind)")
                }
            }
        }
        return violations
    }
}
