import Foundation
import Testing
import PlanEngine
@testable import Steppa

@MainActor
struct CoachTests {
    static let today = AppModelTests.start.adding(days: 9)

    func model() throws -> AppModel {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let source = FakeRunSource(runs: [])
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today }, runSource: source)
        model.acceptDisclaimer()
        model.start(plan)
        return model
    }

    @Test func snapshotDescribesThePlanAndToday() throws {
        let model = try model()
        let snapshot = CoachSnapshot.make(model)
        #expect(snapshot.overview.contains("Half marathon"))
        #expect(snapshot.overview.contains("easy"))
        #expect(snapshot.today.contains(Self.today.description))
        #expect(snapshot.weeks[0]?.contains("Week") == true)
        #expect(snapshot.weeks[-1] != nil)
        #expect(snapshot.recentRuns.contains("No recorded runs"))
    }

    @Test func snapshotIncludesRunAnalysis() async throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let first = try #require(plan.workouts.first)
        let run = HealthIntegrationTests.run(for: first, id: "hk1")
        let source = FakeRunSource(runs: [run])
        source.series["hk1"] = RunSeries(
            distance: stride(from: 0.0, through: run.durationSeconds, by: 10).map { .init($0, $0 / run.durationSeconds * run.distanceMeters) },
            heartRate: stride(from: 0.0, through: run.durationSeconds, by: 10).map { .init($0, 145) })
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today }, runSource: source)
        model.acceptDisclaimer()
        model.start(plan)
        await model.connectHealth()

        let snapshot = CoachSnapshot.make(model)
        #expect(snapshot.recentRuns.contains(first.date.description))
        let details = try #require(snapshot.runDetails[first.date.description])
        #expect(details.contains("Splits"))
        #expect(details.contains("average 145"))
        #expect(details.contains("Planned:"))
    }

    @Test func recapComparesWithEarlierRunsOfTheSameKind() async throws {
        let plan = try PlanBuilder.build(AppModelTests.inputs())
        let easies = plan.workouts.filter { $0.kind == .easy && $0.date <= Self.today }
        let first = try #require(easies.first), last = try #require(easies.last)
        try #require(first.date != last.date)
        let source = FakeRunSource(runs: [HealthIntegrationTests.run(for: first, id: "a"),
                                          HealthIntegrationTests.run(for: last, id: "b")])
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.today }, runSource: source)
        model.acceptDisclaimer()
        model.start(plan)
        await model.connectHealth()

        let run = try #require(model.healthRuns.first { $0.id == "b" })
        let context = CoachSnapshot.recapContext(run, model: model)
        #expect(context.contains("Planned: \(WorkoutKind.easy.name)"))
        #expect(context.contains("Earlier similar runs (newest first)"))
        #expect(context.contains(first.date.formatted(.dateTime.day().month(.abbreviated))))
        #expect(context.contains("This run was in week"))

        let earliest = try #require(model.healthRuns.first { $0.id == "a" })
        #expect(CoachSnapshot.recapContext(earliest, model: model).contains("nothing to compare yet"))
    }

    @Test func zonesAreNamedAndEmptyOnesLeftOut() {
        let line = CoachSnapshot.zoneLine([0, 600, 1800, 600, 0])
        #expect(line.contains("20% in zone 2 (easy)"))
        #expect(line.contains("60% in zone 3 (moderate)"))
        #expect(!line.contains("zone 1"))
        #expect(!line.contains("zone 5"))
    }

    @Test func suggestionsGoThroughTheAppsRules() throws {
        let model = try model()
        let plan = try #require(model.plan)
        let easy = try #require(plan.workouts.first { $0.date > Self.today && $0.kind == .easy })

        #expect(model.apply(CoachSuggestion(action: .skip, date: easy.date, newDate: nil, reason: "Tired")))
        #expect(model.status(of: easy) == .skipped)

        // No workout on that day: refused.
        let rest = try #require((1...14).map { Self.today.adding(days: $0) }.first { model.workout(on: $0) == nil })
        #expect(!model.apply(CoachSuggestion(action: .skip, date: rest, newDate: nil, reason: "")))
        #expect(model.lastError != nil)

        // The race can never be changed by the coach.
        model.lastError = nil
        #expect(!model.apply(CoachSuggestion(action: .skip, date: plan.inputs.raceDate, newDate: nil, reason: "")))
    }

    @Test func suggestionBoxCollectsOnce() {
        let box = CoachSuggestionBox()
        let s = CoachSuggestion(action: .skip, date: Self.today, newDate: nil, reason: "x")
        box.add(s)
        box.add(s)
        #expect(box.take() == [s])
        #expect(box.take().isEmpty)
    }
}

@MainActor
struct CoachFallbackTests {
    let snapshot = CoachSnapshot(overview: "", weeks: [:], recentRuns: "", runDetails: [:], today: "", upcoming: [
        .init(date: LocalDate(year: 2026, month: 11, day: 10), isLongRun: false),
        .init(date: LocalDate(year: 2026, month: 11, day: 15), isLongRun: true),
    ])

    @Test func skipInWordsBecomesAButton() {
        #expect(snapshot.fallbackSuggestion(for: "Skip today's run and rest.")?.date == LocalDate(year: 2026, month: 11, day: 10))
        #expect(snapshot.fallbackSuggestion(for: "I'd skip the long run this week.")?.date == LocalDate(year: 2026, month: 11, day: 15))
        #expect(snapshot.fallbackSuggestion(for: "Run easy and enjoy it.") == nil)
        let empty = CoachSnapshot(overview: "", weeks: [:], recentRuns: "", runDetails: [:], today: "")
        #expect(empty.fallbackSuggestion(for: "Skip it.") == nil)
    }
}
