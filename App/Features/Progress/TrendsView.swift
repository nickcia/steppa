import Charts
import SwiftUI
import PlanEngine

extension AppModel {
    /// The fitness score now: the plan's, raised by any strong recent run.
    var currentFitnessScore: Double? { prediction?.score }

    /// The fitness score as it stood on an earlier day, for showing which way it's heading.
    func fitnessScore(asOf date: LocalDate) -> Double? {
        guard let plan, plan.runWalkWeeksLeft(from: date) == 0 else { return nil }
        return RacePredictor.predict(plan.inputs.goal, fitness: plan.fitness, recentRuns: trainingLog.runs, asOf: date).score
    }

    /// Threshold pace (s/km) for a fitness score.
    func thresholdPace(score: Double) -> Double? {
        guard let plan else { return nil }
        return PaceTable(score: score, goal: plan.inputs.goal).threshold.mid
    }

    /// Daily fitness, fatigue and form from every run TrackStar knows about, scored against threshold pace.
    var trainingLoad: [TrainingLoad.Day] {
        guard let threshold = (currentFitnessScore ?? plan?.fitness.score).flatMap(thresholdPace(score:)) else { return [] }
        return TrainingLoad.days(healthRuns, thresholdSecondsPerKm: threshold, through: today)
    }
}

/// How training is going over time: this week's minutes, fitness against fatigue, and fitness score with threshold pace.
struct TrendsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text("Trends")
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.top, Theme.Spacing.s)
        WeekMinutesCard()
        FitnessFatigueCard()
        FitnessScoreCard()
    }
}

/// Planned and completed running minutes this week.
private struct WeekMinutesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let week = model.today.startOfWeek
        let planned = (model.plan?.workouts ?? []).filter { $0.date.startOfWeek == week }.reduce(0) { $0 + $1.totalSeconds }
        let done = model.healthRuns.filter { $0.date.startOfWeek == week }.reduce(0) { $0 + $1.durationSeconds }
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("This week", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline).foregroundStyle(Theme.ink)
                HStack(alignment: .bottom) {
                    figure(String(localized: "Planned"), minutes: planned, color: Theme.ink)
                    figure(String(localized: "Done"), minutes: done, color: Theme.green)
                }
                HeatBar(value: planned > 0 ? done / planned : 0)
            }
        }
    }

    private func figure(_ label: String, minutes seconds: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.secondaryInk)
            // One run of text, so the unit sits a normal word space after the number.
            (Text("\(Int((seconds / 60).rounded()))").font(.system(size: 34, weight: .semibold)).foregroundStyle(color)
             + Text(" min").font(.subheadline).foregroundStyle(Theme.secondaryInk))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fitness (42-day load), fatigue (7-day load) and form (the balance), with which way each moved this week.
private struct FitnessFatigueCard: View {
    @Environment(AppModel.self) private var model
    @State private var explaining = false

    private static let fatigueColor = Theme.red
    private static let fitnessColor = Theme.green
    private static let formColor = Color(hex: 0x3B82F6)

