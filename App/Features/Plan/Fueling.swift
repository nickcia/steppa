import PlanEngine
import SwiftUI

// Carbohydrate during a run: how much an hour, how many gels, and when to take them. Only runs long enough to need
// it get any: under about 75 minutes the body's own stores are plenty. The rules follow the ACSM / Academy of
// Nutrition and Dietetics / Dietitians of Canada position stand (Thomas, Erdman & Burke, 2016), Jeukendrup's
// reviews on carbohydrate during exercise (2014) and multiple transportable carbohydrates, and his review on training
// the gut (2017). Amounts are for recreational runners: going higher only with practice.

/// Gels and carbs for one run.
nonisolated struct FuelingPlan: Equatable, Sendable {
    /// Carbohydrate to take per hour.
    var gramsPerHour: ClosedRange<Int>
    /// When to take each gel, in minutes from the start.
    var gelMinutes: [Int]
    var gels: Int { gelMinutes.count }
    /// One or two sentences on how to take them.
    var advice: String
}

nonisolated enum Fueling {
    /// A typical gel; most hold 20–30 g of carbohydrate.
    static let gelGrams = 25.0
    /// The first gel goes in about here; before it, the body's own stores are plenty.
    static let firstGelMinute = 35
    /// Shorter runs don't need carbs on the way.
    static let minimumMinutes = 75.0

    /// nil for runs too short to need carbs.
    static func plan(for workout: Workout) -> FuelingPlan? {
        plan(minutes: workout.totalSeconds / 60, isRace: workout.kind == .race)
    }

    static func plan(minutes: Double, isRace: Bool) -> FuelingPlan? {
        guard minutes >= minimumMinutes else { return nil }
        let rate: ClosedRange<Int> = minutes < 150 ? 30...60 : 60...90
        let times = gelMinutes(minutes: minutes, rate: rate)
        let every = times.count > 1 ? times[1] - times[0] : 0
        var advice = every > 0
            ? String(localized: "\(rate.lowerBound)–\(rate.upperBound) g of carbs an hour: a 25 g gel about every \(every) minutes, starting around \(firstGelMinute) minutes in, each with a few mouthfuls of water.")
            : String(localized: "\(rate.lowerBound)–\(rate.upperBound) g of carbs an hour: one 25 g gel around \(firstGelMinute) minutes in, with a few mouthfuls of water.")
        if rate.upperBound > 60 {
            advice += " " + String(localized: "Above 60 g an hour, use gels that mix glucose and fructose, and build up to it over several long runs.")
        }
        if isRace {
            advice += " " + String(localized: "Use the gels you've trained with.")
        } else if minutes >= 90 {
            advice += " " + String(localized: "A good run to practise your race fueling.")
        }
        return FuelingPlan(gramsPerHour: rate, gelMinutes: times, advice: advice)
    }

    /// Gels at the middle of the hourly range, evenly spaced from the first gel, with none in the last 10 minutes.
    static func gelMinutes(minutes: Double, rate: ClosedRange<Int>) -> [Int] {
        let perHour = Double(rate.lowerBound + rate.upperBound) / 2 / gelGrams
        // Rounded to 5 minutes: easy to remember and to set as a watch alert.
        let every = max(15, Int((60 / perHour / 5).rounded()) * 5)
        let last = Int(minutes) - 10
        guard last >= firstGelMinute else { return [firstGelMinute] }
        return Array(stride(from: firstGelMinute, through: last, by: every))
    }
}

/// The Fuel card on a workout long enough to need carbs on the way.
struct FuelingCard: View {
    let workout: Workout
    @State private var showingAbout = false

    var body: some View {
        if let plan = Fueling.plan(for: workout) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack {
                        Label("Fuel on the run", systemImage: "drop")
                            .font(.headline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(plan.gels == 1 ? String(localized: "1 gel") : String(localized: "\(plan.gels) gels"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    // The timetable: when each gel goes in.
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(plan.gelMinutes, id: \.self) { minute in
                                Text(DisplayFormat.duration(Double(minute) * 60))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.subtle, in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(String(localized: "Gels at \(plan.gelMinutes.map { DisplayFormat.duration(Double($0) * 60) }.formatted(.list(type: .and)))"))
                    Text(plan.advice)
                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("About fueling") { showingAbout = true }
                        .font(.subheadline.weight(.semibold))
                }
            }
            .sheet(isPresented: $showingAbout) { FuelingAboutView() }
        }
    }
}

/// How the fueling advice works, its limits, and where it comes from.
struct FuelingAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your body stores enough carbohydrate for about an hour and a half of hard running. Past that, carbs taken while you run keep your pace up, so runs over about 75 minutes get a gel plan. Shorter runs don't need any.")
                    Text("A gel is usually 20–30 g of carbs; counts here assume 25 g. Take standard gels with a few mouthfuls of water. Gels that mix glucose and fructose let you absorb more than 60 g an hour.")
                } header: {
                    Text("How it works")
                }
                Section {
                    Text("Practise on long runs: your gut gets used to carbs with training. Start around 30 g an hour and build up over a few weeks. Nothing new on race day.")
                    Text("Drink to thirst. Drinking more than you need, especially in long races, can be dangerous; add salt in the heat.")
                } header: {
                    Text("Tips")
                }
                Section {
                    Text("This is general guidance for healthy adults. Needs vary with body size, pace, heat and how your stomach copes. If you have diabetes, a digestive condition, an eating disorder or another medical condition, or are pregnant, ask a doctor or registered sports dietitian first.")
                } header: {
                    Text("Your needs")
                }
                Section {
                    Text("Based on the ACSM, Academy of Nutrition and Dietetics and Dietitians of Canada position stand on nutrition and athletic performance (2016), and Jeukendrup's research on carbohydrate during exercise and training the gut.")
                        .font(.footnote)
                } header: {
                    Text("Sources")
                }
            }
            .navigationTitle("Fueling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
