import Foundation
import Testing
@testable import PlanEngine

/// A run at a steady `secondsPerKm`, sampled every 5 s, with heart rate rising by `hrRise` bpm over the run.
private func steadyRun(km: Double, secondsPerKm: Double, hr: Double = 140, hrRise: Double = 0,
                       power: Double? = nil) -> RunSeries {
    let duration = km * secondsPerKm
    let times = stride(from: 0.0, through: duration, by: 5).map { $0 }
    return RunSeries(
        distance: times.map { .init($0, $0 / secondsPerKm * 1000) },
        heartRate: times.map { .init($0, hr + hrRise * $0 / duration) },
        power: power.map { p in times.map { .init($0, p) } } ?? [],
        cadence: times.map { .init($0, 170) },
        altitude: times.map { .init($0, 50 + 10 * sin($0 / 300)) })
}

@Suite struct RunAnalysisTests {
    @Test func movingTimeLeavesOutStops() {
        // 2 km at 5:00/km, a 2-minute stop, then 2 km more.
        var distance: [RunSeries.Point] = stride(from: 0.0, through: 600, by: 5).map { .init($0, $0 / 300 * 1000) }
        distance += stride(from: 605.0, through: 720, by: 5).map { .init($0, 2000) }
        distance += stride(from: 725.0, through: 1320, by: 5).map { .init($0, 2000 + ($0 - 720) / 300 * 1000) }
        let analysis = RunAnalyzer.analyze(RunSeries(distance: distance), distanceMeters: 4_000, durationSeconds: 1_320)
        #expect(abs((analysis.movingSeconds ?? 0) - 1_200) < 15)
        #expect(abs(analysis.movingSecondsPerKm - 300) < 4)
    }

    @Test func bestEffortsFindTheFastestStretch() {
        // 3 km easy at 6:00/km, then 1 km hard at 4:00/km, then 1 km easy.
        var points: [RunSeries.Point] = []
        var t = 0.0, d = 0.0
        for (km, pace) in [(3.0, 360.0), (1.0, 240.0), (1.0, 360.0)] {
            let end = d + km * 1000
            while d < end - 0.001 { t += 5; d = min(end, d + 5 / pace * 1000); points.append(.init(t, d)) }
        }
        let efforts = RunAnalyzer.analyze(RunSeries(distance: [.init(0, 0)] + points), distanceMeters: 5_000,
                                          durationSeconds: t).bestEfforts
        #expect(efforts.map(\.meters) == [400, 1000, 1609.344, 5000])
        #expect(abs((efforts.first { $0.meters == 1000 }?.seconds ?? 0) - 240) < 6)
        #expect(efforts.first { $0.meters == 5000 }.map { abs($0.seconds - t) < 1 } == true)
    }

    @Test func runningFormPowerElevationAndLoad() {
        var series = steadyRun(km: 5, secondsPerKm: 300, hr: 150, power: 260)
        let times = series.distance.map(\.t)
        series.strideLength = times.map { .init($0, 1.1) }
        series.verticalOscillation = times.map { .init($0, 8.8) }
        series.groundContactTime = times.map { .init($0, 240) }
        series.extras = RunExtras(activeCalories: 380, temperatureCelsius: 14, heartRateRecovery: 32)
        let analysis = RunAnalyzer.analyze(series, distanceMeters: 5_000, durationSeconds: 1_500, maxHeartRate: 190)
        #expect(analysis.averageStrideLength == 1.1)
        #expect(analysis.averageGroundContactTime == 240)
        #expect(abs((analysis.verticalRatio ?? 0) - 8) < 0.01)
        #expect(analysis.maxPower == 260)
        #expect(analysis.maxCadence == 170)
        #expect((analysis.elevationLossMeters ?? 0) > 10)
        #expect(analysis.highestAltitude.map { $0 > 55 } == true)
        #expect(analysis.averageTemperature == 14)
        #expect(analysis.extras?.activeCalories == 380)
        // 200 m a minute at 150 bpm.
        #expect(abs((analysis.efficiency ?? 0) - 200.0 / 150) < 0.02)
        // 25 minutes at 150 bpm (zone 3 of 190) is a load of about 75.
        #expect(abs((analysis.trainingLoad ?? 0) - 75) < 3)
    }

    @Test func runsSavedBeforeNewSeriesStillOpen() throws {
        let old = #"{"distance":[{"t":0,"v":0}],"heartRate":[],"power":[],"cadence":[],"altitude":[]}"#
        let series = try JSONDecoder().decode(RunSeries.self, from: Data(old.utf8))
        #expect(series.strideLength.isEmpty && series.extras == nil)
        let round = try JSONDecoder().decode(RunSeries.self, from: JSONEncoder().encode(series))
        #expect(round == series)
    }

