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
        // Half and marathon peaks are set so long runs can reach the lengths published plans use (Higdon's
        // novice marathon peaks near 64 km with a 32 km long run; Pfitzinger's lowest schedule near 88 km).
        case (.halfMarathon, .beginner): 40
        case (.halfMarathon, .intermediate): 55
        case (.halfMarathon, .advanced): 80
        case (.marathon, .beginner): 60
        case (.marathon, .intermediate): 75
        case (.marathon, .advanced): 100
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

    /// Time on feet caps the long run (Daniels: about 150 minutes; marathon plans go to about 3 hours).
    public static func longRunCapSeconds(_ goal: RaceDistance, _ experience: Experience) -> Double {
        switch (goal, experience) {
        case (.marathon, _): 180 * 60
        case (.halfMarathon, .beginner): 120 * 60
        case (.halfMarathon, _): 135 * 60
        case (_, .beginner): 105 * 60
        case _: 120 * 60
        }
    }

    /// Long run's share of the week. Higher when there are few run days, and for the half and marathon, where
    /// the long run is the key session (Higdon's novice plans let it reach about half the week). The validator
    /// still caps it at half the week, and the 10% spike rule limits how fast it grows.
    public static func longRunShare(runDays: Int, goal: RaceDistance = .tenK) -> Double {
        let (base, cap): (Double, Double) = switch goal {
        case .marathon: (0.42, 0.50)
        case .halfMarathon: (0.38, 0.45)
        case .fiveK, .tenK: (0.30, 0.40)
        }
        return min(base + Double(max(0, 4 - runDays)) * 0.04, cap)
    }

    // MARK: Run days

    /// Run days a week this goal usually needs. Faster goals need more days, because the weekly distance that
    /// supports them doesn't fit safely into fewer runs (the long run would be too big a share of the week).
    /// Coaching rules of thumb (Pfitzinger, Hansons, Daniels), deliberately on the generous side.
    public static func recommendedRunDays(_ goal: RaceDistance, goalTimeSeconds: Double?) -> Int {
        // (time faster than which, days needed), fastest first; otherwise the base.
        let (base, tiers): (Int, [(Double, Int)]) = switch goal {
        case .marathon: (3, [(3 * 3600, 6), (3.5 * 3600, 5), (4.25 * 3600, 4)])
        case .halfMarathon: (3, [(1.4 * 3600, 5), (1.75 * 3600, 4)])
        case .tenK: (3, [(38 * 60, 5), (48 * 60, 4)])
        case .fiveK: (2, [(18 * 60, 5), (22 * 60, 4), (27 * 60, 3)])
        }
        guard let goal = goalTimeSeconds, goal > 0 else { return base }
        return tiers.first { goal <= $0.0 }?.1 ?? base
    }

    // MARK: Strides

    /// Strides: short accelerations after an easy run, for speed and form without fatigue (Daniels; Pfitzinger).
    public static let strideSeconds = 20.0
    public static let strideRecoverySeconds = 60.0
    /// Easy running before the strides, so they're done warm.
    public static let strideWarmUpMeters = 1_500.0

    public static func strideReps(_ experience: Experience) -> Int {
        switch experience {
        case .beginner: 4
        case .intermediate: 5
        case .advanced: 6
        }
    }

    /// Easy runs a week that finish with strides. Beginners start after their first two weeks.
    public static func stridesPerWeek(phase: Phase, experience: Experience, weekIndex: Int) -> Int {
        if experience == .beginner { return weekIndex < 2 ? 0 : 1 }
        switch phase {
        case .base, .taper: return 1
        case .build, .peak: return 2
        }
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
