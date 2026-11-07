/// Why the plan should be reconsidered.
public enum AdaptationTrigger: Codable, Hashable, Sendable {
    /// Routine check (e.g. when the app opens or new runs sync): looks at missed training and paces.
    /// Returns the plan unchanged when the athlete is on track.
    case review
    case raceDateChanged(LocalDate)
    case availabilityChanged(runDays: Set<Weekday>, longRunDay: Weekday)
    /// The athlete entered a new race or time-trial result.
    case newRaceResult(RacePerformance)
}

/// A human-readable reason for a change, for the "your plan changed because…" message.
public enum AdaptationReason: Codable, Hashable, Sendable {
    /// Volume lowered because only this share of recent planned distance was run.
    case missedTraining(completedShare: Double)
    /// Volume lowered after this many days without running.
    case returningFromBreak(days: Int)
    case fitnessImproved(from: Double, to: Double)
    case fitnessDeclined(from: Double, to: Double)
    case newRaceResult(score: Double)
    case raceDateChanged(LocalDate)
    case availabilityChanged
}

public struct PlanRevision: Sendable {
    public var plan: TrainingPlan
    public var reasons: [AdaptationReason]
    public var changed: Bool { !reasons.isEmpty }
}

/// Re-plans the remaining weeks after something changes.
///
/// Principles:
/// - The past never changes. Today and later are re-planned; earlier workouts stay as history.
/// - Missed training is never "made up". Volume resumes from what was actually done and grows by the
///   usual safe rules from there.
/// - Fitness moves in small, damped steps and only on new evidence.
public enum PlanAdapter {
    // MARK: Tuning

    /// Window for judging how much planned training was done.
    public static let reviewWindowDays = 14
    /// At or above this share of planned distance the athlete counts as on track.
    public static let onTrackShare = 0.85
    /// Below this much planned distance in the window (or in the first week) there's too little data to judge.
    static let minimumPlannedMeters = 5_000.0

    /// Share of previous volume to resume at after a break with no running.
    public static func resumeShare(afterBreakOf days: Int) -> Double {
        switch days {
        case ..<7: 1
        case 7..<14: 0.8
        case 14..<28: 0.6
        case 28..<56: 0.4
        default: 0.25
        }
    }

    /// Window for pace evidence from quality sessions.
    public static let fitnessEvidenceDays = 28
    public static let minimumPaceSamples = 3
    /// Median expected/actual pace ratio needed before fitness changes.
    static let fasterThreshold = 1.03
    static let slowerThreshold = 0.95
    /// Largest change per adaptation. Increases are smaller than decreases, on purpose.
    static let maxIncrease = 0.02
    static let maxDecrease = 0.03
    /// A recent all-out-equivalent effort this far above current fitness counts as evidence.
    static let bestEffortMargin = 1.02
    static let maxBestEffortIncrease = 0.03

    // MARK: Adapt

    /// - Parameter assessTraining: Whether `log` is a complete record of the athlete's running. Pass
    ///   false when it may not be (e.g. no runs synced or logged yet): missed-training and pace checks are
    ///   then skipped, so a plan is never cut back just because nothing was recorded.
    public static func adapt(
        _ plan: TrainingPlan,
        log: TrainingLog,
        trigger: AdaptationTrigger,
        today: LocalDate,
        assessTraining: Bool = true
    ) throws(PlanError) -> PlanRevision {
        guard today < plan.inputs.raceDate else { throw .planFinished }
        var inputs = plan.inputs
        var fitness = plan.fitness
        var fitnessUpdatedOn = plan.fitnessUpdatedOn
        var reasons: [AdaptationReason] = []

        switch trigger {
        case .review:
            break
        case .raceDateChanged(let date):
            guard date > today, date > inputs.startDate else { throw .raceNotAfterStart }
            if date != inputs.raceDate {
                inputs.raceDate = date
                reasons.append(.raceDateChanged(date))
            }
        case .availabilityChanged(let runDays, let longRunDay):
            inputs.runDays = runDays
            inputs.longRunDay = longRunDay
            try PlanBuilder.validateSchedule(inputs)
            if runDays != plan.inputs.runDays || longRunDay != plan.inputs.longRunDay {
                reasons.append(.availabilityChanged)
            }
        case .newRaceResult(let performance):
            fitness = try FitnessEstimator.estimate(.recentRace(performance), experience: inputs.experience,
                                                    weeklyMeters: inputs.currentWeeklyMeters, asOf: today)
            fitnessUpdatedOn = today
            reasons.append(.newRaceResult(score: fitness.score))
        }

        if case .newRaceResult = trigger {} else if assessTraining,
                                                    let updated = fitnessFromTraining(plan, log: log, today: today) {
            reasons.append(updated.score > fitness.score
                ? .fitnessImproved(from: fitness.score, to: updated.score)
                : .fitnessDeclined(from: fitness.score, to: updated.score))
            fitness = updated
            fitnessUpdatedOn = today
        }

        let volume = assessTraining ? volumeCheck(plan, log: log, today: today) : (cap: nil, reason: nil)
        if let reason = volume.reason { reasons.append(reason) }

        guard !reasons.isEmpty else { return PlanRevision(plan: plan, reasons: []) }

        var revised = rebuild(plan, inputs: inputs, fitness: fitness, volumeCap: volume.cap, today: today)
        revised.fitnessUpdatedOn = fitnessUpdatedOn
        return PlanRevision(plan: revised, reasons: reasons)
    }

