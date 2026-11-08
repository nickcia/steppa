/// Everything the athlete tells us during onboarding.
public struct PlanInputs: Codable, Hashable, Sendable {
    public var goal: RaceDistance
    public var raceDate: LocalDate
    /// First day the plan may schedule a run (usually today).
    public var startDate: LocalDate
    /// Typical weekly running distance over the last few weeks.
    public var currentWeeklyMeters: Double
    public var fitness: FitnessSource
    /// Days the athlete can run. At least two.
    public var runDays: Set<Weekday>
    /// Must be one of `runDays`.
    public var longRunDay: Weekday
    public var experience: Experience
    /// Optional target. Paces are always based on current fitness, never on the goal,
    /// so an ambitious goal produces a warning rather than unsafe sessions.
    public var goalTimeSeconds: Double?
    /// Holidays, busy stretches, injuries and illness (see `TimeOff`). Optional so plans saved before it existed
    /// still load.
    public var timeOff: [TimeOff]?
    /// Set for someone who can't yet run 30 minutes non-stop: the day their run/walk programme starts. The first
    /// weeks are run/walk sessions building to 30 minutes of continuous running (see `RunWalk`), then the normal
    /// plan takes over. nil for everyone else (and for plans saved before it existed).
    public var runWalkStart: LocalDate?

    public init(
        goal: RaceDistance,
        raceDate: LocalDate,
        startDate: LocalDate,
        currentWeeklyMeters: Double,
        fitness: FitnessSource,
        runDays: Set<Weekday>,
        longRunDay: Weekday,
        experience: Experience,
        goalTimeSeconds: Double? = nil,
        timeOff: [TimeOff]? = nil,
        runWalkStart: LocalDate? = nil
    ) {
        self.goal = goal
        self.raceDate = raceDate
        self.startDate = startDate
        self.currentWeeklyMeters = currentWeeklyMeters
        self.fitness = fitness
        self.runDays = runDays
        self.longRunDay = longRunDay
        self.experience = experience
        self.goalTimeSeconds = goalTimeSeconds
        self.timeOff = timeOff
        self.runWalkStart = runWalkStart
    }
}

public enum PlanError: Error, Equatable, Sendable {
    case raceNotAfterStart
    case tooFewRunDays
    case longRunDayNotARunDay
    case invalidPerformance
    case invalidWeeklyVolume
    /// The race date has passed; there is nothing left to plan.
    case planFinished
}
