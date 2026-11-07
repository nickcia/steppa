/// Optional bodyweight strength sessions placed around the running plan.
///
/// Strength work lowers injury risk and improves running economy (Lauersen et al. 2014; Blagrove et al.
/// 2018). The sessions here are short and bodyweight-only, and placed so they never take the edge off a key
/// run: not the day before a quality session or the long run, not on those days, at least two days apart,
/// and tapering off before the race. They aren't part of the running plan's volume.
public enum StrengthSchedule {
    public enum Level: String, Codable, Hashable, Sendable {
        /// Base phase: building strength, 2–3 sets.
        case foundation
        /// Build and peak: keeping it, fewer sets.
        case maintenance
        /// Taper: one light round to stay loose.
        case light
    }

    public struct Session: Codable, Hashable, Sendable, Identifiable {
        public var date: LocalDate
        public var level: Level
        public var id: String { "strength-\(date)" }
    }

    /// No strength in the last days before the race.
    public static let quietDaysBeforeRace = 5

    /// Strength sessions for the whole plan. `perWeek` is the athlete's choice (1 or 2); step-back weeks and the
    /// taper get one, race week none.
    public static func sessions(for plan: TrainingPlan, perWeek: Int) -> [Session] {
        let perWeek = min(max(perWeek, 1), 2)
        let race = plan.inputs.raceDate
        let lastDay = race.adding(days: -(quietDaysBeforeRace + 1))
        let hardDates = Set(plan.workouts.filter(\.kind.isHard).map(\.date))
        var result: [Session] = []

        for week in plan.weeks {
            let level: Level = switch week.phase {
            case .base: .foundation
            case .build, .peak: .maintenance
            case .taper: .light
            }
            let count = week.phase == .taper || week.isStepBack ? 1 : perWeek
            let days = (0..<7).map { week.startDate.adding(days: $0) }
                .filter { $0 >= plan.inputs.startDate && $0 <= lastDay }
                // Not on a hard day, and not the day before one: key runs come first.
                .filter { !hardDates.contains($0) && !hardDates.contains($0.adding(days: 1)) }
            var chosen: [LocalDate] = []
            // Spread out: earliest suitable day first, then the next one at least two days later.
            for day in days where chosen.count < count {
                if let last = chosen.last ?? result.last.map(\.date), last.days(until: day) < 2 { continue }
                chosen.append(day)
            }
            result += chosen.map { Session(date: $0, level: level) }
        }
        return result
    }
}
