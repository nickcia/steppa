/// Turns one week's target volume into concrete workouts on concrete days.
enum WeekLayout {
    struct Context {
        var monday: LocalDate
        var weekIndex: Int
        var phase: Phase
        var volume: Periodisation.WeekVolume
        var inputs: PlanInputs
        var paces: PaceTable
        var isRaceWeek: Bool
        /// When re-planning mid-week: what's already on the calendar before the first day we may change.
        var existing: ExistingWeek = .init()
        /// Longest run in the few weeks before this one (see `PlanRules.maxRunSpike`). Infinity if unknown.
        var recentLongestMeters: Double = .infinity
    }

    /// Longest training run (not a race) in the look-back window before `monday`.
    static func recentLongestMeters(_ workouts: [Workout], before monday: LocalDate) -> Double {
        let from = monday.adding(days: -PlanRules.recentRunWindowDays)
        return workouts.filter { $0.kind != .race && $0.date >= from && $0.date < monday }
            .map(\.totalMeters).max() ?? .infinity
    }

    /// Workouts already in this week (or just before it) that a re-plan must respect.
    struct ExistingWeek {
        /// Dates of hard workouts near the re-planned days, so new hard days aren't placed next to them.
        var hardDates: Set<LocalDate> = []
        var sessionCount = 0
        var hasLongRun = false
        /// Distance the re-planned days may add without the week exceeding its target.
        var remainingMeters: Double = .infinity
        /// Planned training distance, and the part at threshold or faster, already in the week.
        var trainingMeters: Double = 0
        var highIntensityMeters: Double = 0
    }

    struct Result {
        var workouts: [Workout]
        var limitedByAvailability: Bool
    }

    enum SessionKind { case tempo, intervals }

    static func layout(_ c: Context) -> Result {
        let inputs = c.inputs
        let lastTrainingDay = c.isRaceWeek ? inputs.raceDate.adding(days: -1) : c.monday.adding(days: 6)
        let trainingDates = (0..<7).map { c.monday.adding(days: $0) }.filter {
            $0 >= inputs.startDate && $0 <= lastTrainingDay && inputs.runDays.contains($0.weekday)
        }
        // Partial weeks (plan start, race week) get a proportional share of the nominal volume.
        let weekMeters = min(c.volume.meters * min(1, Double(trainingDates.count) / Double(inputs.runDays.count)),
                             max(0, c.existing.remainingMeters))
        func nextToHardDay(_ d: LocalDate) -> Bool {
            c.existing.hardDates.contains(d.adding(days: -1)) || c.existing.hardDates.contains(d.adding(days: 1))
        }
        // The last days before the race are quiet: no long run, no sessions, short easy runs only.
        let quietStart = inputs.raceDate.adding(days: -PlanRules.raceTaperQuietDays)
        let longDate = trainingDates.first {
            $0.weekday == inputs.longRunDay && $0 < quietStart && !c.isRaceWeek
                && !c.existing.hasLongRun && !nextToHardDay($0)
        }

        let marathonPaceLong = inputs.goal == .marathon && c.phase == .peak && !c.volume.isStepBack
            && inputs.experience != .beginner && longDate != nil
        var maxSessions = PlanRules.qualitySessions(phase: c.phase, experience: inputs.experience,
                                                    runDays: inputs.runDays.count, isStepBack: c.volume.isStepBack)
        if marathonPaceLong || c.isRaceWeek { maxSessions = min(maxSessions, 1) }
        maxSessions = max(0, maxSessions - c.existing.sessionCount)

        let latestSessionDate = min(lastTrainingDay, quietStart.adding(days: -1))
        let sessionDates = chooseSessionDates(trainingDates.filter {
                                                  $0 != longDate && $0 <= latestSessionDate && !nextToHardDay($0)
                                              },
                                              longRunDay: inputs.longRunDay, max: maxSessions)
        let kinds = sessionKinds(phase: c.phase, goal: inputs.goal, weekIndex: c.weekIndex, count: sessionDates.count)

        // Drop quality sessions one at a time until the week fits the volume and intensity limits.
        for count in stride(from: sessionDates.count, through: 0, by: -1) {
            func assembleWeek(sizedFor sessionMeters: Double) -> Result {
                assemble(c, trainingDates: trainingDates, weekMeters: weekMeters, sessionWeekMeters: sessionMeters,
                         longDate: longDate, marathonPaceLong: marathonPaceLong,
                         sessions: Array(zip(sessionDates.prefix(count), kinds)))
            }
            // Sessions are sized as a share of the week (Daniels: threshold ≤ 10%, intervals ≤ 8%). When the
            // available days can't hold the full week, size them against what the week actually holds.
            var sizedFor = weekMeters
            var attempt = assembleWeek(sizedFor: sizedFor)
            for _ in 0..<3 {
                let held = attempt.workouts.filter { $0.kind != .race }.reduce(0) { $0 + $1.totalMeters }
                guard held < sizedFor - 1 else { break }
                sizedFor = held
                attempt = assembleWeek(sizedFor: sizedFor)
            }
            let training = attempt.workouts.filter { $0.kind != .race }
            let trainingMeters = training.reduce(0) { $0 + $1.totalMeters }
            let hardMeters = training.reduce(0) { $0 + $1.highIntensityMeters }
            let fits = trainingMeters <= weekMeters * 1.05 + 500
                && hardMeters + c.existing.highIntensityMeters
                    <= (trainingMeters + c.existing.trainingMeters) * PlanRules.maxHighIntensityShare
            if fits || count == 0 { return attempt }
        }
        preconditionFailure("unreachable")
    }

