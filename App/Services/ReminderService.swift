import Foundation
import PlanEngine
import UserNotifications

/// Local "today's workout" reminders. Scheduled on the phone; no push server.
final class ReminderService {
    private let center = UNUserNotificationCenter.current()
    private static let prefix = "workout-"
    /// iOS keeps at most 64 pending notifications per app; two weeks ahead stays well inside that.
    static let daysAhead = 14

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func cancelAll() async {
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    /// Replaces all pending reminders with one per upcoming workout day, at `minutes` past midnight.
    func reschedule(_ workouts: [Workout], minutes: Int, format: DisplayFormat, now: Date = .now) async {
        await cancelAll()
        let today = LocalDate(now)
        let describer = WorkoutDescriber(format: format)
        for workout in workouts where workout.date >= today && today.days(until: workout.date) < Self.daysAhead {
            var when = WatchWorkoutBuilder.startComponents(for: workout.date, minutes: minutes)
            when.calendar = .current
            guard let fireDate = when.date, fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = workout.kind == .race
                ? String(localized: "Race day! Good luck")
                : String(localized: "Today: \(workout.name)")
            content.body = describer.summary(workout) + " · ~" + DisplayFormat.duration(workout.totalSeconds)
            content.sound = .default
            let request = UNNotificationRequest(identifier: Self.prefix + workout.date.description, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }
}
