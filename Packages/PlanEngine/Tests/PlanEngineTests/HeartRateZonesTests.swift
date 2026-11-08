import Testing
@testable import PlanEngine

struct HeartRateZonesTests {
    @Test func zonesFromMaximum() {
        let zones = HeartRateZones.fromMax(190)
        #expect(zones.upperLimits == [114, 133, 152, 171])
        #expect(zones.isValid)
        #expect(zones.zone(for: 100) == 0)
        #expect(zones.zone(for: 140) == 2)
        #expect(zones.zone(for: 185) == 4)
        #expect(zones.range(ofZone: 1) == 114...132)
        #expect(zones.range(ofZone: 4) == 171...190)
    }

    @Test func importsFiveAndSevenZoneSystems() throws {
        // Garmin-style five zones, last limit is the maximum.
        let garmin = try #require(HeartRateZones.imported(upperLimits: [120, 140, 158, 172, 188], maxHeartRate: nil))
        #expect(garmin.upperLimits == [120, 140, 158, 172])
        #expect(garmin.maxHeartRate == 188)
        #expect(garmin.source == .imported)
        // Intervals.icu's seven zones keep their first four limits and the top.
        let seven = try #require(HeartRateZones.imported(upperLimits: [130, 148, 158, 166, 171, 176, 192], maxHeartRate: 192))
        #expect(seven.upperLimits == [130, 148, 158, 166])
        #expect(seven.maxHeartRate == 192)
        // Nonsense is refused.
        #expect(HeartRateZones.imported(upperLimits: [150, 140, 160, 170, 180], maxHeartRate: nil) == nil)
        #expect(HeartRateZones.imported(upperLimits: [120, 140], maxHeartRate: 190) == nil)
    }

    @Test func plannedPacesMapToZones() throws {
        let zones = HeartRateZones.fromMax(190)
        let easy = try #require(zones.target(for: .easy))
        #expect(easy.zones == 1...1)
        #expect(easy.bpm == 114...132)
        #expect(zones.target(for: .threshold)?.zones == 3...3)
        #expect(zones.target(for: .interval)?.bpm == 171...190)
        #expect(zones.target(for: .hill)?.zones == 3...4)
        #expect(zones.target(for: .stride) == nil)
        #expect(zones.target(for: .race) == nil)
    }

    @Test func analysisUsesImportedZones() throws {
        let heart = stride(from: 0.0, through: 600, by: 10).map { RunSeries.Point($0, 150) }
        let series = RunSeries(heartRate: heart)
        let imported = try #require(HeartRateZones.imported(upperLimits: [120, 140, 158, 172, 188], maxHeartRate: nil))
        let analysis = RunAnalyzer.analyze(series, distanceMeters: 2000, durationSeconds: 600, zones: imported)
        #expect(analysis.heartRateZoneSeconds?[2] == 600)
        let byMax = RunAnalyzer.analyze(RunSeries(heartRate: heart.map { .init($0.t, 155) }), distanceMeters: 2000,
                                        durationSeconds: 600, maxHeartRate: 190)
        #expect(byMax.heartRateZoneSeconds?[3] == 600)
        let byImported = RunAnalyzer.analyze(RunSeries(heartRate: heart.map { .init($0.t, 155) }), distanceMeters: 2000,
                                             durationSeconds: 600, maxHeartRate: 190, zones: imported)
        #expect(byImported.heartRateZoneSeconds?[2] == 600)
    }
}