    /// Picks days for quality sessions: never next to the long-run weekday or each other, even across
    /// week boundaries. Fits as many sessions as allowed (up to `max`), then prefers days furthest from
    /// the long run. (A greedy pick of the furthest day first can block a second session: with runs on
    /// Mon–Thu and a Sunday long run, Wednesday alone blocks Tuesday + Thursday.)
    static func chooseSessionDates(_ candidates: [LocalDate], longRunDay: Weekday, max: Int) -> [LocalDate] {
        let eligible = candidates.filter { $0.weekday.circularDistance(to: longRunDay) >= 2 }.sorted()
        guard max > 0, !eligible.isEmpty else { return [] }
        var best: [LocalDate] = []
        var bestSpread = -1
        // At most 7 candidates, so trying every subset is cheap.
        for mask in 1..<(1 << eligible.count) {
            let subset = eligible.indices.filter { mask & (1 << $0) != 0 }.map { eligible[$0] }
            guard subset.count <= max else { continue }
            let apart = subset.indices.allSatisfy { i in
                subset.indices.allSatisfy { j in
                    i == j || subset[i].weekday.circularDistance(to: subset[j].weekday) >= 2
                }
            }
            guard apart else { continue }
            let spread = subset.reduce(0) { $0 + $1.weekday.circularDistance(to: longRunDay) }
            // More sessions first, then further from the long run, then earlier dates.
            if subset.count > best.count || (subset.count == best.count
                && (spread > bestSpread || (spread == bestSpread && subset.lexicographicallyPrecedes(best)))) {
                best = subset
                bestSpread = spread
            }
        }
        return best
    }

    static func sessionKinds(phase: Phase, goal: RaceDistance, weekIndex: Int, count: Int) -> [SessionKind] {
        let shortRace = goal == .fiveK || goal == .tenK
        let order: [SessionKind] = switch phase {
        case .base: [.tempo]
        case .build where count == 1: weekIndex.isMultiple(of: 2) ? [.intervals] : [.tempo]
        case .build, .peak: shortRace ? [.intervals, .tempo] : [.tempo, .intervals]
        case .taper: shortRace ? [.intervals] : [.tempo]
        }
        return Array(order.prefix(count))
    }

    /// Maximum easy-run distance on the quiet days before the race.
    static func quietDayCap(_ date: LocalDate, raceDate: LocalDate) -> Double {
        switch date.days(until: raceDate) {
        case 1: 4_000
        case 2...PlanRules.raceTaperQuietDays: 6_000
        default: .infinity
        }
    }

