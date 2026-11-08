import SwiftData
import SwiftUI
import PlanEngine

/// Opens the races screen (from Settings or the Race day tile).
struct RacesRoute: Hashable {}

/// The goal race and other races. Pushed from Settings rather than being a tab of its own.
struct RacesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var editing: RaceRecord?
    @State private var adding = false

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if let plan = model.plan { GoalRaceCard(plan: plan) }

                    let upcoming = model.races.filter { $0.date >= model.today }
                    let past = model.races.filter { $0.date < model.today }.reversed()
                    SectionTitle(text: String(localized: "Other races"))
                        .padding(.top, Theme.Spacing.s)
                    if model.races.isEmpty {
                        Text("Add tune-up races and past results. A recent result can update your training paces.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(upcoming) { race in RaceRow(race: race).onTapGesture { editing = race } }
                    if !past.isEmpty {
                        Text("Past").font(.headline).foregroundStyle(Theme.secondaryInk).padding(.top, Theme.Spacing.s)
                        ForEach(Array(past)) { race in RaceRow(race: race).onTapGesture { editing = race } }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .screenBackground()
            .navigationTitle("Races")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add race")
                }
            }
            .sheet(isPresented: $adding) { RaceEditor(race: nil) }
            .sheet(item: $editing) { RaceEditor(race: $0) }
    }
}

private struct GoalRaceCard: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model
    @State private var changingDate = false
    @State private var changingGoal = false

    var body: some View {
        let days = max(0, model.today.days(until: plan.inputs.raceDate))
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal race").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    Text(plan.inputs.goal.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text(plan.inputs.raceDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                KindIcon(kind: .race, size: 52, onDark: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(days)")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.sheen)
                Text(days == 1 ? "day to go" : "days to go").font(.headline).foregroundStyle(.white.opacity(0.7))
            }
            if let prediction = model.prediction {
                HStack {
                    raceMetric(DisplayFormat.clock(prediction.seconds), String(localized: "predicted"))
                    raceMetric(plan.inputs.goalTimeSeconds.map(DisplayFormat.clock) ?? "–", String(localized: "goal"))
                }
                Text("Likely range \(DisplayFormat.clock(prediction.fastestSeconds))–\(DisplayFormat.clock(prediction.slowestSeconds)), based on your current fitness.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: Theme.Spacing.s) {
                Button("Change date") { changingDate = true }.buttonStyle(GlassCardButtonStyle())
                Button(plan.inputs.goalTimeSeconds == nil ? "Set goal time" : "Edit goal") { changingGoal = true }
                    .buttonStyle(GlassCardButtonStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkGlass(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.top, Theme.Spacing.s)
        .sheet(isPresented: $changingDate) { RaceDateSheet(current: plan.inputs.raceDate) }
        .sheet(isPresented: $changingGoal) { GoalTimeSheet(plan: plan) }
    }
}

extension GoalRaceCard {
    fileprivate func raceMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Buttons on the dark goal-race card: a subtle light capsule.
private struct GlassCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
    }
}

private struct RaceDateSheet: View {
    let current: LocalDate
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    @State private var updating: PlanChangeRequest?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Race date", selection: $date,
                           in: Calendar.current.date(byAdding: .day, value: 1, to: .now)!...,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Section {
                    Text("Your remaining weeks are re-planned from where your training is now. Completed workouts stay as they are.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
            .navigationTitle("Race date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update plan") {
                        updating = .raceDate(LocalDate(date))
                    }
                    .disabled(LocalDate(date) == current)
                }
            }
            .onAppear { if updating == nil { date = current.date() } }
            .fullScreenCover(item: $updating) { request in
                PlanUpdateView(request: request) {
                    updating = nil
                    dismiss()
                }
            }
        }
    }
}

private struct GoalTimeSheet: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var hasGoal = true
    @State private var seconds: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Toggle("I have a goal time", isOn: $hasGoal.animation())
                if hasGoal {
                    DurationWheels(seconds: $seconds, showHours: plan.inputs.goal != .fiveK)
                }
                Section {
                    Text("Your goal is for motivation and tracking. Training paces always come from your current fitness.")
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
            .navigationTitle("Goal time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.setGoalTime(hasGoal && seconds > 0 ? seconds : nil)
                        dismiss()
                    }
                }
            }
            .onAppear {
                seconds = plan.inputs.goalTimeSeconds ?? OnboardingDraft.typicalTime(plan.inputs.goal)
            }
        }
    }
}

