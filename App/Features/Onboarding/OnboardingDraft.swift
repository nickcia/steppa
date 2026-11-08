import Foundation
import Observation
import PlanEngine

/// Answers collected during onboarding.
@Observable
final class OnboardingDraft {
    enum Step: Int, CaseIterable {
        case welcome, goal, date, experience, fitness, volume, availability, health, review
    }

    enum ResultAge: String, CaseIterable, Identifiable {
        case lastMonth, oneToThreeMonths, threeToSixMonths, sixToTwelveMonths
        var id: String { rawValue }

        var name: String {
            switch self {
            case .lastMonth: String(localized: "In the last month")
            case .oneToThreeMonths: String(localized: "1–3 months ago")
            case .threeToSixMonths: String(localized: "3–6 months ago")
            case .sixToTwelveMonths: String(localized: "6–12 months ago")
            }
        }

        var daysAgo: Int {
            switch self {
            case .lastMonth: 14
            case .oneToThreeMonths: 60
            case .threeToSixMonths: 135
            case .sixToTwelveMonths: 270
            }
        }
    }

    var step: Step = .welcome
    var acceptedDisclaimer = false

    var goal: RaceDistance = .halfMarathon
    var raceDate: Date = Calendar.current.date(byAdding: .day, value: 12 * 7, to: .now) ?? .now
    var hasGoalTime = false
    var goalTimeSeconds: Double = 2 * 3600

    var experience: Experience = .intermediate
    /// Can't run 30 minutes non-stop yet: the plan starts with run/walk (see `RunWalk`), and the fitness and
    /// weekly-distance questions are skipped.
    var startsWithRunWalk = false

    var hasRecentRace = true
    var recentDistance: RaceDistance = .fiveK
    var recentTimeSeconds: Double = 27 * 60
    var recentAge: ResultAge = .lastMonth

    var units: UnitSystem = .localeDefault
    /// In the selected display unit.
    var weeklyDistance: Double = 20

    /// How many days a week they can run; `runDays` then picks which.
    var daysPerWeek = 4 {
        didSet { if daysPerWeek != oldValue { runDays = Self.defaultDays(daysPerWeek, longRunDay: longRunDay) } }
    }
    var runDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday]
    var longRunDay: Weekday = .sunday
    var strengthEnabled = true
    var strengthPerWeek = 2

    /// Run days this goal usually needs; fewer gets a clear warning.
    var recommendedRunDays: Int {
        let days = PlanRules.recommendedRunDays(goal, goalTimeSeconds: hasGoalTime ? goalTimeSeconds : nil)
        return startsWithRunWalk ? max(days, RunWalk.sessionsPerWeek) : days
    }

    /// Steps in order, without the ones that don't apply.
    private var steps: [Step] {
        Step.allCases.filter { !(startsWithRunWalk && ($0 == .fitness || $0 == .volume)) }
    }

    var nextStep: Step {
        steps.first { $0.rawValue > step.rawValue } ?? .review
    }

    var previousStep: Step {
        steps.last { $0.rawValue < step.rawValue } ?? .welcome
    }

    /// A sensible spread for a number of days, with rest between runs where possible and the long run kept.
    static func defaultDays(_ count: Int, longRunDay: Weekday) -> Set<Weekday> {
        let spreads: [Int: [Weekday]] = [
            1: [.sunday],
            2: [.wednesday, .sunday],
            3: [.tuesday, .thursday, .sunday],
            4: [.tuesday, .thursday, .saturday, .sunday],
            5: [.monday, .tuesday, .thursday, .saturday, .sunday],
            6: [.monday, .tuesday, .wednesday, .thursday, .saturday, .sunday],
            7: Weekday.allCases,
        ]
        var days = Set(spreads[min(max(count, 1), 7)] ?? [])
        // Keep the chosen long-run day: swap it in for Sunday.
        if !days.contains(longRunDay), days.contains(.sunday) {
            days.remove(.sunday)
            days.insert(longRunDay)
        }
        return days
    }

    var today: LocalDate { .today }
    var race: LocalDate { LocalDate(raceDate) }
    var weeksToRace: Int { max(0, today.days(until: race) / 7) }

    var canContinue: Bool {
        switch step {
        case .welcome: acceptedDisclaimer
        case .date: race > today.adding(days: 6)
        case .availability: runDays.count == daysPerWeek && runDays.count >= 2 && runDays.contains(longRunDay)
        case .fitness: !hasRecentRace || recentTimeSeconds > 0
        default: true
        }
    }

    var inputs: PlanInputs {
        PlanInputs(
            goal: goal,
            raceDate: race,
            startDate: today,
            currentWeeklyMeters: startsWithRunWalk ? 0 : weeklyDistance * units.metersPerUnit,
            fitness: hasRecentRace && !startsWithRunWalk
                ? .recentRace(RacePerformance(recentDistance, timeSeconds: recentTimeSeconds,
                                              date: today.adding(days: -recentAge.daysAgo)))
                : .estimated,
            runDays: runDays,
            longRunDay: longRunDay,
            experience: experience,
            goalTimeSeconds: hasGoalTime ? goalTimeSeconds : nil,
            runWalkStart: startsWithRunWalk ? today : nil
        )
    }

    /// Typical times to pre-fill the race-time picker when the distance changes.
    static func typicalTime(_ distance: RaceDistance) -> Double {
        switch distance {
        case .fiveK: 27 * 60
        case .tenK: 57 * 60
        case .halfMarathon: 2 * 3600 + 5 * 60
        case .marathon: 4 * 3600 + 20 * 60
        }
    }
}
