import Foundation
import Testing
import PlanEngine
@testable import TrackStar

/// Shoes: counting distance, which shoes a run goes to, and when to suggest new ones.
@MainActor
struct GearTests {
    static let start = AppModelTests.start

    static func run(_ id: String, day: Int, km: Double) -> CompletedRun {
        CompletedRun(id: id, date: start.adding(days: day), distanceMeters: km * 1000, durationSeconds: km * 330)
    }

    /// A model with a plan and Health runs on days 1, 3 and 5 (8, 10 and 12 km).
    func model(runs: [CompletedRun] = [run("a", day: 1, km: 8), run("b", day: 3, km: 10), run("c", day: 5, km: 12)])
        async throws -> (AppModel, FakeRunSource) {
        let source = FakeRunSource(runs: runs)
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { Self.start.adding(days: 6) },
                             runSource: source)
        model.acceptDisclaimer()
        model.start(try PlanBuilder.build(AppModelTests.inputs()))
        await model.connectHealth()
        return (model, source)
    }

    // MARK: Rules

    @Test func wearThresholds() {
        #expect(ShoeWear(distance: 500_000, retireAt: 700_000) == .fine)
        #expect(ShoeWear(distance: 595_000, retireAt: 700_000) == .nearing)
        #expect(ShoeWear(distance: 700_000, retireAt: 700_000) == .due)
        #expect(ShoeWear(distance: 900_000, retireAt: 700_000) == .due)
        #expect(ShoeWear(distance: 10, retireAt: 0) == .fine)
    }

    @Test func racingShoesWearSoonerThanTrainers() {
        #expect(ShoeType.race.suggestedRetirementMeters < ShoeType.lightweight.suggestedRetirementMeters)
        #expect(ShoeType.lightweight.suggestedRetirementMeters < ShoeType.daily.suggestedRetirementMeters)
        // Trainers sit inside the usual 500–800 km guidance.
        for type in [ShoeType.daily, .lightweight, .trail] {
            #expect((500_000...800_000).contains(type.suggestedRetirementMeters))
        }
    }

    @Test func distanceCountsEachRunOnceAndAddsStartingDistance() {
        let id = UUID(), other = UUID()
        let day = Self.start
        let entries = [
            ShoeMileage.Entry(runID: "a", gearID: id, date: day, distanceMeters: 8_000, updatedAt: .distantPast),
            // Counted again by a second device, later: the latest wins, not both.
            ShoeMileage.Entry(runID: "a", gearID: id, date: day, distanceMeters: 8_000, updatedAt: .now),
            ShoeMileage.Entry(runID: "b", gearID: other, date: day, distanceMeters: 10_000),
            ShoeMileage.Entry(runID: "c", gearID: nil, date: day, distanceMeters: 5_000),
        ]
        #expect(ShoeMileage.distance(of: id, startingMeters: 120_000, entries: entries) == 128_000)
        #expect(ShoeMileage.distance(of: other, startingMeters: 0, entries: entries) == 10_000)
    }

    @Test func onlyUncountedRunsFromTheStartDayAreCounted() {
        let runs = [Self.run("a", day: 1, km: 8), Self.run("b", day: 3, km: 10), Self.run("c", day: 5, km: 12)]
        let counted = [ShoeMileage.Entry(runID: "b", gearID: UUID(), date: runs[1].date, distanceMeters: 10_000)]
        let toCount = ShoeMileage.runsToCount(runs, entries: counted, defaultSince: Self.start.adding(days: 2))
        #expect(toCount.map(\.id) == ["c"])
        #expect(ShoeMileage.runsToCount(runs, entries: [], defaultSince: nil).isEmpty)
    }

    @Test func aRunUnderANewIDIsStillRecognised() {
        // A Garmin run that later arrives from Apple Health with another ID and a slightly different distance.
        let entry = ShoeMileage.Entry(runID: "garmin-1", gearID: UUID(), date: Self.start, distanceMeters: 10_000)
        let fromHealth = CompletedRun(id: "hk-1", date: Self.start, distanceMeters: 10_200, durationSeconds: 3_000)
        #expect(ShoeMileage.entry(for: fromHealth, in: [entry]) == entry)
        #expect(ShoeMileage.runsToCount([fromHealth], entries: [entry], defaultSince: Self.start).isEmpty)
    }

    // MARK: In the app

    @Test func runsGoToTheDefaultShoesFromTheirStartDay() async throws {
        let (model, _) = try await model()
        let shoes = GearRecord(kind: .shoes, name: "Pegasus 41", brand: "Nike", startingMeters: 50_000,
                               since: Self.start.adding(days: 2))
        model.addGear(shoes, makeDefault: true)
        #expect(model.defaultShoes?.gearID == shoes.gearID)
        // Runs on days 3 and 5, not the one before the shoes were added.
        #expect(model.distance(in: shoes) == 50_000 + 22_000)
        #expect(model.runCount(in: shoes) == 2)
        #expect(model.gearSummary.contains("Nike Pegasus 41") || model.gearSummary.contains("Pegasus 41"))
    }

    @Test func newRunsArriveInTheDefaultShoesAndSwitchingKeepsHistory() async throws {
        let (model, source) = try await model()
        let first = GearRecord(kind: .shoes, name: "Old pair", since: Self.start)
        model.addGear(first, makeDefault: true)
        #expect(model.distance(in: first) == 30_000)

        let second = GearRecord(kind: .shoes, name: "New pair", since: Self.start.adding(days: 6))
        model.addGear(second, makeDefault: true)
        #expect(model.defaultShoes?.gearID == second.gearID)
        #expect(!first.isDefault)

        source.runs.append(Self.run("d", day: 6, km: 6))
        await model.refreshHealth()
        #expect(model.distance(in: first) == 30_000)
        #expect(model.distance(in: second) == 6_000)
    }

    @Test func changingARunsShoesMovesItsDistance() async throws {
        let (model, _) = try await model()
        let daily = GearRecord(kind: .shoes, name: "Daily", since: Self.start)
        let racers = GearRecord(kind: .shoes, name: "Racers", shoeType: .race, since: Self.start)
        model.addGear(daily, makeDefault: true)
        model.addGear(racers)
        let run = try #require(model.healthRuns.first { $0.id == "c" })

        model.setShoes(racers, for: run)
        #expect(model.shoes(for: run)?.gearID == racers.gearID)
        #expect(model.distance(in: daily) == 18_000)
        #expect(model.distance(in: racers) == 12_000)

        // Taken off every pair: it isn't counted again in the default ones on the next refresh.
        model.setShoes(nil, for: run)
        await model.refreshHealth()
        #expect(model.shoes(for: run) == nil)
        #expect(model.distance(in: daily) == 18_000)
        #expect(model.distance(in: racers) == 0)
    }

    @Test func suggestsReplacingWornShoesButNotRetiredOnes() async throws {
        let (model, _) = try await model()
        let worn = GearRecord(kind: .shoes, name: "Worn", shoeType: .race, startingMeters: 290_000, since: Self.start)
        let fresh = GearRecord(kind: .shoes, name: "Fresh", since: Self.start)
        model.addGear(worn, makeDefault: true)
        model.addGear(fresh)
        // 290 km + 30 km of runs, against 300 km for a racing shoe.
        #expect(model.wear(of: worn) == .due)
        #expect(model.wear(of: fresh) == .fine)
        #expect(model.shoesToReplace.map(\.gearID) == [worn.gearID])

        // A distance the athlete typed wins over the type's suggestion.
        worn.retirementMeters = 370_000
        model.saveGear(worn)
        #expect(model.wear(of: worn) == .nearing)

        model.setRetired(true, worn)
        #expect(model.shoesToReplace.isEmpty)
        #expect(model.defaultShoes == nil)
        #expect(model.distance(in: worn) == 320_000)
    }

    @Test func deletingShoesDoesNotMoveTheirRunsToOtherShoes() async throws {
        let (model, _) = try await model()
        let gone = GearRecord(kind: .shoes, name: "Gone", since: Self.start)
        model.addGear(gone, makeDefault: true)
        let next = GearRecord(kind: .shoes, name: "Next", since: Self.start)
        model.deleteGear(gone)
        model.addGear(next, makeDefault: true)
        #expect(model.distance(in: next) == 0)
    }

    @Test func watchesAreGearButNotShoes() async throws {
        let (model, _) = try await model()
        model.addGear(GearRecord(kind: .watch, name: "Forerunner 265", brand: "Garmin", since: Self.start), makeDefault: true)
        #expect(model.gear.count == 1)
        #expect(model.shoes.isEmpty)
        #expect(model.defaultShoes == nil)
        #expect(model.gear.first?.displayName == "Garmin Forerunner 265")
    }
}
