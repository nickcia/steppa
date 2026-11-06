public enum EditError: Error, Equatable, Sendable {
    case workoutNotFound
    case cannotMoveRace
    /// Workouts in the past, or moves into the past, aren't allowed.
    case dateInPast
    case afterRace
    /// Moves stay within the same Monday–Sunday week so weekly volume stays as planned.
    case differentWeek
    /// The move would break a safety rule, e.g. two hard days in a row.
    case breaksRule(PlanViolation.Rule)
}

/// Manual changes the athlete makes in the calendar.
public enum PlanEditor {
    /// Moves a workout to another day in the same week. If that day already has a workout,
    /// the two swap places. Fails if the result would break a safety rule the plan didn't already break.
    public static func move(_ workoutID: String, to target: LocalDate, in plan: TrainingPlan,
                            today: LocalDate) throws(EditError) -> TrainingPlan {
        guard let w = plan.weeks.firstIndex(where: { $0.workouts.contains { $0.id == workoutID } }),
              let k = plan.weeks[w].workouts.firstIndex(where: { $0.id == workoutID }) else {
            throw .workoutNotFound
        }
        let workout = plan.weeks[w].workouts[k]
        guard workout.kind != .race else { throw .cannotMoveRace }
        guard workout.date >= today, target >= today else { throw .dateInPast }
        guard target < plan.inputs.raceDate else { throw .afterRace }
        guard target.startOfWeek == workout.date.startOfWeek else { throw .differentWeek }
        guard target != workout.date else { return plan }

        var edited = plan
        if let other = edited.weeks[w].workouts.firstIndex(where: { $0.date == target }) {
            guard edited.weeks[w].workouts[other].kind != .race else { throw .cannotMoveRace }
            edited.weeks[w].workouts[other].movedFrom = edited.weeks[w].workouts[other].movedFrom ?? target
            edited.weeks[w].workouts[other].date = workout.date
        }
        edited.weeks[w].workouts[k].movedFrom = workout.movedFrom ?? workout.date
        edited.weeks[w].workouts[k].date = target
        edited.weeks[w].workouts.sort { $0.date < $1.date }

        let before = Set(PlanValidator.validate(plan))
        if let broken = PlanValidator.validate(edited).first(where: { !before.contains($0) }) {
            throw .breaksRule(broken.rule)
        }
        return edited
    }
}
