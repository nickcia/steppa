import SwiftUI
import PlanEngine

/// Month grid of the plan. Tap a day to see (and move or tick off) its workout.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @State private var month: LocalDate = LocalDate.today.firstOfMonth
    @State private var selected: LocalDate = .today

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Card(padding: 12) {
                VStack(spacing: Theme.Spacing.s) {
                    header
                    weekdayHeader
                    grid
                }
            }
            if let workout = model.workout(on: selected) {
                WorkoutCard(workout: workout)
            } else {
                Card {
                    HStack(spacing: Theme.Spacing.m) {
                        KindIcon(kind: nil)
                        Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · " + String(localized: "Rest day"))
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button { month = month.addingMonths(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button { month = month.addingMonths(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.allCases, id: \.self) { day in
                Text(day.shortName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let first = month.startOfWeek
        let weeks = (first.days(until: month.addingMonths(1).adding(days: -1).startOfWeek) / 7) + 1
        return VStack(spacing: 4) {
            ForEach(0..<weeks, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let date = first.adding(days: w * 7 + d)
                        CalendarDay(date: date, inMonth: date.month == month.month, isSelected: date == selected)
                            .onTapGesture { selected = date }
                    }
                }
            }
        }
    }
}

private struct CalendarDay: View {
    let date: LocalDate
    let inMonth: Bool
    let isSelected: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let workout = model.workout(on: date)
        let status = workout.flatMap { model.status(of: $0) }
        VStack(spacing: 4) {
            Text("\(date.day)")
                .font(.footnote.weight(date == model.today ? .heavy : .medium))
                .foregroundStyle(isSelected ? .white : (inMonth ? Theme.ink : Theme.secondaryInk.opacity(0.5)))
            ZStack {
                if let workout {
                    Capsule()
                        .fill(status == .done ? workout.kind.color : workout.kind.color.opacity(status == .skipped ? 0.25 : 0.6))
                        .frame(width: workout.kind == .race ? 18 : 14, height: 5)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSelected ? Theme.accent : (date == model.today ? Theme.accent.opacity(0.12) : .clear),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .opacity(inMonth ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(date.formatted(.dateTime.weekday(.wide).day().month())), \(workout?.kind.name ?? String(localized: "rest day"))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension LocalDate {
    var firstOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }

    func addingMonths(_ n: Int) -> LocalDate {
        let total = (year * 12 + (month - 1)) + n
        return LocalDate(year: total / 12, month: total % 12 + 1, day: 1)
    }
}