    // MARK: Volume

    /// How much recent training was done, and whether the remaining plan should be lowered.
    static func volumeCheck(_ plan: TrainingPlan, log: TrainingLog, today: LocalDate)
        -> (cap: Double?, reason: AdaptationReason?) {
        let start = plan.inputs.startDate
        guard today > start else { return (nil, nil) }
        let currentMonday = today.startOfWeek
        guard let currentIndex = plan.weeks.firstIndex(where: { $0.startDate == currentMonday }),
              currentIndex + 1 < plan.weeks.count,
              let progression = Periodisation.Progression.after(Array(plan.weeks[...currentIndex])) else {
            return (nil, nil) // race week, or nothing to compare against: leave volume alone
        }

        let windowStart = max(today.adding(days: -reviewWindowDays), start)
        let yesterday = today.adding(days: -1)
        let planned = plan.workouts
            .filter { $0.kind != .race && $0.date >= windowStart && $0.date <= yesterday }
            .reduce(0) { $0 + $1.totalMeters }
        let actual = log.runs
            .filter { $0.date >= windowStart && $0.date <= yesterday }
            .reduce(0) { $0 + $1.distanceMeters }
        let lastRun = log.runs.filter { $0.date <= today }.map(\.date).max()
        let daysOff = lastRun.map { $0.days(until: today) } ?? start.days(until: today)

        let share: Double
        let reason: AdaptationReason
        if daysOff >= 7 {
            share = resumeShare(afterBreakOf: daysOff)
            reason = .returningFromBreak(days: daysOff)
        } else if start.days(until: today) >= 7, planned >= minimumPlannedMeters, actual / planned < onTrackShare {
            // Partial training is never treated as worse than a complete break of the same length.
            share = max(actual / planned, resumeShare(afterBreakOf: reviewWindowDays))
            reason = .missedTraining(completedShare: actual / planned)
        } else {
            return (nil, nil)
        }

        let cap = max(progression.lastLoadingMeters * share,
                      min(PlanRules.minimumStartingMeters, progression.lastLoadingMeters))
        // Already lowered on an earlier review? Then don't lower again for the same missed days.
        let upcoming = plan.weeks[(currentIndex + 1)...].prefix(2).map(\.targetMeters).max() ?? 0
        guard upcoming > PlanRules.nextLoadingVolume(after: cap, plan.inputs.experience) + 1 else { return (nil, nil) }
        return (cap, reason)
    }

    // MARK: Fitness

    /// A new fitness estimate if recent training is clear evidence of a change, else nil.
    static func fitnessFromTraining(_ plan: TrainingPlan, log: TrainingLog, today: LocalDate) -> FitnessEstimate? {
        let score = plan.fitness.score
        let since = max(plan.fitnessUpdatedOn ?? plan.inputs.startDate.adding(days: -1),
                        today.adding(days: -fitnessEvidenceDays))

        // 1. Pace in quality sessions vs the paces they were planned at.
        var ratios: [Double] = []
        for workout in plan.workouts where workout.date > since && workout.date <= today
            && (workout.kind == .tempo || workout.kind == .intervals) {
            guard let run = log.run(forWorkout: workout.id), workout.totalMeters > 0 else { continue }
            let distanceRatio = run.distanceMeters / workout.totalMeters
            guard (0.8...1.25).contains(distanceRatio) else { continue }
            let expectedPace = workout.totalSeconds / workout.totalMeters * 1000
            ratios.append(expectedPace / run.paceSecondsPerKm)
        }

        var newScore = score
        if ratios.count >= minimumPaceSamples {
            let median = ratios.sorted()[ratios.count / 2]
            if median >= fasterThreshold {
                newScore = score * (1 + min((median - 1) * 0.5, maxIncrease))
            } else if median <= slowerThreshold {
                newScore = score * (1 - min((1 - median) * 0.5, maxDecrease))
            }
        }

        // 2. A recent effort that implies more fitness than we assume.
        let newRuns = log.runs.filter { $0.date > since }
        if let best = RacePredictor.bestRecentScore(newRuns, asOf: today), best > score * bestEffortMargin {
            newScore = max(newScore, min(best, score * (1 + maxBestEffortIncrease)))
        }

        guard abs(newScore - score) > 0.01 else { return nil }
        let confidence: FitnessEstimate.Confidence = plan.fitness.confidence == .low ? .medium : plan.fitness.confidence
        return FitnessEstimate(score: newScore, confidence: confidence)
    }

