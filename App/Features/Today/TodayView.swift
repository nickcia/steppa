import SwiftUI
import PlanEngine

struct TodayView: View {
    @Environment(AppModel.self) private var model
    /// Changes when the Today tab is tapped while already showing, to jump back to today.
    var resetSignal = 0
    @State private var selected: LocalDate = .today
    @State private var path = NavigationPath()
    @State private var coaching = false
    /// The one-time reveal after building a plan: sections rise in one after another. nil when not revealing.
    @State private var revealStep: Int?
    #if DEBUG
    @State private var debugRecap: CompletedRun?
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header.revealed(0, revealStep)
                    PlanChangeBanner()
                    WeekCard(selected: $selected).revealed(1, revealStep)
                    HeroCard(date: selected).revealed(2, revealStep)
                    if let strength = model.strengthSession(on: selected) {
                        StrengthCard(session: strength).revealed(3, revealStep)
                    }
                    if let plan = model.plan {
                        DashboardTiles(plan: plan).revealed(4, revealStep)
                        TrendCard(plan: plan).revealed(5, revealStep)
                    }
                    upNext.revealed(6, revealStep)
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .statusBarBackdrop()
            .screenBackground()
            .animation(.snappy, value: selected)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .navigationDestination(for: WeeklyDistanceRoute.self) { _ in WeeklyDistanceView() }
            .navigationDestination(for: RunRoute.self) { RunDetailView(runID: $0.runID) }
            .navigationDestination(for: StrengthSchedule.Session.self) { StrengthDetailView(session: $0) }
        }
        .onAppear {
            guard model.revealNewPlan else { return }
            model.revealNewPlan = false
            revealStep = -1
            Task { await playReveal() }
        }
        .sensoryFeedback(.success, trigger: revealStep == 2)
        .onChange(of: resetSignal) {
            path = NavigationPath()
            withAnimation(.snappy) { selected = model.today }
        }
        #if DEBUG
        // `-recap`: open the coach's recap of the latest run (for checking it on a simulator).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-recap") else { return }
            try? await Task.sleep(for: .seconds(1))
            debugRecap = model.healthRuns.max { $0.date < $1.date }
        }
        .sheet(item: $debugRecap) { RunRecapView(run: $0) }
        #endif
    }

    /// Brings the dashboard in section by section, once, right after a plan is built.
    private func playReveal() async {
        if UIAccessibility.isReduceMotionEnabled { revealStep = nil; return }
        try? await Task.sleep(for: .milliseconds(250))
        for step in 0...6 {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { revealStep = step }
            try? await Task.sleep(for: .milliseconds(step == 2 ? 260 : 130))
        }
        try? await Task.sleep(for: .milliseconds(500))
        revealStep = nil
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.today.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                Text("Today")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            if model.showsCoach {
                Button { coaching = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.sheen)
                        Text("Coach").foregroundStyle(Theme.onAccent)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .darkGlass(Capsule())
                }
                .sheet(isPresented: $coaching) { CoachView() }
            }
        }
        .padding(.top, Theme.Spacing.m)
    }

    @ViewBuilder private var upNext: some View {
        let next = (model.plan?.workouts ?? []).filter { $0.date > selected }.prefix(3)
        if !next.isEmpty {
            Text("Coming up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, Theme.Spacing.s)
            VStack(spacing: Theme.Spacing.s) {
                ForEach(Array(next)) { workout in
                    NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A one-week strip that opens up to the whole month. Tap a day to see it in the card below.
private struct WeekCard: View {
    @Binding var selected: LocalDate
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        Card(padding: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    title
                    Spacer()
                    if selected != model.today {
                        // Only shown once you've moved away from today.
                        Button {
                            withAnimation(.snappy) { selected = model.today }
                        } label: {
                            Text("Today")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.accent, in: Capsule())
                        }
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Back to today")
                    }
                    HStack(spacing: 18) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel(expanded ? "Previous month" : "Previous week")
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel(expanded ? "Next month" : "Next week")
                        Button {
                            withAnimation(.snappy) { expanded.toggle() }
                        } label: {
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .frame(width: 30, height: 30)
                                .background(.white, in: Circle())
                        }
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel(expanded ? "Show one week" : "Show the whole month")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
                }
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Text(day.shortName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(days, id: \.self) { date in
                        if expanded && date.month != selected.month {
                            Color.clear.frame(height: 50)
                        } else {
                            DayCell(date: date, isSelected: date == selected)
                                .onTapGesture { withAnimation(.snappy) { selected = date } }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var title: some View {
        if expanded {
            Text(selected.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(Theme.ink)
        } else if let week = model.week(containing: selected) {
            Text(String(localized: "Week \(week.index + 1)"))
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(week.phase.name)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
        } else {
            Text(selected.startOfWeek.formatted(.dateTime.day().month(.wide)))
                .font(.headline)
                .foregroundStyle(Theme.ink)
        }
    }

    /// The selected week, or whole weeks covering the selected month.
    private var days: [LocalDate] {
        guard expanded else { return (0..<7).map { selected.startOfWeek.adding(days: $0) } }
        let first = selected.firstOfMonth
        let next = first.addingMonths(1)
        var dates: [LocalDate] = []
        var day = first.startOfWeek
        while day < next || dates.count % 7 != 0 {
            dates.append(day)
            day = day.adding(days: 1)
        }
        return dates
    }

    /// A week (or month when open) back or forward, keeping the same weekday or day where possible.
    private func step(_ direction: Int) {
        withAnimation(.snappy) {
            if expanded {
                let target = selected.firstOfMonth.addingMonths(direction)
                let today = model.today
                selected = today.firstOfMonth == target ? today : target
            } else {
                selected = selected.adding(days: 7 * direction)
            }
        }
    }
}

private struct DayCell: View {
    let date: LocalDate
    let isSelected: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let workout = model.workout(on: date)
        let status = workout.flatMap { model.status(of: $0) }
        let strength = model.strengthSession(on: date)
        let isToday = date == model.today
        VStack(spacing: 4) {
            Text("\(date.day)")
                .font(.callout.weight(isToday || isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                .frame(width: 38, height: 38)
                .background {
                    if isSelected {
                        Circle().fill(Theme.accent)
                    } else {
                        Circle().fill(.white)
                    }
                }
                .overlay {
                    if isToday && !isSelected {
                        Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                    }
                }
            Group {
                if let workout {
                    if status == .done {
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(Theme.green)
                    } else if status == .skipped {
                        Circle().fill(Theme.subtle)
                    } else {
                        Circle().fill(workout.kind.color)
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: 6, height: 6)
            // A strength session: a small purple dot (outlined once done).
            .overlay(alignment: .leading) {
                if let strength {
                    Circle()
                        .fill(model.isStrengthDone(strength) ? Color.clear : StrengthStyle.color)
                        .strokeBorder(StrengthStyle.color, lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                        .offset(x: workout == nil ? 0 : 8)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(date.formatted(.dateTime.weekday(.wide).day().month())), \(workout?.kind.name ?? String(localized: "rest day"))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The selected day's run as a dark card: the dashboard's focal point.
private struct HeroCard: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model
    @State private var addingToCalendar: Workout?

    var body: some View {
        let workout = model.workout(on: date)
        VStack(alignment: .leading, spacing: 16) {
            if let workout {
                // The whole top of the card opens the workout; the buttons below keep their own actions.
                NavigationLink(value: workout) { summary(workout) }
                    .buttonStyle(HeroPressStyle())
                    .accessibilityHint("Opens the workout")
            } else {
                summary(nil)
            }
            if let workout {
                actions(workout)
            } else {
                Text(isAfterRace ? "Congratulations on finishing your plan."
                                 : "Recovery is training too. A walk or gentle mobility is fine.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkGlass(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func summary(_ workout: Workout?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(workout?.kind.name ?? (isAfterRace ? String(localized: "Plan complete") : String(localized: "Rest day")))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                    if let workout {
                        Text(WorkoutDescriber(format: model.format).summary(workout))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                KindIcon(kind: workout?.kind, size: 52)
            }

            if let workout {
                HStack(spacing: 0) {
                    heroMetric(model.format.distance(workout.totalMeters), String(localized: "distance"))
                    heroMetric("~" + DisplayFormat.duration(workout.totalSeconds), String(localized: "time"))
                    if let target = workout.blocks.flatMap(\.steps).first(where: { $0.purpose == .work })?.step.target {
                        heroMetric(DisplayFormat.clock(model.format.paceSeconds(target.range.mid)),
                                   String(localized: "\(target.zone.name) /\(model.units.distanceUnit)"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var label: String {
        date == model.today ? String(localized: "Today's run") : date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var isAfterRace: Bool { model.plan.map { date > $0.inputs.raceDate } ?? false }

    private func heroMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func actions(_ workout: Workout) -> some View {
        let status = model.status(of: workout)
        if workout.date <= model.today, status == nil {
            HStack(spacing: 8) {
                Button { model.setStatus(.done, for: workout) } label: {
                    Text("Mark as done").frame(maxWidth: .infinity)
                }
                .buttonStyle(HeroButtonStyle(filled: true))
                Button { model.setStatus(.skipped, for: workout) } label: { Text("Skip") }
                    .buttonStyle(HeroButtonStyle(filled: false))
            }
            .sensoryFeedback(.success, trigger: model.status(of: workout))
        } else if let status {
            HStack {
                Label(status == .done ? "Completed" : "Skipped",
                      systemImage: status == .done ? "checkmark.circle.fill" : "forward.end.circle")
                    .font(.headline)
                    .foregroundStyle(status == .done ? Theme.green : .white.opacity(0.7))
                Spacer()
                if let run = model.healthRun(for: workout) {
                    NavigationLink(value: RunRoute(runID: run.id)) {
                        Label("View run", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(HeroButtonStyle(filled: true))
                }
                if model.statuses[workout.id] != nil {
                    Button("Undo") { model.setStatus(nil, for: workout) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        HStack(spacing: 8) {
            if workout.date >= model.today, status == nil {
                if model.isOnWatch(workout) {
                    Label("On your watch", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Button { Task { await model.sendToWatch([workout]) } } label: {
                        Label("Send to watch", systemImage: "applewatch")
                    }
                    .buttonStyle(HeroButtonStyle(filled: false))
                }
            }
            Spacer(minLength: 0)
            MoveWorkoutButton(workout: workout)
                .labelStyle(.iconOnly)
                .buttonStyle(HeroIconButtonStyle())
                .accessibilityLabel("Move workout")
            if workout.date >= model.today {
                Button { addingToCalendar = workout } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .buttonStyle(HeroIconButtonStyle())
                .accessibilityLabel("Add to Calendar")
                .sheet(item: $addingToCalendar) { workout in
                    AddToCalendarSheet(content: model.calendarEvent(for: workout)).ignoresSafeArea()
                }
            }
            NavigationLink(value: workout) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .accessibilityLabel("Workout details")
        }
    }
}

/// The tappable top of the hero card: dims slightly while pressed.
private struct HeroPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round icon buttons on the dark hero card.
private struct HeroIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.12), in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Buttons on the dark hero card: white pill, or a subtle outlined pill.
private struct HeroButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Theme.ink : .white)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(filled ? Color.white : Color.white.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// This week at a glance and the race outlook.
private struct DashboardTiles: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        let week = model.week(containing: model.today)
        let workouts = week?.workouts.filter { $0.kind != .race } ?? []
        let done = workouts.filter { model.status(of: $0) == .done }
        let doneMeters = done.reduce(0) { $0 + (model.healthRun(for: $1)?.distanceMeters ?? $1.totalMeters) }
        let plannedMeters = workouts.reduce(0) { $0 + $1.totalMeters }
        let days = max(model.today.days(until: plan.inputs.raceDate), 0)
        let length = Double(max(plan.inputs.startDate.days(until: plan.inputs.raceDate), 1))
        let elapsed = Double(plan.inputs.startDate.days(until: model.today))
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(title: String(localized: "This week"), symbol: "figure.run", tint: WorkoutKind.easy.color,
                         value: model.format.distance(doneMeters), badge: nil,
                         note: String(localized: "of \(model.format.distance(plannedMeters))"),
                         progress: plannedMeters > 0 ? doneMeters / plannedMeters : 0)
                StatCard(title: String(localized: "Runs"), symbol: "checkmark.circle", tint: Theme.green,
                         value: "\(done.count)/\(workouts.count)", badge: nil,
                         note: String(localized: "done this week"),
                         progress: workouts.isEmpty ? 0 : Double(done.count) / Double(workouts.count))
            }
            GridRow {
                predictionTile
                StatCard(title: String(localized: "Race day"), symbol: "flag.checkered", tint: WorkoutKind.race.color,
                         value: "\(days)", badge: nil,
                         note: String(localized: "days to \(plan.inputs.goal.name.lowercased())"),
                         progress: elapsed / length)
            }
        }
    }

    @ViewBuilder private var predictionTile: some View {
        if let prediction = model.prediction {
            let goal = plan.inputs.goalTimeSeconds
            StatCard(title: String(localized: "Prediction"), symbol: "stopwatch", tint: Theme.amber,
                     value: DisplayFormat.clock(prediction.seconds),
                     badge: goal.map { goal in
                         let gap = prediction.seconds - goal
                         return ((gap <= 0 ? "−" : "+") + DisplayFormat.clock(abs(gap)), gap <= 0)
                     },
                     note: goal.map { String(localized: "goal \(DisplayFormat.clock($0))") } ?? plan.inputs.goal.name,
                     progress: goal.map { min($0 / prediction.seconds, 1) } ?? 0)
        }
    }
}

/// Weekly distance across the whole plan, with this week marked. Opens the week-by-week breakdown.
private struct TrendCard: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model

    var body: some View {
        let totals = WeekTotals(plan: plan, model: model)
        NavigationLink(value: WeeklyDistanceRoute()) {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Weekly distance").font(.headline.weight(.medium)).foregroundStyle(Theme.ink)
                        Spacer()
                        if let current = totals.current {
                            Text(String(localized: "Week \(current.id + 1) of \(totals.all.count)"))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    WeekBarsChart(weeks: totals.all)
                        .frame(height: 120)
                    ChartLegend()
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Weekly distance. Shows each week of the plan."))
    }
}

/// A day's workout (used by the calendar) with its structure and done/skip actions.
struct WorkoutCard: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        let format = model.format
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: 12) {
                    KindIcon(kind: workout.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.kind.name).font(.headline).foregroundStyle(Theme.ink)
                        Text(WorkoutDescriber(format: format).summary(workout))
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer()
                    MoveWorkoutButton(workout: workout)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .accessibilityLabel("Move workout")
                    NavigationLink(value: workout) {
                        Image(systemName: "info.circle").font(.title3)
                    }
                    .accessibilityLabel("Workout details")
                }
                WorkoutMetrics(workout: workout)
                Text(workout.kind.purpose).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                Divider()
                WorkoutStepsView(workout: workout)
                WorkoutStatusButtons(workout: workout)
                SendToWatchButton(workout: workout)
            }
        }
    }
}

/// "Send to Apple Watch" for today's and upcoming workouts.
struct SendToWatchButton: View {
    let workout: Workout
    /// A chip ("Send to watch") rather than a full-width button.
    var compact = false
    @Environment(AppModel.self) private var model
    @State private var sending = false

    var body: some View {
        if workout.date >= model.today, model.status(of: workout) == nil {
            if model.isOnWatch(workout) {
                Label(compact ? "On your watch" : "On your Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.subheadline.weight(compact ? .medium : .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, compact ? 4 : 0)
            } else if compact {
                Button {
                    sending = true
                    Task {
                        await model.sendToWatch([workout])
                        sending = false
                    }
                } label: {
                    Label(sending ? "Sending…" : "Send to watch", systemImage: "applewatch")
                }
                .buttonStyle(.chip)
                .disabled(sending)
            } else {
                Button {
                    sending = true
                    Task {
                        await model.sendToWatch([workout])
                        sending = false
                    }
                } label: {
                    Label(sending ? "Sending…" : "Send to Apple Watch", systemImage: "applewatch")
                }
                .buttonStyle(.secondary)
                .disabled(sending)
            }
        }
    }
}

struct WorkoutMetrics: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        let format = model.format
        HStack(spacing: Theme.Spacing.l) {
            Metric(value: format.distance(workout.totalMeters), label: String(localized: "distance"))
            Metric(value: "~" + DisplayFormat.duration(workout.totalSeconds), label: String(localized: "time"))
            if let range = mainTarget {
                Metric(value: DisplayFormat.clock(format.paceSeconds(range.range.mid)),
                       label: String(localized: "\(range.zone.name) /\(model.units.distanceUnit)"))
            }
        }
    }

    private var mainTarget: PaceTarget? {
        workout.blocks.flatMap(\.steps).first { $0.purpose == .work }?.step.target
    }
}

struct WorkoutStatusButtons: View {
    let workout: Workout
    /// Today shows Skip as a chip instead.
    var showsSkip = true
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.status(of: workout)
        if workout.date <= model.today {
            switch status {
            case .done? where model.healthRun(for: workout) != nil && model.statuses[workout.id] == nil:
                let run = model.healthRun(for: workout)!
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill").foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completed").font(.headline).foregroundStyle(WorkoutKind.easy.color)
                        Text("\(model.format.distance(run.distanceMeters)) · \(model.format.pace(run.paceSecondsPerKm)) · from Apple Health")
                            .font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            case .done?:
                statusRow(String(localized: "Completed"), symbol: "checkmark.circle.fill", color: WorkoutKind.easy.color)
            case .skipped?:
                statusRow(String(localized: "Skipped"), symbol: "forward.end.circle", color: Theme.secondaryInk)
            case nil:
                HStack(spacing: Theme.Spacing.s) {
                    if showsSkip {
                        Button("Skip") { model.setStatus(.skipped, for: workout) }
                            .buttonStyle(.secondary)
                            .frame(maxWidth: 120)
                    }
                    Button("Mark as done") { model.setStatus(.done, for: workout) }
                        .buttonStyle(.primary)
                }
                .sensoryFeedback(.success, trigger: model.status(of: workout))
            }
        }
    }

    private func statusRow(_ text: String, symbol: String, color: Color) -> some View {
        HStack {
            Label(text, systemImage: symbol).font(.headline).foregroundStyle(color)
            Spacer()
            Button("Undo") { model.setStatus(nil, for: workout) }
                .font(.subheadline.weight(.semibold))
        }
        .padding(.top, Theme.Spacing.xs)
    }
}

/// Compact list row for a workout.
struct WorkoutRow: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.status(of: workout)
        HStack(spacing: 12) {
            KindIcon(kind: workout.kind, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.kind.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(workout.date.shortDayMonth) · \(WorkoutDescriber(format: model.format).summary(workout))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if status == .done {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.green)
            } else if status == .skipped {
                Image(systemName: "forward.end.circle").font(.title3).foregroundStyle(Theme.secondaryInk)
            } else {
                ValuePill(text: model.format.distance(workout.totalMeters))
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}


private extension View {
    /// Hidden and lowered until the reveal reaches `index`; untouched when there's no reveal.
    func revealed(_ index: Int, _ step: Int?) -> some View {
        let shown = step.map { $0 >= index } ?? true
        return self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 28)
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
    }
}
