import Charts
import SwiftUI
import PlanEngine

struct TrainingProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = model.plan {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        CompletionCard(plan: plan)
                        VolumeHistoryCard(plan: plan)
                        PredictionCard(plan: plan)
                        ChangeHistory()
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .screenBackground()
            .navigationTitle("Progress")
        }
    }
}

/// Counts for workouts that are due (before today).
struct CompletionStats {
    let done: Int
    let skipped: Int
    let missed: Int

    var due: Int { done + skipped + missed }
    var rate: Double { due == 0 ? 0 : Double(done) / Double(due) }

    init(plan: TrainingPlan, statuses: [String: WorkoutStatus], today: LocalDate) {
        let due = plan.workouts.filter { $0.date < today && $0.kind != .race }
        done = due.filter { statuses[$0.id] == .done }.count
        skipped = due.filter { statuses[$0.id] == .skipped }.count
        missed = due.count - done - skipped
    }
}

private struct CompletionCard: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = CompletionStats(plan: plan, statuses: model.effectiveStatuses, today: model.today)
        Card(padding: 20) {
            HStack(spacing: Theme.Spacing.l) {
                ZStack {
                    Circle().stroke(Theme.subtle, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: stats.rate)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((stats.rate * 100).rounded()))%")
                        .font(.title2.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 104, height: 104)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(Int((stats.rate * 100).rounded())) percent of workouts completed"))
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Workouts completed").font(.headline).foregroundStyle(Theme.ink)
                    Metric(value: "\(stats.done) / \(stats.due)", label: String(localized: "done so far"))
                    if stats.skipped + stats.missed > 0 {
                        Text("\(stats.skipped) skipped · \(stats.missed) not marked")
                            .font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }
}

private struct VolumeHistoryCard: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    private struct Point: Identifiable {
        let id: String
        let week: Int
        let series: String
        let distance: Double
    }

    private var points: [Point] {
        let unit = model.units.metersPerUnit
        let planned = String(localized: "Planned"), done = String(localized: "Completed")
        return plan.weeks.filter { $0.startDate <= model.today }.flatMap { week -> [Point] in
            // Actual distance from Apple Health where available, planned distance for runs ticked off by hand.
            let completed = week.workouts.filter { model.status(of: $0) == .done }
                .reduce(0) { $0 + (model.healthRun(for: $1)?.distanceMeters ?? $1.totalMeters) }
            return [Point(id: "p\(week.index)", week: week.index + 1, series: planned, distance: week.plannedMeters / unit),
                    Point(id: "d\(week.index)", week: week.index + 1, series: done, distance: completed / unit)]
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Weekly distance").font(.headline).foregroundStyle(Theme.ink)
                Chart(points) { point in
                    BarMark(x: .value("Week", String(localized: "W\(point.week)")),
                            y: .value("Distance", point.distance))
                        .foregroundStyle(by: .value("Series", point.series))
                        .position(by: .value("Series", point.series))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale([String(localized: "Planned"): Theme.subtle,
                                            String(localized: "Completed"): Theme.accent])
                .chartYAxisLabel(model.units.distanceUnit)
                .frame(height: 180)
            }
        }
    }
}

private struct PredictionCard: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        if let prediction = model.prediction {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("\(plan.inputs.goal.name) prediction").font(.headline).foregroundStyle(Theme.ink)
                    HStack(alignment: .firstTextBaseline) {
                        Metric(value: DisplayFormat.clock(prediction.seconds), label: String(localized: "if you raced today"))
                        Spacer()
                        if let goal = plan.inputs.goalTimeSeconds {
                            Metric(value: DisplayFormat.clock(goal), label: String(localized: "goal"))
                        }
                        Spacer()
                        Metric(value: String(format: "%.1f", prediction.score), label: String(localized: "fitness score"))
                    }
                    Text(confidenceText)
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }

    private var confidenceText: String {
        switch plan.fitness.confidence {
        case .high: String(localized: "Based on a recent race result and your training.")
        case .medium: String(localized: "Based on an older result and your training. A recent race would sharpen this.")
        case .low: String(localized: "An estimate for now. It firms up as you complete sessions or add a race result.")
        }
    }
}

private struct ChangeHistory: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.changes.isEmpty {
            SectionTitle(text: String(localized: "Plan changes")).padding(.top, Theme.Spacing.s)
            ForEach(model.changes) { change in
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(change.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                        ForEach(change.reasons, id: \.self) { reason in
                            Text(reason.message(model.format)).font(.subheadline).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
        }
    }
}
