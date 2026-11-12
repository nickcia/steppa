import SwiftUI
import PlanEngine

/// The Share button on a workout's page: sends it as a ".trackstar" file, with a line of text for anyone reading
/// the message without TrackStar.
struct ShareWorkoutButton: View {
    let workout: Workout
    @Environment(AppModel.self) private var model

    var body: some View {
        if let shared = model.sharedWorkout(for: workout) {
            let summary = WorkoutDescriber(format: model.format).summary(workout)
            ShareLink(item: SharedWorkoutFile(workout: shared),
                      subject: Text(shared.name),
                      message: Text("\(shared.name): \(summary). Open it in TrackStar to save it and run it with me."),
                      preview: SharePreview(shared.name, image: Image(systemName: "figure.run"))) {
                Label("Share workout", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// A workout someone shared, opened in TrackStar: what it is, at whose paces, and which day to run it.
struct SharedWorkoutSheet: View {
    let shared: SharedWorkout
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choice: SharedWorkout.PaceChoice = .mine
    @State private var day = Date.now
    @State private var keep = true
    @State private var added: Workout?

    /// Before a plan exists there are no paces of their own, and nowhere to put it.
    private var hasPlan: Bool { model.plan != nil }
    private var date: LocalDate { LocalDate(day) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header
                    if hasPlan, shared.hasPaces { pacePicker }
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            WorkoutMetrics(workout: preview)
                            Text("Structure").font(.headline).foregroundStyle(Theme.ink)
                            WorkoutStepsView(workout: preview)
                                .animation(.snappy, value: choice)
                                .contentTransition(.numericText())
                        }
                    }
                    if hasPlan { dayCard } else {
                        Text("Finish setting up your plan, then open the workout again to add it to a day.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .screenBackground()
            .navigationTitle("Shared workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(hasPlan ? "Cancel" : "Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if hasPlan {
                    Button(String(localized: "Add to \(date.shortDayMonth)")) { add() }
                        .buttonStyle(.primary)
                        .disabled(!model.canAddWorkout(on: date))
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background(.bar)
                }
            }
        }
        .onAppear { day = firstFreeDay.date() }
        .alert("Added to your plan", isPresented: Binding(get: { added != nil }, set: { if !$0 { added = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            Text("\(shared.name) is on \(date.formatted(.dateTime.weekday(.wide).day().month(.wide))). It goes to your watch and calendar with the rest of your plan.")
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            KindIcon(kind: .custom, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(shared.name).font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Theme.ink)
                Text("Shared with you").font(.subheadline).foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var pacePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Picker("Paces", selection: $choice) {
                Text("My paces").tag(SharedWorkout.PaceChoice.mine)
                Text("Their paces").tag(SharedWorkout.PaceChoice.theirs)
            }
            .pickerStyle(.segmented)
            Text(choice == .mine
                 ? "Each zone at your own pace, from your fitness. Run it together, each at your own effort."
                 : "The exact paces they run, to stay side by side. Make sure they suit you.")
                .font(.caption).foregroundStyle(Theme.secondaryInk)
        }
    }

    private var dayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                DatePicker("Day", selection: $day, in: range, displayedComponents: .date)
                    .font(.headline)
                if let planned = model.plannedWorkout(on: date), model.canAddWorkout(on: date) {
                    Text(String(localized: "Replaces your \(planned.kind.casualName) that day. Remove it later to bring that back."))
                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
                Toggle("Save to My workouts", isOn: $keep)
                    .font(.subheadline)
            }
        }
    }

    /// The workout as it would run, on the chosen day.
    private var preview: Workout {
        // Without a plan there are no paces of their own; the sender's paces cover everything with a target.
        let paces = model.plan?.paces ?? PaceTable(score: 45, goal: .halfMarathon)
        return shared.template(paces: hasPlan ? choice : .theirs).workout(on: date, id: "shared", paces: paces)
    }

    private var range: ClosedRange<Date> {
        let start = model.today.date()
        let end = (model.plan?.inputs.raceDate.adding(days: -1) ?? model.today).date()
        return start...max(start, end)
    }

    /// Today if there's nothing done yet, else the next day the plan has room for it.
    private var firstFreeDay: LocalDate {
        (0..<14).map { model.today.adding(days: $0) }.first { day in
            model.canAddWorkout(on: day) && model.workout(on: day).map { model.status(of: $0) == nil } ?? true
        } ?? model.today
    }

    private func add() {
        added = model.addSharedWorkout(shared, paces: hasPlan ? choice : .theirs, on: date, keep: keep)
    }
}
