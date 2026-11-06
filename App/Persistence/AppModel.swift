import Foundation
import Observation
import SwiftData
import PlanEngine

/// The app's state: the active plan, workout statuses and preferences.
/// Views read from it; every change goes through its methods so storage stays consistent.
@Observable
final class AppModel {
    private let context: ModelContext

    private(set) var plan: TrainingPlan?
    private(set) var planID: UUID?
    private(set) var statuses: [String: WorkoutStatus] = [:]
    private(set) var units: UnitSystem = .localeDefault
    private(set) var disclaimerAccepted = false
    /// Set when saving fails, so the UI can tell the user.
    var lastError: String?

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    var format: DisplayFormat { DisplayFormat(units: units) }

    // MARK: Loading

    func reload() {
        let profile = fetchProfile()
        units = profile?.units ?? .localeDefault
        disclaimerAccepted = profile?.disclaimerAcceptedAt != nil

        // If two devices both created a plan before syncing, the most recently updated one wins.
        var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.isActive },
                                                     sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        let record = try? context.fetch(descriptor).first
        plan = record?.decoded()
        planID = record?.planID

        statuses = [:]
        if let id = planID {
            let logs = (try? context.fetch(FetchDescriptor<WorkoutLogRecord>(predicate: #Predicate { $0.planID == id }))) ?? []
            for log in logs.sorted(by: { $0.updatedAt < $1.updatedAt }) {
                statuses[log.workoutID] = log.status
            }
        }
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

    // MARK: Derived

    var today: LocalDate { .today }

    func workout(on date: LocalDate) -> Workout? {
        plan?.workouts.first { $0.date == date }
    }

    func week(containing date: LocalDate) -> PlanWeek? {
        plan?.weeks.first { $0.startDate == date.startOfWeek }
    }

    var upcoming: [Workout] {
        plan?.workouts.filter { $0.date > today } ?? []
    }
}
