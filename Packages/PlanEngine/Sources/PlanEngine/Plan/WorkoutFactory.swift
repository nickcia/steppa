/// Builds individual structured workouts.
enum WorkoutFactory {
    struct SessionContext {
        var weekMeters: Double
        var goal: RaceDistance
        var experience: Experience
        var phase: Phase
        var paces: PaceTable
    }

    // MARK: Steps

    static func step(meters: Double, zone: PaceZone?, paces: PaceTable) -> Step {
        let pace = zone.map { paces.range(for: $0).mid } ?? paces.easy.slow
        return Step(goal: .distance(meters: meters),
                    target: zone.map { PaceTarget(zone: $0, range: paces.range(for: $0)) },
                    estimatedMeters: meters,
                    estimatedSeconds: meters / 1000 * pace)
    }

    static func step(seconds: Double, zone: PaceZone?, paces: PaceTable) -> Step {
        let pace = zone.map { paces.range(for: $0).mid } ?? paces.easy.slow
        return Step(goal: .time(seconds: seconds),
                    target: zone.map { PaceTarget(zone: $0, range: paces.range(for: $0)) },
                    estimatedMeters: seconds / pace * 1000,
                    estimatedSeconds: seconds)
    }

    private static func single(_ step: Step, repeat iterations: Int = 1) -> IntervalBlock {
        IntervalBlock(iterations: iterations, steps: [IntervalStep(purpose: .work, step: step)])
    }

    private static func warmupMeters(_ experience: Experience) -> Double { experience == .beginner ? 1_500 : 2_000 }
    private static func cooldownMeters(_ experience: Experience) -> Double { experience == .beginner ? 1_000 : 1_500 }

    // MARK: Simple runs

    static func easy(_ date: LocalDate, meters: Double, paces: PaceTable) -> Workout {
        Workout(date: date, kind: .easy, blocks: [single(step(meters: meters, zone: .easy, paces: paces))])
    }

    static func long(_ date: LocalDate, meters: Double, paces: PaceTable) -> Workout {
        Workout(date: date, kind: .long, blocks: [single(step(meters: meters, zone: .easy, paces: paces))])
    }

    /// Long run whose second part is at marathon pace. Falls back to a plain long run if too short.
    static func marathonPaceLong(_ date: LocalDate, meters: Double, paces: PaceTable) -> Workout {
        let paceMeters = min(max(roundTo500(meters * 0.4), 4_000), 16_000)
        let cooldown = 1_000.0
        let easyMeters = meters - paceMeters - cooldown
        guard easyMeters >= PlanRules.minimumRunMeters else { return long(date, meters: meters, paces: paces) }
        return Workout(date: date, kind: .marathonPaceLong,
                       warmup: step(meters: easyMeters, zone: .easy, paces: paces),
                       blocks: [single(step(meters: paceMeters, zone: .marathon, paces: paces))],
                       cooldown: step(meters: cooldown, zone: .easy, paces: paces))
    }

    static func race(_ date: LocalDate, goal: RaceDistance, paces: PaceTable) -> Workout {
        Workout(date: date, kind: .race, blocks: [single(step(meters: goal.meters, zone: .race, paces: paces))])
    }

    // MARK: Quality sessions

    /// VO₂max intervals with jog recoveries. Returns nil if the week is too small for a meaningful session.
    static func intervals(_ date: LocalDate, _ c: SessionContext) -> Workout? {
        let budget = min(c.weekMeters * PlanRules.intervalBudgetShare, PlanRules.intervalBudgetCap)
        var rep: Double = switch c.goal {
        case .fiveK: 800
        case .tenK, .halfMarathon: 1_000
        case .marathon: 1_200
        }
        if budget < rep * 3 { rep = 400 }
        let reps = min(Int(budget / rep), 8)
        guard reps >= 3 else { return nil }

        let repSeconds = rep / 1000 * c.paces.interval.mid
        let recoverySeconds = max(60, (repSeconds * 0.75 / 15).rounded() * 15)
        let block = IntervalBlock(iterations: reps, steps: [
            IntervalStep(purpose: .work, step: step(meters: rep, zone: .interval, paces: c.paces)),
            IntervalStep(purpose: .recovery, step: step(seconds: recoverySeconds, zone: nil, paces: c.paces)),
        ])
        return Workout(date: date, kind: .intervals,
                       warmup: step(meters: warmupMeters(c.experience), zone: .easy, paces: c.paces),
                       blocks: [block],
                       cooldown: step(meters: cooldownMeters(c.experience), zone: .easy, paces: c.paces))
    }

    /// Threshold session: a continuous tempo run in the peak phase, cruise intervals otherwise.
    static func tempo(_ date: LocalDate, _ c: SessionContext) -> Workout? {
        let budget = min(c.weekMeters * PlanRules.thresholdBudgetShare, PlanRules.thresholdBudgetCap)
        let warmup = step(meters: warmupMeters(c.experience), zone: .easy, paces: c.paces)
        let cooldown = step(meters: cooldownMeters(c.experience), zone: .easy, paces: c.paces)

        if c.phase == .peak, c.experience != .beginner {
            let meters = min(floorTo500(budget), 8_000)
            if meters >= 3_000 {
                return Workout(date: date, kind: .tempo, warmup: warmup,
                               blocks: [single(step(meters: meters, zone: .threshold, paces: c.paces))],
                               cooldown: cooldown)
            }
        }

        var rep: Double = c.experience == .beginner ? 1_000 : 1_600
        if budget < rep * 2 { rep = 1_000 }
        let reps = min(Int(budget / rep), 6)
        guard reps >= 2 else { return nil }
        let block = IntervalBlock(iterations: reps, steps: [
            IntervalStep(purpose: .work, step: step(meters: rep, zone: .threshold, paces: c.paces)),
            IntervalStep(purpose: .recovery, step: step(seconds: 60, zone: nil, paces: c.paces)),
        ])
        return Workout(date: date, kind: .tempo, warmup: warmup, blocks: [block], cooldown: cooldown)
    }
}
