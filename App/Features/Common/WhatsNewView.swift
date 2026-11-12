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

    static let current = WhatsNew(id: "2026-11-garmin", items: [
        Item(symbol: "applewatch.radiowaves.left.and.right",
             title: String(localized: "Garmin, in one tap"),
             detail: String(localized: "Connect Garmin Connect™ in Settings. Your next two weeks of workouts appear on your watch, with every step and pace, and follow your plan as it changes.")),
        Item(symbol: "arrow.down.heart",
             title: String(localized: "Garmin runs come back"),
             detail: String(localized: "Runs you finish on your Garmin tick off your plan and show their splits, heart rate and cadence here.")),
        Item(symbol: "applewatch",
             title: String(localized: "Other watches"),
             detail: String(localized: "COROS, Suunto and Wahoo still connect through Intervals.icu, and Apple Watch works as before.")),
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
