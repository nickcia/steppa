import CryptoKit
import Foundation
import HealthKit
import PlanEngine
import WorkoutKit

/// Converts plan workouts into WorkoutKit structured workouts. Pure, so it's unit-tested.
///
/// The engine's workout shape (warm-up, repeated blocks of work/recovery steps, cool-down) was designed to
/// match WorkoutKit's `CustomWorkout`, so this is a one-to-one mapping.
enum WatchWorkoutBuilder {
    static func plan(for workout: PlanEngine.Workout, format: DisplayFormat) -> WorkoutPlan {
        WorkoutPlan(.custom(customWorkout(workout, format: format)), id: stableID(for: workout))
    }

    static func customWorkout(_ workout: PlanEngine.Workout, format: DisplayFormat) -> CustomWorkout {
        let describer = WorkoutDescriber(format: format)
        // Run/walk sessions name every step, so the watch says Walk and Run rather than Warm up and Recovery.
        let walk = workout.isRunWalkSession ? String(localized: "Walk") : nil
        return CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: "\(workout.kind.name) · \(describer.summary(workout))",
            warmup: workout.warmup.map { step($0, name: walk ?? String(localized: "Warm up"), alert: false) },
            blocks: workout.blocks.map { block in
                WorkoutKit.IntervalBlock(steps: block.steps.map { interval in
                    WorkoutKit.IntervalStep(interval.purpose == .work ? .work : .recovery,
                                            step: step(interval.step,
                                                       name: walk.map { interval.purpose == .work ? String(localized: "Run") : $0 },
                                                       alert: interval.purpose == .work))
                }, iterations: block.iterations)
            },
            cooldown: workout.cooldown.map { step($0, name: walk ?? String(localized: "Cool down"), alert: false) })
    }

    static func step(_ step: PlanEngine.Step, name: String?, alert: Bool) -> WorkoutKit.WorkoutStep {
        let goal: WorkoutGoal = switch step.goal {
        case .distance(let meters): .distance(meters, .meters)
        case .time(let seconds): .time(seconds, .seconds)
        }
        // Pace targets become speed-range alerts on the watch (warm-ups and recoveries stay alert-free).
        // Hills are run by effort and strides are too short for a pace alert to help.
        let paced = step.target.map { !$0.zone.isEffortBased && $0.zone != .stride } ?? false
        let speedAlert: SpeedRangeAlert? = alert && paced ? step.target.map { target in
            .speed(speed(target.range.slow)...speed(target.range.fast), unit: .metersPerSecond, metric: .current)
        } : nil
        if #available(iOS 18.0, *) {
            return WorkoutKit.WorkoutStep(goal: goal, alert: speedAlert,
                                          displayName: name ?? step.target.map { $0.zone.name.capitalized })
        }
        return WorkoutKit.WorkoutStep(goal: goal, alert: speedAlert)
    }

    static func speed(_ secondsPerKm: Double) -> Double { 1000 / secondsPerKm }

    /// The same workout content on the same day always gets the same ID, so re-sending is a no-op and
    /// any change (moved, re-planned, new paces) gets a new ID and replaces the old one.
    static func stableID(for workout: PlanEngine.Workout) -> UUID {
        let data = (try? JSONEncoder.plan.encode(workout)) ?? Data(workout.id.utf8)
        var bytes = Array(SHA256.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // RFC 4122 version 5 style
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// When the workout appears on the watch: the workout's day at the reminder time.
    static func startComponents(for date: LocalDate, minutes: Int) -> DateComponents {
        DateComponents(year: date.year, month: date.month, day: date.day, hour: minutes / 60, minute: minutes % 60)
    }
}

/// A workout ready to hand to the scheduler.
struct WatchItem: Sendable {
    let plan: WorkoutPlan
    let start: DateComponents
}

/// Schedules structured workouts in the Workout app on Apple Watch.
///
/// The scheduler calls run in a `@concurrent` nonisolated context: `WorkoutScheduler` isn't `Sendable`
/// in this SDK, so it must never cross from the main actor. Only `Sendable` values go in and out.
nonisolated final class WatchService: Sendable {
    enum SendError: LocalizedError {
        case unsupported, notAuthorized

        var errorDescription: String? {
            switch self {
            case .unsupported: String(localized: "Sending workouts needs an iPhone paired with an Apple Watch.")
            case .notAuthorized: String(localized: "Allow workout scheduling for this app in Settings › Privacy & Security, then try again.")
            }
        }
    }

    var isSupported: Bool { WorkoutScheduler.isSupported }

    @concurrent private func authorize() async throws {
        guard isSupported else { throw SendError.unsupported }
        let scheduler = WorkoutScheduler.shared
        var state = await scheduler.authorizationState
        if state == .notDetermined { state = await scheduler.requestAuthorization() }
        guard state == .authorized else { throw SendError.notAuthorized }
    }

    /// IDs of everything this app currently has scheduled.
    @concurrent func scheduledIDs() async -> Set<UUID> {
        guard isSupported else { return [] }
        return Set(await WorkoutScheduler.shared.scheduledWorkouts.map(\.plan.id))
    }

    /// Schedules `items` (skipping ones already there) and removes stale ones: anything whose ID isn't in
    /// `current` (re-planned or moved since) or whose day has passed.
    @concurrent func sync(_ items: [WatchItem], keeping current: Set<UUID>, today: LocalDate) async throws {
        try await authorize()
        let scheduler = WorkoutScheduler.shared
        for scheduled in await scheduler.scheduledWorkouts {
            let date = scheduled.date
            let past = (date.year ?? 0, date.month ?? 0, date.day ?? 0) < (today.year, today.month, today.day)
            if !current.contains(scheduled.plan.id) || past {
                await scheduler.remove(scheduled.plan, at: scheduled.date)
            }
        }
        let existing = Set(await scheduler.scheduledWorkouts.map(\.plan.id))
        var room = WorkoutScheduler.maxAllowedScheduledWorkoutCount - existing.count
        for item in items where room > 0 && !existing.contains(item.plan.id) {
            await scheduler.schedule(item.plan, at: item.start)
            room -= 1
        }
    }
}
