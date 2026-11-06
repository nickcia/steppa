import SwiftData
import SwiftUI
import PlanEngine

@main
struct SteppaApp: App {
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container = Persistence.makeContainer(inMemory: DemoData.isRequested)
        self.container = container
        let model = AppModel(context: container.mainContext)
        DemoData.seedIfRequested(model)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if model.plan == nil || !model.disclaimerAccepted {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.plan == nil)
        .environment(\.unitSystem, model.units)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.reload() }
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil },
                                                           set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
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
        for workout in plan.workouts where workout.date < today {
            model.setStatus(workout.date.day % 9 == 0 ? .skipped : .done, for: workout)
        }
    }
}
