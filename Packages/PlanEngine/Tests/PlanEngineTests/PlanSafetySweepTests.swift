import Testing
@testable import PlanEngine

/// Generates plans across a broad grid of realistic inputs and checks every one against the
/// safety validator. This is the main guard against a rule change producing an unsafe plan.
@Suite struct PlanSafetySweepTests {
    static let schedules: [(days: Set<Weekday>, long: Weekday)] = [
        ([.saturday, .sunday], .sunday),
        ([.tuesday, .thursday, .sunday], .sunday),
        ([.monday, .wednesday, .saturday], .saturday),
        ([.monday, .wednesday, .friday, .sunday], .sunday),
        ([.tuesday, .wednesday, .friday, .saturday, .sunday], .saturday),
        ([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday], .saturday),
        (Set(Weekday.allCases), .sunday),
        (Set(Weekday.allCases), .wednesday),
    ]
    static let weekCounts = [1, 2, 4, 7, 11, 16, 24]
    static let startOffsets = [0, 3, 6] // start on Mon / Thu / Sun
    static let volumesKm: [Double] = [0, 12, 30, 55, 90]
    static let fitnesses: [FitnessSource] = [
        .estimated,
        .recentRace(.init(.fiveK, timeSeconds: 33 * 60)),
        .recentRace(.init(.halfMarathon, timeSeconds: 85 * 60)),
    ]

    @Test func everyGeneratedPlanPassesValidation() throws {
        var checked = 0
        var failures: [String] = []
        let monday = LocalDate(year: 2026, month: 11, day: 2)

        for goal in RaceDistance.allCases {
            for experience in Experience.allCases {
                for (si, schedule) in Self.schedules.enumerated() {
                    for weeks in Self.weekCounts {
                        for offset in Self.startOffsets {
                            for (vi, km) in Self.volumesKm.enumerated() {
                                for fitness in Self.fitnesses {
                                    let start = monday.adding(days: offset)
                                    // Vary the race weekday too.
                                    let race = start.adding(days: weeks * 7 + (si + vi + offset) % 7 - 3)
                                    guard race > start else { continue }
                                    let inputs = PlanInputs(goal: goal, raceDate: race, startDate: start,
                                                            currentWeeklyMeters: km * 1000, fitness: fitness,
                                                            runDays: schedule.days, longRunDay: schedule.long,
                                                            experience: experience)
                                    let plan = try PlanBuilder.build(inputs)
                                    checked += 1
                                    let violations = PlanValidator.validate(plan)
                                    if !violations.isEmpty, failures.count < 15 {
                                        failures.append("\(goal) \(experience) days=\(schedule.days.map(\.rawValue).sorted()) long=\(schedule.long) start=\(start) race=\(race) km=\(km): \(violations.prefix(3))")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
        #expect(checked > 10_000)
    }

    /// New runners (run/walk first) on every schedule, plan length, start day and goal, with and without time off.
    @Test func everyRunWalkPlanPassesValidation() throws {
        var failures: [String] = []
        let monday = LocalDate(year: 2026, month: 11, day: 2)
        for goal in RaceDistance.allCases {
            for (si, schedule) in Self.schedules.enumerated() {
                for weeks in Self.weekCounts + [9, 10, 13] {
                    for offset in Self.startOffsets {
                        for withBreak in [false, true] {
                            let start = monday.adding(days: offset)
                            let race = start.adding(days: weeks * 7 + (si + offset) % 7 - 3)
                            guard race > start else { continue }
                            let off = start.adding(days: 17)
                            let inputs = PlanInputs(goal: goal, raceDate: race, startDate: start, currentWeeklyMeters: 0,
                                                    fitness: .estimated, runDays: schedule.days, longRunDay: schedule.long,
                                                    experience: .beginner,
                                                    timeOff: withBreak ? [TimeOff(reason: .injury, start: off, end: off.adding(days: 9))] : nil,
                                                    runWalkStart: start)
                            let plan = try PlanBuilder.build(inputs)
                            let violations = PlanValidator.validate(plan)
                            if !violations.isEmpty, failures.count < 15 {
                                failures.append("\(goal) days=\(schedule.days.map(\.rawValue).sorted()) start=\(start) race=\(race) break=\(withBreak): \(violations.prefix(3))")
                            }
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }
}
