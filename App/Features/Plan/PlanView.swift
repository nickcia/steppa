import SwiftUI
import PlanEngine

struct PlanView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case overview, calendar
        var id: String { rawValue }
        var name: String { self == .overview ? String(localized: "Overview") : String(localized: "Calendar") }
    }

    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .overview

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        if let plan = model.plan {
                            switch mode {
                            case .overview: overview(plan)
                            case .calendar: CalendarView()
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .task(id: mode) {
                    // Wait a frame so the lazy stack has laid out before scrolling to this week.
                    guard mode == .overview else { return }
                    try? await Task.sleep(for: .milliseconds(50))
                    if let current = model.week(containing: model.today), current.index > 0 {
                        proxy.scrollTo(current.index, anchor: .top)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // In the bar so it stays reachable after the list scrolls to this week.
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        }
    }

    private func overview(_ plan: TrainingPlan) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RaceHeader(plan: plan)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Weekly distance").font(.headline).foregroundStyle(Theme.ink)
                    WeeklyVolumeChart(plan: plan, highlight: model.today)
                    PhaseLegend(phases: Phase.allCases.filter { p in plan.weeks.contains { $0.phase == p } })
                }
            }
            ForEach(plan.weeks, id: \.index) { week in
                WeekCard(week: week, isCurrent: week.startDate == model.today.startOfWeek)
                    .id(week.index)
            }
        }
    }
}

private struct RaceHeader: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    KindIcon(kind: .race)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.inputs.goal.name).font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(Theme.ink)
                        Text(plan.inputs.raceDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                }
                HStack {
                    Metric(value: "\(max(0, model.today.days(until: plan.inputs.raceDate)))", label: String(localized: "days to go"))
                    Spacer()
                    Metric(value: DisplayFormat.clock(plan.predictedRaceSeconds), label: String(localized: "predicted"))
                    Spacer()
                    if let goal = plan.inputs.goalTimeSeconds {
                        Metric(value: DisplayFormat.clock(goal), label: String(localized: "goal"))
                    } else {
                        Metric(value: "\(plan.weeks.count)", label: String(localized: "weeks"))
                    }
                }
            }
        }
        .padding(.top, Theme.Spacing.s)
    }
}

private struct WeekCard: View {
    let week: PlanWeek
    let isCurrent: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let done = week.workouts.filter { model.status(of: $0) == .done }.count
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Week \(week.index + 1)"))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("\(week.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(week.startDate.adding(days: 6).formatted(.dateTime.day().month(.abbreviated))) · \(model.format.distance(week.plannedMeters))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer()
                if week.isStepBack { Pill(text: String(localized: "Recovery week"), color: Theme.secondaryInk) }
                Pill(text: week.phase.name, color: week.phase.color)
            }
            if isCurrent {
                Text(String(localized: "This week · \(done) of \(week.workouts.count) done"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            ForEach(week.workouts) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                    .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(isCurrent ? Theme.accent : .clear, lineWidth: 2))
    }
}

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    KindIcon(kind: workout.kind, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.kind.name).font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Theme.ink)
                        Text(workout.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .padding(.top, Theme.Spacing.s)
                if let moved = workout.movedFrom {
                    Label(String(localized: "Moved from \(moved.formatted(.dateTime.weekday(.wide)))"), systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        WorkoutMetrics(workout: workout)
                        Text(workout.kind.purpose).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Text("Structure").font(.headline).foregroundStyle(Theme.ink)
                        WorkoutStepsView(workout: workout)
                    }
                }
                WorkoutStatusButtons(workout: workout)
                SendToWatchButton(workout: workout)
                MoveWorkoutButton(workout: workout)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
