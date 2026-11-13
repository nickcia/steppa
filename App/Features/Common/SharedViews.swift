import Charts
import SwiftUI
import PlanEngine

/// Bar chart of nominal weekly volume, coloured by phase.
struct WeeklyVolumeChart: View, Animatable {
    let plan: TrainingPlan
    var highlight: LocalDate?
    /// 0 to 1: bars grow in from the left, one after another (the plan-ready reveal). 1 shows them all.
    var reveal: Double = 1

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }
    @Environment(\.unitSystem) private var units

    private struct Bar: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let distance: Double
        let color: Color
    }

    /// Precomputed bars. Explicit x and y extents matter: on a numeric x axis `width: .ratio` gives
    /// zero-width bars, and xStart/xEnd with a single y draws a horizontal band, so bars are RectangleMarks with all four edges.
    private var bars: [Bar] {
        let currentWeek = highlight?.startOfWeek
        let count = Double(max(plan.weeks.count, 1))
        return plan.weeks.map { week in
            // Each bar takes a quarter of the reveal to grow; later bars start later.
            let start = Double(week.index) / count * 0.75
            let grown = min(max((reveal - start) / 0.25, 0), 1)
            let eased = 1 - pow(1 - grown, 3)
            let x = Double(week.index + 1)
            let emphasised = currentWeek == nil || week.startDate == currentWeek
            return Bar(id: week.index, start: x - 0.36, end: x + 0.36,
                       distance: week.plannedMeters / units.metersPerUnit * eased,
                       color: (plan.isRunWalkWeek(week) ? WorkoutKind.runWalk.color : week.phase.color)
                           .opacity(emphasised ? 1 : 0.55))
        }
    }

    /// Label every 2nd or 4th week so the axis stays readable.
    private var weekTicks: [Int] {
        let step = plan.weeks.count > 12 ? 4 : 2
        return Array(stride(from: 1, through: plan.weeks.count, by: step))
    }

    /// Fixed while bars grow, so the axis doesn't rescale during the reveal.
    private var yMax: Double {
        (plan.weeks.map(\.plannedMeters).max() ?? 1) / units.metersPerUnit * 1.1
    }

    // A little extra room on the right so the last week label isn't clipped.
    private var xDomain: ClosedRange<Double> { 0.5...(Double(plan.weeks.count) + 1) }

    var body: some View {
        Chart(bars) { bar in
            RectangleMark(xStart: .value("Week", bar.start), xEnd: .value("Week", bar.end),
                          yStart: .value("Distance", 0.0), yEnd: .value("Distance", bar.distance))
                .foregroundStyle(bar.color)
                .cornerRadius(3)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yMax)
        .chartXAxis { AxisMarks(values: weekTicks) { value in AxisValueLabel { weekLabel(value) } } }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { distanceLabel(value) }
            }
        }
        .chartYAxisLabel(units.distanceUnit)
        .frame(height: 170)
        .accessibilityLabel(Text("Weekly distance by week"))
    }

    private func weekLabel(_ value: AxisValue) -> Text {
        Text(value.as(Int.self).map { String(localized: "W\($0)") } ?? "")
    }

    private func distanceLabel(_ value: AxisValue) -> Text {
        Text(value.as(Double.self).map { String(Int($0)) } ?? "")
    }
}

extension TrainingPlan {
    /// One of a new runner's run/walk weeks (see `RunWalk`).
    func isRunWalkWeek(_ week: PlanWeek) -> Bool {
        RunWalk.stage(for: week.startDate, inputs: inputs) != nil
    }

    /// Run/walk weeks from the week containing `date` on.
    func runWalkWeeksLeft(from date: LocalDate) -> Int {
        weeks.filter { $0.startDate >= date.startOfWeek && isRunWalkWeek($0) }.count
    }
}

struct PhaseLegend: View {
    let phases: [Phase]
    var runWalk = false

