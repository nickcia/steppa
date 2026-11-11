import Foundation
import Testing
import PlanEngine
@testable import TrackStar

@MainActor
struct HeartRateTargetsTests {
    let easy = PaceTarget(zone: .easy, range: PaceRange(fast: 345, slow: 375))
    let zones = HeartRateZones.fromMax(190)

    @Test func targetsReadAsPaceHeartRateOrTreadmillSpeed() {
        let format = DisplayFormat(units: .metric)
        #expect(WorkoutDescriber(format: format).detail(easy) == format.paceRange(easy.range))
        #expect(WorkoutDescriber(format: format, display: .heartRate, zones: zones).detail(easy) == "Zone 2 · 114–132 bpm")
        // 375 s/km is 9.6 km/h, 345 s/km is 10.4 km/h.
        #expect(WorkoutDescriber(format: format, display: .treadmill, treadmillUnits: .metric).detail(easy) == "9.6–10.4 km/h")
        #expect(WorkoutDescriber(format: format, display: .treadmill, treadmillUnits: .imperial).detail(easy) == "6.0–6.5 mph")
        // Without zones, heart rate falls back to pace. Strides are too short for heart rate: by feel, with a pace to aim for.
        #expect(WorkoutDescriber(format: format, display: .heartRate).detail(easy) == format.paceRange(easy.range))
        let stride = PaceTarget(zone: .stride, range: PaceRange(fast: 200, slow: 220))
        let byFeel = WorkoutDescriber(format: format, display: .heartRate, zones: zones).detail(stride)
        #expect(byFeel.contains("go by feel") && byFeel.contains(format.paceRange(stride.range)))
        // Strides have a pace and a treadmill speed too (200–220 s/km is 16.4–18.0 km/h).
        #expect(WorkoutDescriber(format: format).detail(stride).hasPrefix(format.paceRange(stride.range)))
        #expect(WorkoutDescriber(format: format, display: .treadmill, treadmillUnits: .metric).detail(stride).hasPrefix("16.4–18.0 km/h"))
    }

    @Test func headlineFollowsTheDisplay() {
        let format = DisplayFormat(units: .metric)
        #expect(WorkoutDescriber(format: format, display: .heartRate, zones: zones).headline(easy) == ("114–132", "zone 2 bpm"))
        #expect(WorkoutDescriber(format: format, display: .treadmill).headline(easy).value == "10.0")
        #expect(WorkoutDescriber(format: format).headline(easy).label == "easy /km")
    }

    @Test func choicesAreRemembered() {
        let model = AppModel(container: Persistence.makeContainer(inMemory: true), clock: { AppModelTests.start })
        model.setTargetDisplay(.treadmill)
        model.setTreadmillUnits(.imperial)
        #expect(model.targetDisplay == .treadmill)
        #expect(model.treadmillUnits == .imperial)
        #expect(model.targetDescriber.display == .treadmill)
    }

    func intervalsModel(_ fake: FakeIntervals) -> AppModel {
        let keychain = IntervalsKeychain(service: "trackstar-tests-\(UUID().uuidString)")
        return AppModel(container: Persistence.makeContainer(inMemory: true), clock: { AppModelTests.start },
                        intervals: IntervalsClient(transport: fake), intervalsKeychain: keychain)
    }

    @Test func watchZonesAreImportedButYourOwnAreKept() async throws {
        let fake = FakeIntervals()
        fake.set("sportSettings", [["types": ["Run", "VirtualRun"], "hr_zones": [120, 140, 158, 172, 188], "max_hr": 188]])
        let model = intervalsModel(fake)
        try await model.connectIntervals(apiKey: FakeIntervals.apiKey)
        await model.refreshIntervalsLinks()
        #expect(model.storedHeartRateZones?.source == .imported)
        #expect(model.heartRateZones?.upperLimits == [120, 140, 158, 172])

        // The athlete edits a limit: later imports leave it alone.
        var custom = try #require(model.heartRateZones)
        custom.upperLimits[1] = 145
        custom.source = .custom
        model.setHeartRateZones(custom)
        await model.refreshIntervalsLinks()
        #expect(model.heartRateZones?.upperLimits[1] == 145)

        // Importing on purpose replaces them.
        #expect(await model.importHeartRateZones())
        #expect(model.heartRateZones?.upperLimits[1] == 140)

        // No zones on Intervals.icu: nothing to import.
        fake.set("sportSettings", nil)
        #expect(await model.importHeartRateZones() == false)
    }
}
