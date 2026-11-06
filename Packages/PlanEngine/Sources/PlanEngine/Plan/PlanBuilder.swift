/// Generates a complete training plan from the athlete's inputs.
///
/// Pure and deterministic: the same inputs always produce the same plan.
public enum PlanBuilder {
    /// Bump when plan output changes, so stored plans can record which rules made them.
    public static let engineVersion = 1

    public static func build(_ inputs: PlanInputs) throws(PlanError) -> TrainingPlan {
        guard inputs.raceDate > inputs.startDate else { throw .raceNotAfterStart }
        guard inputs.runDays.count >= 2 else { throw .tooFewRunDays }
        guard inputs.runDays.contains(inputs.longRunDay) else { throw .longRunDayNotARunDay }
        guard (0...PlanRules.maximumCurrentMeters).contains(inputs.currentWeeklyMeters) else {
            throw .invalidWeeklyVolume
        }

        let fitness = try FitnessEstimator.estimate(inputs.fitness, experience: inputs.experience,
                                                    weeklyMeters: inputs.currentWeeklyMeters, asOf: inputs.startDate)
        let paces = PaceTable(score: fitness.score, goal: inputs.goal)

        let firstMonday = inputs.startDate.startOfWeek
        let weekCount = firstMonday.days(until: inputs.raceDate.startOfWeek) / 7 + 1
        let phases = Periodisation.phases(weekCount: weekCount, goal: inputs.goal)
        let volumes = Periodisation.volumes(phases: phases, goal: inputs.goal, experience: inputs.experience,
                                            currentMeters: inputs.currentWeeklyMeters)

        var weeks: [PlanWeek] = []
        var limited = false
        for index in 0..<weekCount {
            let monday = firstMonday.adding(days: 7 * index)
            let result = WeekLayout.layout(.init(monday: monday, weekIndex: index, phase: phases[index],
                                                 volume: volumes[index], inputs: inputs, paces: paces,
                                                 isRaceWeek: index == weekCount - 1))
            limited = limited || result.limitedByAvailability
            weeks.append(PlanWeek(index: index, startDate: monday, phase: phases[index],
                                  isStepBack: volumes[index].isStepBack, targetMeters: volumes[index].meters,
                                  workouts: result.workouts))
        }
        applyPreRaceQuietDays(&weeks, raceDate: inputs.raceDate, paces: paces)

        var warnings: [PlanWarning] = []
        let recommendedWeeks = PlanRules.recommendedWeeks(inputs.goal)
        if weekCount < PlanRules.minimumWeeks(inputs.goal) {
            warnings.append(.shortPlan(weeks: weekCount, recommendedWeeks: recommendedWeeks))
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

    /// Safety net: in the last few days before the race, any hard or long run becomes a short easy run.
    /// `WeekLayout` already plans these days this way; this guards against future layout changes.
    static func applyPreRaceQuietDays(_ weeks: inout [PlanWeek], raceDate: LocalDate, paces: PaceTable) {
        let quietStart = raceDate.adding(days: -PlanRules.raceTaperQuietDays)
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
