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
        let weekMeters = c.volume.meters * min(1, Double(trainingDates.count) / Double(inputs.runDays.count))
        // The last days before the race are quiet: no long run, no sessions, short easy runs only.
        let quietStart = inputs.raceDate.adding(days: -PlanRules.raceTaperQuietDays)
        let longDate = trainingDates.first { $0.weekday == inputs.longRunDay && $0 < quietStart && !c.isRaceWeek }

        let marathonPaceLong = inputs.goal == .marathon && c.phase == .peak && !c.volume.isStepBack
            && inputs.experience != .beginner && longDate != nil
        var maxSessions = PlanRules.qualitySessions(phase: c.phase, experience: inputs.experience,
                                                    runDays: inputs.runDays.count, isStepBack: c.volume.isStepBack)
        if marathonPaceLong || c.isRaceWeek { maxSessions = min(maxSessions, 1) }

        let latestSessionDate = min(lastTrainingDay, quietStart.adding(days: -1))
        let sessionDates = chooseSessionDates(trainingDates.filter { $0 != longDate && $0 <= latestSessionDate },
                                              longRunDay: inputs.longRunDay, max: maxSessions)
        let kinds = sessionKinds(phase: c.phase, goal: inputs.goal, weekIndex: c.weekIndex, count: sessionDates.count)

        // Drop quality sessions one at a time until the week fits the volume and intensity limits.
        for count in stride(from: sessionDates.count, through: 0, by: -1) {
            let attempt = assemble(c, trainingDates: trainingDates, weekMeters: weekMeters, longDate: longDate,
                                   marathonPaceLong: marathonPaceLong,
                                   sessions: Array(zip(sessionDates.prefix(count), kinds)))
            let training = attempt.workouts.filter { $0.kind != .race }
            let trainingMeters = training.reduce(0) { $0 + $1.totalMeters }
            let hardMeters = training.reduce(0) { $0 + $1.highIntensityMeters }
            let fits = trainingMeters <= weekMeters * 1.05 + 500
                && hardMeters <= trainingMeters * PlanRules.maxHighIntensityShare
            if fits || count == 0 { return attempt }
        }
        preconditionFailure("unreachable")
    }

    /// Picks days for quality sessions: never next to the long-run weekday or each other, even across
    /// week boundaries, preferring days furthest from the long run.
    static func chooseSessionDates(_ candidates: [LocalDate], longRunDay: Weekday, max: Int) -> [LocalDate] {
        let ranked = candidates
            .filter { $0.weekday.circularDistance(to: longRunDay) >= 2 }
            .sorted {
                let a = $0.weekday.circularDistance(to: longRunDay), b = $1.weekday.circularDistance(to: longRunDay)
                return a != b ? a > b : $0 < $1
            }
        var chosen: [LocalDate] = []
        for date in ranked where chosen.count < max {
            if chosen.allSatisfy({ $0.weekday.circularDistance(to: date.weekday) >= 2 }) {
                chosen.append(date)
            }
        }
        return chosen.sorted()
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
        longDate: LocalDate?,
        marathonPaceLong: Bool,
        sessions planned: [(LocalDate, SessionKind)]
    ) -> Result {
        let inputs = c.inputs
        let paces = c.paces
        let sessionContext = WorkoutFactory.SessionContext(weekMeters: weekMeters, goal: inputs.goal,
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

        // Long run: a share of the week, capped by distance and by time on feet.
        let minRun = PlanRules.minimumRunMeters
        let longCap = min(PlanRules.longRunCapMeters(inputs.goal, inputs.experience),
                          PlanRules.longRunCapSeconds(inputs.goal, inputs.experience) / paces.easy.mid * 1000)
        var longMeters = longDate == nil ? 0 : min(weekMeters * PlanRules.longRunShare(runDays: inputs.runDays.count), longCap)

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
        let easyCap = PlanRules.easyRunCapMeters(inputs.experience)
        if perEasy > easyCap {
            perEasy = easyCap
            limited = true
        }
        // When easy runs are capped, the long run must still not dominate the week.
        if easyCount > 0 || !sessions.isEmpty {
            let restOfWeek = sessionMeters + Double(easyCount) * floorTo500(perEasy)
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
            WorkoutFactory.easy($0, meters: min(floorTo500(perEasy), quietDayCap($0, raceDate: inputs.raceDate)), paces: paces)
        }
        if let longDate {
            let meters = floorTo500(longMeters)
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
