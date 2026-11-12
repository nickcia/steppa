import Charts
import SwiftUI
import PlanEngine

struct TrainingProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = model.plan {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Progress")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.top, Theme.Spacing.s)
                        if model.includesGarminRuns {
                            // Garmin asks for this wherever totals or charts are worked out partly from its data.
                            Text("Includes runs recorded on Garmin devices")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        DistanceTrendCard(plan: plan)
                        StatGrid(plan: plan)
                        RecentRuns()
                        PredictionCard(plan: plan)
                        ChangeHistory()
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
            .scrollIndicators(.hidden)
            .statusBarBackdrop()
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: WeeklyDistanceRoute.self) { _ in WeeklyDistanceView() }
            .navigationDestination(for: RunRoute.self) { RunDetailView(runID: $0.runID) }
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

/// Distance per week against the plan.
struct WeekTotals {
    struct Week: Identifiable {
        let id: Int
        let startDate: LocalDate
        let phase: Phase
        let isStepBack: Bool
        let planned: Double
        let completed: Double
        let isCurrent: Bool
        let isFuture: Bool
        var ratio: Double { planned > 0 ? completed / planned : 0 }
    }

    /// Every week of the plan.
    let all: [Week]
    /// Weeks that have started (including this one).
    var weeks: [Week] { all.filter { !$0.isFuture } }
    var current: Week? { all.first(where: \.isCurrent) }

    init(plan: TrainingPlan, model: AppModel) {
        let thisMonday = model.today.startOfWeek
        all = plan.weeks.map { week in
            // Actual distance from Apple Health where available, planned distance for runs ticked off by hand.
            let completed = week.workouts.filter { model.status(of: $0) == .done }
                .reduce(0) { $0 + (model.healthRun(for: $1)?.distanceMeters ?? $1.totalMeters) }
            return Week(id: week.index, startDate: week.startDate, phase: week.phase, isStepBack: week.isStepBack,
                        planned: week.plannedMeters, completed: completed,
                        isCurrent: week.startDate == thisMonday, isFuture: week.startDate > thisMonday)
        }
    }
}

/// One solid bar per week. Weeks gone by show the distance run, coloured by how much of the plan it was (red under
/// half, amber, green on target); weeks to come show the planned distance in grey.
struct WeekBarsChart: View {
    let weeks: [WeekTotals.Week]
    var showsMarker = true

