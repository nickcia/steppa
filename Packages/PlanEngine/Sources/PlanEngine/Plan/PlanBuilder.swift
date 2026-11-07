/// Generates a complete training plan from the athlete's inputs.
///
/// Pure and deterministic: the same inputs always produce the same plan.
public enum PlanBuilder {
    /// Bump when plan output changes, so stored plans can record which rules made them.
    public static let engineVersion = 2

    public static func build(_ inputs: PlanInputs) throws(PlanError) -> TrainingPlan {
        guard inputs.raceDate > inputs.startDate else { throw .raceNotAfterStart }
        try validateSchedule(inputs)
        guard (0...PlanRules.maximumCurrentMeters).contains(inputs.currentWeeklyMeters) else {
            throw .invalidWeeklyVolume
        }

        let fitness = try FitnessEstimator.estimate(inputs.fitness, experience: inputs.experience,
                                                    weeklyMeters: inputs.currentWeeklyMeters, asOf: inputs.startDate)
        let paces = PaceTable(score: fitness.score, goal: inputs.goal)
        let (weeks, limited) = buildWeeks(inputs, paces: paces, from: inputs.startDate, resuming: nil)

        var warnings: [PlanWarning] = []
        let recommendedWeeks = PlanRules.recommendedWeeks(inputs.goal)
        if weeks.count < PlanRules.minimumWeeks(inputs.goal) {
            warnings.append(.shortPlan(weeks: weeks.count, recommendedWeeks: recommendedWeeks))
        }
        let recommendedVolume = PlanRules.recommendedCurrentMeters(inputs.goal)
        if inputs.currentWeeklyMeters < recommendedVolume {
            warnings.append(.lowStartingVolume(recommendedMeters: recommendedVolume))
        }
        if limited { warnings.append(.volumeLimitedByAvailability) }
        let predicted = FitnessModel.raceTimeSeconds(distanceMeters: inputs.goal.meters, score: fitness.score)
        if let goalTime = inputs.goalTimeSeconds, goalTime > 0,
           FitnessModel.score(distanceMeters: inputs.goal.meters, timeSeconds: goalTime) > fitness.score * 1.06 {
            warnings.append(.ambitiousGoal(predictedSeconds: predicted))
        }
        if fitness.confidence == .low { warnings.append(.estimatedFitness) }

        return TrainingPlan(engineVersion: engineVersion, inputs: inputs, fitness: fitness, paces: paces,
                            weeks: weeks, warnings: warnings)
    }

    static func validateSchedule(_ inputs: PlanInputs) throws(PlanError) {
        guard inputs.runDays.count >= 2 else { throw .tooFewRunDays }
        guard inputs.runDays.contains(inputs.longRunDay) else { throw .longRunDayNotARunDay }
    }

    /// Lays out every week from the week containing `from` up to race week.
    /// Workouts are only placed on or after `from`. Week indices start at 0.
    static func buildWeeks(
        _ inputs: PlanInputs,
        paces: PaceTable,
        from start: LocalDate,
        resuming: Periodisation.Progression?,
        firstWeekExisting: WeekLayout.ExistingWeek = .init(),
        history: [Workout] = []
    ) -> (weeks: [PlanWeek], limited: Bool) {
        var layoutInputs = inputs
        layoutInputs.startDate = start
        let firstMonday = start.startOfWeek
        let weekCount = firstMonday.days(until: inputs.raceDate.startOfWeek) / 7 + 1
        let phases = Periodisation.phases(weekCount: weekCount, goal: inputs.goal)
        let volumes = Periodisation.volumes(phases: phases, goal: inputs.goal, experience: inputs.experience,
                                            currentMeters: inputs.currentWeeklyMeters, resuming: resuming)
        var weeks: [PlanWeek] = []
        var limited = false
        // Share of the last full loading week's target that the available days could actually hold.
        // Step-back and taper weeks cut from what was held, not from a target the athlete never ran;
        // otherwise a week limited by availability gets little or no reduction.
        var heldShare = 1.0
        for index in 0..<weekCount {
            let monday = firstMonday.adding(days: 7 * index)
            var volume = volumes[index]
            if volume.isStepBack || phases[index] == .taper { volume.meters *= heldShare }
            let result = WeekLayout.layout(.init(monday: monday, weekIndex: index, phase: phases[index],
                                                 volume: volume, inputs: layoutInputs, paces: paces,
                                                 isRaceWeek: index == weekCount - 1,
                                                 existing: index == 0 ? firstWeekExisting : .init(),
                                                 recentLongestMeters: WeekLayout.recentLongestMeters(
                                                     history + weeks.flatMap(\.workouts), before: monday)))
            limited = limited || result.limitedByAvailability
            let week = PlanWeek(index: index, startDate: monday, phase: phases[index],
                                isStepBack: volume.isStepBack, targetMeters: volume.meters,
                                workouts: result.workouts)
            if !volume.isStepBack, phases[index] != .taper, monday >= start, index < weekCount - 1, volume.meters > 0, week.trainingMeters > 0 {
                heldShare = min(1, week.trainingMeters / volume.meters)
            }
            weeks.append(week)
        }
        applyPreRaceQuietDays(&weeks, raceDate: inputs.raceDate, paces: paces, from: start)
        return (weeks, limited)
    }

    /// Safety net: in the last few days before the race, any hard or long run becomes a short easy run.
    /// `WeekLayout` already plans these days this way; this guards against future layout changes.
    /// Workouts before `from` are history and are never changed.
    static func applyPreRaceQuietDays(_ weeks: inout [PlanWeek], raceDate: LocalDate, paces: PaceTable,
                                      from: LocalDate) {
        let quietStart = max(raceDate.adding(days: -PlanRules.raceTaperQuietDays), from)
        for w in weeks.indices {
            for k in weeks[w].workouts.indices {
                let workout = weeks[w].workouts[k]
                guard workout.kind != .race, workout.date >= quietStart, workout.date < raceDate else { continue }
                let cap = WeekLayout.quietDayCap(workout.date, raceDate: raceDate)
                if workout.kind.isHard || workout.totalMeters > cap {
                    weeks[w].workouts[k] = WorkoutFactory.easy(workout.date,
                                                               meters: min(floorTo500(workout.totalMeters), cap),
                                                               paces: paces)
                }
            }
        }
    }
}
