import SwiftUI
import PlanEngine

/// "Your plan changed because…" banner, shown until dismissed.
struct PlanChangeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let change = model.unseenChange {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.sheen, in: Circle())
                    .shadow(color: Theme.sheenColors[1].opacity(0.3), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Your plan has been updated")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    ForEach(change.reasons, id: \.self) { reason in
                        Text(reason.message(model.format))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if change.reasons.contains(where: \.isAboutMissedTraining) {
                        Text("Ran but didn't tick it off? Mark those runs as done, then undo this change.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    HStack(spacing: Theme.Spacing.s) {
                        Button("Got it") { withAnimation { model.markChangesSeen() } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                        if change.previousPlanData != nil {
                            Button("Undo") { withAnimation { model.undo(change) } }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.subtle.opacity(0.7), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.Spacing.xs)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .currentHighlight(true, cornerRadius: Theme.Radius.card)
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
                Label("Move", systemImage: "arrow.left.arrow.right")
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
                        // A planned run can't land under one of the athlete's own workouts (it would be hidden).
                        let available = date >= model.today && date != workout.date && (raceDate.map { date < $0 } ?? true)
                            && (workout.isCustom || existing?.isCustom != true)
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
                                    Text(existing.map { date == workout.date ? String(localized: "Currently here")
                                        : workout.isCustom ? String(localized: "Replaces \($0.kind.casualName)")
                                        : String(localized: "Swap with \($0.name.lowercased())") }
                                         ?? String(localized: "Rest day"))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                            }
                        }
                        .disabled(!available)
                    }
                } footer: {
                    if workout.isCustom {
                        Text("Your workout takes the place of whatever is on that day.")
                    } else {
                        Text("Workouts move within the same week so your weekly distance stays the same. Hard days are kept apart.")
                    }
                }
            }
            .navigationTitle(workout.isCustom ? String(localized: "Move \(workout.name)") : String(localized: "Move \(workout.name.lowercased())"))
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
