import Foundation
import Observation
import PlanEngine

/// Answers collected during onboarding.
@Observable
final class OnboardingDraft {
    enum Step: Int, CaseIterable {
        case welcome, goal, date, experience, fitness, volume, availability, review
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

    var hasRecentRace = true
    var recentDistance: RaceDistance = .fiveK
    var recentTimeSeconds: Double = 27 * 60
    var recentAge: ResultAge = .lastMonth

    var units: UnitSystem = .localeDefault
    /// In the selected display unit.
    var weeklyDistance: Double = 20

    var runDays: Set<Weekday> = [.tuesday, .thursday, .saturday, .sunday]
    var longRunDay: Weekday = .sunday

    var today: LocalDate { .today }
    var race: LocalDate { LocalDate(raceDate) }
    var weeksToRace: Int { max(0, today.days(until: race) / 7) }

    var canContinue: Bool {
        switch step {
        case .welcome: acceptedDisclaimer
        case .date: race > today.adding(days: 6)
        case .availability: runDays.count >= 2 && runDays.contains(longRunDay)
        case .fitness: !hasRecentRace || recentTimeSeconds > 0
        default: true
        }
    }

    var inputs: PlanInputs {
        PlanInputs(
            goal: goal,
            raceDate: race,
            startDate: today,
            currentWeeklyMeters: weeklyDistance * units.metersPerUnit,
            fitness: hasRecentRace
                ? .recentRace(RacePerformance(recentDistance, timeSeconds: recentTimeSeconds,
                                              date: today.adding(days: -recentAge.daysAgo)))
                : .estimated,
            runDays: runDays,
            longRunDay: longRunDay,
            experience: experience,
            goalTimeSeconds: hasGoalTime ? goalTimeSeconds : nil
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
