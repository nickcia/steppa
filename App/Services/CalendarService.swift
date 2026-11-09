import CryptoKit
import EventKit
import EventKitUI
import Foundation
import SwiftUI
import PlanEngine

/// What a workout looks like as a calendar event. Pure, so it's unit-tested.
struct CalendarEventContent: Equatable {
    var title: String
    var notes: String
    var start: Date
    var end: Date
    /// Identifies the event as this app's, and changes whenever its content does.
    var key: String

    /// Events this app creates carry this URL scheme, followed by the key.
    static let urlScheme = "trackstar-workout"
    /// Schemes used before the app was renamed: events carrying them are still this app's.
    static let legacyURLSchemes = ["steppa-workout"]

    var url: URL? { URL(string: "\(Self.urlScheme):\(key)") }

    static func key(from url: URL?) -> String? {
        guard let url, let scheme = url.scheme, ([urlScheme] + legacyURLSchemes).contains(scheme) else { return nil }
        return String(url.absoluteString.dropFirst(scheme.count + 1))
    }

    /// The workout on its day at `minutes` after midnight (the reminder time), lasting its estimated duration.
    static func make(for workout: Workout, format: DisplayFormat, minutes: Int,
                     calendar: Calendar = .current) -> CalendarEventContent {
        let describer = WorkoutDescriber(format: format)
        let title = "\(workout.name) · \(describer.summary(workout))"
        var lines: [String] = []
        for section in describer.sections(workout) {
            switch section {
            case .single(let line):
                lines.append(text(line))
            case .repeated(let times, let repeated):
                lines.append("\(times) ×")
                lines += repeated.map { "  " + text($0) }
            }
        }
        lines.append("")
        lines.append(workout.kind.purpose)
        let notes = lines.joined(separator: "\n")

        let day = calendar.date(from: DateComponents(year: workout.date.year, month: workout.date.month,
                                                     day: workout.date.day)) ?? .now
        let start = calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
        // Round up to the next 5 minutes so the block looks tidy in a calendar.
        let minutesLong = max(5, Int((workout.totalSeconds / 60 / 5).rounded(.up)) * 5)
        let end = calendar.date(byAdding: .minute, value: minutesLong, to: start) ?? start

        let digest = SHA256.hash(data: Data("\(title)|\(notes)|\(start.timeIntervalSince1970)|\(minutesLong)".utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return CalendarEventContent(title: title, notes: notes, start: start, end: end, key: "\(workout.id)-\(hash)")
    }

    /// Any other event (e.g. a strength session) on `date` at `minutes` after midnight.
    static func make(title: String, notes: String, date: LocalDate, minutes: Int, durationMinutes: Int, id: String,
                     calendar: Calendar = .current) -> CalendarEventContent {
        let day = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)) ?? .now
        let start = calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
        let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
        let digest = SHA256.hash(data: Data("\(title)|\(notes)|\(start.timeIntervalSince1970)|\(durationMinutes)".utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return CalendarEventContent(title: title, notes: notes, start: start, end: end, key: "\(id)-\(hash)")
    }

    private static func text(_ line: WorkoutDescriber.Line) -> String {
        line.detail.map { "\(line.title) · \($0)" } ?? line.title
    }

    /// Which wanted events to add and which existing ones (by event identifier) to remove.
    static func diff(wanted: [CalendarEventContent], existing: [(id: String, key: String?)])
        -> (add: [CalendarEventContent], remove: [String]) {
        let wantedKeys = Set(wanted.map(\.key))
        var seen: Set<String> = []
        // Events without a key were added by hand, even if into this calendar: they're never removed.
        let remove = existing.filter { event in
            guard let key = event.key else { return false }
            return !wantedKeys.contains(key) || !seen.insert(key).inserted
        }.map(\.id)
        let present = Set(existing.compactMap(\.key))
        return (wanted.filter { !present.contains($0.key) }, remove)
    }
}

/// Keeps a dedicated calendar in step with the plan.
///
/// Only events in the calendar this app created are ever touched. iOS needs full calendar access for that (an app
/// can't otherwise update or remove events it added), so it's off until the athlete turns it on in Settings.
final class CalendarService {
    private let store = EKEventStore()
    private let defaults: UserDefaults
    private static let calendarIDKey = "calendarSync.calendarID"

    enum SyncError: LocalizedError {
        case noAccess
        case noCalendarSource

        var errorDescription: String? {
            switch self {
            case .noAccess: String(localized: "Allow full calendar access for this app in Settings › Privacy & Security › Calendars, then try again.")
            case .noCalendarSource: String(localized: "Couldn't find a calendar account on this iPhone to add a calendar to.")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Makes the app's calendar contain exactly `events` from `from` onwards. Past events are left as a record.
    func sync(_ events: [CalendarEventContent], from: Date, through: Date) throws {
        guard hasAccess else { throw SyncError.noAccess }
        let calendar = try appCalendar()
        let existing = store.events(matching: store.predicateForEvents(withStart: from, end: through, calendars: [calendar]))
        let plan = CalendarEventContent.diff(
            wanted: events,
            existing: existing.map { (id: $0.eventIdentifier ?? "", key: CalendarEventContent.key(from: $0.url)) })
        for event in existing where plan.remove.contains(event.eventIdentifier ?? "") {
            try store.remove(event, span: .thisEvent, commit: false)
        }
        for content in plan.add {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = content.title
            event.notes = content.notes
            event.startDate = content.start
            event.endDate = content.end
            event.url = content.url
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    /// Deletes the app's calendar and everything in it.
    func removeCalendar() throws {
        defer { defaults.removeObject(forKey: Self.calendarIDKey) }
        guard hasAccess, let id = defaults.string(forKey: Self.calendarIDKey),
              let calendar = store.calendar(withIdentifier: id) else { return }
        try store.removeCalendar(calendar, commit: true)
    }

    /// The calendar this app created, made on first use in the same account as the default calendar.
    private func appCalendar() throws -> EKCalendar {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "TrackStar"
        if let id = defaults.string(forKey: Self.calendarIDKey), let existing = store.calendar(withIdentifier: id) {
            // Calendars made before the app was renamed carry the old name.
            if existing.title == "Steppa", existing.title != name {
                existing.title = name
                try? store.saveCalendar(existing, commit: true)
            }
            return existing
        }
        guard let source = store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw SyncError.noCalendarSource
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = name
        calendar.source = source
        calendar.cgColor = UIColor(hex: 0x5CCB6A).cgColor
        try store.saveCalendar(calendar, commit: true)
        defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
        return calendar
    }
}

/// iOS's own "New Event" sheet, filled in with one workout. The athlete reviews it and taps Add; the app needs no
/// calendar permission for this.
struct AddToCalendarSheet: UIViewControllerRepresentable {
    let content: CalendarEventContent
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = content.title
        event.notes = content.notes
        event.startDate = content.start
        event.endDate = content.end
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
