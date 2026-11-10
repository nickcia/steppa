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
                    .frame(width: 220)
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: TimeOffRoute()) {
                        Image(systemName: "airplane")
                    }
                    .accessibilityLabel("Time off")
                }
            }
            .navigationDestination(for: TimeOffRoute.self) { _ in TimeOffView() }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .navigationDestination(for: RunRoute.self) { RunDetailView(runID: $0.runID) }
            .navigationDestination(for: StrengthSchedule.Session.self) { StrengthDetailView(session: $0) }
        }
    }

    private func overview(_ plan: TrainingPlan) -> some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RaceHeader(plan: plan)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Weekly distance").font(.headline).foregroundStyle(Theme.ink)
                    WeeklyVolumeChart(plan: plan, highlight: model.today)
                    PhaseLegend(plan: plan)
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
                    if plan.runWalkWeeksLeft(from: model.today) > 0 {
                        Metric(value: "\(plan.runWalkWeeksLeft(from: model.today))", label: String(localized: "weeks to 30 min"))
                    } else {
                        Metric(value: DisplayFormat.clock(model.prediction?.seconds ?? plan.predictedRaceSeconds), label: String(localized: "predicted"))
                    }
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
                if isCurrent {
                    SheenPill(text: String(localized: "This week"))
                } else {
                    if week.isStepBack { Pill(text: String(localized: "Recovery week"), color: Theme.secondaryInk) }
                    Pill(text: week.phase.name, color: week.phase.color)
                }
            }
            if isCurrent {
                HStack(spacing: 10) {
                    HeatBar(value: week.workouts.isEmpty ? 0 : Double(done) / Double(week.workouts.count))
                    Text(String(localized: "\(done) of \(week.workouts.count) done"))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                }
                .padding(.vertical, 2)
            }
            ForEach(timeOffHere) { period in
                NavigationLink(value: TimeOffRoute()) {
                    HStack(spacing: 12) {
                        ActivityIcon(symbol: period.reason.symbol, colors: period.reason.colors, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(period.reason.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(period.datesText).font(.caption).foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Text(period.mode == .easyOnly ? String(localized: "Easy only") : String(localized: "Time off"))
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(14)
                    .background(Theme.subtle.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            ForEach(rows, id: \.id) { row in
                switch row {
                case .workout(let workout):
                    NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                        .buttonStyle(.plain)
                case .strength(let session):
                    NavigationLink(value: session) { StrengthRow(session: session) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.card.opacity(isCurrent ? 0 : 0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .currentHighlight(isCurrent, cornerRadius: Theme.Radius.card)
    }

    private enum Row {
        case workout(Workout)
        case strength(StrengthSchedule.Session)
        var id: String { switch self { case .workout(let w): w.id; case .strength(let s): s.id } }
        var date: LocalDate { switch self { case .workout(let w): w.date; case .strength(let s): s.date } }
    }

    /// Time off that overlaps this week.
    private var timeOffHere: [TimeOff] {
        let end = week.startDate.adding(days: 6)
        return model.timeOff.filter { $0.start <= end && ($0.end ?? end) >= week.startDate }
    }

    /// Runs and strength sessions in date order (a strength session sits after the run on the same day).
    private var rows: [Row] {
        let end = week.startDate.adding(days: 7)
        let strength = model.strengthSessions.filter { $0.date >= week.startDate && $0.date < end }
        return (week.workouts.map(Row.workout) + strength.map(Row.strength))
            .enumerated()
            .sorted { a, b in a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset }
            .map(\.element)
    }
}

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(AppModel.self) private var model
    @State private var addingToCalendar = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    KindIcon(kind: workout.kind, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name).font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Theme.ink)
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
                        // Run/walk is by feel: no targets to show as pace, heart rate or speed.
                        if !workout.isRunWalkSession { TargetDisplayPicker() }
                        WorkoutStepsView(workout: workout)
                            .animation(.snappy, value: model.targetDisplay)
                            .contentTransition(.numericText())
                    }
                }
                if workout.date == model.today, workout.kind != .race, model.status(of: workout) == nil {
                    Button { Task { await model.startGuidedRun(workout) } } label: {
                        Label("Start on this phone", systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                }
                WorkoutStatusButtons(workout: workout)
                if let run = model.healthRun(for: workout) {
                    NavigationLink(value: RunRoute(runID: run.id)) {
                        Label("View your run", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.secondary)
                }
                SyncWithWatchButton(workout: workout)
                HStack(spacing: Theme.Spacing.l) {
                    MoveWorkoutButton(workout: workout)
                    if workout.date >= model.today {
                        Button { addingToCalendar = true } label: {
                            Label("Add to Calendar", systemImage: "calendar.badge.plus")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .sheet(isPresented: $addingToCalendar) {
                    AddToCalendarSheet(content: model.calendarEvent(for: workout)).ignoresSafeArea()
                }
                if workout.isCustom { CustomWorkoutActions(workout: workout).padding(.top, Theme.Spacing.s) }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// Switches workout targets between pace, heart rate and treadmill speed, with km/h or mph for the treadmill.
struct TargetDisplayPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Picker("Show targets as", selection: Binding(get: { model.targetDisplay }, set: { model.setTargetDisplay($0) })) {
                ForEach(WorkoutTargetDisplay.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.targetDisplay {
            case .pace:
                EmptyView()
            case .heartRate:
                Text(zonesNote).font(.caption).foregroundStyle(Theme.secondaryInk)
            case .treadmill:
                HStack {
                    Text("Many runners set a 1% incline to match running outside.")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Picker("Treadmill speed", selection: Binding(get: { model.treadmillUnits }, set: { model.setTreadmillUnits($0) })) {
                        Text("km/h").tag(UnitSystem.metric)
                        Text("mph").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    private var zonesNote: String {
        switch model.heartRateZones?.source {
        case .imported?: String(localized: "Zones from your watch, through Intervals.icu. Heart rate takes a minute to settle, so go by feel at the start of each step.")
        case .custom?: String(localized: "Zones you set in Settings. Heart rate takes a minute to settle, so go by feel at the start of each step.")
        case .estimated?: String(localized: "Zones estimated from your maximum heart rate. Import your watch's zones or set your own in Settings.")
        case nil: String(localized: "Add your age in Apple Health, or set your zones in Settings, to see heart-rate targets.")
        }
    }
}