    var body: some View {
        Canvas { context, size in
            guard !weeks.isEmpty else { return }
            let markerSpace: CGFloat = showsMarker ? 22 : 0
            let chartHeight = size.height - markerSpace
            let peak = max(weeks.map { max($0.planned, $0.completed) }.max() ?? 1, 1)
            let column = size.width / CGFloat(weeks.count)
            let barWidth = max(min(column * 0.62, 18), 3)
            func barHeight(_ week: WeekTotals.Week) -> CGFloat {
                let meters = week.isFuture ? week.planned : week.completed
                return max(CGFloat(min(meters, peak) / peak) * chartHeight, 4)
            }
            for (i, week) in weeks.enumerated() {
                let left = CGFloat(i) * column + (column - barWidth) / 2
                let height = barHeight(week)
                let bar = CGRect(x: left, y: size.height - height, width: barWidth, height: height)
                let color: Color = week.isFuture ? Theme.subtle
                    : (week.completed > 0 ? Theme.heat(week.ratio) : Theme.subtle.opacity(0.6))
                context.fill(Path(roundedRect: bar, cornerRadius: min(barWidth / 2, 5)), with: .color(color))
            }

            // The "Now" marker sits above this week's bar, kept inside the chart at either end.
            for (i, week) in weeks.enumerated() where showsMarker && week.isCurrent {
                let center = CGFloat(i) * column + column / 2
                let top = size.height - barHeight(week) - 6
                let label = context.resolve(Text("Now").font(.caption2.weight(.bold)).foregroundStyle(.white))
                let labelSize = label.measure(in: size)
                let width = labelSize.width + 12
                let x = min(max(center - width / 2, 0), size.width - width)
                let pill = CGRect(x: x, y: max(top - labelSize.height - 4, 0), width: width, height: labelSize.height + 4)
                context.fill(Path(roundedRect: pill, cornerRadius: pill.height / 2), with: .color(Theme.accent))
                context.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Opens the week-by-week breakdown.
struct WeeklyDistanceRoute: Hashable {}

/// Every week of the plan: planned and run distance, with the current week highlighted.
struct WeeklyDistanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let plan = model.plan {
                let totals = WeekTotals(plan: plan, model: model)
                let doneToDate = totals.weeks.reduce(0) { $0 + $1.completed }
                let plannedToDate = totals.weeks.reduce(0) { $0 + $1.planned }
                let planTotal = totals.all.reduce(0) { $0 + $1.planned }
                VStack(alignment: .leading, spacing: 12) {
                    Card(padding: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .lastTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.format.distance(doneToDate))
                                        .font(.system(size: 44, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.ink)
                                    Text(String(localized: "run of \(model.format.distance(plannedToDate)) planned so far"))
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                                Spacer()
                                let share = plannedToDate > 0 ? doneToDate / plannedToDate : 0
                                Text("\(Int((share * 100).rounded()))%")
                                    .font(.title2.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.heat(share))
                            }
                            WeekBarsChart(weeks: totals.all)
                                .frame(height: 170)
                            ChartLegend()
                            Text(String(localized: "Whole plan: \(model.format.distance(planTotal)) over \(totals.all.count) weeks."))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    ForEach(totals.all) { week in
                        WeekDistanceRow(week: week)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("Weekly distance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(Theme.subtle, String(localized: "Coming up"))
            item(Theme.red, String(localized: "Under half"))
            item(Theme.amber, String(localized: "Most"))
            item(Theme.green, String(localized: "On target"))
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryInk)
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

private struct WeekDistanceRow: View {
    let week: WeekTotals.Week
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(localized: "Week \(week.id + 1)")).font(.headline).foregroundStyle(Theme.ink)
                Text(week.isStepBack ? String(localized: "\(week.phase.name) · easier week") : week.phase.name)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                if week.isCurrent {
                    SheenPill(text: String(localized: "This week"))
                } else {
                    Text("\(week.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(week.startDate.adding(days: 6).formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                if week.isFuture {
                    Text(model.format.distance(week.planned))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryInk)
                    Text("planned").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                } else {
                    Text(model.format.distance(week.completed))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text(String(localized: "of \(model.format.distance(week.planned))"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer()
                if !week.isFuture {
                    Text("\(Int((week.ratio * 100).rounded()))%")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
            }
            if !week.isFuture { HeatBar(value: week.ratio) }
        }
        .padding(16)
        .background(week.isCurrent ? Color.clear : Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .currentHighlight(week.isCurrent, cornerRadius: Theme.Radius.control)
        .opacity(week.isFuture ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// The headline card: total distance so far, and every week drawn as fine vertical lines whose height is the
/// distance run and whose colour shows how much of the plan was done (red under half, amber, green on target).
private struct DistanceTrendCard: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        let totals = WeekTotals(plan: plan, model: model)
        let completed = totals.weeks.reduce(0) { $0 + $1.completed }
        let planned = totals.weeks.reduce(0) { $0 + $1.planned }
        let share = planned > 0 ? completed / planned : 0
        NavigationLink(value: WeeklyDistanceRoute()) {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Distance so far").font(.title3.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(Int((share * 100).rounded()))%")
                        .font(.title3.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.heat(share))
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(model.format.distance(completed))
                        .font(.system(size: 56, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                WeekBarsChart(weeks: totals.all)
                    .frame(height: 170)
                    .padding(.top, Theme.Spacing.s)
                HStack {
                    Text("Week 1")
                    Spacer()
                    Text(String(localized: "Week \(totals.all.count)"))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryInk)
                ChartLegend().padding(.top, 4)
            }
        }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Four small cards: a big number, a change badge, a note and a red-to-green bar.
private struct StatGrid: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = CompletionStats(plan: plan, statuses: model.effectiveStatuses, today: model.today)
        let totals = WeekTotals(plan: plan, model: model)
        let thisWeek = totals.weeks.last
        let due = plan.workouts.filter { $0.date < model.today && $0.kind != .race }
        let plannedSeconds = due.reduce(0) { $0 + $1.totalSeconds }
        let doneSeconds = due.filter { model.status(of: $0) == .done }
            .reduce(0) { $0 + (model.healthRun(for: $1)?.durationSeconds ?? $1.totalSeconds) }
        let elapsed = Double(plan.inputs.startDate.days(until: model.today))
        let length = Double(max(plan.inputs.startDate.days(until: plan.inputs.raceDate), 1))
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(title: String(localized: "Runs done"), symbol: "checkmark.circle", tint: Theme.green,
                         value: "\(stats.done)", badge: nil,
                         note: String(localized: "of \(stats.due) so far"), progress: stats.rate)
                StatCard(title: String(localized: "This week"), symbol: "figure.run", tint: WorkoutKind.easy.color,
                         value: model.format.distance(thisWeek?.completed ?? 0),
                         badge: nil,
                         note: String(localized: "of \(model.format.distance(thisWeek?.planned ?? 0)) planned"),
                         progress: thisWeek?.ratio ?? 0)
            }
            GridRow {
                StatCard(title: String(localized: "Time running"), symbol: "stopwatch", tint: Theme.amber,
                         value: DisplayFormat.duration(doneSeconds), badge: nil,
                         note: String(localized: "of \(DisplayFormat.duration(plannedSeconds)) planned"),
                         progress: plannedSeconds > 0 ? doneSeconds / plannedSeconds : 0)
                StatCard(title: String(localized: "Plan"), symbol: "flag.checkered", tint: WorkoutKind.race.color,
                         value: "\(Int((min(max(elapsed / length, 0), 1) * 100).rounded()))%", badge: nil,
                         note: String(localized: "\(max(model.today.days(until: plan.inputs.raceDate), 0)) days to go"),
                         progress: elapsed / length)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    let badge: (String, Bool)?
    let note: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(title).font(.headline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(height: 24)
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 38, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                if let badge { DeltaBadge(text: badge.0, isGood: badge.1) }
            }
            Text(note).font(.subheadline).foregroundStyle(Theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                HeatBar(value: progress)
                Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .padding(.top, 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The latest runs from the athlete's devices; each opens its analysis.
private struct RecentRuns: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let runs = model.healthRuns.sorted { $0.date > $1.date }.prefix(8)
        if !runs.isEmpty {
            Text("Recent runs")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, Theme.Spacing.s)
            VStack(spacing: 8) {
                ForEach(Array(runs)) { run in
                    NavigationLink(value: RunRoute(runID: run.id)) { row(run) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ run: CompletedRun) -> some View {
        let analysis = model.analysis(for: run)
        let workout = model.workout(for: run)
        return HStack(spacing: 12) {
            KindIcon(kind: workout?.kind ?? .easy, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout?.name ?? String(localized: "Run"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(run.date.shortDayMonth) · \(model.format.pace(analysis.secondsPerKm))\(analysis.averageHeartRate.map { " · \(Int($0.rounded())) bpm" } ?? "")")
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                if let garmin = model.garminAttribution(for: run) {
                    Text(garmin).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                }
            }
            Spacer()
            ValuePill(text: model.format.distance(run.distanceMeters))
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
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