    @Test func splitsAndAverages() {
        let series = steadyRun(km: 5.5, secondsPerKm: 300, power: 250)
        let analysis = RunAnalyzer.analyze(series, distanceMeters: 5_500, durationSeconds: 1_650, maxHeartRate: 190)
        #expect(analysis.splits.count == 6)
        #expect(abs(analysis.splits[0].seconds - 300) < 0.5)
        #expect(abs(analysis.splits[5].meters - 500) < 1)
        #expect(abs((analysis.averageHeartRate ?? 0) - 140) < 0.5)
        #expect(analysis.averagePower == 250)
        #expect(analysis.averageCadence == 170)
        #expect(analysis.paceVariability.map { $0 < 0.01 } == true)
        #expect((analysis.elevationGainMeters ?? 0) > 10)
    }

    @Test func mileSplits() {
        let analysis = RunAnalyzer.analyze(steadyRun(km: 5, secondsPerKm: 300), distanceMeters: 5_000,
                                           durationSeconds: 1_500, splitMeters: 1609.344)
        #expect(analysis.splits.count == 4) // 3 full miles and 171 m
        #expect(abs(analysis.splits[0].seconds - 482.8) < 0.5)
    }

    @Test func heartRateZones() throws {
        // 140 of 190 is 74%: zone 3 the whole way.
        let analysis = RunAnalyzer.analyze(steadyRun(km: 5, secondsPerKm: 300), distanceMeters: 5_000,
                                           durationSeconds: 1_500, maxHeartRate: 190)
        let zones = try #require(analysis.heartRateZoneSeconds)
        #expect(zones.count == 5)
        #expect(abs(zones[2] - 1_500) < 6)
        #expect(zones[0] + zones[1] + zones[3] + zones[4] < 6)
    }

    @Test func driftShowsRisingHeartRateAtSteadyPace() throws {
        let steady = RunAnalyzer.analyze(steadyRun(km: 8, secondsPerKm: 360), distanceMeters: 8_000, durationSeconds: 2_880)
        #expect(abs(try #require(steady.heartRateDrift)) < 0.005)
        let drifting = RunAnalyzer.analyze(steadyRun(km: 8, secondsPerKm: 360, hrRise: 16), distanceMeters: 8_000,
                                           durationSeconds: 2_880)
        #expect(try #require(drifting.heartRateDrift) > 0.04)
        // Too short to judge.
        #expect(RunAnalyzer.analyze(steadyRun(km: 3, secondsPerKm: 300), distanceMeters: 3_000,
                                    durationSeconds: 900).heartRateDrift == nil)
    }

    @Test func missingDataIsLeftOut() {
        let analysis = RunAnalyzer.analyze(RunSeries(), distanceMeters: 5_000, durationSeconds: 1_500, maxHeartRate: 190)
        #expect(analysis.splits.isEmpty)
        #expect(analysis.averageHeartRate == nil && analysis.averagePower == nil && analysis.heartRateZoneSeconds == nil)
        #expect(analysis.secondsPerKm == 300)
    }

    @Test func maxHeartRateIgnoresSingleSpikes() {
        var spiky = steadyRun(km: 5, secondsPerKm: 300, hr: 150)
        spiky.heartRate.append(.init(10, 229))
        let runs = [spiky, steadyRun(km: 5, secondsPerKm: 300, hr: 170)]
        #expect(RunAnalyzer.highestRecordedHeartRate(runs) == 170)
        // Age 40: 208 − 28 = 180, above anything recorded.
        #expect(RunAnalyzer.estimatedMaxHeartRate(age: 40, runs: runs) == 180)
        #expect(RunAnalyzer.estimatedMaxHeartRate(age: 60, runs: [steadyRun(km: 5, secondsPerKm: 300, hr: 185)]) == 185)
        // Without an age, 170 recorded is too low to be a real maximum.
        #expect(RunAnalyzer.estimatedMaxHeartRate(age: nil, runs: runs) == nil)
    }

    @Test func downsamplingKeepsEnds() {
        let series = steadyRun(km: 20, secondsPerKm: 300).downsampled(to: 100)
        #expect(series.distance.count == 100)
        #expect(series.distance.last?.v == steadyRun(km: 20, secondsPerKm: 300).distance.last?.v)
    }

    @Test func easyRunPaceAgainstTarget() throws {
        let paces = PaceTable(score: 45, goal: .tenK)
        let workout = WorkoutFactory.easy(LocalDate(year: 2026, month: 11, day: 10), meters: 8_000, paces: paces)
        func analysis(_ pace: Double) -> RunAnalysis {
            RunAnalyzer.analyze(RunSeries(), distanceMeters: 8_000, durationSeconds: 8 * pace)
        }
        #expect(PlannedComparison.compare(workout, analysis(paces.easy.mid))?.verdict == .onTarget)
        #expect(PlannedComparison.compare(workout, analysis(paces.easy.fast * 0.9))?.verdict == .faster)
        #expect(PlannedComparison.compare(workout, analysis(paces.easy.slow * 1.1))?.verdict == .slower)
    }
}
