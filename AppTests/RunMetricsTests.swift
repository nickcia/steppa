import Foundation
import Testing
import PlanEngine
@testable import TrackStar

/// The run page's metric groups: only what was recorded, in the athlete's units.
@MainActor
struct RunMetricsTests {
    func analysis(extras: RunExtras? = nil, form: Bool = true) -> RunAnalysis {
        let times = stride(from: 0.0, through: 1500, by: 5).map { $0 }
        var series = RunSeries(distance: times.map { .init($0, $0 / 300 * 1000) },
                               heartRate: times.map { .init($0, 150) },
                               cadence: times.map { .init($0, 172) },
                               altitude: times.map { .init($0, 40 + 10 * sin($0 / 300)) })
        if form {
            series.strideLength = times.map { .init($0, 1.1) }
            series.verticalOscillation = times.map { .init($0, 8.8) }
            series.groundContactTime = times.map { .init($0, 240) }
        }
        series.extras = extras
        return RunAnalyzer.analyze(series, distanceMeters: 5_000, durationSeconds: 1_500, maxHeartRate: 190)
    }

    func group(_ title: String, _ a: RunAnalysis, _ units: UnitSystem = .metric) -> RunMetricsCard.Group? {
        RunMetricsCard.groups(a, units: units).first { $0.title == title }
    }

    @Test func onlyRecordedMetricsAppear() {
        let bare = analysis(form: false)
        #expect(group("Running form", bare)?.rows.map(\.label) == ["Cadence"])
        #expect(group("Power", bare)?.rows.isEmpty == true)
        #expect(group("Conditions and effort", bare)?.rows.isEmpty == true)
        let full = analysis(extras: RunExtras(activeCalories: 400, temperatureCelsius: 20, humidity: 60, indoor: false,
                                              heartRateRecovery: 30, effortScore: 6))
        #expect(group("Running form", full)?.rows.count == 5)
        #expect(group("Conditions and effort", full)?.rows.map(\.label) == ["Temperature", "Humidity", "Where", "Calories", "Effort"])
        #expect(group("Heart", full)?.rows.contains { $0.label == "Recovery" && $0.value == "−30 bpm" } == true)
    }

    @Test func unitsFollowTheAthlete() {
        let a = analysis(extras: RunExtras(temperatureCelsius: 20))
        #expect(group("Conditions and effort", a, .imperial)?.rows.first?.value == "68°F")
        #expect(group("Running form", a, .imperial)?.rows.first { $0.label == "Stride length" }?.value == "3.6 ft")
        #expect(group("Elevation", a, .imperial)?.rows.first?.value.hasSuffix("ft") == true)
    }

    @Test func aBestEffortAsLongAsTheRunIsLeftOut() {
        // 5 km run: the 5K "best effort" is the run itself.
        let labels = group("Best efforts", analysis())?.rows.map(\.label) ?? []
        #expect(labels == ["400 m", "1 km", "1 mile"])
    }

    @Test func chartsOnlyForSeriesWithData() {
        let series = RunSeries(distance: (0...60).map { .init(Double($0) * 5, Double($0) * 16) },
                               heartRate: (0...60).map { .init(Double($0) * 5, 150) })
        let main = RunSeriesChartsCard.metrics(series, units: .metric, set: .main).filter { $0.samples.count > 2 }.map(\.title)
        #expect(main == ["Pace", "Heart rate"])
        #expect(RunSeriesChartsCard.metrics(series, units: .metric, set: .more).allSatisfy { $0.samples.count <= 2 })
    }
}
