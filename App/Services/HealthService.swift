import Foundation
import HealthKit
import PlanEngine

/// Where completed runs come from. Apple Health in the app; a fake in tests.
protocol RunSource {
    var isAvailable: Bool { get }
    func requestAccess() async throws
    func runs(since: LocalDate) async throws -> [CompletedRun]
}

/// Reads running workouts from Apple Health. Read-only: nothing is ever written.
///
/// Runs recorded by Apple Watch, and by Garmin, Coros, Strava and others that sync into Health,
/// all arrive here the same way.
final class HealthKitRunSource: RunSource {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning)]
    }

    func requestAccess() async throws {
        // Health never reveals whether read access was granted (privacy); a denial just returns no data.
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func runs(since start: LocalDate) async throws -> [CompletedRun] {
        let running = HKQuery.predicateForWorkouts(activityPredicate:
            HKQuery.predicateForWorkoutActivities(workoutActivityType: .running))
        let recent = HKQuery.predicateForSamples(withStart: start.date(), end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: [running, recent]))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = try await descriptor.result(for: store)
        return workouts.compactMap(Self.run)
    }

    static func run(from workout: HKWorkout) -> CompletedRun? {
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let meters = workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter())
            ?? workout.totalDistance?.doubleValue(for: .meter())
        guard let meters, meters >= RunMatcher.minimumRunMeters, workout.duration > 0 else { return nil }
        return CompletedRun(id: workout.uuid.uuidString, date: LocalDate(workout.startDate),
                            distanceMeters: meters, durationSeconds: workout.duration)
    }
}