    /// The phases in this plan, with Run/walk first for a new runner's plan.
    init(plan: TrainingPlan) {
        phases = Phase.allCases.filter { p in plan.weeks.contains { $0.phase == p && !plan.isRunWalkWeek($0) } }
        runWalk = plan.weeks.contains { plan.isRunWalkWeek($0) }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if runWalk {
                HStack(spacing: 6) {
                    Circle().fill(WorkoutKind.runWalk.color).frame(width: 8, height: 8)
                    Text("Run/walk").font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
            ForEach(phases, id: \.self) { phase in
                HStack(spacing: 6) {
                    Circle().fill(phase.color).frame(width: 8, height: 8)
                    Text(phase.name).font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }
}

/// Warm-up, blocks and cool-down, with pace ranges.
struct WorkoutStepsView: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        let describer = model.targetDescriber
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(describer.sections(workout)) { section in
                switch section {
                case .single(let line):
                    StepRow(line: line)
                case .repeated(let times, let lines):
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("\(times) ×")
                            .font(.headline.weight(.heavy))
                            .fontDesign(.rounded)
                            .foregroundStyle(Theme.ink)
                        ForEach(lines) { StepRow(line: $0) }
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.subtle, lineWidth: 1.5))
                }
            }
        }
    }
}

private struct StepRow: View {
    let line: WorkoutDescriber.Line

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(line.zone?.color ?? Theme.subtle)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(line.isRecovery ? .regular : .semibold))
                    .foregroundStyle(line.isRecovery ? Theme.secondaryInk : Theme.ink)
                if let detail = line.detail {
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

extension PlanWarning {
    /// `goalSeconds`: the athlete's goal time, so a stretch goal can say how far off it is.
    func message(_ format: DisplayFormat, goalSeconds: Double? = nil) -> String {
        switch self {
        case .shortPlan(let weeks, let recommended):
            String(localized: "You have \(weeks) weeks; \(recommended) is ideal for this distance. The plan is compressed, so aim to arrive healthy rather than chase a time.")
        case .lowStartingVolume(let meters):
            String(localized: "This race usually starts from at least \(format.distance(meters)) a week. The plan builds gradually from where you are; a later race or shorter distance would give you more room.")
        case .volumeLimitedByAvailability:
            String(localized: "Your available days limit how much the plan can build. Adding a run day would allow more volume.")
        case .ambitiousGoal(let predicted):
            Self.stretchGoal(goal: goalSeconds, predicted: predicted)
        case .unusualRaceTime(let meters, let seconds):
            Self.unusualRace(meters: meters, seconds: seconds, format: format)
        case .fewRunDays(let recommended):
            String(localized: "This goal usually needs at least \(recommended) runs a week. With fewer, it's unlikely to be realistic: the plan keeps you safe, but it can't build enough distance. Add run days or choose a gentler goal.")
        case .estimatedFitness:
            String(localized: "Without a recent race, your paces are an estimate. They'll adjust as you complete runs.")
        }
    }

    /// Names the gap between the goal and today's fitness, and keeps it encouraging: a stretch is allowed.
    private static func stretchGoal(goal: Double?, predicted: Double) -> String {
        guard let goal, goal > 0, predicted > goal else {
            return String(localized: "Your goal is a stretch from where your fitness is today (around \(DisplayFormat.clock(predicted))). That's okay: paces start from where you are and speed up as you get fitter.")
        }
        let gap = predicted - goal
        // Round the gap to something a person would say: seconds under 2 minutes, then whole minutes.
        let gapText = gap < 120 ? String(localized: "\(Int(gap.rounded())) seconds")
            : String(localized: "\(Int((gap / 60).rounded())) minutes")
        let share = gap / predicted
        let size = share > 0.10 ? String(localized: "That's a big jump for one training block, and it's worth going for.")
            : String(localized: "That's a real stretch, and very doable with steady training.")
        return String(localized: "Your goal of \(DisplayFormat.clock(goal)) is about \(gapText) faster than the \(DisplayFormat.clock(predicted)) your fitness points to today. \(size) Your paces start from where you are now and get faster as you do, so training stays safe; watch your predicted time close the gap.")
    }

    /// A race result outside what the model covers: says what looked off, and that it's fixable.
    private static func unusualRace(meters: Double, seconds: Double, format: DisplayFormat) -> String {
        // "5K", "10K", but "half marathon" in the middle of a sentence.
        let race = RaceDistance.allCases.first { abs($0.meters - meters) < 1 }
            .map { $0 == .fiveK || $0 == .tenK ? $0.name : $0.name.lowercased() } ?? format.distance(meters)
        let time = DisplayFormat.clock(seconds)
        let pace = format.pace(seconds / (meters / 1000))
        if FitnessModel.score(distanceMeters: meters, timeSeconds: seconds) > FitnessModel.supportedScores.upperBound {
            return String(localized: "Your \(race) time of \(time) works out to \(pace), faster than the world record, so it might be a typo. If it is, go back and fix it. Otherwise your paces start at elite level and adjust after your first few runs.")
        }
        return String(localized: "Your \(race) time of \(time) works out to \(pace), about walking pace, so it might be a typo. If it is, go back and fix it. If not, that's a fine place to start: your paces begin gently and adjust after your first few runs.")
    }
}

/// Short reminder shown in onboarding and settings.
struct DisclaimerText: View {
    var body: some View {
        Text("This app gives general training guidance, not medical advice. Talk to a doctor before starting a new training programme, especially if you have a health condition, an injury or are returning after a long break. Stop and seek advice if you feel pain, dizziness or chest discomfort.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryInk)
    }
}

/// A workout's shape at a glance: one bar per step, as wide as it lasts and as tall as it's hard, in its zone's
/// colour. Easy running is a long low bar; intervals are a row of tall bars with low recoveries between.
struct WorkoutShapeView: View {
    let workout: Workout
    var height: CGFloat = 48
    /// On the dark Today card: no-target steps (walks, jogs) show in white rather than grey.
    var onDark = false

    struct Bar: Identifiable, Equatable {
        let id: Int
        let seconds: Double
        /// 0–1: how hard, for the bar's height.
        let intensity: Double
        let zone: PaceZone?
        let isRecovery: Bool
    }

    /// Every step in order, repeats laid out in full.
    static func bars(_ workout: Workout) -> [Bar] {
        var steps: [(step: Step, recovery: Bool)] = []
        if let warmup = workout.warmup { steps.append((warmup, false)) }
        for block in workout.blocks {
            for _ in 0..<max(1, block.iterations) {
                steps += block.steps.map { ($0.step, $0.purpose == .recovery) }
            }
        }
        if let cooldown = workout.cooldown { steps.append((cooldown, false)) }
        // Run/walk: walking breaks are the low bars, running the slightly taller ones.
        let runWalk = workout.isRunWalkSession
        return steps.enumerated().map { index, item in
            let zone = item.step.target?.zone
            var intensity = Self.intensity(zone)
            if item.recovery { intensity = min(intensity, 0.22) }
            if runWalk { intensity = item.recovery || index == 0 || index == steps.count - 1 ? 0.18 : 0.4 }
            return Bar(id: index, seconds: max(1, item.step.estimatedSeconds), intensity: intensity,
                       zone: runWalk && intensity < 0.3 ? nil : zone, isRecovery: item.recovery)
        }
    }

    static func intensity(_ zone: PaceZone?) -> Double {
        switch zone {
        case nil: 0.2
        case .easy?: 0.36
        case .marathon?: 0.55
        case .race?: 0.66
        case .threshold?: 0.72
        case .interval?, .hill?: 0.88
        case .repetition?, .stride?: 1
        }
    }

    var body: some View {
        let bars = Self.bars(workout)
        let total = bars.reduce(0) { $0 + $1.seconds }
        let gap: CGFloat = bars.count > 40 ? 1 : 2
        GeometryReader { proxy in
            let usable = proxy.size.width - gap * CGFloat(max(0, bars.count - 1))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(bar))
                        .frame(width: max(2, usable * bar.seconds / total), height: max(6, height * bar.intensity))
                }
            }
            .frame(width: proxy.size.width, height: height, alignment: .bottomLeading)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func color(_ bar: Bar) -> Color {
        guard let zone = bar.zone else { return onDark ? .white.opacity(0.35) : Theme.subtle }
        return bar.isRecovery ? zone.color.opacity(0.55) : zone.color
    }
}
