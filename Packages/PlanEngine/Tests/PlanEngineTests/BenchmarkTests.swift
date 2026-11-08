import Foundation
import Testing
@testable import PlanEngine

// Benchmark: compares generated plans with ranges taken from published coaching methods and
// sports-science literature. Only summary numbers are recorded here, never a published plan.
// The method, the sources and the results are written up in docs/PLAN-BENCHMARK.md.
//
// Rules for changing this file:
// - Never widen a range to make a plan pass. A range changes only when the cited source says so.
// - When a metric falls outside its range and the engine is not changed, list it in
//   `ReferenceRanges.knownDeviations` with the reason, and in docs/PLAN-BENCHMARK.md.
//   The test fails if a known deviation stops reproducing, so the list can't go stale.

// MARK: - Reference ranges

struct Reference: Sendable {
    var low: Double
    var high: Double
    /// Short citation keys; full references are in docs/PLAN-BENCHMARK.md.
    var sources: String

    init(_ low: Double, _ high: Double, _ sources: String) {
        self.low = low
        self.high = high
        self.sources = sources
    }

    func contains(_ value: Double) -> Bool { value >= low - 1e-9 && value <= high + 1e-9 }
}

enum Metric: String, CaseIterable, Sendable {
    case planWeeks = "Plan length (weeks)"
    case peakOverStart = "Peak ÷ starting volume"
    case maxWeeklyIncrease = "Largest weekly increase"
    case twoWeekIncrease = "Largest 2-week increase"
    case stepBackEvery = "Step-back every N weeks"
    case longRunShare = "Long-run share (mean)"
    case longRunShareMax = "Long-run share (max)"
    case peakLongRunKm = "Longest long run (km)"
    case peakLongRunMinutes = "Longest long run (min)"
    case sessionSpike = "Run vs longest in 30 days"
    case qualityPerWeek = "Quality sessions / week"
    case belowThresholdShare = "Share below threshold"
    case thresholdSessionShare = "Threshold work ÷ week"
    case intervalSessionShare = "Interval work ÷ week"
    case taperWeeks = "Taper length (weeks)"
    case taperCut = "Taper volume cut"

    var isPercent: Bool {
        switch self {
        case .maxWeeklyIncrease, .twoWeekIncrease, .sessionSpike, .longRunShare, .longRunShareMax, .belowThresholdShare,
             .thresholdSessionShare, .intervalSessionShare, .taperCut: true
        default: false
        }
    }
}