    private static func assemble(
        _ c: Context,
        trainingDates: [LocalDate],
        weekMeters: Double,
        sessionWeekMeters: Double,
        longDate: LocalDate?,
        marathonPaceLong: Bool,
        sessions planned: [(LocalDate, SessionKind)]
    ) -> Result {
        let inputs = c.inputs
        let paces = c.paces
        let sessionContext = WorkoutFactory.SessionContext(weekMeters: sessionWeekMeters, goal: inputs.goal,
                                                           experience: inputs.experience, phase: c.phase, paces: paces)
        let sessions = planned.compactMap { date, kind in
            switch kind {
            case .tempo: WorkoutFactory.tempo(date, sessionContext)
            case .intervals: WorkoutFactory.intervals(date, sessionContext)
            }
        }
        let sessionDates = Set(sessions.map(\.date))
        let sessionMeters = sessions.reduce(0) { $0 + $1.totalMeters }
        let easyDates = trainingDates.filter { $0 != longDate && !sessionDates.contains($0) }

        // Long run: a share of the full week (even if the week is partial), capped by distance, by time
        // on feet, and by what's left of this week's budget.
        let minRun = PlanRules.minimumRunMeters
        let spikeCap = c.recentLongestMeters * PlanRules.maxRunSpike
        // Runs are planned in 500 m steps. A run held back by the spike cap uses 100 m steps instead, so
        // it can still grow by the full 10% rather than a rounded-down 500 m.
        func runMeters(_ meters: Double) -> Double {
            meters >= spikeCap - 1 ? (meters / 100).rounded(.down) * 100 : floorTo500(meters)
        }
        let longCap = min(PlanRules.longRunCapMeters(inputs.goal, inputs.experience),
                          PlanRules.longRunCapSeconds(inputs.goal, inputs.experience) / paces.easy.mid * 1000,
                          spikeCap)
        var longMeters = longDate == nil ? 0 : min(c.volume.meters * PlanRules.longRunShare(runDays: inputs.runDays.count),
                                                   longCap, max(0, weekMeters - sessionMeters))

        // Easy runs share what's left; drop easy days rather than schedule pointlessly short runs.
        let remaining = max(0, weekMeters - sessionMeters - longMeters)
        var easyCount = easyDates.count
        if easyCount > 0, remaining / Double(easyCount) < minRun {
            easyCount = Int(remaining / minRun)
        }
        var perEasy = easyCount > 0 ? remaining / Double(easyCount) : 0

        // The long run should be the week's longest run.
        if longDate != nil, easyCount > 0, perEasy > longMeters {
            let pool = remaining + longMeters
            let equal = pool / Double(easyCount + 1)
            if equal >= minRun {
                longMeters = min(equal, longCap)
                perEasy = (pool - longMeters) / Double(easyCount)
            }
        }

        var limited = false
        let easyCap = min(PlanRules.easyRunCapMeters(inputs.experience), spikeCap)
        if perEasy > easyCap {
            perEasy = easyCap
            limited = true
        }
        // When easy runs are capped, the long run must still not dominate the week.
        if easyCount > 0 || !sessions.isEmpty || c.existing.trainingMeters > 0 {
            let restOfWeek = sessionMeters + Double(easyCount) * runMeters(perEasy) + c.existing.trainingMeters
            if longMeters > restOfWeek {
                longMeters = restOfWeek
                limited = true
            }
        }

        // Prefer easy days that don't follow a hard day, so recovery days become rest days first.
        let hardDates = sessionDates.union(longDate.map { [$0] } ?? [])
        func followsHardDay(_ d: LocalDate) -> Bool {
            hardDates.contains(d.adding(days: -1)) || d.weekday == inputs.longRunDay.next
        }
        let chosenEasy = easyDates
            .sorted { a, b in
                let ah = followsHardDay(a), bh = followsHardDay(b)
                return ah != bh ? !ah : a < b
            }
            .prefix(easyCount)

        var workouts = sessions
        workouts += chosenEasy.map {
            WorkoutFactory.easy($0, meters: min(runMeters(perEasy), quietDayCap($0, raceDate: inputs.raceDate)), paces: paces)
        }
        if let longDate {
            let meters = runMeters(longMeters)
            if meters >= minRun {
                workouts.append(marathonPaceLong
                    ? WorkoutFactory.marathonPaceLong(longDate, meters: meters, paces: paces)
                    : WorkoutFactory.long(longDate, meters: meters, paces: paces))
            }
        }
        if easyDates.isEmpty, remaining > weekMeters * 0.15 { limited = true }
        if c.isRaceWeek {
            workouts.append(WorkoutFactory.race(inputs.raceDate, goal: inputs.goal, paces: paces))
        }
        return Result(workouts: workouts.sorted { $0.date < $1.date }, limitedByAvailability: limited)
    }
}
