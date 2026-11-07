import Testing
@testable import PlanEngine

@Suite struct StrengthScheduleTests {
    @Test func placedAroundKeyRuns() throws {
        for goal in RaceDistance.allCases {
            for perWeek in [1, 2] {
                let plan = try PlanBuilder.build(sampleInputs(goal: goal, weeks: PlanRules.recommendedWeeks(goal)))
                let sessions = StrengthSchedule.sessions(for: plan, perWeek: perWeek)
                let hard = Set(plan.workouts.filter(\.kind.isHard).map(\.date))
                #expect(!sessions.isEmpty)
                for session in sessions {
                    #expect(!hard.contains(session.date), "\(goal): strength on a hard day")
                    #expect(!hard.contains(session.date.adding(days: 1)), "\(goal): strength the day before a hard day")
                    #expect(session.date >= plan.inputs.startDate)
                    #expect(session.date.days(until: plan.inputs.raceDate) > StrengthSchedule.quietDaysBeforeRace)
                }
                for (a, b) in zip(sessions, sessions.dropFirst()) {
                    #expect(a.date.days(until: b.date) >= 2, "\(goal): sessions too close")
                }
                for week in plan.weeks {
                    let inWeek = sessions.filter { $0.date >= week.startDate && $0.date < week.startDate.adding(days: 7) }
                    let limit = week.phase == .taper || week.isStepBack ? 1 : perWeek
                    #expect(inWeek.count <= limit)
                }
            }
        }
    }

    @Test func levelFollowsThePhase() throws {
        let plan = try PlanBuilder.build(sampleInputs(goal: .marathon, weeks: 16))
        let sessions = StrengthSchedule.sessions(for: plan, perWeek: 2)
        for session in sessions {
            let phase = try #require(plan.weeks.first { session.date >= $0.startDate && session.date < $0.startDate.adding(days: 7) }).phase
            switch phase {
            case .base: #expect(session.level == .foundation)
            case .build, .peak: #expect(session.level == .maintenance)
            case .taper: #expect(session.level == .light)
            }
        }
        #expect(sessions.contains { $0.level == .foundation } && sessions.contains { $0.level == .maintenance })
    }
}
