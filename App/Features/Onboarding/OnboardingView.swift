import SwiftUI
import PlanEngine

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = OnboardingDraft()
    @State private var preview: Result<TrainingPlan, PlanError>?
    /// True while the plan is being built and its checklist shown, before the review appears.
    @State private var building = false
    /// What Apple Health said about the answers; nil until checked, or when Health isn't connected.
    @State private var calibration: HistoryCalibration.Result?

    var body: some View {
        VStack(spacing: 0) {
            if draft.step != .welcome { topBar }
            ScrollView {
                content
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
                    .id(draft.step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
            bottomBar
        }
        .screenBackground()
        .environment(\.unitSystem, draft.units)
        .onAppear {
            #if DEBUG
            // `-buildPlan`: skip the questions with their defaults and go straight to building the plan.
            if ProcessInfo.processInfo.arguments.contains("-buildPlan") {
                draft.acceptedDisclaimer = true
                go(to: .review)
            }
            // `-availability`: jump to the run-days step with a 3-hour marathon goal (shows the warning at 2 days).
            if ProcessInfo.processInfo.arguments.contains("-availability") {
                draft.acceptedDisclaimer = true
                draft.goal = .marathon
                draft.hasGoalTime = true
                draft.goalTimeSeconds = 3 * 3600
                draft.daysPerWeek = 2
                draft.step = .availability
            }
            #endif
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button {
                go(to: OnboardingDraft.Step(rawValue: draft.step.rawValue - 1) ?? .welcome)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Back")
            HeatBar(value: Double(draft.step.rawValue) / Double(OnboardingDraft.Step.allCases.count - 1))
                .animation(.snappy, value: draft.step)
                .accessibilityElement()
                .accessibilityLabel("Step \(draft.step.rawValue) of \(OnboardingDraft.Step.allCases.count - 1)")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            switch draft.step {
            case .review:
                Button(building ? "Building your plan…" : "Start my plan") { startPlan() }
                    .buttonStyle(.primary)
                    .disabled(planOrNil == nil || building)
            case .health:
                Button("Connect Apple Health") {
                    Task {
                        await model.connectHealth()
                        go(to: .review)
                    }
                }
                .buttonStyle(.primary)
                Button("Not now") { go(to: .review) }
                    .buttonStyle(.secondary)
            case .welcome:
                Button("Get started") { go(to: .goal) }
                    .buttonStyle(.primary)
                    .disabled(!draft.canContinue)
            default:
                Button("Continue") { go(to: OnboardingDraft.Step(rawValue: draft.step.rawValue + 1)!) }
                    .buttonStyle(.primary)
                    .disabled(!draft.canContinue)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.background)
    }

    private func go(to step: OnboardingDraft.Step) {
        if step == .review { buildPlan() }
        withAnimation(.snappy) { draft.step = step }
    }

    /// Checks the answers against recent runs in Apple Health (when connected), then builds the plan.
    private func buildPlan() {
        preview = nil
        calibration = nil
        building = true
        let inputs = draft.inputs
        Task {
            let runs = await model.runsBeforePlan(starting: inputs.startDate)
            let checked = runs.map { HistoryCalibration.calibrate(inputs, runs: $0) }
            calibration = checked
            do throws(PlanError) {
                preview = .success(try PlanBuilder.build(checked?.inputs ?? inputs))
            } catch {
                preview = .failure(error)
                building = false
            }
        }
    }

    private var planOrNil: TrainingPlan? {
        if case .success(let plan) = preview { return plan }
        return nil
    }

    private func startPlan() {
        guard let plan = planOrNil else { return }
        model.setUnits(draft.units)
        model.acceptDisclaimer()
        model.revealNewPlan = true
        model.start(plan)
        model.setStrength(enabled: draft.strengthEnabled, perWeek: draft.strengthPerWeek)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch draft.step {
        case .welcome: WelcomeStep(draft: draft)
        case .goal: GoalStep(draft: draft)
        case .date: DateStep(draft: draft)
        case .experience: ExperienceStep(draft: draft)
        case .fitness: FitnessStep(draft: draft)
        case .volume: VolumeStep(draft: draft)
        case .availability: AvailabilityStep(draft: draft)
        case .health: HealthStep()
        case .review:
            if building {
                BuildingPlanView(plan: planOrNil, calibration: calibration, checksHealth: model.healthConnected,
                                 draft: draft) {
                    withAnimation(.easeOut(duration: 0.2)) { building = false }
                }
                // Gone quickly, so it never shows through the reveal that follows.
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            } else {
                // The review animates itself in (see ReviewStep), so it needs no transition of its own.
                ReviewStep(draft: draft, preview: preview)
                    .transition(.identity)
            }
        }
    }
}

// MARK: - Shared step pieces

private struct StepHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle).font(.body).foregroundStyle(Theme.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.Spacing.m)
    }
}

