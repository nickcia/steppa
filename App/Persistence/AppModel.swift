import CoreData
import Foundation
import Observation
import SwiftData
import PlanEngine

/// The app's state: the active plan, workout statuses, races and preferences.
/// Views read from it; every change goes through its methods so storage stays consistent.
@Observable
final class AppModel {
    /// Held strongly: a `ModelContext` doesn't keep its container alive, and using a context whose
    /// container has been released traps inside SwiftData.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// Injectable so tests can pin "today".
    private let clock: () -> LocalDate
    private let runSource: RunSource?
    private let reminders: ReminderService?
    private let watch: WatchService?
    private let calendar: CalendarService?
    private let intervals: IntervalsClient?
    private let intervalsKeychain: IntervalsKeychain
    /// "Sign in with Intervals.icu"; nil in builds without a client ID, which connect with an API key instead.
    let intervalsOAuth: IntervalsOAuth?

    private(set) var plan: TrainingPlan?
    /// Set when a plan has just been built in onboarding: the main screen opens on Today and plays its reveal once.
    var revealNewPlan = false
    private(set) var planID: UUID?
    private(set) var statuses: [String: WorkoutStatus] = [:]
    private(set) var units: UnitSystem = .localeDefault
    private(set) var disclaimerAccepted = false
    private(set) var races: [RaceRecord] = []
    private(set) var changes: [PlanChangeRecord] = []
    /// Runs read from Apple Health, and which planned workout each one fulfilled.
    /// Runs from the athlete's devices: Apple Health, plus runs only on Intervals.icu (not in Health).
    private(set) var healthRuns: [CompletedRun] = []
    private var runsFromHealth: [CompletedRun] = []
    private var intervalsActivities: [IntervalsActivity] = []
    /// Health run ID → the same run on Intervals.icu, which usually has fuller data (e.g. from Garmin).
    private var intervalsActivityForRun: [String: String] = [:]
    /// Recorded data per run ID, for run analysis.
    private(set) var runSeries: [String: RunSeries] = [:]
    private(set) var healthMatches: [String: CompletedRun] = [:]
    private(set) var healthConnected = false
    private(set) var remindersEnabled = false
    private(set) var reminderMinutes = 7 * 60
    private(set) var watchAutoSync = false
    private(set) var strengthEnabled = false
    private(set) var strengthPerWeek = 2
    private(set) var coachEnabled = true
    /// Zones imported from the athlete's watch platform or typed in; nil means worked out from maximum heart rate.
    private(set) var storedHeartRateZones: HeartRateZones?
    /// How workout targets are shown: pace, heart rate or treadmill speed.
    private(set) var targetDisplay: WorkoutTargetDisplay = .pace
    /// km/h or mph on the treadmill, separate from distance units.
    private(set) var treadmillUnits: UnitSystem = .metric
    /// Workouts currently scheduled on the watch (by WorkoutKit plan ID).
    private(set) var watchScheduledIDs: Set<UUID> = []
    /// The Intervals.icu connection (from the Keychain); nil when not connected.
    private(set) var intervalsAccount: IntervalsCredentials?
    /// The athlete's Intervals.icu settings: which watch services are linked and receiving workouts.
    private(set) var intervalsAthlete: IntervalsAthlete?
    private(set) var intervalsLastSync: Date?
    private(set) var intervalsSyncing = false
    /// What was last sent, so coming back to the app doesn't re-sync an unchanged plan every time.
    private var intervalsSyncedIDs: Set<String>?
    /// "Show my plan in Calendar". Kept on this device only, like calendar access itself.
    private(set) var calendarSyncEnabled = false
    private var calendarSyncedKeys: Set<String>?
    private static let calendarSyncKey = "calendarSync.enabled"
    /// Set when saving fails or an edit is refused, so the UI can tell the user.
    var lastError: String?

