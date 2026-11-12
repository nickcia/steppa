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

    static let current = WhatsNew(id: "2026-11-trends", items: [
        Item(symbol: "waveform.path.ecg",
             title: String(localized: "Fitness, fatigue and form"),
             detail: String(localized: "Progress now shows how your fitness is building, how tired you are, and your fitness score and threshold pace over time.")),
        Item(symbol: "map",
             title: String(localized: "Your runs, with maps"),
             detail: String(localized: "Recent runs show their route. After a run, save a picture of it sized for Strava, or share it anywhere.")),
        Item(symbol: "drop",
             title: String(localized: "Fuel on the run"),
             detail: String(localized: "Runs over 75 minutes come with a gel plan: how many, and when to take them.")),
        Item(symbol: "shoe",
             title: String(localized: "Gear and shared workouts"),
             detail: String(localized: "Track the distance on your shoes in Settings › Gear, and share a workout with a friend so you can run it together.")),
        Item(symbol: "link",
             title: String(localized: "Connections in one place"),
             detail: String(localized: "Apple Health, your watch and Strava now live in Settings › Connections. Heart-rate zones now update from your runs.")),
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