/// Large tappable option card with a selection ring.
private struct ChoiceCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            HStack {
                content
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.subtle)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Hours / minutes / seconds wheels.
struct DurationWheels: View {
    @Binding var seconds: Double
    var showHours = true

    var body: some View {
        HStack(spacing: 0) {
            if showHours {
                wheel(0...9, unit: "h", component(get: { $0 / 3600 }, set: { total, h in h * 3600 + total % 3600 }))
            }
            wheel(0...59, unit: "min", component(get: { ($0 % 3600) / 60 },
                                                 set: { total, m in (total / 3600) * 3600 + m * 60 + total % 60 }))
            wheel(0...59, unit: "s", component(get: { $0 % 60 }, set: { total, s in total - total % 60 + s }))
        }
        .frame(height: 150)
    }

    /// A binding to one component (h, min or s) of the total.
    private func component(get: @escaping @Sendable (Int) -> Int,
                           set: @escaping @Sendable (Int, Int) -> Int) -> Binding<Int> {
        let total = $seconds
        return Binding(get: { get(Int(total.wrappedValue)) },
                       set: { total.wrappedValue = Double(set(Int(total.wrappedValue), $0)) })
    }

    private func wheel(_ range: ClosedRange<Int>, unit: String, _ value: Binding<Int>) -> some View {
        Picker(unit, selection: value) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
                .padding(.top, Theme.Spacing.xl)
            StepHeader(title: String(localized: "Train smarter for your next race"),
                       subtitle: String(localized: "A personal plan that adapts as you go. Free, private, and yours."))
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Feature(symbol: "calendar", title: String(localized: "A plan built around your week"),
                        detail: String(localized: "Runs fit the days you're free, with a sensible mix of easy days and sessions."))
                Feature(symbol: "applewatch", title: String(localized: "Works with your watch"),
                        detail: String(localized: "Runs from Apple Watch, Garmin, Coros and others arrive through Apple Health. No extra accounts. (We don't connect to Strava directly, but most watches that sync to Strava can also sync to Apple Health.)"))
                Feature(symbol: "lock.shield", title: String(localized: "Private by design"),
                        detail: String(localized: "No sign-up and no servers. Your data stays on your phone and your own iCloud."))
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    DisclaimerText()
                    Toggle("I understand this isn't medical advice", isOn: $draft.acceptedDisclaimer)
                        .font(.subheadline.weight(.semibold))
                        .tint(Theme.accent)
                }
            }
        }
    }

    private struct Feature: View {
        let symbol: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }
}

