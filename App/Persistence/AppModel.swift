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

    private(set) var plan: TrainingPlan?
    private(set) var planID: UUID?
    private(set) var statuses: [String: WorkoutStatus] = [:]
    private(set) var units: UnitSystem = .localeDefault
    private(set) var disclaimerAccepted = false
    private(set) var races: [RaceRecord] = []
    private(set) var changes: [PlanChangeRecord] = []
    /// Set when saving fails or an edit is refused, so the UI can tell the user.
    var lastError: String?

    init(container: ModelContainer, clock: @escaping () -> LocalDate = { .today }) {
        self.container = container
        self.clock = clock
        reload()
    }

    var today: LocalDate { clock() }
    var format: DisplayFormat { DisplayFormat(units: units) }

    // MARK: Loading

    func reload() {
        let profile = fetchProfile()
        units = profile?.units ?? .localeDefault
        disclaimerAccepted = profile?.disclaimerAcceptedAt != nil

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
    }

    func endPlan() {
        guard let id = planID else { return }
        let records = (try? context.fetch(FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.planID == id }))) ?? []
        for record in records { record.isActive = false }
        save()
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
        return true
    }

    // MARK: Adaptation

    /// What the athlete actually did. Until Apple Health is connected, workouts marked done count as
    /// runs of the planned distance and duration; skipped and unmarked workouts count as missed.
    /// Only treated as complete once the athlete has started ticking workouts off (see `adapt`).
    var trainingLog: TrainingLog {
        guard let plan else { return TrainingLog() }
        var log = TrainingLog()
        for workout in plan.workouts where statuses[workout.id] == .done {
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
        guard let plan, !statuses.isEmpty, today < plan.inputs.raceDate else { return }
        adapt(.review)
    }

    @discardableResult
    private func adapt(_ trigger: AdaptationTrigger) -> Bool {
        guard let plan else { return false }
        do {
            let revision = try PlanAdapter.adapt(plan, log: trainingLog, trigger: trigger, today: today,
                                                 assessTraining: !statuses.isEmpty)
            return revision.changed ? store(revision.plan, reasons: revision.reasons) : true
        } catch {
            lastError = error.message
            return false
        }
    }

    func changeRaceDate(_ date: LocalDate) { adapt(.raceDateChanged(date)) }

    func changeAvailability(runDays: Set<Weekday>, longRunDay: Weekday) {
        adapt(.availabilityChanged(runDays: runDays, longRunDay: longRunDay))
    }

    func applyRaceResult(_ performance: RacePerformance) { adapt(.newRaceResult(performance)) }

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

    func status(of workout: Workout) -> WorkoutStatus? { statuses[workout.id] }

    func setStatus(_ status: WorkoutStatus?, for workout: Workout) {
        guard let planID else { return }
        let workoutID = workout.id
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

    // MARK: Preferences

    func setUnits(_ newUnits: UnitSystem) {
        profile().units = newUnits
        save()
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

    var prediction: RacePrediction? {
        guard let plan else { return nil }
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

    static let currentFormat = "steppa-export"
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
        guard bundle.format == currentFormat else { throw ImportError.notAnExport }
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
        }
    }
}
