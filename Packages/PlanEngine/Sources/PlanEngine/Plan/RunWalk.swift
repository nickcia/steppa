/// The start of a plan for someone who can't yet run 30 minutes non-stop.
///
/// Three run/walk sessions a week, each a 5-minute walk, repeats of running and walking, and a 5-minute walk. The
/// running grows and the walking shrinks week by week until the athlete runs 30 minutes without stopping (the usual
/// shape of beginner programmes: short run intervals, walk breaks no longer than about two minutes, roughly nine
/// weeks). Then the normal plan takes over from there. Running is by feel ("you could hold a conversation"), so the
/// steps carry no pace target. With less time before the race the stages are compressed, and weeks lost to time off
/// don't count, so the athlete picks up where they left off.
public enum RunWalk {
    public struct Stage: Hashable, Sendable {
        public var reps: Int
        public var runSeconds: Double
        /// 0 for the last stages, which are one continuous run.
        public var walkSeconds: Double

        public var isContinuous: Bool { walkSeconds == 0 }
        public var runningSeconds: Double { Double(reps) * runSeconds }
    }

    public static let stages: [Stage] = [
        Stage(reps: 8, runSeconds: 60, walkSeconds: 90),
        Stage(reps: 7, runSeconds: 90, walkSeconds: 90),
        Stage(reps: 6, runSeconds: 120, walkSeconds: 90),
        Stage(reps: 5, runSeconds: 180, walkSeconds: 90),
        Stage(reps: 4, runSeconds: 300, walkSeconds: 120),
        Stage(reps: 3, runSeconds: 480, walkSeconds: 120),
        Stage(reps: 2, runSeconds: 720, walkSeconds: 120),
        Stage(reps: 1, runSeconds: 25 * 60, walkSeconds: 0),
        Stage(reps: 1, runSeconds: 30 * 60, walkSeconds: 0),
    ]

    public static let sessionsPerWeek = 3
    static let walkWarmUpSeconds = 300.0
    /// A brisk walk, for distance estimates.
    static let walkSecondsPerKm = 600.0

    /// Weeks of run/walk before race week: all the stages if there's time, fewer (compressed) if not.
    /// A first week with fewer than two run days left doesn't count (it isn't enough to move a stage on).
    static func programWeeks(_ inputs: PlanInputs) -> Int {
        guard let start = inputs.runWalkStart else { return 0 }
        let weeks = start.startOfWeek.days(until: inputs.raceDate.startOfWeek) / 7
        let available = (0..<max(0, weeks)).filter { index in
            let monday = start.startOfWeek.adding(days: 7 * index)
            return (0..<7).filter { monday.adding(days: $0) >= start && inputs.runDays.contains(monday.adding(days: $0).weekday) }.count >= 2
        }.count
        return min(stages.count, available)
    }

    /// The stage for the week starting `monday`, or nil when that week is normal training (or race week).
    public static func stage(for monday: LocalDate, inputs: PlanInputs) -> Stage? {
        guard let start = inputs.runWalkStart, monday >= start.startOfWeek,
              monday < inputs.raceDate.startOfWeek else { return nil }
        let count = programWeeks(inputs)
        guard count > 0 else { return nil }
        // Weeks the athlete could actually train in (two or more free run days) move them on a stage.
        var done = 0
        var week = start.startOfWeek
        while week < monday {
            let free = (0..<7).map { week.adding(days: $0) }.filter {
                $0 >= start && inputs.runDays.contains($0.weekday) && !inputs.isUnavailable($0)
            }
            if free.count >= 2 { done += 1 }
            week = week.adding(days: 7)
        }
        guard done < count else { return nil }
        // Compressed: spread the weeks across the stages, always ending at 30 minutes non-stop.
        let index = count == 1 ? stages.count - 1
            : Int((Double(done) * Double(stages.count - 1) / Double(count - 1)).rounded())
        return stages[index]
    }

    /// Weekly distance at the end of run/walk (three 30-minute easy runs), where the normal plan picks up.
    static func handoffMeters(_ paces: PaceTable) -> Double {
        Double(sessionsPerWeek) * 30 * 60 / paces.easy.slow * 1000
    }

    /// A week of run/walk sessions on the free run days, spread out (the long-run day first, then days furthest
    /// from the others), never more than `sessionsPerWeek`. `alreadyDone` counts runs earlier in a re-planned week.
    static func layout(_ c: WeekLayout.Context, stage: Stage) -> WeekLayout.Result {
        let inputs = c.inputs
        let last = c.monday.adding(days: 6)
        let free = (0..<7).map { c.monday.adding(days: $0) }.filter {
            $0 >= inputs.startDate && $0 <= last && inputs.runDays.contains($0.weekday) && !inputs.isUnavailable($0)
        }
        let wanted = max(0, sessionsPerWeek - c.existing.runCount)
        var chosen: [LocalDate] = []
        if let long = free.first(where: { $0.weekday == inputs.longRunDay }), wanted > 0 { chosen.append(long) }
        while chosen.count < wanted {
            // Furthest from the days already chosen (and from runs already done this week).
            let taken = chosen + Array(c.existing.hardDates)
            let candidates = free.filter { !chosen.contains($0) }
            guard let next = candidates.max(by: { a, b in
                gap(a, taken) < gap(b, taken) || (gap(a, taken) == gap(b, taken) && a > b)
            }) else { break }
            chosen.append(next)
        }
        let workouts = chosen.sorted().map { session($0, stage: stage, paces: c.paces) }
        return WeekLayout.Result(workouts: workouts, limitedByAvailability: false)
    }

    private static func gap(_ date: LocalDate, _ taken: [LocalDate]) -> Int {
        taken.map { abs($0.days(until: date)) }.min() ?? 7
    }

    static func session(_ date: LocalDate, stage: Stage, paces: PaceTable) -> Workout {
        let run = WorkoutFactory.step(seconds: stage.runSeconds, zone: nil, paces: paces)
        if stage.isContinuous {
            return Workout(date: date, kind: .easy, warmup: walk(walkWarmUpSeconds),
                           blocks: [IntervalBlock(iterations: 1, steps: [IntervalStep(purpose: .work, step: run)])],
                           cooldown: walk(walkWarmUpSeconds))
        }
        return Workout(date: date, kind: .runWalk, warmup: walk(walkWarmUpSeconds),
                       blocks: [IntervalBlock(iterations: stage.reps, steps: [
                           IntervalStep(purpose: .work, step: run),
                           IntervalStep(purpose: .recovery, step: walk(stage.walkSeconds)),
                       ])],
                       cooldown: walk(walkWarmUpSeconds))
    }

    private static func walk(_ seconds: Double) -> Step {
        Step(goal: .time(seconds: seconds), target: nil,
             estimatedMeters: seconds / walkSecondsPerKm * 1000, estimatedSeconds: seconds)
    }
}

extension Workout {
    /// Walking steps (warm-up, cool-down and walk breaks of a run/walk session) have no target and a walking pace.
    public var isRunWalkSession: Bool { kind == .runWalk || (kind == .easy && warmup != nil && warmup?.target == nil) }
}
