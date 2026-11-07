/// All the tunable training rules in one place. `docs/PLAN-RULES.md` describes them in plain English;
/// keep the two in sync.
public enum PlanRules {
    // MARK: Plan length

    public static func recommendedWeeks(_ goal: RaceDistance) -> Int {
        switch goal {
        case .fiveK: 8
        case .tenK: 10
        case .halfMarathon: 12
        case .marathon: 16
        }
    }

    /// Below this many weeks the plan gets a `shortPlan` warning.
    public static func minimumWeeks(_ goal: RaceDistance) -> Int {
        switch goal {
        case .fiveK: 4
        case .tenK: 6
        case .halfMarathon: 8
        case .marathon: 12
        }
    }

    /// Volume multipliers for the taper weeks, relative to the last loading week.
    /// The last entry is race week (excluding the race itself).
    public static func taperFactors(_ goal: RaceDistance) -> [Double] {
        switch goal {
        case .fiveK, .tenK: [0.6]
        case .halfMarathon: [0.7, 0.45]
        case .marathon: [0.75, 0.6, 0.4]
        }
    }

    // MARK: Volume

    public static let minimumStartingMeters = 8_000.0
    public static let maximumCurrentMeters = 300_000.0

    /// Below this current weekly volume a `lowStartingVolume` warning is shown.
    public static func recommendedCurrentMeters(_ goal: RaceDistance) -> Double {
        switch goal {
        case .fiveK: 0
        case .tenK: 10_000
        case .halfMarathon: 15_000
        case .marathon: 25_000
        }
    }

    static func peakTargetMeters(_ goal: RaceDistance, _ experience: Experience) -> Double {
        let km: Double = switch (goal, experience) {
        case (.fiveK, .beginner): 25
        case (.fiveK, .intermediate): 40
        case (.fiveK, .advanced): 60
        case (.tenK, .beginner): 30
        case (.tenK, .intermediate): 50
        case (.tenK, .advanced): 70
        case (.halfMarathon, .beginner): 35
        case (.halfMarathon, .intermediate): 55
        case (.halfMarathon, .advanced): 80
        case (.marathon, .beginner): 45
        case (.marathon, .intermediate): 65
        case (.marathon, .advanced): 95
        }
        return km * 1000
    }

    /// Peak weekly volume: the target for this goal and level, or the athlete's current volume
    /// if that's higher (we don't force a big drop), capped at 130% of the target.
    public static func peakMeters(_ goal: RaceDistance, _ experience: Experience, currentMeters: Double) -> Double {
        let target = peakTargetMeters(goal, experience)
        return min(max(target, currentMeters), target * 1.3)
    }

    public static func startMeters(currentMeters: Double, peakMeters: Double) -> Double {
        min(max(currentMeters, minimumStartingMeters), peakMeters)
    }

    public static func weeklyGrowthRate(_ experience: Experience) -> Double {
        experience == .beginner ? 0.08 : 0.10
    }

    /// At very low volume a percentage rule is needlessly slow, so a small absolute increase is allowed.
    /// Small enough that two loading weeks never add more than 30% (Nielsen et al. 2014), even from 8 km.
    public static let minimumIncreaseMeters = 1_000.0

    /// Largest volume increase over the last loading week that any plan may contain.
    /// The validator checks every plan against this.
    public static func maximumAllowedVolume(after previous: Double) -> Double {
        max(previous * 1.10, previous + minimumIncreaseMeters)
    }

    static func nextLoadingVolume(after previous: Double, _ experience: Experience) -> Double {
        previous + max(previous * weeklyGrowthRate(experience), minimumIncreaseMeters)
    }

    /// A step-back week comes after this many loading weeks.
    public static func loadingWeeksBeforeStepBack(_ experience: Experience) -> Int {
        experience == .beginner ? 2 : 3
    }

    public static let stepBackFactor = 0.8

    // MARK: Runs

    public static let minimumRunMeters = 3_000.0

    /// No run may be longer than this multiple of the longest run in the last few weeks. Overuse injuries
    /// rose when a single run exceeded the longest run of the previous 30 days by more than 10%
    /// (Frandsen et al. 2025).
    public static let maxRunSpike = 1.10
    /// Look-back for `maxRunSpike`, in days before the week's Monday. 24 days keeps every run in the week
    /// within 30 days of the runs it is compared with.
    static let recentRunWindowDays = 24

    public static func easyRunCapMeters(_ experience: Experience) -> Double {
        switch experience {
        case .beginner: 10_000
        case .intermediate: 14_000
        case .advanced: 18_000
        }
    }

    public static func longRunCapMeters(_ goal: RaceDistance, _ experience: Experience) -> Double {
        let km: Double = switch (goal, experience) {
        case (.fiveK, .beginner): 12
        case (.fiveK, .intermediate): 16
        case (.fiveK, .advanced): 18
        case (.tenK, .beginner): 14
        case (.tenK, .intermediate): 18
        case (.tenK, .advanced): 20
        case (.halfMarathon, .beginner): 18
        case (.halfMarathon, .intermediate): 21
        case (.halfMarathon, .advanced): 24
        case (.marathon, .beginner): 28
        case (.marathon, .intermediate): 32
        case (.marathon, .advanced): 34
        }
        return km * 1000
    }

    public static func longRunCapSeconds(_ goal: RaceDistance, _ experience: Experience) -> Double {
        switch (goal, experience) {
        case (.marathon, .beginner): 165 * 60
        case (.marathon, _): 180 * 60
        case (_, .beginner): 105 * 60
        case _: 120 * 60
        }
    }

    /// Long run's share of the week. Higher when there are few run days.
    public static func longRunShare(runDays: Int) -> Double {
        min(0.30 + Double(max(0, 4 - runDays)) * 0.05, 0.40)
    }

    // MARK: Intensity

    /// At most this share of weekly distance at threshold pace or faster.
    public static let maxHighIntensityShare = 0.20
    /// Work-portion budgets as a share of the week.
    static let thresholdBudgetShare = 0.10
    static let intervalBudgetShare = 0.08
    static let thresholdBudgetCap = 10_000.0
    static let intervalBudgetCap = 8_000.0

    /// No hard session (including long runs) on the three days before the race.
    public static let raceTaperQuietDays = 3

    public static func qualitySessions(phase: Phase, experience: Experience, runDays: Int, isStepBack: Bool) -> Int {
        var count: Int = switch (phase, experience) {
        case (.base, .beginner): 0
        case (.base, _): 1
        case (.build, .beginner), (.peak, .beginner): 1
        case (.build, _), (.peak, _): runDays >= 4 ? 2 : 1
        case (.taper, _): 1
        }
        if runDays <= 2 { count = 0 }
        if isStepBack { count = max(0, count - 1) }
        return count
    }
}
