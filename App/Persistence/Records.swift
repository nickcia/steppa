import Foundation
import SwiftData
import PlanEngine

// SwiftData models. They follow CloudKit's rules from day one so that iCloud sync can be switched on
// without a migration: every property has a default or is optional, no unique constraints, and
// relationships (none yet) must be optional.

/// A training plan, stored as one encoded `TrainingPlan` value.
///
/// Why one blob rather than a record per workout: CloudKit syncs records independently, so a
/// per-workout model could briefly show a mix of two plan revisions on another device. A single
/// record always syncs as a consistent whole. Plans are small (~100 KB); external storage keeps
/// larger ones off the main record.
@Model
final class PlanRecord {
    var planID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isActive: Bool = true
    var revision: Int = 0
    @Attribute(.externalStorage) var planData: Data?

    init(plan: TrainingPlan) throws {
        try update(plan)
    }

    func update(_ plan: TrainingPlan) throws {
        planData = try JSONEncoder.plan.encode(plan)
        revision = plan.revision
        updatedAt = .now
    }

    func decoded() -> TrainingPlan? {
        guard let planData else { return nil }
        return try? JSONDecoder().decode(TrainingPlan.self, from: planData)
    }
}

enum WorkoutStatus: String, Codable, CaseIterable {
    case done, skipped
}

/// Whether the athlete did a workout. Kept apart from the plan so ticking a run off never
/// rewrites (or conflicts with) the whole plan.
@Model
final class WorkoutLogRecord {
    var planID: UUID?
    var workoutID: String = ""
    var statusRaw: String = WorkoutStatus.done.rawValue
    /// Health workout matched to this planned workout, if any.
    var runID: String?
    var updatedAt: Date = Date.now

    init(planID: UUID, workoutID: String, status: WorkoutStatus) {
        self.planID = planID
        self.workoutID = workoutID
        self.statusRaw = status.rawValue
    }

    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .done }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }
}

/// App-wide preferences that should follow the athlete to a new phone.
@Model
final class ProfileRecord {
    var unitsRaw: String = UnitSystem.metric.rawValue
    var disclaimerAcceptedAt: Date?
    var createdAt: Date = Date.now

    init(units: UnitSystem) {
        unitsRaw = units.rawValue
    }

    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }
}

extension JSONEncoder {
    /// Stable output: sorted keys keep stored plans byte-identical for identical content.
    nonisolated static var plan: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum Persistence {
    static let models: [any PersistentModel.Type] = [PlanRecord.self, WorkoutLogRecord.self, ProfileRecord.self]

    /// Local-only store for now. iCloud sync is switched on in a later milestone by changing
    /// `cloudKitDatabase` once the iCloud container exists.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Schema(models), configurations: configuration)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }
}