enum ReferenceRanges {
    /// Reference range for a metric, or nil when no citable range exists for that combination.
    static func range(_ metric: Metric, _ goal: RaceDistance, _ level: Experience) -> Reference? {
        switch metric {
        case .planWeeks:
            return switch goal {
            case .fiveK: Reference(6, 12, "Higdon 5K; Pfitzinger FRR")
            case .tenK: Reference(8, 12, "Higdon 10K; Pfitzinger FRR")
            case .halfMarathon: Reference(10, 16, "Higdon HM; Pfitzinger FRR")
            case .marathon: Reference(12, 24, "Higdon M; Pfitzinger AM; Daniels")
            }
        case .peakOverStart:
            // Published plans build from week 1 to peak by roughly 1.2–2.7×.
            return Reference(1.0, 2.7, "Higdon; Pfitzinger AM")
        case .maxWeeklyIncrease:
            // ≤10% per week between loading weeks (Pfitzinger; widely used "10% rule").
            // Small absolute steps are allowed at low volume: see `weeklyIncreaseFloorMeters`.
            return Reference(0, 0.10, "Pfitzinger AM; Buist 2008")
        case .twoWeekIncrease:
            return Reference(0, 0.30, "Nielsen 2014")
        case .stepBackEvery:
            return Reference(3, 4, "Higdon; Daniels")
        case .longRunShare:
            // Daniels: ≤25% (≤30% under 64 km/week). Novice plans (Higdon) reach ~50% at peak.
            return Reference(0.25, 0.50, "Daniels; Higdon")
        case .longRunShareMax:
            return Reference(0, 0.50, "Higdon")
        case .peakLongRunKm:
            // Longest run in published half and marathon plans. 5K/10K plans vary too widely to cite.
            return switch (goal, level) {
            case (.halfMarathon, .beginner): Reference(14, 19, "Higdon HM Novice")
            case (.halfMarathon, .intermediate): Reference(16, 22, "Higdon HM Intermediate; Pfitzinger FRR")
            case (.halfMarathon, .advanced): Reference(19, 26, "Pfitzinger FRR")
            case (.marathon, .beginner): Reference(26, 32, "Hansons; Higdon M Novice")
            case (.marathon, .intermediate): Reference(29, 35, "Higdon M Intermediate; Pfitzinger AM")
            case (.marathon, .advanced): Reference(32, 35, "Pfitzinger AM")
            default: nil
            }
        case .peakLongRunMinutes:
            // Daniels caps long runs at 150 min; marathon plans commonly allow up to ~3 h.
            return goal == .marathon ? Reference(0, 180, "Daniels; Higdon; Pfitzinger AM")
                : Reference(0, 150, "Daniels")
        case .sessionSpike:
            // Overuse injuries rose when one run exceeded the longest run of the previous 30 days by >10%.
            return Reference(0, 0.10, "Frandsen 2025")
        case .qualityPerWeek:
            // Build/peak weeks with 4+ run days. Long runs are not counted.
            return switch level {
            case .beginner: Reference(0, 1, "Higdon Novice; Daniels")
            case .intermediate: Reference(1, 2, "Higdon Intermediate; Daniels 2Q")
            case .advanced: Reference(2, 2, "Daniels 2Q; Pfitzinger")
            }
        case .belowThresholdShare:
            return Reference(0.75, 1.0, "Seiler 2010; Stöggl & Sperlich 2015")
        case .thresholdSessionShare:
            return Reference(0, 0.10, "Daniels")
        case .intervalSessionShare:
            return Reference(0, 0.08, "Daniels")
        case .taperWeeks:
            return switch goal {
            case .fiveK, .tenK: Reference(1, 2, "Mujika 2003; Bosquet 2007")
            case .halfMarathon: Reference(1, 3, "Bosquet 2007")
            case .marathon: Reference(2, 3, "Pfitzinger AM; Smyth 2021")
            }
        case .taperCut:
            return Reference(0.41, 0.60, "Bosquet 2007")
        }
    }

    /// Daniels: add at most about 1 mile per week. Below ~16 km/week a 10% step is smaller than that.
    static let weeklyIncreaseFloorMeters = 1_609.0

    /// Metric outside its published range that the engine deliberately does not change (yet),
    /// keyed as "metric|goal|level". Each one is explained in docs/PLAN-BENCHMARK.md.
    static let knownDeviations: [String: String] = {
        var d: [String: String] = [:]
        let shortTaper = "Race week is light by design (quiet last 3 days), so a 1-week taper cuts more than "
            + "Bosquet's 41–60%. Still within Mujika & Padilla's 60–90%. Not changed: more race-week running "
            + "is not clearly safer."
        for goal in [RaceDistance.fiveK, .tenK] {
            for level in Experience.allCases { d[key(.taperCut, goal, level)] = shortTaper }
        }
        d[key(.taperCut, .marathon, .beginner)] = "Borderline (just under 41% in one grid case): beginners "
            + "step back every 3rd week, so the pre-taper average includes lower weeks."
        // Long runs were raised for the half and marathon (larger long-run share, higher marathon peaks). What
        // still keeps some short is deliberate and safety-related.
        d[key(.peakLongRunKm, .halfMarathon, .beginner)] = "Beginners grow 8% a week with an easier week every "
            + "third week, and no run may exceed the last few weeks' longest by more than 10%; from a low start in "
            + "a 12-week plan the long run reaches about 14 km. Longer plans get closer."
        d[key(.peakLongRunKm, .marathon, .beginner)] = "The 3-hour cap on time on feet binds first: at beginner "
            + "easy paces, 3 hours is about 21–24 km. Published novice plans go further (and longer in time)."
        for level in [Experience.intermediate, .advanced] {
            d[key(.peakLongRunKm, .marathon, level)] = "Short plans and low starts hit the 10% growth rule; "
                + "typical inputs reach the range (intermediate up to 29 km, advanced up to 34 km)."
        }
        return d
    }()

