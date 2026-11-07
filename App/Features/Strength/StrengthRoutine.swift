import SwiftUI
import PlanEngine

/// The bodyweight routines behind each strength level. No equipment; a wall or a step for balance is enough.
struct StrengthRoutine {
    struct Exercise: Identifiable, Hashable {
        let name: String
        let amount: String
        let cue: String
        var id: String { name }
    }

    let title: String
    let summary: String
    let rounds: Int
    let minutes: Int
    let exercises: [Exercise]

    static func `for`(_ level: StrengthSchedule.Level) -> StrengthRoutine {
        switch level {
        case .foundation:
            StrengthRoutine(
                title: String(localized: "Strength foundation"),
                summary: String(localized: "Builds the strength that keeps running form together when you're tired."),
                rounds: 3, minutes: 25, exercises: [
                    .init(name: String(localized: "Squats"), amount: String(localized: "12"),
                          cue: String(localized: "Sit back and down, knees over toes, chest up.")),
                    .init(name: String(localized: "Reverse lunges"), amount: String(localized: "10 each leg"),
                          cue: String(localized: "Step back, lower until both knees are at right angles.")),
                    .init(name: String(localized: "Glute bridges"), amount: String(localized: "15"),
                          cue: String(localized: "Drive through your heels, squeeze at the top for a second.")),
                    .init(name: String(localized: "Single-leg calf raises"), amount: String(localized: "15 each leg"),
                          cue: String(localized: "Slow on the way down. Hold a wall for balance.")),
                    .init(name: String(localized: "Single-leg Romanian deadlift"), amount: String(localized: "10 each leg"),
                          cue: String(localized: "Hinge at the hip with a flat back; reach towards the floor.")),
                    .init(name: String(localized: "Plank"), amount: String(localized: "40 s"),
                          cue: String(localized: "Straight line from head to heels; don't let your hips sag.")),
                    .init(name: String(localized: "Side plank"), amount: String(localized: "30 s each side"),
                          cue: String(localized: "Hips high; drop to your knees if needed.")),
                    .init(name: String(localized: "Dead bug"), amount: String(localized: "10 each side"),
                          cue: String(localized: "Lower back stays pressed to the floor.")),
                ])
        case .maintenance:
            StrengthRoutine(
                title: String(localized: "Strength maintenance"),
                summary: String(localized: "Keeps the strength you've built without adding fatigue to harder training."),
                rounds: 2, minutes: 18, exercises: [
                    .init(name: String(localized: "Split squats"), amount: String(localized: "10 each leg"),
                          cue: String(localized: "Back knee towards the floor, front heel down.")),
                    .init(name: String(localized: "Single-leg glute bridges"), amount: String(localized: "12 each leg"),
                          cue: String(localized: "Keep your hips level as you lift.")),
                    .init(name: String(localized: "Step-ups"), amount: String(localized: "10 each leg"),
                          cue: String(localized: "Push through the top foot; don't spring off the bottom one.")),
                    .init(name: String(localized: "Calf raises"), amount: String(localized: "20"),
                          cue: String(localized: "On a step if you have one; full range, slow down.")),
                    .init(name: String(localized: "Plank"), amount: String(localized: "45 s"),
                          cue: String(localized: "Brace as if someone's about to poke your stomach.")),
                    .init(name: String(localized: "Side plank"), amount: String(localized: "30 s each side"),
                          cue: String(localized: "Stack your feet or stagger them for balance.")),
                ])
        case .light:
            StrengthRoutine(
                title: String(localized: "Light strength"),
                summary: String(localized: "A short round to stay loose before race day. Nothing should feel hard."),
                rounds: 1, minutes: 10, exercises: [
                    .init(name: String(localized: "Squats"), amount: String(localized: "10"),
                          cue: String(localized: "Easy pace, full range.")),
                    .init(name: String(localized: "Glute bridges"), amount: String(localized: "12"),
                          cue: String(localized: "Squeeze at the top.")),
                    .init(name: String(localized: "Calf raises"), amount: String(localized: "15"),
                          cue: String(localized: "Smooth and controlled.")),
                    .init(name: String(localized: "Plank"), amount: String(localized: "30 s"),
                          cue: String(localized: "Just hold good form.")),
                    .init(name: String(localized: "Leg swings"), amount: String(localized: "10 each way, each leg"),
                          cue: String(localized: "Front to back, then side to side, holding a wall.")),
                ])
        }
    }

    /// For calendar notes and sharing as text.
    var text: String {
        ([String(localized: "\(rounds) rounds · about \(minutes) min")]
         + exercises.map { "\($0.name) · \($0.amount)" }).joined(separator: "\n")
    }
}

/// One strength session: the exercises, how to do them, and marking it done.
struct StrengthDetailView: View {
    let session: StrengthSchedule.Session
    @Environment(AppModel.self) private var model

    var body: some View {
        let routine = StrengthRoutine.for(session.level)
        let done = model.isStrengthDone(session)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    Text(routine.title).font(.system(size: 32, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(routine.summary).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, Theme.Spacing.s)

                HStack(spacing: 12) {
                    tile("\(routine.rounds)", routine.rounds == 1 ? String(localized: "round") : String(localized: "rounds"))
                    tile("~\(routine.minutes) min", String(localized: "time"))
                    tile("\(routine.exercises.count)", String(localized: "exercises"))
                }

                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(routine.rounds == 1 ? "Do each once" : "Do the list \(routine.rounds) times, resting a minute between rounds")
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { index, exercise in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.onAccent)
                                    .frame(width: 26, height: 26)
                                    .background(StrengthStyle.color, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(exercise.name).font(.headline).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text(exercise.amount).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                                    }
                                    Text(exercise.cue).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                                }
                            }
                        }
                    }
                }

                Text("Stop if anything hurts. Strength work should leave you feeling worked, not sore for days.")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)

                if session.date <= model.today {
                    if done {
                        HStack {
                            Label("Done", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Theme.green)
                            Spacer()
                            Button("Undo") { model.setStrengthDone(false, for: session) }.font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Button("Mark as done") { model.setStrengthDone(true, for: session) }
                            .buttonStyle(.primary)
                            .sensoryFeedback(.success, trigger: done)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// The strength session as a compact card (Today), opening its detail.
struct StrengthCard: View {
    let session: StrengthSchedule.Session
    @Environment(AppModel.self) private var model

    var body: some View {
        let routine = StrengthRoutine.for(session.level)
        NavigationLink(value: session) {
            HStack(spacing: 14) {
                Image(systemName: StrengthStyle.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(StrengthStyle.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.title).font(.headline).foregroundStyle(Theme.ink)
                    Text("~\(routine.minutes) min · \(routine.exercises.count) exercises · bodyweight")
                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
                Spacer()
                if model.isStrengthDone(session) {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.green)
                } else {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                }
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

enum StrengthStyle {
    static let color = Color(hex: 0x8E7CF0)
    static let gradient = LinearGradient(colors: [Color(hex: 0xC6B9FF), color, Color(hex: 0x5B47C9)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let symbol = "figure.strengthtraining.functional"
}