private struct GoalStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            StepHeader(title: String(localized: "What are you training for?"))
            ForEach(RaceDistance.allCases, id: \.self) { distance in
                ChoiceCard(selected: draft.goal == distance, action: {
                    draft.goal = distance
                    draft.goalTimeSeconds = OnboardingDraft.typicalTime(distance)
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(distance.name).font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(Theme.ink)
                        Text(String(localized: "Ideally \(PlanRules.recommendedWeeks(distance)) weeks or more"))
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
    }
}

private struct DateStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StepHeader(title: String(localized: "When is your race?"),
                       subtitle: String(localized: "\(draft.weeksToRace) weeks from today."))
            Card {
                DatePicker("Race date", selection: $draft.raceDate,
                           in: Calendar.current.date(byAdding: .day, value: 7, to: .now)!...Calendar.current.date(byAdding: .year, value: 1, to: .now)!,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Toggle("I have a goal time", isOn: $draft.hasGoalTime.animation())
                        .font(.headline)
                        .tint(Theme.accent)
                    if draft.hasGoalTime {
                        DurationWheels(seconds: $draft.goalTimeSeconds, showHours: draft.goal != .fiveK)
                        Text("Your paces always start from your current fitness, so an ambitious goal won't make sessions unsafe.")
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
    }
}

private struct ExperienceStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            StepHeader(title: String(localized: "How would you describe your running?"))
            ForEach(Experience.allCases, id: \.self) { level in
                ChoiceCard(selected: draft.experience == level, action: { draft.experience = level }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.name).font(.headline).foregroundStyle(Theme.ink)
                        Text(level.detail).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
    }
}

private struct FitnessStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StepHeader(title: String(localized: "Your current fitness"),
                       subtitle: String(localized: "A recent race or hard time trial sets your training paces."))
            Picker("Recent result", selection: $draft.hasRecentRace.animation()) {
                Text("I have a recent result").tag(true)
                Text("I don't").tag(false)
            }
            .pickerStyle(.segmented)

            if draft.hasRecentRace {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        Picker("Distance", selection: $draft.recentDistance) {
                            ForEach(RaceDistance.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: draft.recentDistance) { _, new in
                            draft.recentTimeSeconds = OnboardingDraft.typicalTime(new)
                        }
                        Text("Finish time").font(.headline).foregroundStyle(Theme.ink)
                        DurationWheels(seconds: $draft.recentTimeSeconds,
                                       showHours: draft.recentDistance != .fiveK)
                        Picker("When", selection: $draft.recentAge) {
                            ForEach(OnboardingDraft.ResultAge.allCases) { Text($0.name).tag($0) }
                        }
                        .tint(Theme.accent)
                    }
                }
            } else {
                Card {
                    Label("No problem. We'll estimate your paces conservatively from your experience and weekly distance, then adjust as you run.",
                          systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }
}

private struct VolumeStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        let maxValue: Double = draft.units == .metric ? 120 : 75
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            StepHeader(title: String(localized: "How much do you run now?"),
                       subtitle: String(localized: "Your typical weekly distance over the last month. Be honest: the plan builds from here."))
            Picker("Units", selection: $draft.units) {
                ForEach(UnitSystem.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.units) { old, new in
                draft.weeklyDistance = (draft.weeklyDistance * old.metersPerUnit / new.metersPerUnit).rounded()
            }
            Card {
                VStack(spacing: Theme.Spacing.m) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(draft.weeklyDistance))")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("\(draft.units.distanceUnit) / week")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .foregroundStyle(Theme.ink)
                    Slider(value: $draft.weeklyDistance, in: 0...maxValue, step: 1)
                        .tint(Theme.accent)
                        .accessibilityValue(Text("\(Int(draft.weeklyDistance)) \(draft.units.distanceUnit) per week"))
                }
            }
        }
    }
}

