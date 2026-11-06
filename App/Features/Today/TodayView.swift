import SwiftUI
import PlanEngine

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: LocalDate = .today

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header
                    WeekStrip(selected: $selected)
                    if let workout = model.workout(on: selected) {
                        WorkoutCard(workout: workout)
                    } else {
                        RestDayCard(date: selected)
                    }
                    upNext
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(model.today.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryInk)
            HStack(alignment: .firstTextBaseline) {
                Text(selected == model.today ? "Today" : selected.formatted(.dateTime.weekday(.wide)))
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let plan = model.plan {
                    let days = model.today.days(until: plan.inputs.raceDate)
                    Pill(text: String(localized: "\(plan.inputs.goal.name) in \(days) days"), color: WorkoutKind.race.color)
                }
            }
        }
        .padding(.top, Theme.Spacing.m)
    }

    @ViewBuilder private var upNext: some View {
        let next = (model.plan?.workouts ?? []).filter { $0.date > selected }.prefix(3)
        if !next.isEmpty {
            SectionTitle(text: String(localized: "Coming up"))
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

/// Seven days of the selected week, with arrows to move between weeks.
private struct WeekStrip: View {
    @Binding var selected: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        let monday = selected.startOfWeek
        Card(padding: 12) {
            VStack(spacing: Theme.Spacing.s) {
                HStack {
                    Button { selected = selected.adding(days: -7) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous week")
                    Spacer()
                    if let week = model.week(containing: selected) {
                        Text(String(localized: "Week \(week.index + 1) · \(week.phase.name)"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button { selected = selected.adding(days: 7) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next week")
                }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.accent)

                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { offset in
                        let date = monday.adding(days: offset)
                        DayCell(date: date, isSelected: date == selected)
                            .onTapGesture { withAnimation(.snappy) { selected = date } }
                    }
                }
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
        let isToday = date == model.today
        VStack(spacing: 6) {
            Text(date.weekday.shortName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryInk)
            Text("\(date.day)")
                .font(.callout.weight(isToday ? .heavy : .semibold))
                .fontDesign(.rounded)
                .foregroundStyle(isSelected ? .white : Theme.ink)
            ZStack {
                if let workout {
                    Circle()
                        .fill(status == .done ? workout.kind.color : .clear)
                        .strokeBorder(workout.kind.color, lineWidth: 2)
                    if status == .done {
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .black)).foregroundStyle(.white)
                    } else if status == .skipped {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .black)).foregroundStyle(workout.kind.color)
                    }
                } else {
                    Circle().fill(Theme.subtle).frame(width: 5, height: 5)
                }
            }
            .frame(width: 14, height: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(isSelected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(date.formatted(.dateTime.weekday(.wide).day().month())), \(workout?.kind.name ?? String(localized: "rest day"))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The selected day's workout with its structure and done/skip actions.
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
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.status(of: workout)
        if workout.date <= model.today {
            switch status {
            case .done?:
                statusRow(String(localized: "Completed"), symbol: "checkmark.circle.fill", color: WorkoutKind.easy.color)
            case .skipped?:
                statusRow(String(localized: "Skipped"), symbol: "forward.end.circle", color: Theme.secondaryInk)
            case nil:
                HStack(spacing: Theme.Spacing.s) {
                    Button("Skip") { model.setStatus(.skipped, for: workout) }
                        .buttonStyle(.secondary)
                        .frame(maxWidth: 120)
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

private struct RestDayCard: View {
    let date: LocalDate
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(padding: 20) {
            HStack(spacing: Theme.Spacing.m) {
                KindIcon(kind: nil)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isAfterRace ? "Plan complete" : "Rest day").font(.headline).foregroundStyle(Theme.ink)
                    Text(isAfterRace
                         ? "Congratulations on finishing your plan."
                         : "Recovery is when your body adapts to training. A walk or gentle mobility is fine.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }

    private var isAfterRace: Bool {
        model.plan.map { date > $0.inputs.raceDate } ?? false
    }
}

/// Compact list row for a workout.
struct WorkoutRow: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        let status = model.status(of: workout)
        HStack(spacing: 12) {
            KindIcon(kind: workout.kind, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.kind.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(workout.date.shortDayMonth) · \(WorkoutDescriber(format: model.format).summary(workout))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if status == .done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(WorkoutKind.easy.color)
            } else if status == .skipped {
                Image(systemName: "forward.end.circle").foregroundStyle(Theme.secondaryInk)
            } else {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.subtle)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
