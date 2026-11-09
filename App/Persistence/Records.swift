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
    /// When Apple Health access was requested (Health never says whether it was granted).
    var healthRequestedAt: Date?
    var remindersEnabled: Bool = false
    /// Minutes after midnight for reminders and for when workouts appear on the watch.
    var reminderMinutes: Int = 7 * 60
    var watchAutoSync: Bool = false
    /// Set by the athlete; otherwise estimated (see AppModel.maxHeartRate).
    var maxHeartRate: Double?
    /// Optional bodyweight strength sessions around the running plan.
    var strengthEnabled: Bool = false
    var strengthPerWeek: Int = 2
    /// Show the on-device coach (where Apple Intelligence is available).
    var coachEnabled: Bool = true
    /// Heart-rate zones imported from the athlete's watch platform or typed in (JSON of HeartRateZones). nil means
    /// zones are worked out from maximum heart rate.
    var heartRateZonesData: Data?
    /// How workout targets are shown: pace, heart rate or treadmill speed (WorkoutTargetDisplay).
    var targetDisplayRaw: String?
    /// km/h or mph for treadmill speeds, chosen separately from distance units.
    var treadmillUnitsRaw: String?

    init(units: UnitSystem) {
        unitsRaw = units.rawValue
    }

    var units: UnitSystem {
        get { UnitSystem(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }
}

/// A race other than the plan's goal race (e.g. a tune-up 10K), or a past result.
@Model
final class RaceRecord {
    var raceID: UUID = UUID()
    var name: String = ""
    var distanceRaw: String = RaceDistance.tenK.rawValue
    /// `YYYY-MM-DD`; stored as text so a time-zone change can never move the race.
    var dateString: String = ""
    var goalSeconds: Double?
    var resultSeconds: Double?
    var createdAt: Date = Date.now

    init(name: String, distance: RaceDistance, date: LocalDate, goalSeconds: Double? = nil, resultSeconds: Double? = nil) {
        self.name = name
        self.distanceRaw = distance.rawValue
        self.dateString = date.description
        self.goalSeconds = goalSeconds
        self.resultSeconds = resultSeconds
    }

    var distance: RaceDistance {
        get { RaceDistance(rawValue: distanceRaw) ?? .tenK }
        set { distanceRaw = newValue.rawValue }
    }

    var date: LocalDate {
        get { LocalDate(iso: dateString) ?? .today }
        set { dateString = newValue.description }
    }
}

/// A record of why the plan changed, shown as "Your plan changed because…".
@Model
final class PlanChangeRecord {
    var planID: UUID?
    var createdAt: Date = Date.now
    var reasonsData: Data?
    var seen: Bool = false
    /// The plan as it was before this change, so the athlete can undo it.
    @Attribute(.externalStorage) var previousPlanData: Data?

    init(planID: UUID, reasons: [AdaptationReason], previous: TrainingPlan? = nil) {
        self.planID = planID
        self.reasonsData = try? JSONEncoder.plan.encode(reasons)
        self.previousPlanData = previous.flatMap { try? JSONEncoder.plan.encode($0) }
    }

    var reasons: [AdaptationReason] {
        get {
            guard let reasonsData else { return [] }
            return (try? JSONDecoder().decode([AdaptationReason].self, from: reasonsData)) ?? []
        }
        set { reasonsData = try? JSONEncoder.plan.encode(newValue) }
    }

    var previousPlan: TrainingPlan? {
        previousPlanData.flatMap { try? JSONDecoder().decode(TrainingPlan.self, from: $0) }
    }
}

/// What a watch recorded during one run, kept so runs can be analysed later without asking Health or
/// Intervals.icu again. Stored downsampled (at most a few hundred points per series).
@Model
final class RunDetailRecord {
    /// The run's ID: the Health workout's UUID, or "icu-<id>" for runs only on Intervals.icu.
    var runID: String = ""
    /// "health" or "intervals".
    var source: String = ""
    var fetchedAt: Date = Date.now
    @Attribute(.externalStorage) var seriesData: Data?

    init(runID: String, source: String, series: RunSeries) {
        self.runID = runID
        self.source = source
        self.seriesData = try? JSONEncoder().encode(series.downsampled())
    }

    var series: RunSeries? {
        seriesData.flatMap { try? JSONDecoder().decode(RunSeries.self, from: $0) }
    }
}

/// A workout the athlete built and saved to reuse ("My workouts").
@Model
final class WorkoutTemplateRecord {
    var templateID: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var templateData: Data?

    init(_ template: WorkoutTemplate) throws {
        templateID = template.id
        try update(template)
    }

    func update(_ template: WorkoutTemplate) throws {
        templateData = try JSONEncoder.plan.encode(template)
        name = template.name
        updatedAt = .now
    }

    var template: WorkoutTemplate? {
        templateData.flatMap { try? JSONDecoder().decode(WorkoutTemplate.self, from: $0) }
    }
}

/// A custom workout put on a day. Holds its own copy of the blocks, so changing a saved workout later doesn't
/// rewrite days already planned with it. Kept apart from the plan, so re-planning never loses it.
@Model
final class ScheduledWorkoutRecord {
    var scheduleID: UUID = UUID()
    var dateString: String = ""
    var createdAt: Date = Date.now
    var templateData: Data?

    init(_ scheduled: ScheduledWorkout) throws {
        scheduleID = scheduled.id
        try update(scheduled)
    }

    func update(_ scheduled: ScheduledWorkout) throws {
        dateString = scheduled.date.description
        templateData = try JSONEncoder.plan.encode(scheduled.template)
    }

    var scheduled: ScheduledWorkout? {
        guard let date = LocalDate(iso: dateString),
              let template = templateData.flatMap({ try? JSONDecoder().decode(WorkoutTemplate.self, from: $0) }) else { return nil }
        return ScheduledWorkout(id: scheduleID, date: date, template: template)
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
    static let models: [any PersistentModel.Type] = [PlanRecord.self, WorkoutLogRecord.self, ProfileRecord.self,
                                                     RaceRecord.self, PlanChangeRecord.self, RunDetailRecord.self,
                                                     WorkoutTemplateRecord.self, ScheduledWorkoutRecord.self]

    /// Syncs through the user's private CloudKit database when built with `ENABLE_ICLOUD = YES`
    /// (see Config/App.xcconfig); otherwise the store is local to the device.
    static var syncsWithICloud: Bool {
        #if ICLOUD
        true
        #else
        false
        #endif
    }

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: syncsWithICloud && !inMemory ? .automatic : .none)
        do {
            return try ModelContainer(for: Schema(models), configurations: configuration)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }
}
