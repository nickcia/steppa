import SwiftUI
import PlanEngine

/// Guided setup for Garmin, COROS, Suunto and Wahoo after signing in to Intervals.icu: the watch has to be linked on
/// Intervals.icu itself (watch makers don't let other apps do it), so this walks through that one step and notices
/// when it's done.
struct WatchSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var brand: IntervalsAthlete.Link.Service = .garmin
    @State private var checking = false
    @State private var openedIntervals = false

    private var ready: IntervalsAthlete.Link? { model.intervalsAthlete?.links.first { $0.uploading } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ready == nil ? "Connect your watch" : "You're all set")
                            .font(.largeTitle.weight(.bold)).foregroundStyle(Theme.ink)
                        Text(ready == nil
                             ? "One more step: link your watch to Intervals.icu. It takes about a minute, and you only do it once."
                             : "Your workouts are on their way to your \(ready?.name ?? "watch").")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        step(1, done: true, title: String(localized: "Sign in to Intervals.icu"),
                             detail: String(localized: "Done. Intervals.icu passes your workouts on to your watch."))
                        step(2, done: ready != nil, title: String(localized: "Link your \(brandName)"),
                             detail: ready == nil ? nil : String(localized: "Linked, receiving workouts."))
                        if ready == nil { linkInstructions }
                        step(3, done: ready != nil, title: String(localized: "Workouts reach your watch"),
                             detail: ready == nil ? String(localized: "We'll check as soon as you're back here.") : nextWorkoutText)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    if let link = model.intervalsAthlete?.links.first(where: { !$0.uploading }), ready == nil {
                        // Linked, but planned workouts aren't switched on (rare: we turn it on automatically).
                        Card {
                            HStack {
                                Text("\(link.name) is linked, but isn't receiving workouts yet.").font(.subheadline)
                                Spacer()
                                Button("Turn on") { Task { await model.enableIntervalsUpload(link) } }
                                    .buttonStyle(.chip)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) { bottomButtons }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if ready == nil { Button("Later") { dismiss() } }
                }
            }
            .animation(.snappy, value: ready)
            .sensoryFeedback(.success, trigger: ready != nil)
            .onChange(of: scenePhase) { _, phase in
                // Back from Intervals.icu: look for the new link straight away.
                if phase == .active, openedIntervals { Task { await check() } }
            }
            .task {
                if let linked = model.intervalsAthlete?.links.first { brand = linked.service }
            }
        }
    }

    private var brandName: String {
        IntervalsAthlete.Link(service: brand, uploading: false).name
    }

    private var linkInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Watch", selection: $brand) {
                ForEach(IntervalsAthlete.Link.Service.allCases, id: \.self) { service in
                    Text(IntervalsAthlete.Link(service: service, uploading: false).name).tag(service)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                instruction(1, String(localized: "Tap Open Intervals.icu below. Scroll to Connections."))
                instruction(2, String(localized: "Find \(brandName) and tap Connect. Tick Upload planned workouts if you see it."))
                instruction(3, String(localized: "Sign in to \(brandName), allow access, then come back to TrackStar."))
            }
        }
        .padding(.leading, 42)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).monospacedDigit()
            Text(text).font(.subheadline).foregroundStyle(Theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, done: Bool, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if done {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.onAccent)
                } else {
                    Circle().strokeBorder(Theme.subtle, lineWidth: 2)
                    Text("\(number)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var nextWorkoutText: String {
        guard let next = model.plan?.workouts.first(where: { $0.date >= model.today }) else {
            return String(localized: "New workouts are sent as your plan changes.")
        }
        let day = next.date == model.today ? String(localized: "today")
            : next.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let app = ready?.service == .garmin ? "Garmin Connect" : String(localized: "the \(ready?.name ?? "watch") app")
        return String(localized: "Your next workout, \(next.kind.casualName) \(day), shows on your watch after its next sync with \(app).")
    }

    private var bottomButtons: some View {
        VStack(spacing: Theme.Spacing.s) {
            if ready != nil {
                Button("Done") { dismiss() }.buttonStyle(.primary)
            } else {
                Button {
                    openedIntervals = true
                    openURL(AppModel.intervalsConnectionsURL)
                } label: {
                    Label("Open Intervals.icu", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.primary)
                if openedIntervals {
                    Button {
                        Task { await check() }
                    } label: {
                        HStack(spacing: 8) {
                            if checking { ProgressView() }
                            Text(checking ? "Checking…" : "I've linked it, check again")
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(checking)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(Theme.background)
    }

    private func check() async {
        guard !checking else { return }
        checking = true
        await model.refreshIntervalsLinks()
        checking = false
    }
}

/// Today's reminder to finish connecting a watch, shown while Intervals.icu is connected but no watch receives
/// workouts yet.
struct WatchSetupNudge: View {
    @Environment(AppModel.self) private var model
    @AppStorage("watchSetupNudgeDismissed") private var dismissed = false
    @State private var settingUp = false

    var body: some View {
        if model.intervalsNeedsWatch, !dismissed {
            Card {
                HStack(alignment: .top, spacing: 12) {
                    ActivityIcon(symbol: "applewatch.radiowaves.left.and.right", colors: Theme.sheenColors, size: 40)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Finish connecting your watch").font(.headline).foregroundStyle(Theme.ink)
                        Text("Link your Garmin (or COROS, Suunto, Wahoo) on Intervals.icu so your workouts reach it.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        HStack(spacing: 8) {
                            Button("Finish setup") { settingUp = true }.buttonStyle(.chip)
                            Button("Not now") { withAnimation { dismissed = true } }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .sheet(isPresented: $settingUp) { WatchSetupView() }
        }
    }
}