private struct AvailabilityStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            StepHeader(title: String(localized: "How many days a week can you run?"),
                       subtitle: String(localized: "Be realistic about a normal week. Four or more lets the plan include more variety."))
            HStack(spacing: 6) {
                ForEach(2...7, id: \.self) { count in
                    let on = draft.daysPerWeek == count
                    Button {
                        withAnimation(.snappy) { draft.daysPerWeek = count }
                    } label: {
                        Text("\(count)")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(on ? .white : Theme.ink)
                            .background(on ? Theme.accent : Theme.card,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(count) days")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: draft.daysPerWeek)

            if draft.daysPerWeek < draft.recommendedRunDays {
                FewDaysWarning(draft: draft)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Which days?").font(.headline).foregroundStyle(Theme.ink)
                Text(dayCountHint).font(.subheadline)
                    .foregroundStyle(draft.runDays.count == draft.daysPerWeek ? Theme.secondaryInk : Theme.amber)
                WeekdayChips(selection: $draft.runDays, limit: draft.daysPerWeek)
                    .onChange(of: draft.runDays) { _, days in
                        if !days.contains(draft.longRunDay), let fallback = days.sorted().last { draft.longRunDay = fallback }
                    }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Long run day").font(.headline).foregroundStyle(Theme.ink)
                Text("Usually the day you have the most time.").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                Picker("Long run day", selection: $draft.longRunDay) {
                    ForEach(draft.runDays.sorted(), id: \.self) { Text($0.mediumName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Toggle(isOn: $draft.strengthEnabled.animation()) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Strength training").font(.headline).foregroundStyle(Theme.ink)
                            Text("Short bodyweight sessions on easy days. They help prevent injury and make you faster.")
                                .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    .tint(Theme.accent)
                    if draft.strengthEnabled {
                        Picker("Sessions a week", selection: $draft.strengthPerWeek) {
                            Text("1 a week").tag(1)
                            Text("2 a week").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .animation(.snappy, value: draft.daysPerWeek < draft.recommendedRunDays)
    }

    private var dayCountHint: String {
        let chosen = draft.runDays.count, wanted = draft.daysPerWeek
        if chosen == wanted { return String(localized: "Tap a day to swap it.") }
        return chosen < wanted ? String(localized: "Pick \(wanted - chosen) more.")
                               : String(localized: "Untick \(chosen - wanted) to keep it to \(wanted).")
    }
}

/// Shown when the goal usually needs more run days than the athlete has, e.g. a 3-hour marathon on two days.
private struct FewDaysWarning: View {
    let draft: OnboardingDraft

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text("That's not enough for this goal").font(.headline).foregroundStyle(Theme.ink)
                Text(message).font(.subheadline).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        let goal = draft.hasGoalTime
            ? String(localized: "A \(DisplayFormat.clock(draft.goalTimeSeconds)) \(draft.goal.name.lowercased())")
            : String(localized: "A \(draft.goal.name.lowercased())")
        return String(localized: "\(goal) usually needs at least \(draft.recommendedRunDays) runs a week. On \(draft.daysPerWeek), it's unrealistic: the plan can't safely build the distance it takes. Add days, or go back and pick a gentler goal time.")
    }
}

private struct HealthStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            StepHeader(title: String(localized: "Connect Apple Health"),
                       subtitle: String(localized: "So your runs tick themselves off and your plan can adapt to what you actually did."))
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("Reads your running workouts and distance. Nothing else.", systemImage: "figure.run")
                Label("Never writes to Health, and nothing leaves your phone.", systemImage: "lock")
                Label("Works with Apple Watch, Garmin, Coros and any app that saves runs to Health.", systemImage: "applewatch")
                Label("Use Strava? We don't connect to it directly. If your watch syncs to Strava, it can usually sync to Apple Health too.", systemImage: "arrow.triangle.branch")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            Text("You can change this any time in the Health app under Sharing › Apps. Without Health, tick runs off by hand.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
        }
    }
}

struct WeekdayChips: View {
    @Binding var selection: Set<Weekday>
    /// At most this many days; when full, tapping another day swaps it for the most recently added one.
    var limit: Int? = nil
    @State private var order: [Weekday] = []

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on {
                        selection.remove(day)
                        order.removeAll { $0 == day }
                    } else {
                        if let limit, selection.count >= limit {
                            let last = order.last(where: selection.contains) ?? selection.sorted().last
                            if let last { selection.remove(last); order.removeAll { $0 == last } }
                        }
                        selection.insert(day)
                        order.append(day)
                    }
                } label: {
                    Text(day.shortName)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(on ? .white : Theme.ink)
                        .background(on ? Theme.accent : Theme.card,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

extension Weekday {
    private var symbolIndex: Int { rawValue % 7 } // Calendar symbols start on Sunday.
    var shortName: String { Calendar.current.veryShortStandaloneWeekdaySymbols[symbolIndex] }
    var mediumName: String { Calendar.current.shortStandaloneWeekdaySymbols[symbolIndex] }
    var fullName: String { Calendar.current.standaloneWeekdaySymbols[symbolIndex] }
}

/// What went into the plan, one line at a time.
///
/// Building a plan takes milliseconds, so nothing here pretends to compute. The only real wait is reading recent
/// runs from Apple Health, which shows a spinner while it happens. After that, each finished line stays up for
/// roughly as long as it takes to read (longer lines stay longer), so people can follow how their answers became a
/// plan. A tap skips to the result.
private struct BuildingPlanView: View {
    let plan: TrainingPlan?
    let calibration: HistoryCalibration.Result?
    let checksHealth: Bool
    let draft: OnboardingDraft
    let onFinished: () -> Void
    @Environment(\.unitSystem) private var units
    @State private var revealed = 0
    @State private var finished = false

    private struct Item {
        let title: String
        let detail: String
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            StepHeader(title: String(localized: "Building your plan"),
                       subtitle: String(localized: "\(draft.goal.name) on \(draft.race.dayMonth)"))
            VStack(alignment: .leading, spacing: 18) {
                if plan == nil && checksHealth {
                    row(title: String(localized: "Checking your recent runs"),
                        detail: String(localized: "Reading the last \(HistoryCalibration.lookbackWeeks) weeks from Apple Health"),
                        state: .working)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    row(title: item.title, detail: item.detail, state: index < revealed ? .done : .waiting)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            if plan != nil {
                Text("Tap to skip")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if plan != nil { finish() } }
        .task(id: plan == nil) {
            guard plan != nil else { return }
            for item in items {
                withAnimation(.snappy) { revealed += 1 }
                try? await Task.sleep(for: readingTime(item))
                if Task.isCancelled || finished { return }
            }
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }

    /// Long enough to read the line: a short base plus about 25 ms a character, between 0.6 and 1.8 seconds.
    private func readingTime(_ item: Item) -> Duration {
        let characters = Double(item.title.count + item.detail.count)
        return .milliseconds(Int(min(max(0.35 + characters * 0.025, 0.6), 1.8) * 1000))
    }

    private enum RowState { case working, done, waiting }

    private func row(title: String, detail: String, state: RowState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                switch state {
                case .working:
                    ProgressView()
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                        .transition(.opacity)
                case .waiting:
                    Circle().strokeBorder(Theme.subtle, lineWidth: 2)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(state == .waiting ? Theme.secondaryInk : Theme.ink)
                if state != .waiting {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var items: [Item] {
        guard let plan else { return [] }
        let format = DisplayFormat(units: units)
        var items: [Item] = []
        if let calibration {
            items.append(Item(title: String(localized: "Checking your recent runs"), detail: volumeText(calibration, format)))
        }
        items.append(Item(title: String(localized: "Reading your fitness"), detail: fitnessText(format)))
        items.append(Item(title: String(localized: "Setting your paces"),
                          detail: String(localized: "Easy about \(DisplayFormat.clock(format.paceSeconds(plan.paces.easy.mid))) · threshold \(format.pace(plan.paces.threshold.mid))")))
        items.append(Item(title: String(localized: "Building \(plan.weeks.count) weeks"),
                          detail: String(localized: "From \(format.distance(plan.inputs.currentWeeklyMeters)) up to \(format.distance(plan.weeks.map(\.targetMeters).max() ?? 0)) a week, then a taper")))
        items.append(Item(title: String(localized: "Checking the safety rules"),
                          detail: PlanValidator.validate(plan).isEmpty
                              ? String(localized: "Gradual build and easy days between hard ones, checked week by week")
                              : String(localized: "Adjusted to stay within the rules")))
        return items
    }

    private func volumeText(_ result: HistoryCalibration.Result, _ format: DisplayFormat) -> String {
        switch result.volume {
        case .notEnoughHistory(let runs):
            runs == 0 ? String(localized: "No runs in Apple Health yet, so we've gone with your answers")
                      : String(localized: "Only \(runs) runs recorded lately, so we've gone with your answers")
        case .confirmed(let observed):
            String(localized: "About \(format.distance(observed)) a week, as you said")
        case .lowered(let stated, let observed):
            String(localized: "You said \(format.distance(stated)) a week; Health shows about \(format.distance(observed)), so we start from that")
        case .raised(_, let observed, let used):
            String(localized: "Health shows about \(format.distance(observed)) a week; we start from \(format.distance(used)) to build up safely")
        }
    }

    private func fitnessText(_ format: DisplayFormat) -> String {
        if case .fromRun(let meters, let seconds, let date)? = calibration?.fitness {
            return String(localized: "From your \(format.distance(meters)) run in \(DisplayFormat.clock(seconds)) on \(date.formatted(.dateTime.day().month(.abbreviated)))")
        }
        return draft.hasRecentRace
            ? String(localized: "From your \(draft.recentDistance.name) in \(DisplayFormat.clock(draft.recentTimeSeconds))")
            : String(localized: "Estimated from your experience and weekly distance")
    }
}

/// The finished plan, revealed in a short sequence: the headline, then the numbers counting up, then the weeks
/// growing in from the left. It plays once, never delays the "Start my plan" button, and with Reduce Motion on
/// it simply fades in.
private struct ReviewStep: View {
    let draft: OnboardingDraft
    let preview: Result<TrainingPlan, PlanError>?
    @Environment(\.unitSystem) private var units
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var chartReveal = 0.0

    var body: some View {
        let format = DisplayFormat(units: units)
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            switch preview {
            case .success(let plan):
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 52, height: 52)
                        .background(Theme.accent, in: Circle())
                        .scaleEffect(stage >= 1 ? 1 : 0.4)
                        .opacity(stage >= 1 ? 1 : 0)
                    StepHeader(title: String(localized: "Your plan is ready"),
                               subtitle: String(localized: "\(draft.goal.name) on \(plan.inputs.raceDate.dayMonth)"))
                        .opacity(stage >= 1 ? 1 : 0)
                        .offset(y: stage >= 1 || reduceMotion ? 0 : 12)
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack {
                            Metric(value: stage >= 2 ? "\(plan.weeks.count)" : "0", label: String(localized: "weeks"))
                            Spacer()
                            Metric(value: stage >= 2 ? format.distance(plan.weeks.map(\.targetMeters).max() ?? 0)
                                                    : format.distance(0),
                                   label: String(localized: "peak week"))
                            Spacer()
                            Metric(value: stage >= 2 ? DisplayFormat.clock(plan.predictedRaceSeconds) : "0:00:00",
                                   label: String(localized: "predicted today"))
                        }
                        .contentTransition(.numericText())
                        WeeklyVolumeChart(plan: plan, reveal: chartReveal)
                        PhaseLegend(phases: Phase.allCases.filter { p in plan.weeks.contains { $0.phase == p } })
                            .opacity(stage >= 3 ? 1 : 0)
                    }
                }
                .opacity(stage >= 2 ? 1 : 0)
                .scaleEffect(stage >= 2 || reduceMotion ? 1 : 0.97, anchor: .top)
                Group {
                    if !plan.warnings.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                                ForEach(plan.warnings, id: \.self) { warning in
                                    Label(warning.message(format), systemImage: "info.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    }
                    Text("Your predicted time improves as you train. The plan adapts if you miss runs or your fitness changes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .opacity(stage >= 3 ? 1 : 0)
                .task { await reveal() }
                .sensoryFeedback(.success, trigger: stage >= 1)
            case .failure(let error):
                StepHeader(title: String(localized: "Let's adjust something"), subtitle: error.message)
            case nil:
                ProgressView()
            }
        }
    }

    private func reveal() async {
        guard stage == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { stage = 3 }
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

extension PlanError {
    var message: String {
        switch self {
        case .raceNotAfterStart: String(localized: "The race date needs to be in the future.")
        case .tooFewRunDays: String(localized: "Choose at least two days to run.")
        case .longRunDayNotARunDay: String(localized: "Your long run day must be one of your run days.")
        case .invalidPerformance: String(localized: "That race time doesn't look right. Check the distance and time.")
        case .invalidWeeklyVolume: String(localized: "That weekly distance doesn't look right.")
        case .planFinished: String(localized: "This plan has finished.")
        }
    }
}
