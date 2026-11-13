import Foundation
/// Generates a complete training plan from the athlete's inputs.
///
/// Pure and deterministic: the same inputs always produce the same plan.
public enum PlanBuilder {
    /// Bump when plan output changes, so stored plans can record which rules made them.
    public static let engineVersion = 5

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
        if inputs.runWalkStart != nil {
            // Run/walk to 30 minutes takes about nine weeks before any race training starts.
            let wanted = RunWalk.stages.count + recommendedWeeks / 2
            if weeks.count < RunWalk.stages.count + 1 {
                warnings.append(.shortPlan(weeks: weeks.count, recommendedWeeks: wanted))
            }
        } else if weeks.count < PlanRules.minimumWeeks(inputs.goal) {
            warnings.append(.shortPlan(weeks: weeks.count, recommendedWeeks: recommendedWeeks))
        }
        let recommendedVolume = PlanRules.recommendedCurrentMeters(inputs.goal)
        if inputs.runWalkStart == nil, inputs.currentWeeklyMeters < recommendedVolume {
            warnings.append(.lowStartingVolume(recommendedMeters: recommendedVolume))
        }
        var recommendedDays = PlanRules.recommendedRunDays(inputs.goal, goalTimeSeconds: inputs.goalTimeSeconds)
        if inputs.runWalkStart != nil { recommendedDays = max(recommendedDays, RunWalk.sessionsPerWeek) }
        if inputs.runDays.count < recommendedDays {
            warnings.append(.fewRunDays(recommended: recommendedDays))
        }
        // New runners aren't nudged to add run days: three is the right number while they start.
        if limited, inputs.runWalkStart == nil || inputs.runDays.count < RunWalk.sessionsPerWeek {
            warnings.append(.volumeLimitedByAvailability)
        }
        let predicted = FitnessModel.raceTimeSeconds(distanceMeters: inputs.goal.meters, score: fitness.score)
        if let goalTime = inputs.goalTimeSeconds, goalTime > 0,
           FitnessModel.score(distanceMeters: inputs.goal.meters, timeSeconds: goalTime) > fitness.score * 1.06 {
            warnings.append(.ambitiousGoal(predictedSeconds: predicted))
        }
        if fitness.confidence == .low { warnings.append(.estimatedFitness) }
        if case .recentRace(let race) = inputs.fitness,
           !FitnessModel.supportedScores.contains(FitnessModel.score(distanceMeters: race.distanceMeters, timeSeconds: race.timeSeconds)) {
            warnings.append(.unusualRaceTime(distanceMeters: race.distanceMeters, timeSeconds: race.timeSeconds))
        }

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
        // New runners' run/walk weeks come first; the phases and volume progression cover the weeks after them,
        // starting from what run/walk ends at (three 30-minute runs a week).
        let runWalkWeeks = (0..<weekCount).filter {
            RunWalk.stage(for: firstMonday.adding(days: 7 * $0), inputs: inputs) != nil
        }.count
        let normalCount = weekCount - runWalkWeeks
        let currentMeters = inputs.runWalkStart == nil ? inputs.currentWeeklyMeters
            : max(inputs.currentWeeklyMeters, RunWalk.handoffMeters(paces))
        let phases = Array(repeating: Phase.base, count: runWalkWeeks)
            + Periodisation.phases(weekCount: normalCount, goal: inputs.goal)
        var volumes = Array(repeating: Periodisation.WeekVolume(meters: 0, isStepBack: false), count: runWalkWeeks)
            + Periodisation.volumes(phases: Array(phases[runWalkWeeks...]), goal: inputs.goal,
                                    experience: inputs.experience, currentMeters: currentMeters,
                                    resuming: runWalkWeeks > 0 ? nil : resuming)
        // The last loading week the athlete actually trained in, for restarting after a break.
        var lastHeldLoading = resuming?.lastLoadingMeters
        var breaksHandled: Set<UUID> = []
        var weeks: [PlanWeek] = []
        var limited = false
        // Share of the last full loading week's target that the available days could actually hold.
        // Step-back and taper weeks cut from what was held, not from a target the athlete never ran;
        // otherwise a week limited by availability gets little or no reduction.
        var heldShare = 1.0
        // In a new plan the first weeks have no history, so the 10% rule would compare runs with the plan's
        // own first (often partial) week. Assume a usual long run of 30% of the weekly distance the athlete
        // reported (a typical share) until the plan has a few weeks of its own.
        let assumedLongest = history.isEmpty && resuming == nil
            ? max(inputs.currentWeeklyMeters * 0.30, PlanRules.minimumRunMeters) : 0
        func recentLongest(before monday: LocalDate) -> Double {
            let planned = WeekLayout.recentLongestMeters(history + weeks.flatMap(\.workouts), before: monday)
            guard planned.isFinite, monday.adding(days: -PlanRules.recentRunWindowDays) < start else { return planned }
            return max(planned, assumedLongest)
        }
        for index in 0..<weekCount {
            let monday = firstMonday.adding(days: 7 * index)
            // Back from a week or more off: restart at a share of what was being run before (the same shares as
            // an unplanned break) and build up again from there by the usual rules.
            if phases[index] != .taper, let before = lastHeldLoading,
               let back = inputs.timeOffPeriods.first(where: { off in
                   guard off.mode == .noRunning, !breaksHandled.contains(off.id), let end = off.end,
                         let length = off.length, length >= TimeOff.breakDaysForReset else { return false }
                   return end >= monday.adding(days: -7) && end < monday.adding(days: 6)
               }) {
                breaksHandled.insert(back.id)
                let restart = max(before * PlanAdapter.resumeShare(afterBreakOf: back.length ?? 0),
                                  min(PlanRules.minimumStartingMeters, before))
                // The first week back is the restart; the weeks after it grow from there by the usual rules.
                let rest = Periodisation.volumes(phases: Array(phases[(index + 1)...]), goal: inputs.goal,
                                                 experience: inputs.experience, currentMeters: currentMeters,
                                                 resuming: .init(lastLoadingMeters: restart, consecutiveLoadingWeeks: 1))
                volumes.replaceSubrange(index..., with: [.init(meters: restart, isStepBack: false)] + rest)
            }
            if index < runWalkWeeks {
                let result = WeekLayout.layout(.init(monday: monday, weekIndex: index, phase: .base,
                                                     volume: volumes[index], inputs: layoutInputs, paces: paces,
                                                     isRaceWeek: false,
                                                     existing: index == 0 ? firstWeekExisting : .init()))
                let held = result.workouts.reduce(0) { $0 + $1.totalMeters }
                weeks.append(PlanWeek(index: index, startDate: monday, phase: .base, isStepBack: false,
                                      targetMeters: held, workouts: result.workouts))
                continue
            }
            var volume = volumes[index]
            if volume.isStepBack || phases[index] == .taper { volume.meters *= heldShare }
            let result = WeekLayout.layout(.init(monday: monday, weekIndex: index - runWalkWeeks, phase: phases[index],
                                                 volume: volume, inputs: layoutInputs, paces: paces,
                                                 isRaceWeek: index == weekCount - 1,
                                                 existing: index == 0 ? firstWeekExisting : .init(),
                                                 recentLongestMeters: recentLongest(before: monday)))
            limited = limited || result.limitedByAvailability
            let week = PlanWeek(index: index, startDate: monday, phase: phases[index],
                                isStepBack: volume.isStepBack, targetMeters: volume.meters,
                                workouts: result.workouts)
            if !volume.isStepBack, phases[index] != .taper, monday >= start, index < weekCount - 1, volume.meters > 0, week.trainingMeters > 0 {
                heldShare = min(1, week.trainingMeters / volume.meters)
            }
            if !volume.isStepBack, phases[index] != .taper, week.trainingMeters > 0 { lastHeldLoading = volume.meters }
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
