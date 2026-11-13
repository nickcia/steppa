import SwiftUI

/// What changed in this update, shown once when someone who already has a plan opens the new version. People
/// installing for the first time don't see it: everything is new to them.
///
/// For a new update, change `id` and `items`. Leaving `id` as it is shows nothing new.
nonisolated struct WhatsNew: Sendable {
    struct Item: Identifiable, Sendable {
        var symbol: String
        var title: String
        var detail: String
        var id: String { title }
    }

    var id: String
    var items: [Item]

    static let current = WhatsNew(id: "2026-11-run-analytics", items: [
        Item(symbol: "chart.xyaxis.line",
             title: String(localized: "Much more on every run"),
             detail: String(localized: "Open a run for its route, best efforts, heart rate, running form, power, elevation and conditions, each with its own chart.")),
        Item(symbol: "heart",
             title: String(localized: "Smarter heart-rate zones"),
             detail: String(localized: "Zones come from your watch, your runs or your own maximum heart rate, and Today lets you know when a run suggests they need a change.")),
        Item(symbol: "chart.bar",
             title: String(localized: "See a workout's shape"),
             detail: String(localized: "Workouts show a small chart of their steps, so you can see warm-up, efforts and recoveries at a glance.")),
        Item(symbol: "figure.run",
             title: String(localized: "Clearer names"),
             detail: String(localized: "Easy runs that end with strides are called \"Easy run with strides\", and Strava titles read \"Week 5 - Easy run 9.5 km\".")),
    ])

    static let seenKey = "whatsNew.seen"

    /// Whether this update's notes still need showing.
    static var isUnseen: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-whatsNew") { return true }
        #endif
        return UserDefaults.standard.string(forKey: seenKey) != current.id
    }

    static func markSeen() { UserDefaults.standard.set(current.id, forKey: seenKey) }
}

struct WhatsNewView: View {
    var whatsNew = WhatsNew.current
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("What's new")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, Theme.Spacing.xl)
                    ForEach(whatsNew.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 44, height: 44)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            Button("Continue") { dismiss() }
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
        }
        .background(Theme.background)
        .presentationDetents([.large])
        .onDisappear { WhatsNew.markSeen() }
    }
}
