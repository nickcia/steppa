/// Splits the weeks before a race into phases and assigns each week a target volume.
enum Periodisation {
    /// Phase for each week, in order. The last week always contains the race.
    static func phases(weekCount: Int, goal: RaceDistance) -> [Phase] {
        let taper = min(PlanRules.taperFactors(goal).count, weekCount)
        let remaining = weekCount - taper
        let peak = remaining >= 3 ? max(1, Int((Double(remaining) * 0.2).rounded())) : 0
        let build = remaining >= 2 ? Int((Double(remaining) * 0.35).rounded()) : 0
        let base = remaining - peak - build
        return Array(repeating: .base, count: base)
            + Array(repeating: .build, count: build)
            + Array(repeating: .peak, count: peak)
            + Array(repeating: .taper, count: taper)
    }

    struct WeekVolume: Equatable {
        var meters: Double
        var isStepBack: Bool
    }

    /// Where volume progression stands part-way through a plan.
    struct Progression: Equatable {
        /// Target of the most recent loading (non-step-back, non-taper) week.
        var lastLoadingMeters: Double
        /// Loading weeks since the last step-back.
        var consecutiveLoadingWeeks: Int

        /// Replays existing weeks to find where progression stands after them.
        static func after(_ weeks: [PlanWeek]) -> Progression? {
            var state: Progression?
            for week in weeks {
                if week.isStepBack {
                    state?.consecutiveLoadingWeeks = 0
                } else if week.phase != .taper {
                    state = Progression(lastLoadingMeters: week.targetMeters,
                                        consecutiveLoadingWeeks: (state?.consecutiveLoadingWeeks ?? 0) + 1)
                }
            }
            return state
        }
    }

    /// Nominal weekly volumes: steady growth capped by `PlanRules`, a step-back week after every
    /// few loading weeks, then the taper. Pass `resuming` to continue an existing plan's progression.
    static func volumes(phases: [Phase], goal: RaceDistance, experience: Experience, currentMeters: Double,
                        resuming: Progression? = nil) -> [WeekVolume] {
        let peak = PlanRules.peakMeters(goal, experience, currentMeters: currentMeters)
        let start = PlanRules.startMeters(currentMeters: currentMeters, peakMeters: peak)
        let loadingRun = PlanRules.loadingWeeksBeforeStepBack(experience)
        let taperCount = phases.filter { $0 == .taper }.count
        let taperFactors = Array(PlanRules.taperFactors(goal).suffix(taperCount))

        var result: [WeekVolume] = []
        var lastLoading = resuming?.lastLoadingMeters ?? start
        var consecutiveLoading = resuming?.consecutiveLoadingWeeks ?? 0
        var taperIndex = 0

        for (index, phase) in phases.enumerated() {
            if phase == .taper {
                result.append(WeekVolume(meters: lastLoading * taperFactors[taperIndex], isStepBack: false))
                taperIndex += 1
            } else if index == 0 && resuming == nil {
                result.append(WeekVolume(meters: start, isStepBack: false))
                consecutiveLoading = 1
            } else if consecutiveLoading >= loadingRun {
                result.append(WeekVolume(meters: lastLoading * PlanRules.stepBackFactor, isStepBack: true))
                consecutiveLoading = 0
            } else {
                lastLoading = min(peak, PlanRules.nextLoadingVolume(after: lastLoading, experience))
                result.append(WeekVolume(meters: lastLoading, isStepBack: false))
                consecutiveLoading += 1
            }
        }
        return result
    }
}
