import CoreLocation
import SwiftData
import SwiftUI
import PlanEngine

@main
struct TrackStarApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var crashes = CrashReporter()
    @State private var guidedRun = GuidedRunController.shared
    private let watchPairing: WatchPairing?

    init() {
        let container = Persistence.makeContainer(inMemory: DemoData.usesMemoryStore)
        self.container = container
        let server = DemoData.usesMemoryStore ? nil : TrackStarServer.configured
        let model = AppModel(container: container,
                             runSource: DemoData.usesMemoryStore ? nil : HealthKitRunSource(),
                             reminders: ReminderService(), watch: WatchService(),
                             calendar: DemoData.usesMemoryStore ? nil : CalendarService(),
                             intervals: DemoData.usesMemoryStore ? nil : IntervalsClient(),
                             intervalsOAuth: .configured,
                             strava: DemoData.usesMemoryStore ? nil : StravaClient(),
                             stravaOAuth: .configured(server: server),
                             server: server)
        DemoData.seedIfRequested(model)
        #if DEBUG
        if DemoData.fakesIntervals { model.debugFakeIntervalsConnection() }
        #endif
        if DemoData.pretendsAppleWatch {
            model.appleWatchPaired = true
            watchPairing = nil
        } else {
            watchPairing = WatchPairing { [weak model] paired in model?.appleWatchPaired = paired }
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(crashes)
                .environment(guidedRun)
                .tint(Theme.accent)
                // The look is designed for light surfaces only.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(CrashReporter.self) private var crashes
    @Environment(GuidedRunController.self) private var guidedRun
    #if DEBUG
    /// `-watchSetup`: open the watch setup sheet at launch.
    @State private var debugWatchSetup = ProcessInfo.processInfo.arguments.contains("-watchSetup")
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingWhatsNew = false
    /// A workout someone shared, opened from a ".trackstar" file.
    @State private var receivedWorkout: ReceivedWorkout?
    @State private var receivedProblem: String?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.plan == nil || !model.disclaimerAccepted {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    // A fresh set of tabs for each plan, so a new plan always opens on Today.
                    .id(model.planID)
                    .transition(.opacity)
                    // After an update, what changed, once. Not over a crash report or a run in progress.
                    .onAppear {
                        if WhatsNew.isUnseen, crashes.pending == nil, guidedRun.session == nil { showingWhatsNew = true }
                    }
                    .sheet(isPresented: $showingWhatsNew) { WhatsNewView() }
            }
        }
        .animation(.default, value: model.plan == nil)
        .environment(\.unitSystem, model.units)
        // After a crash, iOS hands the report over on a later launch: offer to send it, once.
        .sheet(item: Binding(get: { model.plan == nil ? nil : crashes.pending },
                             set: { if $0 == nil { crashes.clear() } })) { crash in
            BugReportView(crash: crash)
        }
        // A guided run takes over the screen until it's closed.
        .fullScreenCover(isPresented: Binding(get: { guidedRun.session != nil }, set: { _ in })) {
            GuidedRunView()
                .environment(model)
                .environment(guidedRun)
                .interactiveDismissDisabled()
        }
        .task {
            // If iOS closed the app during a guided run, carry on with it.
            if model.plan != nil { guidedRun.restoreIfNeeded(describer: model.targetDescriber) }
            crashes.start()
            #if DEBUG
            // `-crashReport`: show the after-a-crash prompt with a made-up report.
            if ProcessInfo.processInfo.arguments.contains("-crashReport") { crashes.accept([.sample]) }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $debugWatchSetup) { WatchSetupView().environment(model) }
        #endif
        #if DEBUG
        // `-guidedRun`: start today's (or the next) workout as a guided run, once there's a plan.
        .task(id: model.planID) {
            guard ProcessInfo.processInfo.arguments.contains("-guidedRun"), guidedRun.session == nil,
                  let workout = model.plan?.workouts.first(where: { $0.date >= model.today && $0.kind != .race }) else { return }
            try? await Task.sleep(for: .seconds(1))
            await model.startGuidedRun(workout)
        }
        #endif
        // Strava's own app sends the athlete back here after "Authorize".
        .onOpenURL { url in
            // A shared workout (from AirDrop, Messages, Files…).
            if SharedWorkout.canOpen(url) {
                do throws(SharedWorkout.Problem) {
                    receivedWorkout = ReceivedWorkout(workout: try SharedWorkout.read(from: url))
                } catch {
                    receivedProblem = error.errorDescription
                }
                return
            }
            Task { await model.handleOpenURL(url) }
        }
        .sheet(item: $receivedWorkout) { received in
            SharedWorkoutSheet(shared: received.workout).environment(model)
        }
        .alert("Couldn't open this workout", isPresented: Binding(get: { receivedProblem != nil },
                                                                  set: { if !$0 { receivedProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(receivedProblem ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.becameActive() }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil },
                                                           set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

enum AppTab: Hashable, CaseIterable {
    case today, plan, progress, settings

    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .plan: "Plan"
        case .progress: "Progress"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .plan: "calendar"
        case .progress: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct MainTabs: View {
    @State private var tab: AppTab = MainTabs.initialTab
    /// Bumped when the Today tab is tapped while already open: Today jumps back to today, as tab bars usually do.
    @State private var todayReset = 0

    /// Today, or with `-tab plan|progress|settings` in debug builds, that tab (for screenshots).
    private static var initialTab: AppTab {
        #if DEBUG
        switch DemoData.launchValue("-tab") {
        case "plan": return .plan
        case "progress": return .progress
        case "settings": return .settings
        default: return .today
        }
        #else
        return .today
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView(resetSignal: todayReset).tabRoot(.today)
            PlanView().tabRoot(.plan)
            TrainingProgressView().tabRoot(.progress)
            SettingsView().tabRoot(.settings)
        }
        .overlay(alignment: .bottom) {
            TabBar(selection: $tab) { tapped in
                if tapped == .today { todayReset += 1 }
            }
        }
    }
}

/// A floating dark bar: icons, with the current tab as a white capsule that shows its name.
private struct TabBar: View {
    @Binding var selection: AppTab
    /// Called when the already-selected tab is tapped again.
    var onReselect: (AppTab) -> Void = { _ in }
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = tab == selection
                Button {
                    if tab == selection {
                        onReselect(tab)
                    } else {
                        withAnimation(.snappy(duration: 0.3)) { selection = tab }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: .medium))
                        if isSelected {
                            Text(tab.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(isSelected ? Theme.ink : .white.opacity(0.85))
                    .padding(.horizontal, isSelected ? 16 : 0)
                    .frame(maxWidth: isSelected ? nil : .infinity, minHeight: 48)
                    .background {
                        if isSelected {
                            Capsule().fill(.white).matchedGeometryEffect(id: "selected", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(6)
        .barGlass(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, 2)
    }
}

private extension View {
    /// A tab's content: hides the system tab bar and leaves room for the floating one.
    func tabRoot(_ tab: AppTab) -> some View {
        self
            // The floating bar is about 60 pt tall plus its shadow: every scroll view in the tab gets that much
            // extra room at the end, so the last row can scroll clear of it.
            .contentMargins(.bottom, 84, for: .scrollContent)
            .toolbar(.hidden, for: .tabBar)
            .tag(tab)
    }
}

/// Launch with `-demo` to start with a sample plan part-way through (for screenshots and testing).
/// Uses an in-memory store so real data is never touched.
enum DemoData {
    static var isRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }

    /// Demo mode and `-newRunner` (onboarding as a new runner) never touch real data.
    static var usesMemoryStore: Bool {
        #if DEBUG
        isRequested || ["-newRunner", "-slowRunner"].contains { ProcessInfo.processInfo.arguments.contains($0) }
        #else
        false
        #endif
    }

    #if DEBUG
    /// The value after a launch argument, e.g. `-tab plan` gives "plan" for "-tab".
    static func launchValue(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    #endif

    /// Demo screenshots and `-appleWatch` (the simulator has no watch) act as if an Apple Watch is paired.
    static var pretendsAppleWatch: Bool {
        #if DEBUG
        isRequested || ProcessInfo.processInfo.arguments.contains("-appleWatch")
        #else
        false
        #endif
    }

    static var fakesIntervals: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-intervalsConnected")
        #else
        false
        #endif
    }

    #if !DEBUG
    static func seedIfRequested(_ model: AppModel) {}
    #else
    static func seedIfRequested(_ model: AppModel) {
        guard isRequested, model.plan == nil else { return }
        let today = LocalDate.today
        let inputs = PlanInputs(goal: .halfMarathon, raceDate: today.adding(days: 75), startDate: today.adding(days: -24),
                                currentWeeklyMeters: 28_000, fitness: .recentRace(.init(.tenK, timeSeconds: 52 * 60)),
                                runDays: [.tuesday, .thursday, .saturday, .sunday], longRunDay: .sunday,
                                experience: .intermediate, goalTimeSeconds: 1 * 3600 + 55 * 60)
        guard let plan = try? PlanBuilder.build(inputs) else { return }
        model.acceptDisclaimer()
        model.start(plan)
        var runs: [CompletedRun] = []
        var series: [String: RunSeries] = [:]
        for workout in plan.workouts where workout.date < today {
            if workout.date.day % 9 == 0 {
                model.setStatus(.skipped, for: workout)
                continue
            }
            // A believable recording: a little off the target pace, heart rate drifting up on longer runs.
            let id = "demo-\(workout.id)"
            let variation = 1 + Double(workout.date.day % 7 - 3) * 0.015
            let pace = (workout.blocks.first?.steps.first?.step.target?.range.mid ?? 400) * variation
            let meters = workout.totalMeters
            let duration = meters / 1000 * pace
            let baseHR: Double = workout.kind == .easy || workout.kind == .long ? 142 : 158
            let rise: Double = workout.kind == .long ? 12 : 5
            let times = Array(stride(from: 0.0, through: duration, by: 10))
            series[id] = RunSeries(
                distance: times.map { .init($0, $0 / duration * meters * (1 + 0.03 * sin($0 / 240))) },
                heartRate: times.map { .init($0, baseHR + rise * $0 / duration + 4 * sin($0 / 90) - (($0 < 300) ? (300 - $0) / 10 : 0)) },
                power: times.map { .init($0, 245 + 12 * sin($0 / 150)) },
                cadence: times.map { .init($0, 166 + 3 * sin($0 / 200)) },
                altitude: times.map { .init($0, 40 + 12 * sin($0 / 400)) },
                strideLength: times.map { .init($0, 1.08 + 0.04 * sin($0 / 180)) },
                verticalOscillation: times.map { .init($0, 8.6 + 0.4 * sin($0 / 220)) },
                groundContactTime: times.map { .init($0, 248 + 8 * sin($0 / 160)) },
                extras: RunExtras(activeCalories: meters / 1000 * 68, temperatureCelsius: 11, humidity: 72, indoor: false,
                                  heartRateRecovery: 31, effortScore: workout.kind == .easy ? 4 : 7))
            runs.append(CompletedRun(id: id, date: workout.date, distanceMeters: meters, durationSeconds: duration,
                                     start: Calendar.current.date(bySettingHour: 7, minute: 10, second: 0, of: workout.date.date())))
        }
        model.loadDemoRuns(runs, series: series)
        // Out-and-back loops along a waterfront for the run cards' maps, longer for longer runs.
        for run in runs {
            let length = run.distanceMeters / 2 / 111_000
            let points = (0...60).map { i -> CLLocationCoordinate2D in
                let t = Double(i) / 60
                let out = t < 0.5 ? t * 2 : (1 - t) * 2
                return CLLocationCoordinate2D(latitude: 43.6365 + out * length * 0.35 + (t < 0.5 ? 0 : 0.0012),
                                              longitude: -79.4040 + out * length * 1.3)
            }
            model.debugSetRoute(points, for: run.id)
        }
        model.setMaxHeartRate(188)
        model.setStrength(enabled: true)
    }
    #endif
}

/// A shared workout waiting to be looked at; a fresh one each time a file is opened.
struct ReceivedWorkout: Identifiable {
    let id = UUID()
    let workout: SharedWorkout
}