    static func key(_ metric: Metric, _ goal: RaceDistance, _ level: Experience) -> String {
        "\(metric.rawValue)|\(goal.rawValue)|\(level.rawValue)"
    }
}

// MARK: - Metrics

struct PlanMetrics {
    var values: [Metric: Double] = [:]

    init(_ plan: TrainingPlan) {
        let weeks = plan.weeks
        let raceWeek = weeks.count - 1
        let loading = weeks.filter { $0.phase != .taper && !$0.isStepBack }
        func long(_ w: PlanWeek) -> Workout? { w.workouts.first { $0.kind == .long || $0.kind == .marathonPaceLong } }

        values[.planWeeks] = Double(weeks.count)
        if let first = weeks.first, let peak = loading.map(\.targetMeters).max() {
            values[.peakOverStart] = peak / first.targetMeters
        }

        // Progression between consecutive loading weeks (step-backs are recovery, not a new baseline).
        // An increase within the 1-mile floor counts as 0%.
        var maxInc = 0.0, max2 = 0.0
        for i in loading.indices.dropFirst() {
            let prev = loading[i - 1].targetMeters, cur = loading[i].targetMeters
            if cur - prev > ReferenceRanges.weeklyIncreaseFloorMeters + 1 { maxInc = max(maxInc, cur / prev - 1) }
            if i >= 2 { max2 = max(max2, cur / loading[i - 2].targetMeters - 1) }
        }
        values[.maxWeeklyIncrease] = maxInc
        values[.twoWeekIncrease] = max2

        var run = 0, longestRun = 0
        for w in weeks where w.phase != .taper {
            if w.isStepBack { run = 0 } else { run += 1; longestRun = max(longestRun, run) }
        }
        if weeks.contains(where: \.isStepBack) { values[.stepBackEvery] = Double(longestRun + 1) }

        // Full training weeks only: not the race week.
        let full = weeks.filter { $0.index != raceWeek }
        let shares = full.filter { $0.phase != .taper }.compactMap { w -> Double? in
            guard let l = long(w), w.trainingMeters > 0 else { return nil }
            return l.totalMeters / w.trainingMeters
        }
        if !shares.isEmpty {
            values[.longRunShare] = shares.reduce(0, +) / Double(shares.count)
            values[.longRunShareMax] = shares.max()
        }
        let longs = weeks.compactMap(long)
        values[.peakLongRunKm] = (longs.map(\.totalMeters).max() ?? 0) / 1000
        values[.peakLongRunMinutes] = (longs.map(\.totalSeconds).max() ?? 0) / 60

        // Daniels' 2Q plans count a long run with marathon-pace segments as a quality session.
        // Largest single-run spike over the longest run in the previous 30 days. Runs in the first two
        // weeks are skipped (the plan has no history of the athlete's own runs yet); the race is excluded.
        let runs = plan.workouts.filter { $0.kind != .race }
        let firstDate = plan.inputs.startDate
        var spike = 0.0
        for run in runs where firstDate.days(until: run.date) >= 14 {
            let prior = runs.filter { $0.date < run.date && $0.date.days(until: run.date) <= 30 }
            if let longest = prior.map(\.totalMeters).max(), longest > 0 {
                spike = max(spike, run.totalMeters / longest - 1)
            }
        }
        values[.sessionSpike] = spike

        let quality = full.filter { $0.phase == .build || $0.phase == .peak }
            .map { w in w.workouts.filter { [.tempo, .intervals, .marathonPaceLong].contains($0.kind) }.count }
        if let q = quality.max() { values[.qualityPerWeek] = Double(q) }

        let training = plan.workouts.filter { $0.kind != .race }
        let total = training.reduce(0) { $0 + $1.totalMeters }
        let hard = training.reduce(0) { $0 + $1.highIntensityMeters }
        values[.belowThresholdShare] = 1 - hard / total

        // Daniels' caps apply to training weeks. In the taper, volume drops while intensity is kept
        // (Mujika & Padilla 2003; Bosquet 2007), so the share rises by design; the validator's 20% cap
        // still applies there.
        var tShare = 0.0, iShare = 0.0
        for w in weeks where w.trainingMeters > 0 && w.phase != .taper {
            for workout in w.workouts where workout.kind == .tempo || workout.kind == .intervals {
                let share = workout.highIntensityMeters / w.trainingMeters
                if workout.kind == .tempo { tShare = max(tShare, share) } else { iShare = max(iShare, share) }
            }
        }
        values[.thresholdSessionShare] = tShare
        values[.intervalSessionShare] = iShare

        let taper = weeks.filter { $0.phase == .taper }
        values[.taperWeeks] = Double(taper.count)
        let preTaper = weeks.filter { $0.phase != .taper && !$0.isStepBack }.suffix(3)
        if !taper.isEmpty, !preTaper.isEmpty {
            let before = preTaper.reduce(0) { $0 + $1.trainingMeters } / Double(preTaper.count)
            let during = taper.reduce(0) { $0 + $1.trainingMeters } / Double(taper.count)
            values[.taperCut] = 1 - during / before
        }
    }
}

