import Testing
@testable import PlanEngine

/// Adapts many plans, at many points, under many behaviours and triggers, then adapts again on top.
/// Every revision must pass the validator, leave history untouched and keep workout IDs unique.
@Suite struct AdaptationSweepTests {
    static let schedules: [(days: Set<Weekday>, long: Weekday)] = [
        ([.tuesday, .thursday, .sunday], .sunday),
        ([.monday, .wednesday, .friday, .sunday], .sunday),
        ([.tuesday, .wednesday, .friday, .saturday, .sunday], .saturday),
        (Set(Weekday.allCases), .wednesday),
    ]

    static func behaviours(_ today: LocalDate) -> [Behaviour] {
        [
            Behaviour(),
            Behaviour(completion: { $0.date.daysSinceEpoch.isMultiple(of: 2) ? 0 : 1 }),
            Behaviour(completion: { $0.date >= today.adding(days: -12) ? 0 : 1 }),
            Behaviour(completion: { _ in 0.6 }),
            Behaviour(paceFactor: 0.9),
            Behaviour(paceFactor: 1.12),
        ]
    }

    static func triggers(_ plan: TrainingPlan, today: LocalDate, scheduleIndex: Int) -> [AdaptationTrigger] {
        let other = schedules[(scheduleIndex + 1) % schedules.count]
        var result: [AdaptationTrigger] = [
            .review,
            .raceDateChanged(plan.inputs.raceDate.adding(days: 15)),
            .availabilityChanged(runDays: other.days, longRunDay: other.long),
            .newRaceResult(.init(.fiveK, timeSeconds: 24 * 60, date: today)),
        ]
        let earlier = today.adding(days: 10)
        if earlier < plan.inputs.raceDate { result.append(.raceDateChanged(earlier)) }
        return result
    }

    @Test func everyRevisionIsSound() throws {
        var adapted = 0
        var failures: [String] = []
        let start = LocalDate(year: 2026, month: 11, day: 4) // a Wednesday

        for goal in RaceDistance.allCases {
            for experience in Experience.allCases {
                for (si, schedule) in Self.schedules.enumerated() {
                    for weeks in [6, 12, 20] {
                        let inputs = PlanInputs(goal: goal, raceDate: start.adding(days: weeks * 7 + si), startDate: start,
                                                currentWeeklyMeters: 30_000, fitness: .recentRace(.init(.tenK, timeSeconds: 50 * 60)),
                                                runDays: schedule.days, longRunDay: schedule.long, experience: experience)
                        let plan = try PlanBuilder.build(inputs)
                        for offset in [2, 10, 17, 33, 60] {
                            let today = start.adding(days: offset)
                            guard today < plan.inputs.raceDate else { continue }
                            for (bi, behaviour) in Self.behaviours(today).enumerated() {
                                let log = simulateLog(plan, until: today, behaviour)
                                for trigger in Self.triggers(plan, today: today, scheduleIndex: si) {
                                    let label = "\(goal) \(experience) s\(si) \(weeks)w day+\(offset) b\(bi) \(trigger)"
                                    let first = try PlanAdapter.adapt(plan, log: log, trigger: trigger, today: today)
                                    adapted += 1
                                    if let problem = problems(plan, first.plan, today: today), failures.count < 12 {
                                        failures.append("\(label): \(problem)")
                                    }
                                    // A second review nine days later, with different behaviour.
                                    let later = today.adding(days: 9)
                                    guard later < first.plan.inputs.raceDate else { continue }
                                    let next = Self.behaviours(later)[(bi + 1) % 6]
                                    let laterLog = simulateLog(first.plan, until: later, next, into: log)
                                    let second = try PlanAdapter.adapt(first.plan, log: laterLog, trigger: .review, today: later)
                                    adapted += 1
                                    if let problem = problems(first.plan, second.plan, today: later), failures.count < 12 {
                                        failures.append("\(label) → review +9: \(problem)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(adapted > 5_000)
    }

    private func problems(_ old: TrainingPlan, _ new: TrainingPlan, today: LocalDate) -> String? {
        let violations = PlanValidator.validate(new)
        if !violations.isEmpty { return "\(violations.prefix(3))" }
        if old.workouts.filter({ $0.date < today }) != new.workouts.filter({ $0.date < today }) { return "history changed" }
        let ids = new.workouts.map(\.id)
        if Set(ids).count != ids.count { return "duplicate IDs" }
        return nil
    }
}