    init(container: ModelContainer, clock: @escaping () -> LocalDate = { .today },
         runSource: RunSource? = nil, reminders: ReminderService? = nil, watch: WatchService? = nil,
         calendar: CalendarService? = nil,
         intervals: IntervalsClient? = nil, intervalsOAuth: IntervalsOAuth? = nil,
         intervalsKeychain: IntervalsKeychain = IntervalsKeychain()) {
        self.container = container
        self.clock = clock
        self.runSource = runSource
        self.reminders = reminders
        self.watch = watch
        self.calendar = calendar
        self.calendarSyncEnabled = calendar != nil && UserDefaults.standard.bool(forKey: Self.calendarSyncKey)
        self.intervals = intervals
        self.intervalsKeychain = intervalsKeychain
        self.intervalsOAuth = intervalsOAuth
        self.intervalsAccount = intervals == nil ? nil : intervalsKeychain.load()
        reload()
        if Persistence.syncsWithICloud {
            // Another device changed something: re-read so the UI shows it.
            remoteChanges = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                    self?.reload()
                }
            }
        }
    }

    private var remoteChanges: Task<Void, Never>?

    var today: LocalDate { clock() }
    var format: DisplayFormat { DisplayFormat(units: units) }

    // MARK: Loading

    func reload() {
        let profile = fetchProfile()
        units = profile?.units ?? .localeDefault
        disclaimerAccepted = profile?.disclaimerAcceptedAt != nil
        healthConnected = profile?.healthRequestedAt != nil
        remindersEnabled = profile?.remindersEnabled ?? false
        reminderMinutes = profile?.reminderMinutes ?? 7 * 60
        watchAutoSync = profile?.watchAutoSync ?? false
        strengthEnabled = profile?.strengthEnabled ?? false
        strengthPerWeek = profile?.strengthPerWeek ?? 2
        coachEnabled = profile?.coachEnabled ?? true
        storedHeartRateZones = profile?.heartRateZonesData.flatMap { try? JSONDecoder().decode(HeartRateZones.self, from: $0) }
        targetDisplay = profile?.targetDisplayRaw.flatMap(WorkoutTargetDisplay.init(rawValue:)) ?? .pace
        treadmillUnits = profile?.treadmillUnitsRaw.flatMap(UnitSystem.init(rawValue:)) ?? units

        // If two devices both created a plan before syncing, the most recently updated one wins.
        let record = activePlanRecord()
        plan = record?.decoded()
        planID = record?.planID

        statuses = [:]
        changes = []
        if let id = planID {
            let logs = (try? context.fetch(FetchDescriptor<WorkoutLogRecord>(predicate: #Predicate { $0.planID == id }))) ?? []
            for log in logs.sorted(by: { $0.updatedAt < $1.updatedAt }) {
                statuses[log.workoutID] = log.status
            }
            changes = (try? context.fetch(FetchDescriptor<PlanChangeRecord>(
                predicate: #Predicate { $0.planID == id },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        }
        races = ((try? context.fetch(FetchDescriptor<RaceRecord>())) ?? []).sorted { $0.date < $1.date }
        // Merged rather than replaced, so recordings fetched this session survive a reload.
        let stored = Dictionary(((try? context.fetch(FetchDescriptor<RunDetailRecord>())) ?? []).compactMap { record in
            record.series.map { (record.runID, $0) }
        }, uniquingKeysWith: { a, _ in a })
        runSeries.merge(stored) { _, saved in saved }
        matchHealthRuns()
    }

    /// Pairs Health runs with planned workouts up to today. Workouts the athlete marked as skipped
    /// are left out, so a run on that day isn't counted against them.
    private func matchHealthRuns() {
        guard let plan else { healthMatches = [:]; return }
        let candidates = plan.workouts.filter { $0.date <= today && statuses[$0.id] != .skipped }
        let runsByID = Dictionary(healthRuns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        healthMatches = Dictionary(RunMatcher.match(workouts: candidates, runs: healthRuns)
            .compactMap { match in runsByID[match.runID].map { (match.workoutID, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    private func activePlanRecord() -> PlanRecord? {
        var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.isActive },
                                                     sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchProfile() -> ProfileRecord? {
        let descriptor = FetchDescriptor<ProfileRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try? context.fetch(descriptor).first
    }

    private func profile() -> ProfileRecord {
        if let existing = fetchProfile() { return existing }
        let created = ProfileRecord(units: units)
        context.insert(created)
        return created
    }

    private func save() {
        do {
            try context.save()
        } catch {
            lastError = String(localized: "Couldn't save your changes: \(error.localizedDescription)")
        }
        reload()
    }

    // MARK: Plan

    func start(_ newPlan: TrainingPlan) {
        do {
            let active = try context.fetch(FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.isActive }))
            for record in active { record.isActive = false }
            context.insert(try PlanRecord(plan: newPlan))
        } catch {
            lastError = String(localized: "Couldn't save your plan: \(error.localizedDescription)")
        }
        save()
        planDidChange()
    }

    func endPlan() {
        guard let id = planID else { return }
        let records = (try? context.fetch(FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.planID == id }))) ?? []
        for record in records { record.isActive = false }
        save()
        planDidChange()
    }

    /// Replaces the active plan's contents (after an edit or adaptation). Returns false if refused.
    @discardableResult
    private func store(_ updated: TrainingPlan, reasons: [AdaptationReason] = []) -> Bool {
        guard let record = activePlanRecord(), let id = planID else { return false }
        // Last line of defence: never store a plan that breaks a safety rule.
        let violations = PlanValidator.validate(updated)
        guard violations.isEmpty else {
            lastError = String(localized: "That change would make the plan unsafe, so it wasn't applied.")
            return false
        }
        do {
            let previous = plan
            try record.update(updated)
            if !reasons.isEmpty {
                // Several changes before the athlete has seen them read as one: merge them, keeping the
                // earliest "before" plan so Undo goes all the way back.
                if let pending = unseenChange {
                    pending.reasons = pending.reasons.filter { !reasons.contains($0) } + reasons
                    pending.createdAt = .now
                } else {
                    context.insert(PlanChangeRecord(planID: id, reasons: reasons, previous: previous))
                }
            }
        } catch {
            lastError = String(localized: "Couldn't save your plan: \(error.localizedDescription)")
            return false
        }
        save()
        planDidChange()
        return true
    }

    // MARK: Adaptation

    /// What the athlete actually did: runs from Apple Health, plus workouts ticked off by hand that no Health
    /// run covers (counted at the planned distance and duration). Skipped and unmarked workouts count as missed.
    /// Only treated as complete once there's some record of running (see `hasTrainingRecord`).
    var trainingLog: TrainingLog {
        guard let plan else { return TrainingLog() }
        var log = TrainingLog(runs: healthRuns,
                              matches: healthMatches.map { RunMatch(workoutID: $0.key, runID: $0.value.id) })
        for workout in plan.workouts where statuses[workout.id] == .done && healthMatches[workout.id] == nil {
            let id = "manual-\(workout.id)"
            log.runs.append(CompletedRun(id: id, date: workout.date, distanceMeters: workout.totalMeters,
                                         durationSeconds: workout.totalSeconds))
            log.matches.append(RunMatch(workoutID: workout.id, runID: id))
        }
        return log
    }

    /// Routine check, run when the app comes to the foreground (not on every tick, so logging several
    /// runs at once produces one change). Only runs once the athlete has started ticking workouts off,
    /// so a plan isn't cut back just because nobody recorded anything.
    func reviewPlan() {
        guard let plan, hasTrainingRecord, today < plan.inputs.raceDate else { return }
        adapt(.review)
    }

    /// Whether the training log can be trusted to show missed runs: the athlete ticks runs off, or Health has runs.
    var hasTrainingRecord: Bool { !statuses.isEmpty || !healthRuns.isEmpty }

    @discardableResult
    private func adapt(_ trigger: AdaptationTrigger) -> Bool {
        guard let plan else { return false }
        do {
            let revision = try PlanAdapter.adapt(plan, log: trainingLog, trigger: trigger, today: today,
                                                 assessTraining: hasTrainingRecord)
            return revision.changed ? store(revision.plan, reasons: revision.reasons) : true
        } catch {
            lastError = error.message
            return false
        }
    }

    @discardableResult
    func changeRaceDate(_ date: LocalDate) -> Bool { adapt(.raceDateChanged(date)) }

    @discardableResult
    func changeAvailability(runDays: Set<Weekday>, longRunDay: Weekday) -> Bool {
        adapt(.availabilityChanged(runDays: runDays, longRunDay: longRunDay))
    }

    @discardableResult
    func applyRaceResult(_ performance: RacePerformance) -> Bool { adapt(.newRaceResult(performance)) }

    // MARK: Time off

    /// Holidays, busy stretches, injuries and illness, in date order.
    var timeOff: [TimeOff] { plan?.inputs.timeOffPeriods ?? [] }

    /// The time off covering today, if any.
    var currentTimeOff: TimeOff? { plan?.inputs.timeOff(on: today) }

    /// Replaces the list of time off and re-plans around it.
    @discardableResult
    func changeTimeOff(_ periods: [TimeOff]) -> Bool { adapt(.timeOffChanged(periods)) }

    /// The list after the athlete says they're back from this time off today: it ends yesterday (or goes, if it
    /// hadn't started).
    func timeOffEndingToday(_ period: TimeOff) -> [TimeOff] {
        timeOff.compactMap { other in
            guard other.id == period.id else { return other }
            guard other.start < today else { return nil }
            var ended = other
            ended.end = today.adding(days: -1)
            return ended
        }
    }

    func setGoalTime(_ seconds: Double?) {
        guard var updated = plan else { return }
        updated.inputs.goalTimeSeconds = seconds
        store(updated)
    }

    func markChangesSeen() {
        for change in changes where !change.seen { change.seen = true }
        save()
    }

    var unseenChange: PlanChangeRecord? { changes.first { !$0.seen } }

    /// Restores the plan from before a change. Only the most recent change can be undone.
    func undo(_ change: PlanChangeRecord) {
        guard change.persistentModelID == changes.first?.persistentModelID,
              let previous = change.previousPlan, let record = activePlanRecord() else { return }
        do {
            try record.update(previous)
            context.delete(change)
        } catch {
            lastError = String(localized: "Couldn't undo: \(error.localizedDescription)")
        }
        save()
    }

    // MARK: Workouts

    /// Ticked off by hand, or done because a Health run matched it.
    func status(of workout: Workout) -> WorkoutStatus? {
        statuses[workout.id] ?? (healthMatches[workout.id] != nil ? .done : nil)
    }

    var effectiveStatuses: [String: WorkoutStatus] {
        var result = statuses
        for id in healthMatches.keys where result[id] == nil { result[id] = .done }
        return result
    }

    /// The Health run that completed this workout, if any.
    func healthRun(for workout: Workout) -> CompletedRun? { healthMatches[workout.id] }

    func setStatus(_ status: WorkoutStatus?, for workout: Workout) {
        setStatus(status, forID: workout.id)
    }

    private func setStatus(_ status: WorkoutStatus?, forID workoutID: String) {
        guard let planID else { return }
        let existing = (try? context.fetch(FetchDescriptor<WorkoutLogRecord>(
            predicate: #Predicate { $0.planID == planID && $0.workoutID == workoutID }))) ?? []
        if let status {
            if let record = existing.first {
                record.status = status
                existing.dropFirst().forEach(context.delete)
            } else {
                context.insert(WorkoutLogRecord(planID: planID, workoutID: workoutID, status: status))
            }
        } else {
            existing.forEach(context.delete)
        }
        save()
    }

    /// Moves a workout within its week. Returns false (and sets `lastError`) if it isn't allowed.
    @discardableResult
    func move(_ workout: Workout, to date: LocalDate) -> Bool {
        guard let plan else { return false }
        do {
            return store(try PlanEditor.move(workout.id, to: date, in: plan, today: today))
        } catch {
            lastError = error.message
            return false
        }
    }

    // MARK: Races

    func addRace(_ race: RaceRecord) {
        context.insert(race)
        save()
    }

    func saveRaces() { save() }

    func deleteRace(_ race: RaceRecord) {
        context.delete(race)
        save()
    }

    // MARK: Apple Health

    var healthAvailable: Bool { runSource?.isAvailable ?? false }

    func connectHealth() async {
        guard let runSource else { return }
        do {
            try await runSource.requestAccess()
            profile().healthRequestedAt = .now
            save()
            await refreshHealth()
        } catch {
            lastError = String(localized: "Couldn't connect to Apple Health: \(error.localizedDescription)")
        }
    }

    /// Re-reads runs from Health (since a little before the plan started), then reviews the plan.
    /// Runs from Apple Health in the weeks before a new plan starts, to check the onboarding answers against.
    /// nil when Health isn't connected or can't be read.
    func runsBeforePlan(starting start: LocalDate) async -> [CompletedRun]? {
        guard healthConnected, let runSource else { return nil }
        return try? await runSource.runs(since: start.adding(days: -HistoryCalibration.lookbackWeeks * 7))
    }

    /// Fetches runs from Apple Health and Intervals.icu (whichever are connected), merges them, ticks off
    /// workouts, and fetches recorded data for recent runs that don't have it yet.
    func refreshHealth() async {
        guard let plan else { return }
        let since = plan.inputs.startDate.adding(days: -RacePredictor.lookbackDays)
        if healthConnected, let runSource {
            // Health can be unavailable (e.g. phone locked); keep the last runs and try again next time.
            if let runs = try? await runSource.runs(since: since) { runsFromHealth = runs }
        }
        if let intervals, let account = intervalsAccount,
           let activities = try? await intervals.activities(from: since, through: today, credentials: account) {
            intervalsActivities = activities.filter(\.isRun)
        }
        mergeRuns()
        matchHealthRuns()
        reviewPlan()
        await fetchRunDetails()
    }

    /// Health runs plus Intervals.icu runs that aren't in Health. The same run in both (same day, distance within
    /// 5%) counts once, using Health's record and Intervals.icu's data.
    private func mergeRuns() {
        var unmatched = intervalsActivities
        intervalsActivityForRun = [:]
        for run in runsFromHealth {
            if let index = unmatched.firstIndex(where: { activity in
                activity.date == run.date && (activity.distance.map { abs($0 - run.distanceMeters) <= run.distanceMeters * 0.05 } ?? false)
            }) {
                intervalsActivityForRun[run.id] = unmatched[index].id
                unmatched.remove(at: index)
            }
        }
        healthRuns = (runsFromHealth + unmatched.compactMap(\.completedRun)).sorted { $0.date < $1.date }
    }

    /// Recorded data for the last 8 weeks of runs, at most 12 new runs per refresh. Intervals.icu is preferred when
    /// it has the run (it keeps everything the watch recorded); Apple Health otherwise.
    private func fetchRunDetails() async {
        let missing = healthRuns.filter { runSeries[$0.id] == nil && $0.date.days(until: today) <= 56 }.suffix(12)
        for run in missing {
            var series: RunSeries?
            var source = "health"
            let activityID = run.id.hasPrefix("icu-") ? String(run.id.dropFirst(4)) : intervalsActivityForRun[run.id]
            if let activityID, let intervals, let account = intervalsAccount {
                series = try? await intervals.series(activityID: activityID, credentials: account)
                source = "intervals"
            }
            if series == nil, !run.id.hasPrefix("icu-"), let runSource {
                series = try? await runSource.series(forRun: run.id)
                source = "health"
            }
            guard let series else { continue }
            context.insert(RunDetailRecord(runID: run.id, source: source, series: series))
            runSeries[run.id] = series.downsampled()
        }
        if !missing.isEmpty { try? context.save() }
    }

    #if DEBUG
    /// Sample runs with recordings for `-demo` (in memory only).
    func loadDemoRuns(_ runs: [CompletedRun], series: [String: RunSeries]) {
        runsFromHealth = runs
        runSeries = series
        mergeRuns()
        matchHealthRuns()
    }
    #endif

    /// Maximum heart rate for zones: the athlete's own setting, else estimated from age and recorded runs.
    var estimatedMaxHeartRate: Double? {
        fetchProfile()?.maxHeartRate
            ?? RunAnalyzer.estimatedMaxHeartRate(age: runSource?.age(), runs: Array(runSeries.values))
    }

    var maxHeartRateIsSet: Bool { fetchProfile()?.maxHeartRate != nil }

    func setMaxHeartRate(_ bpm: Double?) {
        profile().maxHeartRate = bpm
        save()
    }

    /// Splits, averages and zones for a run, in the athlete's units. nil when nothing was recorded.
    func analysis(for run: CompletedRun) -> RunAnalysis {
        RunAnalyzer.analyze(runSeries[run.id] ?? RunSeries(), distanceMeters: run.distanceMeters,
                            durationSeconds: run.durationSeconds, splitMeters: units.metersPerUnit,
                            maxHeartRate: estimatedMaxHeartRate, zones: storedHeartRateZones)
    }

    // MARK: Heart-rate zones and how targets are shown

    /// The athlete's zones: imported or typed in, otherwise worked out from maximum heart rate. nil only when
    /// there's no maximum to work from (no age in Health and no recorded runs).
    var heartRateZones: HeartRateZones? {
        storedHeartRateZones ?? estimatedMaxHeartRate.map { HeartRateZones.fromMax($0) }
    }

    /// nil goes back to zones worked out from maximum heart rate.
    func setHeartRateZones(_ zones: HeartRateZones?) {
        profile().heartRateZonesData = zones.flatMap { try? JSONEncoder().encode($0) }
        save()
    }

    /// Describes workouts with targets in the athlete's chosen display (pace, heart rate or treadmill speed).
    var targetDescriber: WorkoutDescriber {
        WorkoutDescriber(format: format, display: targetDisplay, zones: heartRateZones, treadmillUnits: treadmillUnits)
    }

    func setTargetDisplay(_ display: WorkoutTargetDisplay) {
        profile().targetDisplayRaw = display.rawValue
        save()
    }

    func setTreadmillUnits(_ units: UnitSystem) {
        profile().treadmillUnitsRaw = units.rawValue
        save()
    }

    /// The planned workout a run ticked off, if any.
    func workout(for run: CompletedRun) -> Workout? {
        guard let id = healthMatches.first(where: { $0.value.id == run.id })?.key else { return nil }
        return plan?.workouts.first { $0.id == id }
    }

    /// Where a run's data came from, for the run screen.
    func dataSource(for run: CompletedRun) -> String? {
        guard runSeries[run.id] != nil else { return nil }
        let record = try? context.fetch(FetchDescriptor<RunDetailRecord>(predicate: #Predicate { $0.runID == run.id })).first
        return record?.source
    }

    // MARK: Reminders and Apple Watch

    func setReminders(enabled: Bool) async {
        if enabled, let reminders, await !reminders.requestAuthorization() {
            lastError = String(localized: "Notifications are turned off for this app. You can allow them in Settings › Notifications.")
            return
        }
        profile().remindersEnabled = enabled
        save()
        await syncReminders()
    }

    func setReminderTime(minutes: Int) async {
        profile().reminderMinutes = minutes
        save()
        await syncReminders()
        if watchAutoSync { await syncWatch() }
        await syncCalendar()
    }

    func setWatchAutoSync(_ enabled: Bool) async {
        profile().watchAutoSync = enabled
        save()
        if enabled { await syncWatch() }
    }

    private func syncReminders() async {
        guard let reminders else { return }
        if remindersEnabled, let plan {
            await reminders.reschedule(plan.workouts, minutes: reminderMinutes, format: format)
        } else {
            await reminders.cancelAll()
        }
    }

    var watchSupported: Bool { watch?.isSupported ?? false }

    func isOnWatch(_ workout: Workout) -> Bool {
        watchScheduledIDs.contains(WatchWorkoutBuilder.stableID(for: workout))
    }

    /// Puts these workouts on the watch, and tidies away any that were re-planned or moved.
    func sendToWatch(_ workouts: [Workout]) async {
        guard let watch else { return }
        do {
            try await watch.sync(watchItems(workouts), keeping: currentWatchIDs, today: today)
            watchScheduledIDs = await watch.scheduledIDs()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The next seven days of workouts, kept in step with the plan when auto-sync is on.
    func syncWatch() async {
        guard watchAutoSync else { return }
        // With no plan this sends nothing, which also clears this app's workouts off the watch.
        await sendToWatch((plan?.workouts ?? []).filter { $0.date >= today && today.days(until: $0.date) < 7 })
    }

    func refreshWatchState() async {
        if let watch { watchScheduledIDs = await watch.scheduledIDs() }
    }

    private var currentWatchIDs: Set<UUID> {
        Set((plan?.workouts ?? []).map(WatchWorkoutBuilder.stableID(for:)))
    }

    private func watchItems(_ workouts: [Workout]) -> [WatchItem] {
        workouts.filter { $0.date >= today }.map {
            WatchItem(plan: WatchWorkoutBuilder.plan(for: $0, format: format),
                      start: WatchWorkoutBuilder.startComponents(for: $0.date, minutes: reminderMinutes))
        }
    }

    // MARK: Intervals.icu (Garmin, Coros and others)

    var intervalsAvailable: Bool { intervals != nil }

    /// Swaps the sign-in redirect for an access token, then connects.
    func finishIntervalsSignIn(callback: URL, attempt: IntervalsOAuth.Attempt) async throws {
        guard let intervals, let intervalsOAuth else { return }
        let code = try IntervalsOAuth.code(from: callback, attempt: attempt)
        try await connect(try await intervals.signIn(code: code, attempt: attempt, oauth: intervalsOAuth))
    }

    /// Connects with a personal API key (builds without an OAuth client ID). Throws if the key is wrong.
    func connectIntervals(apiKey: String) async throws {
        guard let intervals else { return }
        try await connect(try await intervals.signIn(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func connect(_ credentials: IntervalsCredentials) async throws {
        try intervalsKeychain.save(credentials)
        intervalsAccount = credentials
        intervalsSyncedIDs = nil
        intervalsAthlete = nil
        // Linked watches start receiving workouts straight away, so there's nothing to switch on by hand.
        await refreshIntervalsLinks(enableAll: true)
        await syncIntervals(force: true)
    }

    /// Re-reads which watch services are linked, and switches on workout upload for any service linked since
    /// the last look (or for all of them with `enableAll`, when connecting). So linking Garmin on Intervals.icu
    /// and coming back is all it takes, while a service the athlete later turns off by hand stays off.
    func refreshIntervalsLinks(enableAll: Bool = false) async {
        guard let intervals, let account = intervalsAccount else { return }
        do {
            var athlete = try await intervals.athlete(account)
            let previous = intervalsAthlete.map { Set($0.links.map(\.service)) }
            let toEnable = athlete.links.filter { link in
                !link.uploading && (enableAll || previous.map { !$0.contains(link.service) } ?? false)
            }
            if !toEnable.isEmpty {
                try await intervals.enableUpload(for: toEnable, credentials: account)
                athlete = try await intervals.athlete(account)
            }
            intervalsAthlete = athlete
            adoptImportedZones(from: athlete)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Keeps imported zones in step with the athlete's watch platform. Zones the athlete typed in are left alone.
    private func adoptImportedZones(from athlete: IntervalsAthlete) {
        guard let imported = athlete.runningHeartRateZones, storedHeartRateZones?.source != .custom,
              storedHeartRateZones != imported else { return }
        setHeartRateZones(imported)
    }

    /// Fetches the athlete's zones from Intervals.icu (where Garmin and others sync them) and uses them.
    /// Returns false if there are none to import.
    @discardableResult
    func importHeartRateZones() async -> Bool {
        guard let intervals, let account = intervalsAccount else { return false }
        do {
            let athlete = try await intervals.athlete(account)
            intervalsAthlete = athlete
            guard let imported = athlete.runningHeartRateZones else { return false }
            setHeartRateZones(imported)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Switches on workout upload for one linked service (the "Turn on" button in Settings).
    func enableIntervalsUpload(_ link: IntervalsAthlete.Link) async {
        guard let intervals, let account = intervalsAccount else { return }
        do {
            try await intervals.enableUpload(for: [link], credentials: account)
            intervalsAthlete = try await intervals.athlete(account)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Where the athlete links Garmin (and other watches) to Intervals.icu.
    static let intervalsConnectionsURL = URL(string: "https://intervals.icu/settings")!

    /// Removes this app's upcoming workouts from Intervals.icu (best effort), then forgets the key.
    func disconnectIntervals() async {
        if let intervals, let account = intervalsAccount {
            _ = try? await intervals.sync([], from: today, through: intervalsSyncEnd, credentials: account)
        }
        intervalsKeychain.delete()
        intervalsAccount = nil
        intervalsAthlete = nil
        intervalsLastSync = nil
        intervalsSyncedIDs = nil
    }

    /// Makes the Intervals.icu calendar match the plan from today on. Skipped when nothing changed since the
    /// last sync, unless `force` (the "Sync now" button).
    func syncIntervals(force: Bool = false) async {
        guard let intervals, let account = intervalsAccount, !intervalsSyncing else { return }
        let events = (plan?.workouts ?? []).filter { $0.date >= today }
            .map { IntervalsWorkoutBuilder.event(for: $0, format: format) }
        let ids = Set(events.map(\.external_id))
        if !force, ids == intervalsSyncedIDs { return }
        intervalsSyncing = true
        defer { intervalsSyncing = false }
        do {
            _ = try await intervals.sync(events, from: today, through: intervalsSyncEnd, credentials: account)
            intervalsSyncedIDs = ids
            intervalsLastSync = .now
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Far enough ahead to cover the whole plan, and to clear workouts left over from a longer earlier plan.
    private var intervalsSyncEnd: LocalDate {
        max(plan?.workouts.last?.date ?? today, today.adding(days: 400))
    }

    // MARK: Strength

    /// Strength sessions for the current plan (empty when turned off).
    var strengthSessions: [StrengthSchedule.Session] {
        guard strengthEnabled, let plan else { return [] }
        return StrengthSchedule.sessions(for: plan, perWeek: strengthPerWeek)
    }

    func strengthSession(on date: LocalDate) -> StrengthSchedule.Session? {
        strengthSessions.first { $0.date == date }
    }

    func isStrengthDone(_ session: StrengthSchedule.Session) -> Bool { statuses[session.id] == .done }

    func setStrengthDone(_ done: Bool, for session: StrengthSchedule.Session) {
        setStatus(done ? .done : nil, forID: session.id)
    }

    func setStrength(enabled: Bool, perWeek: Int? = nil) {
        let p = profile()
        p.strengthEnabled = enabled
        if let perWeek { p.strengthPerWeek = min(max(perWeek, 1), 2) }
        save()
        Task { await syncCalendar() }
    }

    // MARK: Coach

    /// The coach shows when it's turned on and this iPhone can run it.
    var showsCoach: Bool { coachEnabled && CoachAvailability.current != .unsupported }

    func setCoachEnabled(_ enabled: Bool) {
        profile().coachEnabled = enabled
        save()
    }

    /// Applies a change the coach suggested, through the same rules as moving or skipping by hand.
    /// Returns false (with `lastError` set) if it isn't allowed.
    @discardableResult
    func apply(_ suggestion: CoachSuggestion) -> Bool {
        // Time off is chosen in its own screen (dates, open-ended or not), not applied straight from the coach.
        guard suggestion.action != .timeOff else { return false }
        guard let workout = workout(on: suggestion.date), workout.kind != .race else {
            lastError = String(localized: "There's no workout on that day to change.")
            return false
        }
        switch suggestion.action {
        case .skip:
            setStatus(.skipped, for: workout)
            return true
        case .move:
            guard let newDate = suggestion.newDate else { return false }
            return move(workout, to: newDate)
        case .timeOff:
            return false
        }
    }

    // MARK: Calendar

    var calendarAvailable: Bool { calendar != nil }

    /// The workout as a calendar event, at the reminder time.
    func calendarEvent(for workout: Workout) -> CalendarEventContent {
        CalendarEventContent.make(for: workout, format: format, minutes: reminderMinutes)
    }

    /// A strength session as a calendar event: an hour after the reminder time, so it follows any run that day.
    func calendarEvent(for session: StrengthSchedule.Session) -> CalendarEventContent {
        let routine = StrengthRoutine.for(session.level)
        return CalendarEventContent.make(title: routine.title, notes: routine.text, date: session.date,
                                         minutes: reminderMinutes + 60, durationMinutes: routine.minutes,
                                         id: session.id)
    }

    func setCalendarSync(_ enabled: Bool) async {
        guard let calendar else { return }
        if enabled {
            guard await calendar.requestAccess() else {
                lastError = CalendarService.SyncError.noAccess.localizedDescription
                return
            }
            calendarSyncEnabled = true
            UserDefaults.standard.set(true, forKey: Self.calendarSyncKey)
            await syncCalendar(force: true)
        } else {
            calendarSyncEnabled = false
            calendarSyncedKeys = nil
            UserDefaults.standard.set(false, forKey: Self.calendarSyncKey)
            do { try calendar.removeCalendar() } catch { lastError = error.localizedDescription }
        }
    }

    /// Makes the app's calendar match the plan from today on (skipped when nothing changed, unless `force`).
    func syncCalendar(force: Bool = false) async {
        guard let calendar, calendarSyncEnabled else { return }
        let events = (plan?.workouts ?? []).filter { $0.date >= today }.map(calendarEvent(for:))
            + strengthSessions.filter { $0.date >= today }.map(calendarEvent(for:))
        let keys = Set(events.map(\.key))
        if !force, keys == calendarSyncedKeys { return }
        let from = Calendar.current.startOfDay(for: today.date())
        let through = Calendar.current.date(byAdding: .day, value: 400, to: from) ?? from
        let end = max(through, events.map(\.end).max() ?? through)
        do {
            try calendar.sync(events, from: from, through: end)
            calendarSyncedKeys = keys
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Keeps reminders, the watch, Intervals.icu and the calendar in step after the plan changes.
    private func planDidChange() {
        Task {
            await syncReminders()
            await syncWatch()
            await syncIntervals()
            await syncCalendar()
        }
    }

    /// Everything to do when the app comes to the foreground.
    func becameActive() async {
        reload()
        await refreshHealth()
        reviewPlan()
        await syncReminders()
        await syncWatch()
        await refreshWatchState()
        if intervalsAccount != nil {
            await refreshIntervalsLinks()
            await syncIntervals()
        }
        await syncCalendar()
    }

    // MARK: Preferences

    func setUnits(_ newUnits: UnitSystem) {
        profile().units = newUnits
        save()
        // Paces on Intervals.icu and in calendar notes are written per km or per mile.
        Task {
            await syncIntervals()
            await syncCalendar()
        }
    }

    func acceptDisclaimer() {
        let p = profile()
        if p.disclaimerAcceptedAt == nil { p.disclaimerAcceptedAt = .now }
        save()
    }

    // MARK: Export / import

    func exportBundle() -> ExportBundle {
        ExportBundle(exportedAt: .now, units: units, disclaimerAcceptedAt: fetchProfile()?.disclaimerAcceptedAt,
                     plan: plan, statuses: statuses,
                     races: races.map(ExportBundle.Race.init),
                     changes: changes.map { .init(date: $0.createdAt, reasons: $0.reasons) })
    }

    /// Replaces everything stored with the contents of an export.
    func importBundle(_ bundle: ExportBundle) {
        for type in [PlanRecord.self, WorkoutLogRecord.self, RaceRecord.self, PlanChangeRecord.self] as [any PersistentModel.Type] {
            try? context.delete(model: type)
        }
        let p = profile()
        p.units = bundle.units
        p.disclaimerAcceptedAt = bundle.disclaimerAcceptedAt ?? p.disclaimerAcceptedAt
        if let plan = bundle.plan, let record = try? PlanRecord(plan: plan) {
            context.insert(record)
            for (workoutID, status) in bundle.statuses {
                context.insert(WorkoutLogRecord(planID: record.planID, workoutID: workoutID, status: status))
            }
            for change in bundle.changes {
                let r = PlanChangeRecord(planID: record.planID, reasons: change.reasons)
                r.createdAt = change.date
                r.seen = true
                context.insert(r)
            }
        }
        for race in bundle.races {
            context.insert(RaceRecord(name: race.name, distance: race.distance, date: race.date,
                                      goalSeconds: race.goalSeconds, resultSeconds: race.resultSeconds))
        }
        save()
    }

    // MARK: Derived

    func workout(on date: LocalDate) -> Workout? {
        plan?.workouts.first { $0.date == date }
    }

    func week(containing date: LocalDate) -> PlanWeek? {
        plan?.weeks.first { $0.startDate == date.startOfWeek }
    }

    /// nil while a new runner is still on run/walk: a race time means little before they can run 30 minutes.
    var prediction: RacePrediction? {
        guard let plan, plan.runWalkWeeksLeft(from: today) == 0 else { return nil }
        return RacePredictor.predict(plan.inputs.goal, fitness: plan.fitness, recentRuns: trainingLog.runs, asOf: today)
    }
}

/// Everything the app stores, as one JSON document. Versioned so future releases can still import it.
/// `nonisolated`: plain data, encoded off the main thread by the share sheet.
nonisolated struct ExportBundle: Codable, Equatable {
    struct Race: Codable, Equatable {
        var name: String
        var distance: RaceDistance
        var date: LocalDate
        var goalSeconds: Double?
        var resultSeconds: Double?

        init(name: String, distance: RaceDistance, date: LocalDate, goalSeconds: Double?, resultSeconds: Double?) {
            self.name = name
            self.distance = distance
            self.date = date
            self.goalSeconds = goalSeconds
            self.resultSeconds = resultSeconds
        }

        init(_ record: RaceRecord) {
            self.init(name: record.name, distance: record.distance, date: record.date,
                      goalSeconds: record.goalSeconds, resultSeconds: record.resultSeconds)
        }
    }

    struct Change: Codable, Equatable {
        var date: Date
        var reasons: [AdaptationReason]
    }

    static let currentFormat = "trackstar-export"
    /// Backups made before the app was renamed.
    static let legacyFormats = ["steppa-export"]
    static let currentVersion = 1

    var format = currentFormat
    var version = currentVersion
    var exportedAt: Date
    var units: UnitSystem
    var disclaimerAcceptedAt: Date?
    var plan: TrainingPlan?
    var statuses: [String: WorkoutStatus]
    var races: [Race]
    var changes: [Change]

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    enum ImportError: LocalizedError {
        case notAnExport, newerVersion

        var errorDescription: String? {
            switch self {
            case .notAnExport: String(localized: "This file isn't an export from this app.")
            case .newerVersion: String(localized: "This file was exported by a newer version of the app. Update the app and try again.")
            }
        }
    }

    static func decode(_ data: Data) throws -> ExportBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle: ExportBundle
        do { bundle = try decoder.decode(ExportBundle.self, from: data) } catch { throw ImportError.notAnExport }
        guard bundle.format == currentFormat || legacyFormats.contains(bundle.format) else { throw ImportError.notAnExport }
        guard bundle.version <= currentVersion else { throw ImportError.newerVersion }
        return bundle
    }
}

extension EditError {
    var message: String {
        switch self {
        case .workoutNotFound: String(localized: "That workout no longer exists.")
        case .cannotMoveRace: String(localized: "Race day can't be moved here. Change the race date in Races instead.")
        case .dateInPast: String(localized: "Past workouts can't be moved.")
        case .afterRace: String(localized: "Workouts can't be moved past race day.")
        case .differentWeek: String(localized: "Workouts can be moved within the same week.")
        case .dayOff: String(localized: "That day is marked as time off.")
        case .breaksRule(let rule):
            switch rule {
            case .consecutiveHardDays: String(localized: "That would put two hard days in a row. Try another day.")
            case .hardBeforeRace: String(localized: "Hard sessions can't go in the last three days before your race.")
            default: String(localized: "That move would break one of the plan's safety rules.")
            }
        }
    }
}

extension AdaptationReason {
    func message(_ format: DisplayFormat) -> String {
        switch self {
        case .missedTraining(let share):
            String(localized: "You completed \(Int((share * 100).rounded()))% of your planned distance over the last two weeks, so the coming weeks start a little lower and build back gradually.")
        case .returningFromBreak(let days):
            String(localized: "Welcome back. After \(days) days off, the plan eases you back in rather than picking up where you left off.")
        case .fitnessImproved:
            String(localized: "Your recent sessions were faster than planned, so your paces have been nudged up slightly.")
        case .fitnessDeclined:
            String(localized: "Your recent sessions were slower than planned, so your paces have been eased slightly.")
        case .newRaceResult:
            String(localized: "Your paces have been updated from your new race result.")
        case .raceDateChanged(let date):
            String(localized: "Your plan has been rebuilt around your new race date, \(date.dayMonth).")
        case .availabilityChanged:
            String(localized: "Your runs have been moved to fit your new available days.")
        case .timeOffChanged:
            String(localized: "Your plan has been rebuilt around your time off, and eases you back in afterwards.")
        }
    }
}