// MARK: - Grid

enum BenchmarkGrid {
    /// Typical starting weekly volume (km) for someone choosing this plan.
    static func typicalStartKm(_ goal: RaceDistance, _ level: Experience) -> Double {
        switch (goal, level) {
        case (.fiveK, .beginner): 10
        case (.fiveK, .intermediate): 25
        case (.fiveK, .advanced): 40
        case (.tenK, .beginner): 15
        case (.tenK, .intermediate): 30
        case (.tenK, .advanced): 50
        case (.halfMarathon, .beginner): 18
        case (.halfMarathon, .intermediate): 35
        case (.halfMarathon, .advanced): 55
        case (.marathon, .beginner): 25
        case (.marathon, .intermediate): 45
        case (.marathon, .advanced): 65
        }
    }

    static func fitness(_ level: Experience) -> FitnessSource {
        switch level {
        case .beginner: .recentRace(.init(.fiveK, timeSeconds: 32 * 60))
        case .intermediate: .recentRace(.init(.tenK, timeSeconds: 48 * 60))
        case .advanced: .recentRace(.init(.halfMarathon, timeSeconds: 85 * 60))
        }
    }

    /// Run days with a Sunday long run.
    static let schedules: [Set<Weekday>] = [
        [.tuesday, .thursday, .sunday],
        [.tuesday, .thursday, .saturday, .sunday],
        [.monday, .tuesday, .thursday, .saturday, .sunday],
        [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday],
    ]
    static let startFactors = [0.8, 1.0, 1.25]
    static let monday = LocalDate(year: 2026, month: 11, day: 2)

    struct Case {
        var goal: RaceDistance
        var level: Experience
        var runDays: Int
        var plan: TrainingPlan
    }

    /// Plans starting on a Monday, racing on a Sunday, at the recommended length and 4 weeks longer.
    static func plans(_ goal: RaceDistance, _ level: Experience) throws -> [Case] {
        var cases: [Case] = []
        for days in schedules {
            for factor in startFactors {
                for weeks in [PlanRules.recommendedWeeks(goal), PlanRules.recommendedWeeks(goal) + 4] {
                    let inputs = PlanInputs(goal: goal, raceDate: monday.adding(days: weeks * 7 - 1),
                                            startDate: monday,
                                            currentWeeklyMeters: typicalStartKm(goal, level) * factor * 1000,
                                            fitness: fitness(level), runDays: days, longRunDay: .sunday,
                                            experience: level)
                    cases.append(Case(goal: goal, level: level, runDays: days.count,
                                      plan: try PlanBuilder.build(inputs)))
                }
            }
        }
        return cases
    }
}

// MARK: - Tests

