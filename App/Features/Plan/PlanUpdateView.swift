import SwiftUI
import PlanEngine

/// A change the athlete made that re-plans the rest of their training.
enum PlanChangeRequest: Hashable, Identifiable {
    case availability(runDays: Set<Weekday>, longRunDay: Weekday)
    case raceDate(LocalDate)
    case raceResult(RacePerformance)
    case timeOff([TimeOff])

    var id: Self { self }
}

/// Re-plans after the athlete changes something, the same way onboarding builds a plan: a short checklist of
/// what's being redone, then the updated plan revealed with what changed. The change is applied straight away;
/// the checklist paces the explanation, not the work. A tap skips to the result.
struct PlanUpdateView: View {
    let request: PlanChangeRequest
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var before: TrainingPlan?
    @State private var applied: Bool?
    @State private var revealed = 0
    @State private var showingResult = false
    @State private var stage = 0
    @State private var chartReveal = 0.0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    if showingResult, let plan = model.plan {
                        result(plan)
                    } else {
                        checklist
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button(showingResult ? "Done" : "Updating your plan…") { onDone() }
                .buttonStyle(.primary)
                .disabled(!showingResult)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
        }
        .screenBackground()
        .environment(\.unitSystem, model.units)
        .task { await run() }
    }

    // MARK: Checklist

    private struct Item { let title: String; let detail: String }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Updating your plan").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                Text(headline).font(.body).foregroundStyle(Theme.secondaryInk)
            }
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    row(item, done: index < revealed)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            if applied == true {
                Text("Tap to skip").font(.footnote).foregroundStyle(Theme.secondaryInk).frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if applied == true { finish() } }
    }

    private func row(_ item: Item, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                        .transition(.opacity)
                } else {
                    Circle().strokeBorder(Theme.subtle, lineWidth: 2)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).foregroundStyle(done ? Theme.ink : Theme.secondaryInk)
                if done {
                    Text(item.detail).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        switch request {
        case .availability: String(localized: "Moving your training onto your new days")
        case .raceDate(let date): String(localized: "Re-planning for \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
        case .raceResult(let result): String(localized: "Using your \(model.format.distance(result.distanceMeters)) result")
        case .timeOff: String(localized: "Planning around your time off")
        }
    }

    private var items: [Item] {
        guard let plan = model.plan else { return [] }
        let format = model.format
        let done = model.healthRuns.filter { $0.date >= plan.weeks.first?.startDate ?? model.today }.count
        var items = [Item(title: String(localized: "Reading your training so far"),
                          detail: done == 0 ? String(localized: "Starting from where your plan is now")
                                            : String(localized: "\(done) runs logged since the plan started"))]
        let peak = format.distance(plan.weeks.filter { $0.startDate >= model.today.startOfWeek }.map(\.targetMeters).max() ?? 0)
        switch request {
        case .availability(let days, let long):
            items.append(Item(title: String(localized: "Moving workouts to your new days"),
                              detail: String(localized: "\(days.sorted().map(\.mediumName).joined(separator: ", ")), long run on \(long.fullName)")))
            items.append(Item(title: String(localized: "Rebalancing each week"),
                              detail: String(localized: "Up to \(peak) a week at the peak")))
        case .raceDate:
            let weeksLeft = max(0, model.today.days(until: plan.inputs.raceDate) / 7)
            items.append(Item(title: String(localized: "Rebuilding the phases"),
                              detail: String(localized: "\(weeksLeft) weeks to go: build, peak, then taper")))
            items.append(Item(title: String(localized: "Setting each week's distance"),
                              detail: String(localized: "Up to \(peak) a week at the peak")))
        case .raceResult(let result):
            items.append(Item(title: String(localized: "Updating your fitness"),
                              detail: String(localized: "From your \(format.distance(result.distanceMeters)) in \(DisplayFormat.clock(result.timeSeconds))")))
            items.append(Item(title: String(localized: "Resetting your paces"),
                              detail: String(localized: "Easy about \(DisplayFormat.clock(format.targetPaceSeconds(plan.paces.easy.mid))) · threshold \(format.targetPace(plan.paces.threshold.mid))")))
        case .timeOff:
            break
        }
        if case .timeOff(let periods) = request {
            let days = periods.filter { $0.end.map { $0 >= model.today } ?? true }
                .reduce(0) { $0 + ($1.length ?? 0) }
            items.append(Item(title: String(localized: "Clearing your days off"),
                              detail: periods.contains { $0.end == nil }
                                  ? String(localized: "Nothing planned until you're back")
                                  : String(localized: "\(days) days with nothing planned")))
            let longBreak = periods.contains { ($0.length ?? 0) >= TimeOff.breakDaysForReset && ($0.end ?? model.today) >= model.today }
            items.append(Item(title: String(localized: "Easing you back in"),
                              detail: longBreak ? String(localized: "Restarting lower after a week or more off, then building back up")
                                                : String(localized: "Short breaks just shrink those weeks a little")))
        }
        items.append(Item(title: String(localized: "Checking the safety rules"),
                          detail: String(localized: "Gradual build and easy days between hard ones, checked week by week")))
        return items
    }

    private func run() async {
        guard applied == nil else { return }
        before = model.plan
        let ok = switch request {
        case .availability(let days, let long): model.changeAvailability(runDays: days, longRunDay: long)
        case .raceDate(let date): model.changeRaceDate(date)
        case .raceResult(let result): model.applyRaceResult(result)
        case .timeOff(let periods): model.changeTimeOff(periods)
        }
        applied = ok
        guard ok else { finish(); return }
        for item in items {
            withAnimation(.snappy) { revealed += 1 }
            let characters = Double(item.title.count + item.detail.count)
            try? await Task.sleep(for: .milliseconds(Int(min(max(0.35 + characters * 0.025, 0.6), 1.8) * 1000)))
            if showingResult { return }
        }
        finish()
    }

    private func finish() {
        guard !showingResult else { return }
        withAnimation(.easeOut(duration: 0.2)) { showingResult = true }
    }

    // MARK: Result

    @ViewBuilder private func result(_ plan: TrainingPlan) -> some View {
        let format = model.format
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if applied == false {
                Text("Couldn't update your plan").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                Text(model.lastError ?? String(localized: "Nothing was changed.")).foregroundStyle(Theme.secondaryInk)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: Circle())
                    .scaleEffect(stage >= 1 ? 1 : 0.4)
                    .opacity(stage >= 1 ? 1 : 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your plan is updated").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("\(plan.inputs.goal.name) on \(plan.inputs.raceDate.formatted(.dateTime.day().month(.wide)))")
                        .foregroundStyle(Theme.secondaryInk)
                }
                .opacity(stage >= 1 ? 1 : 0)
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack {
                            Metric(value: "\(max(0, model.today.days(until: plan.inputs.raceDate) / 7))", label: String(localized: "weeks to go"))
                            Spacer()
                            Metric(value: format.distance(plan.weeks.map(\.targetMeters).max() ?? 0), label: String(localized: "peak week"))
                            Spacer()
                            if plan.runWalkWeeksLeft(from: model.today) > 0 {
                                Metric(value: "\(plan.runWalkWeeksLeft(from: model.today))", label: String(localized: "weeks to 30 min"))
                            } else {
                                Metric(value: DisplayFormat.clock(plan.predictedRaceSeconds), label: String(localized: "predicted today"))
                            }
                        }
                        WeeklyVolumeChart(plan: plan, highlight: model.today, reveal: chartReveal)
                        PhaseLegend(plan: plan)
                    }
                }
                .opacity(stage >= 2 ? 1 : 0)
                Group {
                    let changed = before.map { $0 != plan } ?? true
                    let reasons = changed ? (model.changes.first?.reasons.map { $0.message(format) } ?? []) : []
                    if !changed {
                        Text("Nothing needed to change.").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                    if !reasons.isEmpty || !plan.warnings.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                                ForEach(reasons, id: \.self) { reason in
                                    Label(reason, systemImage: "arrow.triangle.2.circlepath").font(.subheadline).foregroundStyle(Theme.ink)
                                }
                                ForEach(plan.warnings, id: \.self) { warning in
                                    Label(warning.message(format, goalSeconds: plan.inputs.goalTimeSeconds), systemImage: "info.circle").font(.subheadline).foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    }
                }
                .opacity(stage >= 3 ? 1 : 0)
            }
        }
        .task { await reveal() }
        .sensoryFeedback(.success, trigger: stage >= 1)
    }

    private func reveal() async {
        guard stage == 0 else { return }
        if reduceMotion {
            stage = 3
            chartReveal = 1
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { stage = 2 }
        withAnimation(.easeOut(duration: 1.1).delay(0.15)) { chartReveal = 1 }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeOut(duration: 0.4)) { stage = 3 }
    }
}
