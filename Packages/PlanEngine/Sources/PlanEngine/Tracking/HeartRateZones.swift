import Foundation

/// Five heart-rate zones, as upper limits in beats per minute.
///
/// Zones come from the athlete's watch platform when they can be imported (Garmin and others sync their zones to
/// Intervals.icu), from limits the athlete types in, or, failing both, from their maximum heart rate (60, 70, 80
/// and 90% of it). Planned paces map onto zones so a workout can be run by heart rate instead.
public struct HeartRateZones: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Worked out from maximum heart rate.
        case estimated
        /// Imported from the athlete's watch platform, through Intervals.icu.
        case imported
        /// Typed in by the athlete.
        case custom
    }

    /// Upper limits of zones 1 to 4, rising. Zone 5 runs from the last of these up to `maxHeartRate`.
    public var upperLimits: [Double]
    public var maxHeartRate: Double
    public var source: Source

    public init(upperLimits: [Double], maxHeartRate: Double, source: Source) {
        self.upperLimits = upperLimits
        self.maxHeartRate = maxHeartRate
        self.source = source
    }

    /// Zone limits as a share of maximum heart rate: Z1 < 60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 ≥ 90%.
    public static let maxShares: [Double] = [0.60, 0.70, 0.80, 0.90]

    public static func fromMax(_ maxHeartRate: Double, source: Source = .estimated) -> HeartRateZones {
        HeartRateZones(upperLimits: maxShares.map { ($0 * maxHeartRate).rounded() }, maxHeartRate: maxHeartRate.rounded(),
                       source: source)
    }

    /// Zones from a watch platform's list of upper limits (the last is usually the maximum). Five-zone systems
    /// (Garmin, Polar, COROS) are used as they are; systems with more zones (Intervals.icu's seven) keep their
    /// first four limits and their top, so the athlete's own thresholds still divide the easy and hard zones.
    /// nil if the limits don't make sense.
    public static func imported(upperLimits: [Double], maxHeartRate: Double?) -> HeartRateZones? {
        let limits = upperLimits.filter { (60...240).contains($0) }
        guard limits.count >= 5, zip(limits, limits.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        let top = max(maxHeartRate ?? 0, limits.last!)
        return HeartRateZones(upperLimits: Array(limits.prefix(4)), maxHeartRate: top, source: .imported)
    }

    public var isValid: Bool {
        upperLimits.count == 4 && zip(upperLimits, upperLimits.dropFirst()).allSatisfy({ $0 < $1 })
            && (upperLimits.last ?? .infinity) < maxHeartRate && (upperLimits.first ?? 0) > 40
    }

    /// The zone (0 for zone 1 … 4 for zone 5) a heart rate falls in.
    public func zone(for bpm: Double) -> Int {
        upperLimits.firstIndex(where: { bpm < $0 }) ?? upperLimits.count
    }

    /// The beats-per-minute range of a zone (0…4). Zone 1 starts at half of maximum.
    public func range(ofZone zone: Int) -> ClosedRange<Double> {
        let index = min(max(zone, 0), upperLimits.count)
        let lower = index == 0 ? (maxHeartRate * 0.5).rounded() : upperLimits[index - 1]
        let upper = index < upperLimits.count ? upperLimits[index] - 1 : maxHeartRate
        return lower...max(lower, upper)
    }

    /// Which zones a planned pace corresponds to, as a range of zone numbers (0…4), or nil when the step is run by
    /// feel instead (strides, and race pace, where the goal is the clock).
    ///
    /// Easy and long running sits in zone 2, marathon pace in zone 3, threshold in zone 4 and interval and
    /// repetition pace in zone 5 (Seiler; Daniels). Hill reps are short and hard: heart rate lags, so they're given
    /// as zones 4–5 to aim for by the top of each climb.
    public static func zones(for pace: PaceZone) -> ClosedRange<Int>? {
        switch pace {
        case .easy: 1...1
        case .marathon: 2...2
        case .threshold: 3...3
        case .interval, .repetition: 4...4
        case .hill: 3...4
        case .stride, .race: nil
        }
    }

    /// The heart-rate range for a planned pace, from the bottom of its lowest zone to the top of its highest.
    public func target(for pace: PaceZone) -> (zones: ClosedRange<Int>, bpm: ClosedRange<Double>)? {
        guard let zones = Self.zones(for: pace) else { return nil }
        return (zones, range(ofZone: zones.lowerBound).lowerBound...range(ofZone: zones.upperBound).upperBound)
    }
}
