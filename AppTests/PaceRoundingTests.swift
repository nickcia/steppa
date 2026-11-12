import Testing
@testable import TrackStar
import PlanEngine

/// Target paces read to the nearest 5 seconds, in the athlete's own units; paces actually run stay exact.
@MainActor
struct PaceRoundingTests {
    let metric = DisplayFormat(units: .metric)
    let imperial = DisplayFormat(units: .imperial)

    @Test func targetsRoundToFiveSecondsPerKm() {
        #expect(metric.paceRange(PaceRange(fast: 301, slow: 322)) == "5:00–5:20 /km")
        #expect(metric.targetPace(327.4) == "5:25 /km")
        #expect(metric.targetPace(328) == "5:30 /km")
    }

    @Test func milesRoundInMilesNotKilometres() {
        // 300 s/km is 8:02.8 /mi, which reads 8:05 /mi.
        #expect(imperial.targetPace(300) == "8:05 /mi")
    }

    @Test func actualPacesStayExact() {
        #expect(metric.pace(301) == "5:01 /km")
    }

    @Test func roundedRangesForWatchesMatchWhatsShownAndNeverCollapse() {
        let rounded = metric.rounded(PaceRange(fast: 301, slow: 303))
        #expect(rounded.fast == 300)
        #expect(rounded.slow == 305)
        let miles = imperial.rounded(PaceRange(fast: 300, slow: 320))
        #expect(imperial.paceRange(miles) == imperial.paceRange(PaceRange(fast: 300, slow: 320)))
    }
}
