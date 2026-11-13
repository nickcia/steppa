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

    /// Clears what heart-rate suggestions remember between launches, so tests don't leak into each other.
    func resetHeartRateMemory() {
        UserDefaults.standard.removeObject(forKey: "heartRate.dismissed")
        UserDefaults.standard.removeObject(forKey: "heartRate.watchMaxWhenOverridden")
    }

    /// A run on `day` whose heart rate peaked at `peak` (twice, so it isn't treated as a spike).
    func run(_ id: String, day: LocalDate, peak: Double) -> (CompletedRun, RunSeries) {
        (CompletedRun(id: id, date: day, distanceMeters: 8_000, durationSeconds: 2_700),
         RunSeries(heartRate: [.init(0, 120), .init(600, peak), .init(1200, peak), .init(1800, 150)]))
    }

    @Test func watchZonesComeFirstAndYourMaxScalesThem() async throws {
        resetHeartRateMemory()
        let fake = FakeIntervals()
        fake.set("sportSettings", [["types": ["Run", "VirtualRun"], "hr_zones": [120, 140, 158, 172, 188], "max_hr": 188]])
        let model = intervalsModel(fake)
        try await model.connectIntervals(apiKey: FakeIntervals.apiKey)
        await model.refreshIntervalsLinks()
        #expect(model.heartRateSource == .watch(provider: "Intervals.icu"))
        #expect(model.heartRateZones?.upperLimits == [120, 140, 158, 172])
        #expect(model.ownMaxReplacesWatch)

        // Their own maximum: the watch's zones keep their shape and scale to it.
        model.setMaxHeartRate(198)
        #expect(model.heartRateSource == .yourMax)
        #expect(model.heartRateZones?.maxHeartRate == 198)
        #expect(model.heartRateZones?.upperLimits == [126, 147, 166, 181])
        #expect(model.heartRateSuggestion == nil)

        // The watch's maximum changes later: their own still wins, and they're offered the watch's.
        fake.set("sportSettings", [["types": ["Run"], "hr_zones": [121, 141, 159, 173, 190], "max_hr": 190]])
        await model.refreshIntervalsLinks()
        #expect(model.heartRateZones?.maxHeartRate == 198)
        let suggestion = try #require(model.heartRateSuggestion)
        #expect(suggestion.reason == .watchChanged(provider: "Intervals.icu"))
        #expect(suggestion.newMax == 190)
        model.acceptHeartRateSuggestion(suggestion)
        #expect(model.heartRateSource == .watch(provider: "Intervals.icu"))
        #expect(model.heartRateZones?.upperLimits == [121, 141, 159, 173])

        // Re-syncing goes back to the watch's zones; no zones there leaves the last ones.
        model.setMaxHeartRate(200)
        await model.useWatchHeartRate()
        #expect(!model.maxHeartRateIsSet)
        #expect(model.heartRateZones?.maxHeartRate == 190)
    }

    @Test func aHigherRunIsSuggestedOnceUntilAnswered() throws {
        resetHeartRateMemory()
        let model = try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 30))
        model.setMaxHeartRate(185)
        let (high, series) = run("r1", day: model.today.adding(days: -3), peak: 194)
        model.loadDemoRuns([high], series: ["r1": series])
        let suggestion = try #require(model.heartRateSuggestion)
        #expect(suggestion.newMax == 194)
        #expect(suggestion.current == 185)

        // Not now: it stays away, even after the app reopens.
        model.dismissHeartRateSuggestion(suggestion)
        #expect(model.heartRateSuggestion == nil)

        // Accepting a new one sets the maximum and the zones follow.
        let (higher, more) = run("r2", day: model.today.adding(days: -1), peak: 199)
        model.loadDemoRuns([high, higher], series: ["r1": series, "r2": more])
        let next = try #require(model.heartRateSuggestion)
        model.acceptHeartRateSuggestion(next)
        #expect(model.estimatedMaxHeartRate == 199)
        #expect(model.heartRateZones?.upperLimits.last == (0.9 * 199).rounded())
        #expect(model.heartRateSuggestion == nil)
    }

    @Test func automaticMaximumsFollowRunsWithoutAsking() throws {
        resetHeartRateMemory()
        let model = try AppModelTests.startedModel(today: AppModelTests.start.adding(days: 30))
        let (high, series) = run("r1", day: model.today.adding(days: -3), peak: 191)
        model.loadDemoRuns([high], series: ["r1": series])
        #expect(model.heartRateSource == .runs(high))
        #expect(model.estimatedMaxHeartRate == 191)
        #expect(model.heartRateSuggestion == nil)
    }

    @Test func zonesTypedInByHandBecomeYourMaximum() throws {
        resetHeartRateMemory()
        let container = Persistence.makeContainer(inMemory: true)
        let model = AppModel(container: container, clock: { AppModelTests.start })
        // How earlier builds stored zones the athlete typed in.
        model.setHeartRateZones(HeartRateZones(upperLimits: [118, 139, 155, 170], maxHeartRate: 186, source: .custom))
        let reopened = AppModel(container: container, clock: { AppModelTests.start })
        #expect(reopened.storedHeartRateZones == nil)
        #expect(reopened.heartRateSource == .yourMax)
        #expect(reopened.estimatedMaxHeartRate == 186)
    }
}