@Suite struct BenchmarkTests {
    struct Row {
        var metric: Metric
        var goal: RaceDistance
        var level: Experience
        var low: Double
        var high: Double
        var reference: Reference?
        var inRange: Bool { reference.map { $0.contains(low) && $0.contains(high) } ?? true }
    }

    @Test func generatedPlansFallWithinPublishedRanges() throws {
        var rows: [Row] = []
        for goal in RaceDistance.allCases {
            for level in Experience.allCases {
                let cases = try BenchmarkGrid.plans(goal, level)
                for c in cases { #expect(PlanValidator.validate(c.plan).isEmpty) }
                for metric in Metric.allCases {
                    let values: [Double]
                    switch metric {
                    case .planWeeks:
                        // The recommended length, i.e. what the app suggests.
                        values = [Double(PlanRules.recommendedWeeks(goal))]
                    case .qualityPerWeek:
                        values = cases.filter { $0.runDays >= 4 }.compactMap { PlanMetrics($0.plan).values[metric] }
                    default:
                        values = cases.compactMap { PlanMetrics($0.plan).values[metric] }
                    }
                    guard let lo = values.min(), let hi = values.max() else { continue }
                    rows.append(Row(metric: metric, goal: goal, level: level, low: lo, high: hi,
                                    reference: ReferenceRanges.range(metric, goal, level)))
                }
            }
        }

        print(Self.table(rows))

        for row in rows {
            let key = ReferenceRanges.key(row.metric, row.goal, row.level)
            let known = ReferenceRanges.knownDeviations[key]
            switch (row.inRange, known) {
            case (false, nil):
                Issue.record("\(key): \(Self.format(row.low, row.metric))–\(Self.format(row.high, row.metric)) is outside \(Self.format(row.reference!, row.metric)) (\(row.reference!.sources))")
            case (true, .some):
                Issue.record("\(key) is now within range: remove it from knownDeviations and docs/PLAN-BENCHMARK.md")
            default:
                break
            }
        }
    }

    /// Pace relationships for fitness scores from about a 34-minute to a 16-minute 5K.
    @Test func pacesMatchPublishedRelationships() {
        var failures: [String] = []
        for score in stride(from: 30.0, through: 70.0, by: 2.5) {
            let p = PaceTable(score: score, goal: .marathon)
            func racePace(_ meters: Double) -> Double {
                FitnessModel.raceTimeSeconds(distanceMeters: meters, score: score) / (meters / 1000)
            }
            let mp = racePace(42_195), hm = racePace(21_097.5), tenK = racePace(10_000)
            let fiveK = racePace(5_000), threeK = racePace(3_000)
            // Daniels: T ≈ pace held for about an hour. Pfitzinger: LT ≈ 15K to half-marathon pace.
            // Accept 10K to half-marathon pace.
            if !(tenK * 0.99...hm * 1.01).contains(p.threshold.mid) {
                failures.append("score \(score): threshold \(Int(p.threshold.mid)) s/km outside 10K \(Int(tenK))–HM \(Int(hm))")
            }
            // Daniels: I pace could be raced for about 10–15 minutes, whatever the runner's level.
            let tenMin = Self.racePaceForDuration(10 * 60, score), fifteenMin = Self.racePaceForDuration(15 * 60, score)
            if !(tenMin * 0.99...fifteenMin * 1.01).contains(p.interval.mid) {
                failures.append("score \(score): interval \(Int(p.interval.mid)) s/km outside 10–15 min race pace")
            }
            // Pfitzinger: VO₂max intervals at 3K–5K pace. His books address runners who race 3K in about
            // 15 minutes or less (score ≥ 35); slower runners take longer than 15 minutes over 3K.
            if score >= 35, !(threeK * 0.99...fiveK * 1.01).contains(p.interval.mid) {
                failures.append("score \(score): interval \(Int(p.interval.mid)) s/km outside 3K \(Int(threeK))–5K \(Int(fiveK))")
            }
            // Pfitzinger: general aerobic 15–25% slower than marathon pace, recovery slower still.
            // Accept a band midpoint 10–35% slower.
            let easyRatio = p.easy.mid / mp
            if !(1.10...1.35).contains(easyRatio) {
                failures.append("score \(score): easy midpoint \(String(format: "%.2f", easyRatio))× marathon pace")
            }
            // Marathon pace sits between easy and threshold.
            if !(p.threshold.mid < p.marathon.mid && p.marathon.mid < p.easy.fast) {
                failures.append("score \(score): marathon pace not between threshold and easy")
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    /// Pace (s/km) of an all-out effort lasting `seconds`, from the Daniels & Gilbert equations.
    static func racePaceForDuration(_ seconds: Double, _ score: Double) -> Double {
        var lo = 1_000.0, hi = 20_000.0 // metres
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if FitnessModel.raceTimeSeconds(distanceMeters: mid, score: score) < seconds { lo = mid } else { hi = mid }
        }
        return seconds / (lo / 1000)
    }

    // MARK: Formatting

    static func format(_ v: Double, _ metric: Metric) -> String {
        if metric.isPercent { return "\(Int((v * 100).rounded()))%" }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    static func format(_ r: Reference, _ metric: Metric) -> String {
        r.low == 0 ? "≤ \(format(r.high, metric))" : r.low == r.high ? format(r.low, metric)
            : "\(format(r.low, metric))–\(format(r.high, metric))"
    }

    static func table(_ rows: [Row]) -> String {
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        let level = ["beginner": "beg", "intermediate": "int", "advanced": "adv"]
        var out = "\nTrackStar plan benchmark (\(Metric.allCases.count) metrics; ✅ in range, ⚠️ known deviation, ❌ outside)\n"
        out += pad("Metric", 26) + pad("Race", 13) + pad("Lvl", 5) + pad("TrackStar", 13) + pad("Reference", 13) + "Source\n"
        for row in rows {
            let known = ReferenceRanges.knownDeviations[ReferenceRanges.key(row.metric, row.goal, row.level)] != nil
            let mark = row.reference == nil ? "  " : row.inRange ? "✅" : known ? "⚠️" : "❌"
            let value = row.low == row.high ? format(row.low, row.metric)
                : "\(format(row.low, row.metric))–\(format(row.high, row.metric))"
            out += pad(row.metric.rawValue, 26) + pad(row.goal.rawValue, 13) + pad(level[row.level.rawValue]!, 5)
                + pad(value, 13) + pad(row.reference.map { format($0, row.metric) } ?? "—", 13)
                + mark + " " + (row.reference?.sources ?? "informational") + "\n"
        }
        return out
    }
}

// MARK: - Coach review samples

/// Renders the sample plans in docs/PLAN-BENCHMARK.md ("Coach review kit") as Markdown.
/// Run with `STEPPA_PRINT_SAMPLES=1 swift test --filter CoachReviewSamples` and paste the output.
@Suite struct CoachReviewSamples {
    struct Sample {
        var title: String
        var inputs: PlanInputs
    }

    static let monday = LocalDate(year: 2026, month: 11, day: 2)

    static let samples: [Sample] = [
        Sample(title: "A. Half marathon, beginner: 12 weeks, 3 run days, 18 km/week now, 5K in 32:00",
               inputs: PlanInputs(goal: .halfMarathon, raceDate: monday.adding(days: 12 * 7 - 1), startDate: monday,
                                  currentWeeklyMeters: 18_000, fitness: .recentRace(.init(.fiveK, timeSeconds: 32 * 60)),
                                  runDays: [.tuesday, .thursday, .sunday], longRunDay: .sunday, experience: .beginner)),
        Sample(title: "B. Marathon, intermediate: 16 weeks, 5 run days, 45 km/week now, 10K in 48:00",
               inputs: PlanInputs(goal: .marathon, raceDate: monday.adding(days: 16 * 7 - 1), startDate: monday,
                                  currentWeeklyMeters: 45_000, fitness: .recentRace(.init(.tenK, timeSeconds: 48 * 60)),
                                  runDays: [.tuesday, .wednesday, .thursday, .saturday, .sunday], longRunDay: .sunday,
                                  experience: .intermediate)),
        Sample(title: "C. 5K, advanced: 8 weeks, 6 run days, 50 km/week now, 5K in 19:30",
               inputs: PlanInputs(goal: .fiveK, raceDate: monday.adding(days: 8 * 7 - 2), startDate: monday,
                                  currentWeeklyMeters: 50_000, fitness: .recentRace(.init(.fiveK, timeSeconds: 19.5 * 60)),
                                  runDays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday],
                                  longRunDay: .saturday, experience: .advanced)),
        Sample(title: "D. 10K, intermediate: 10 weeks, 4 run days, 25 km/week now, no race result",
               inputs: PlanInputs(goal: .tenK, raceDate: monday.adding(days: 10 * 7 - 1), startDate: monday,
                                  currentWeeklyMeters: 25_000, fitness: .estimated,
                                  runDays: [.monday, .wednesday, .friday, .sunday], longRunDay: .sunday,
                                  experience: .intermediate)),
    ]

    @Test func samplesAreValidAndRender() throws {
        var out = ""
        for sample in Self.samples {
            let plan = try PlanBuilder.build(sample.inputs)
            #expect(PlanValidator.validate(plan).isEmpty)
            out += Self.render(sample.title, plan) + "\n"
        }
        if ProcessInfo.processInfo.environment["STEPPA_PRINT_SAMPLES"] != nil { print(out) }
    }

    static func pace(_ secondsPerKm: Double) -> String {
        let s = Int(secondsPerKm.rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// h:mm for times of an hour or more, otherwise m:ss.
    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? "\(s / 3600):\(String(format: "%02d", s % 3600 / 60))"
            : "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    static func km(_ meters: Double) -> String {
        let v = (meters / 100).rounded() / 10
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }

    static func cell(_ w: Workout) -> String {
        let work = w.blocks.first?.steps.first { $0.purpose == .work }?.step
        let reps = w.blocks.first?.iterations ?? 1
        switch w.kind {
        case .easy:
            let strides = w.blocks.count > 1 ? w.blocks.last.map { " + \($0.iterations)×20 s strides" } ?? "" : ""
            return "E \(km(w.totalMeters))\(strides)"
        case .long: return "L \(km(w.totalMeters))"
        case .marathonPaceLong: return "L \(km(w.totalMeters)) (last \(km(work?.estimatedMeters ?? 0)) @M)"
        case .tempo:
            return reps == 1 ? "T \(km(work?.estimatedMeters ?? 0)) cont. (\(km(w.totalMeters)))"
                : "T \(reps)×\(Int(work?.estimatedMeters ?? 0)) m (\(km(w.totalMeters)))"
        case .intervals: return "I \(reps)×\(Int(work?.estimatedMeters ?? 0)) m (\(km(w.totalMeters)))"
        case .race: return "**RACE**"
        case .hills: return "H \(reps)×\(Int(work?.estimatedSeconds ?? 0)) s uphill (\(km(w.totalMeters)))"
        }
    }

    static func render(_ title: String, _ plan: TrainingPlan) -> String {
        let p = plan.paces
        var out = "#### \(title)\n\n"
        out += "Paces (min/km): easy \(pace(p.easy.fast))–\(pace(p.easy.slow)), marathon \(pace(p.marathon.mid)), "
            + "threshold \(pace(p.threshold.mid)), interval \(pace(p.interval.mid)). "
            + "Predicted race time: \(time(plan.predictedRaceSeconds)).\n\n"
        out += "| Wk | Phase | Mon | Tue | Wed | Thu | Fri | Sat | Sun | km |\n"
        out += "|---|---|---|---|---|---|---|---|---|---|\n"
        for week in plan.weeks {
            let days = (0..<7).map { d -> String in
                let date = week.startDate.adding(days: d)
                return week.workouts.first { $0.date == date }.map(cell) ?? ""
            }
            let phase = week.phase.rawValue + (week.isStepBack ? " (step-back)" : "")
            out += "| \(week.index + 1) | \(phase) | " + days.joined(separator: " | ") + " | \(km(week.trainingMeters)) |\n"
        }
        return out
    }
}
