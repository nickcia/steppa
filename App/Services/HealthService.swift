import Foundation
import HealthKit
import PlanEngine

/// Where completed runs come from. Apple Health in the app; a fake in tests.
protocol RunSource {
    var isAvailable: Bool { get }
    func requestAccess() async throws
    func runs(since: LocalDate) async throws -> [CompletedRun]
    /// What the watch recorded during a run, if anything: distance, heart rate, power, cadence.
    func series(forRun id: String) async throws -> RunSeries?
    /// The athlete's age from Health, for estimating maximum heart rate. nil if not shared.
    func age() -> Int?
}

/// Reads running workouts from Apple Health. Read-only: nothing is ever written.
///
/// Runs recorded by Apple Watch, and by Garmin, Coros, Strava and others that sync into Health,
/// all arrive here the same way.
final class HealthKitRunSource: RunSource {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Workouts and distance tick off the plan; the rest (heart rate, power, cadence) is for run analysis.
    /// Asking again after an update only prompts for the new types.
    private var readTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.heartRate),
         HKQuantityType(.runningPower), HKQuantityType(.stepCount), HKCharacteristicType(.dateOfBirth)]
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

    func series(forRun id: String) async throws -> RunSeries? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let byID = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
                                           sortDescriptors: [])
        guard let workout = try await byID.result(for: store).first else { return nil }
        let start = workout.startDate, end = workout.endDate
        let during = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        func samples(_ type: HKQuantityTypeIdentifier) async throws -> [HKQuantitySample] {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(type), predicate: during)],
                sortDescriptors: [SortDescriptor(\.startDate)])
            return try await descriptor.result(for: store)
        }
        func seconds(_ date: Date) -> Double { date.timeIntervalSince(start) }

        // Distance: running total at the end of each sample. A single sample for the whole run (some apps
        // write that) says nothing about pace along the way, so it's left out rather than faked as even splits.
        var distance: [RunSeries.Point] = []
        let distanceSamples = try await samples(.distanceWalkingRunning)
        if distanceSamples.count >= 10 {
            var total = 0.0
            distance = [.init(0, 0)] + distanceSamples.map { sample in
                total += sample.quantity.doubleValue(for: .meter())
                return .init(seconds(sample.endDate), total)
            }
        }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heartRate = try await samples(.heartRate).map { RunSeries.Point(seconds($0.startDate), $0.quantity.doubleValue(for: bpm)) }
        let power = try await samples(.runningPower).map { RunSeries.Point(seconds($0.startDate), $0.quantity.doubleValue(for: .watt())) }
        // Cadence from step counts: steps per minute over each (short) sample.
        let cadence = try await samples(.stepCount).compactMap { sample -> RunSeries.Point? in
            let length = sample.endDate.timeIntervalSince(sample.startDate)
            guard length >= 5, length <= 300 else { return nil }
            let mid = sample.startDate.addingTimeInterval(length / 2)
            return .init(seconds(mid), sample.quantity.doubleValue(for: .count()) / length * 60)
        }
        let series = RunSeries(distance: distance, heartRate: heartRate, power: power, cadence: cadence)
        return series.isEmpty ? nil : series
    }

    func age() -> Int? {
        guard let birth = try? store.dateOfBirthComponents(), let date = Calendar.current.date(from: birth) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: .now).year
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