    var body: some View {
        let days = model.trainingLoad
        if let now = days.last {
            let weekAgo = days.count > 7 ? days[days.count - 8] : days.first!
            let state = TrainingLoad.State(form: now.form)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Fitness, fatigue and form", systemImage: "waveform.path.ecg")
                            .font(.headline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(name(state))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Theme.subtle, in: Capsule())
                    }
                    HStack {
                        number(String(localized: "Fatigue"), now.fatigue, weekAgo.fatigue, Self.fatigueColor)
                        number(String(localized: "Fitness"), now.fitness, weekAgo.fitness, Self.fitnessColor)
                        number(String(localized: "Form"), now.form, weekAgo.form, Self.formColor)
                    }
                    chart(Array(days.suffix(90)))
                    Text(advice(state))
                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("How this works") { explaining = true }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .sheet(isPresented: $explaining) { TrainingLoadAboutView() }
        }
    }

    private func number(_ label: String, _ value: Double, _ before: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.secondaryInk)
            HStack(spacing: 4) {
                Text("\(Int(value.rounded()))").font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(color)
                let change = value - before
                if abs(change) >= 1 {
                    Image(systemName: change > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .accessibilityLabel(change > 0 ? String(localized: "up this week") : String(localized: "down this week"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ days: [TrainingLoad.Day]) -> some View {
        Chart {
            ForEach(days, id: \.date) { day in
                LineMark(x: .value("Day", day.date.date()), y: .value("Load", day.fitness), series: .value("Line", "Fitness"))
                    .foregroundStyle(Self.fitnessColor)
                LineMark(x: .value("Day", day.date.date()), y: .value("Load", day.fatigue), series: .value("Line", "Fatigue"))
                    .foregroundStyle(Self.fatigueColor.opacity(0.7))
                AreaMark(x: .value("Day", day.date.date()), y: .value("Form", day.form))
                    .foregroundStyle(Self.formColor.opacity(0.15))
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.hairline)
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .chartYAxis(.hidden)
        .frame(height: 110)
        .accessibilityHidden(true)
    }

    private func name(_ state: TrainingLoad.State) -> String {
        switch state {
        case .overreaching: String(localized: "Very tired")
        case .building: String(localized: "Building")
        case .balanced: String(localized: "Balanced")
        case .fresh: String(localized: "Fresh")
        case .detraining: String(localized: "Resting")
        }
    }

    private func advice(_ state: TrainingLoad.State) -> String {
        switch state {
        case .overreaching: String(localized: "You're carrying a lot of fatigue. Keep easy days truly easy, and take a rest day if your legs feel heavy.")
        case .building: String(localized: "Fatigue is above fitness, as it should be mid-block: this is where fitness grows.")
        case .balanced: String(localized: "Training and recovery are in balance.")
        case .fresh: String(localized: "You're fresh: a good place to be before a race or a hard session.")
        case .detraining: String(localized: "You've been resting for a while, so fitness is starting to slip. A few easy runs will turn it around.")
        }
    }
}

/// Fitness score (an effective VO₂max from your runs) and the threshold pace it gives.
private struct FitnessScoreCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let score = model.currentFitnessScore, let threshold = model.thresholdPace(score: score) {
            let before = model.fitnessScore(asOf: model.today.adding(days: -28))
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Fitness score and threshold", systemImage: "figure.run")
                        .font(.headline).foregroundStyle(Theme.ink)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FITNESS SCORE").font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.secondaryInk)
                            HStack(spacing: 6) {
                                Text(score.formatted(.number.precision(.fractionLength(1))))
                                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.ink)
                                if let before { change(score - before, higherIsBetter: true) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("THRESHOLD PACE").font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.secondaryInk)
                            HStack(spacing: 6) {
                                Text(model.format.targetPace(threshold))
                                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                if let before, let old = model.thresholdPace(score: before) {
                                    // A faster threshold is a lower number of seconds.
                                    change(old - threshold, higherIsBetter: true, hidden: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Your fitness score works like a VO₂max estimate, from your plan and your best recent runs. Arrows compare with 4 weeks ago.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func change(_ delta: Double, higherIsBetter: Bool, hidden: Bool = false) -> some View {
        if abs(delta) >= 0.1 {
            let good = (delta > 0) == higherIsBetter
            Image(systemName: delta > 0 ? (hidden ? "arrow.up" : "arrow.up") : "arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(good ? Theme.green : Theme.red, in: Circle())
                .accessibilityLabel(good ? String(localized: "better than 4 weeks ago") : String(localized: "lower than 4 weeks ago"))
        }
    }
}

struct TrainingLoadAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Each run gets a load score from how long and how hard it was: an hour at your threshold pace is 100, an easy hour about 60.")
                    Text("Fitness is your average load over the last 6 weeks: it rises slowly with steady training. Fatigue is the same over the last week: it rises and falls quickly. Form is fitness minus fatigue.")
                    Text("In a training block, fatigue sits above fitness and form is negative: that's normal. Before a race, the taper lets fatigue fall so form turns positive.")
                } header: {
                    Text("How it works")
                }
                Section {
                    Text("Load is worked out from pace, so hills, heat and trails count for less than they felt. Use the trend, not the exact number. It takes about 6 weeks of runs for fitness to settle.")
                } header: {
                    Text("Limits")
                }
                Section {
                    Text("Based on the fitness–fatigue model (Banister, 1975) as used by most training apps, with a running stress score from pace against threshold pace.")
                        .font(.footnote)
                } header: {
                    Text("Sources")
                }
            }
            .navigationTitle("Fitness and fatigue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
