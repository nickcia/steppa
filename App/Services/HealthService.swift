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
    /// Asks to save runs recorded on the phone (guided runs) as workouts.
    func requestWriteAccess() async throws
    /// Saves a guided run as a running workout with its distance and route. Returns the workout's ID.
    func save(_ recording: GuidedRunRecording) async throws -> String?
    /// When runs recorded by something other than this app (a watch, another app) happened, from `start` on.
    /// For spotting a watch that recorded the same run as the phone.
    func otherRuns(since start: Date) async -> [DateInterval]
}

extension RunSource {
    func requestWriteAccess() async throws {}
    func save(_ recording: GuidedRunRecording) async throws -> String? { nil }
    func otherRuns(since start: Date) async -> [DateInterval] { [] }
}

/// Reads running workouts from Apple Health, and saves runs recorded on the phone during a guided run (nothing else
/// is ever written).
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

    /// Only what a guided run records: the workout, its distance and its route.
    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning), HKSeriesType.workoutRoute()]
    }

    func requestWriteAccess() async throws {
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func save(_ recording: GuidedRunRecording) async throws -> String? {
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return nil }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = recording.route.isEmpty ? .unknown : .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: recording.start)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let samples = recording.segments.map {
            HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: $0.meters),
                             start: $0.start, end: max($0.end, $0.start.addingTimeInterval(1)))
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }
        let events = recording.pauses.flatMap { pause in
            [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil),
             HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil)]
        }
        if !events.isEmpty { try await builder.addWorkoutEvents(events) }
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: false, "TrackStarWorkoutID": recording.workoutID])
        try await builder.endCollection(at: recording.end)
        guard let workout = try await builder.finishWorkout() else { return nil }
        if recording.route.count >= 2 {
            let route = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await route.insertRouteData(recording.route)
            try await route.finishRoute(with: workout, metadata: nil)
        }
        return workout.uuid.uuidString
    }

    func otherRuns(since start: Date) async -> [DateInterval] {
        let running = HKQuery.predicateForWorkouts(activityPredicate:
            HKQuery.predicateForWorkoutActivities(workoutActivityType: .running))
        let recent = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: [running, recent]))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = (try? await descriptor.result(for: store)) ?? []
        let mine = Bundle.main.bundleIdentifier
        return workouts.filter { $0.sourceRevision.source.bundleIdentifier != mine }
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
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