    // MARK: Rebuild

    static func rebuild(_ plan: TrainingPlan, inputs: PlanInputs, fitness: FitnessEstimate,
                        volumeCap: Double?, today: LocalDate) -> TrainingPlan {
        let paces = PaceTable(score: fitness.score, goal: inputs.goal)
        let revision = plan.revision + 1
        var weeks: [PlanWeek]
        var limited: Bool

        let currentMonday = today.startOfWeek
        if let currentIndex = plan.weeks.firstIndex(where: { $0.startDate == currentMonday }), today >= inputs.startDate {
            let prior = Array(plan.weeks[..<currentIndex])
            let current = plan.weeks[currentIndex]
            func capped(_ p: Periodisation.Progression?) -> Periodisation.Progression? {
                guard let cap = volumeCap else { return p }
                let base = p ?? .init(lastLoadingMeters: cap, consecutiveLoadingWeeks: 0)
                return .init(lastLoadingMeters: min(base.lastLoadingMeters, cap),
                             consecutiveLoadingWeeks: base.consecutiveLoadingWeeks)
            }

            // This week: keep what's already happened, re-plan today onwards. The week keeps its
            // original target and phase so the volume history stays consistent.
            let past = current.workouts.filter { $0.date < today }
            let pastMeters = past.filter { $0.kind != .race }.reduce(0) { $0 + $1.totalMeters }
            let recentHard = Set(plan.workouts
                .filter { $0.date < today && $0.date >= today.adding(days: -1) && $0.kind.isHard }
                .map(\.date))
            var layoutInputs = inputs
            layoutInputs.startDate = today
            let raceThisWeek = inputs.raceDate.startOfWeek == currentMonday
            let thisWeek = WeekLayout.layout(.init(
                monday: currentMonday, weekIndex: current.index, phase: current.phase,
                volume: .init(meters: min(current.targetMeters, volumeCap ?? .infinity), isStepBack: current.isStepBack),
                inputs: layoutInputs, paces: paces, isRaceWeek: raceThisWeek,
                existing: .init(hardDates: recentHard,
                                sessionCount: past.filter { $0.kind == .tempo || $0.kind == .intervals }.count,
                                hasLongRun: past.contains { $0.kind == .long || $0.kind == .marathonPaceLong },
                                remainingMeters: current.targetMeters - pastMeters,
                                trainingMeters: pastMeters,
                                highIntensityMeters: past.reduce(0) { $0 + $1.highIntensityMeters }),
                recentLongestMeters: WeekLayout.recentLongestMeters(plan.workouts, before: currentMonday)))
            var merged = current
            merged.workouts = past + thisWeek.workouts
            weeks = prior + [merged]
            limited = thisWeek.limitedByAvailability

            if !raceThisWeek {
                let mergedHard = Set(merged.workouts.filter(\.kind.isHard).map(\.date))
                let future = PlanBuilder.buildWeeks(
                    inputs, paces: paces, from: currentMonday.adding(days: 7),
                    resuming: capped(Periodisation.Progression.after(weeks)),
                    firstWeekExisting: .init(hardDates: mergedHard),
                    history: weeks.flatMap(\.workouts))
                weeks += future.weeks
                limited = limited || future.limited
            }
            for i in weeks.indices { weeks[i].index = i }
        } else {
            // The plan hasn't started yet: rebuild it all.
            (weeks, limited) = PlanBuilder.buildWeeks(inputs, paces: paces, from: inputs.startDate, resuming: nil)
        }
        PlanBuilder.applyPreRaceQuietDays(&weeks, raceDate: inputs.raceDate, paces: paces, from: today)

        // Re-planned workouts get a revision suffix so their IDs never collide with history
        // (e.g. a past workout the athlete moved off its original date).
        for w in weeks.indices {
            for k in weeks[w].workouts.indices where weeks[w].workouts[k].date >= today {
                weeks[w].workouts[k].id = "\(weeks[w].workouts[k].date)~r\(revision)"
            }
        }

        var warnings = plan.warnings.filter { $0 != .estimatedFitness || fitness.confidence == .low }
        if limited, !warnings.contains(.volumeLimitedByAvailability) { warnings.append(.volumeLimitedByAvailability) }

        var revised = plan
        revised.inputs = inputs
        revised.fitness = fitness
        revised.paces = paces
        revised.weeks = weeks
        revised.warnings = warnings
        revised.revision = revision
        revised.revisedOn = today
        return revised
    }
}
