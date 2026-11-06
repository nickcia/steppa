import SwiftUI
import PlanEngine

/// "Your plan changed because…" banner, shown until dismissed.
struct PlanChangeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let change = model.unseenChange {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Label("Your plan has been updated", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                    ForEach(change.reasons, id: \.self) { reason in
                        Text(reason.message(model.format))
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                    }
                    if change.reasons.contains(where: \.isAboutMissedTraining) {
                        Text("Ran but didn't tick it off? Mark those runs as done, then undo this change.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    HStack(spacing: Theme.Spacing.l) {
                        Button("Got it") { withAnimation { model.markChangesSeen() } }
                        if change.previousPlanData != nil {
                            Button("Undo") { withAnimation { model.undo(change) } }
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, Theme.Spacing.xs)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1.5))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

extension AdaptationReason {
    var isAboutMissedTraining: Bool {
        switch self {
        case .missedTraining, .returningFromBreak: true
        default: false
        }
    }
}

/// Button that opens the move sheet, for future workouts.
struct MoveWorkoutButton: View {
    let workout: Workout
    @Environment(AppModel.self) private var model
    @State private var showing = false

    var body: some View {
        if workout.kind != .race, workout.date >= model.today {
            Button { showing = true } label: {
                Label("Move", systemImage: "calendar.badge.clock")
            }
            .font(.subheadline.weight(.semibold))
            .sheet(isPresented: $showing) {
                MoveWorkoutSheet(workout: workout)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Lets the athlete pick another day this week. Taken days swap.
struct MoveWorkoutSheet: View {
    let workout: Workout
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        let monday = workout.date.startOfWeek
        let raceDate = model.plan?.inputs.raceDate
        NavigationStack {
            List {
                Section {
                    ForEach(0..<7, id: \.self) { offset in
                        let date = monday.adding(days: offset)
                        let existing = model.workout(on: date)
                        let available = date >= model.today && date != workout.date && (raceDate.map { date < $0 } ?? true)
                        Button {
                            if model.move(workout, to: date) {
                                dismiss()
                            } else {
                                error = model.lastError
                                model.lastError = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                KindIcon(kind: existing?.kind, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(available ? Theme.ink : Theme.secondaryInk)
                                    Text(existing.map { date == workout.date ? String(localized: "Currently here") : String(localized: "Swap with \($0.kind.name.lowercased())") }
                                         ?? String(localized: "Rest day"))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                            }
                        }
                        .disabled(!available)
                    }
                } footer: {
                    Text("Workouts move within the same week so your weekly distance stays the same. Hard days are kept apart.")
                }
            }
            .navigationTitle(String(localized: "Move \(workout.kind.name.lowercased())"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .alert("Can't move here", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}
