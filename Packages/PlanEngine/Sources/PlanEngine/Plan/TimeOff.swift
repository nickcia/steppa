import Foundation

/// Days the athlete can't train normally: a holiday, a busy stretch, an injury or illness.
///
/// The plan leaves these days empty (or keeps them to short easy runs), scales those weeks down, and after a week
/// or more off it restarts volume lower and builds back up by the usual rules, instead of carrying on as if
/// nothing happened. After an injury or illness the first days back are easy running only.
public struct TimeOff: Codable, Hashable, Sendable, Identifiable {
    public enum Reason: String, Codable, CaseIterable, Sendable {
        case vacation, busy, injury, illness, other
    }

    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// No running at all.
        case noRunning
        /// Short easy runs only: no long run, no sessions (e.g. a holiday with some time to run).
        case easyOnly
    }

    public var id: UUID
    public var reason: Reason
    public var mode: Mode
    public var start: LocalDate
    /// Last day off, inclusive. nil when it isn't known yet (an injury "until it's better"): every day from `start`
    /// is off until the athlete says they're back.
    public var end: LocalDate?

    public init(id: UUID = UUID(), reason: Reason, mode: Mode = .noRunning, start: LocalDate, end: LocalDate?) {
        self.id = id
        self.reason = reason
        self.mode = mode
        self.start = start
        self.end = end
    }

    public func contains(_ date: LocalDate) -> Bool {
        date >= start && (end.map { date <= $0 } ?? true)
    }

    /// Days off, or nil while open-ended.
    public var length: Int? { end.map { start.days(until: $0) + 1 } }

    /// After an injury or illness of three days or more, easy running only for a while: a week after an injury, a
    /// few days after an illness (the usual return-to-run caution). nil otherwise.
    public var easyReturn: ClosedRange<LocalDate>? {
        guard mode == .noRunning, let end, let length, length >= 3 else { return nil }
        switch reason {
        case .injury: return end.adding(days: 1)...end.adding(days: 7)
        case .illness: return end.adding(days: 1)...end.adding(days: 3)
        case .vacation, .busy, .other: return nil
        }
    }

    /// Easy runs on easy-only days are capped at this distance.
    public static let easyOnlyMaxMeters = 8_000.0
    /// A break at least this long restarts volume lower afterwards (see `PlanAdapter.resumeShare`).
    public static let breakDaysForReset = 7
}

extension PlanInputs {
    /// All time off, in date order.
    public var timeOffPeriods: [TimeOff] { (timeOff ?? []).sorted { $0.start < $1.start } }

    /// The time off covering a date, if any.
    public func timeOff(on date: LocalDate) -> TimeOff? {
        timeOffPeriods.first { $0.contains(date) }
    }

    /// No running at all on this date.
    public func isUnavailable(_ date: LocalDate) -> Bool {
        timeOffPeriods.contains { $0.mode == .noRunning && $0.contains(date) }
    }

    /// Easy running only on this date: easy-only time off, or the first days back after an injury or illness.
    public func isEasyOnly(_ date: LocalDate) -> Bool {
        timeOffPeriods.contains { ($0.mode == .easyOnly && $0.contains(date)) || ($0.easyReturn?.contains(date) ?? false) }
    }
}