private struct RaceRow: View {
    let race: RaceRecord
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.today.days(until: race.date)
        HStack(spacing: 12) {
            KindIcon(kind: .race, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(race.name.isEmpty ? race.distance.name : race.name)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(race.distance.name) · \(race.date.formatted(.dateTime.day().month().year()))")
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            if let result = race.resultSeconds {
                Text(DisplayFormat.clock(result)).font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(Theme.ink)
            } else if days >= 0 {
                if race.persistentModelID == model.races.first(where: { $0.date >= model.today && $0.resultSeconds == nil })?.persistentModelID {
                    SheenPill(text: String(localized: "Next · in \(days) days"))
                } else {
                    Text(String(localized: "in \(days) days")).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Add or edit a race. Entering a result for a recent race offers to update training paces.
private struct RaceEditor: View {
    let race: RaceRecord?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var distance: RaceDistance = .tenK
    @State private var date = Date()
    @State private var hasGoal = false
    @State private var goalSeconds: Double = 0
    @State private var hasResult = false
    @State private var resultSeconds: Double = 0
    @State private var offerPaceUpdate = false

    private var isPast: Bool { LocalDate(date) <= model.today }

    @State private var updating: PlanChangeRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (optional)", text: $name)
                    Picker("Distance", selection: $distance) {
                        ForEach(RaceDistance.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section {
                    Toggle("Goal time", isOn: $hasGoal.animation())
                    if hasGoal { DurationWheels(seconds: $goalSeconds, showHours: distance != .fiveK) }
                }
                if isPast {
                    Section {
                        Toggle("Finish time", isOn: $hasResult.animation())
                        if hasResult { DurationWheels(seconds: $resultSeconds, showHours: distance != .fiveK) }
                    }
                }
                if race != nil {
                    Section {
                        Button("Delete race", role: .destructive) {
                            if let race { model.deleteRace(race) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(race == nil ? "Add race" : "Edit race")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear(perform: load)
            .onChange(of: distance) { _, new in
                if !hasGoal { goalSeconds = OnboardingDraft.typicalTime(new) }
                if !hasResult { resultSeconds = OnboardingDraft.typicalTime(new) }
            }
            .fullScreenCover(item: $updating) { request in
                PlanUpdateView(request: request) {
                    updating = nil
                    dismiss()
                }
            }
            .alert("Update your training paces?", isPresented: $offerPaceUpdate) {
                Button("Update paces") {
                    updating = .raceResult(RacePerformance(distance, timeSeconds: resultSeconds, date: LocalDate(date)))
                }
                Button("Not now", role: .cancel) { dismiss() }
            } message: {
                Text("This result can be used to recalculate your fitness and training paces for the rest of your plan.")
            }
        }
    }

    private func load() {
        guard let race else {
            goalSeconds = OnboardingDraft.typicalTime(distance)
            resultSeconds = OnboardingDraft.typicalTime(distance)
            return
        }
        name = race.name
        distance = race.distance
        date = race.date.date()
        hasGoal = race.goalSeconds != nil
        goalSeconds = race.goalSeconds ?? OnboardingDraft.typicalTime(race.distance)
        hasResult = race.resultSeconds != nil
        resultSeconds = race.resultSeconds ?? OnboardingDraft.typicalTime(race.distance)
    }

    private func save() {
        let result = isPast && hasResult && resultSeconds > 0 ? resultSeconds : nil
        let isNewResult = result != nil && result != race?.resultSeconds
        if let race {
            race.name = name
            race.distance = distance
            race.date = LocalDate(date)
            race.goalSeconds = hasGoal ? goalSeconds : nil
            race.resultSeconds = result
            model.saveRaces()
        } else {
            model.addRace(RaceRecord(name: name, distance: distance, date: LocalDate(date),
                                     goalSeconds: hasGoal ? goalSeconds : nil, resultSeconds: result))
        }
        // Only recent results are worth re-basing paces on.
        if isNewResult, model.plan != nil, LocalDate(date).days(until: model.today) <= 90 {
            offerPaceUpdate = true
        } else {
            dismiss()
        }
    }
}
