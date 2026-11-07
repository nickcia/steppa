import Foundation

/// A recorded run's data over time, from whatever the watch saved (Apple Health or Intervals.icu).
/// Every series is optional: a watch that doesn't record power simply has no power.
public struct RunSeries: Codable, Hashable, Sendable {
    /// Seconds from the start and the distance covered by then, in metres. Drives pace and splits.
    public var distance: [Point]
    public var heartRate: [Point]
    /// Watts.
    public var power: [Point]
    /// Steps per minute (both feet).
    public var cadence: [Point]
    /// Metres above sea level.
    public var altitude: [Point]

    public struct Point: Codable, Hashable, Sendable {
        public var t: Double
        public var v: Double
        public init(_ t: Double, _ v: Double) { self.t = t; self.v = v }
    }

    public init(distance: [Point] = [], heartRate: [Point] = [], power: [Point] = [],
                cadence: [Point] = [], altitude: [Point] = []) {
        self.distance = distance
        self.heartRate = heartRate
        self.power = power
        self.cadence = cadence
        self.altitude = altitude
    }

    public var isEmpty: Bool {
        distance.isEmpty && heartRate.isEmpty && power.isEmpty && cadence.isEmpty && altitude.isEmpty
    }

    /// At most `limit` points per series, keeping the shape, so stored runs stay small.
    public func downsampled(to limit: Int = 600) -> RunSeries {
        func thin(_ points: [Point]) -> [Point] {
            guard points.count > limit else { return points }
            let step = Double(points.count - 1) / Double(limit - 1)
            return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
        }
        return RunSeries(distance: thin(distance), heartRate: thin(heartRate), power: thin(power),
                         cadence: thin(cadence), altitude: thin(altitude))
    }
}

/// What a run's data says: splits, averages, heart-rate zones and how steady it was.
public struct RunAnalysis: Codable, Hashable, Sendable {
    public struct Split: Codable, Hashable, Sendable {
        /// 1-based.
        public var index: Int
        /// The split's length; the last one may be partial.
        public var meters: Double
        public var seconds: Double
        public var averageHeartRate: Double?
        public var secondsPerKm: Double { seconds / meters * 1000 }
    }

    public var distanceMeters: Double
    public var durationSeconds: Double
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var averagePower: Double?
    public var averageCadence: Double?
    public var elevationGainMeters: Double?
    public var splits: [Split]
    /// Seconds in each of five heart-rate zones (see `RunAnalyzer.zoneBounds`); nil without heart rate or max HR.
    public var heartRateZoneSeconds: [Double]?
    /// How much heart rate rose for the same pace from the first half to the second, as a fraction
    /// (0.05 = 5%). Above about 5% on a steady easy run usually means it was harder than it should have been,
    /// or it was hot. nil when there isn't enough steady data.
    public var heartRateDrift: Double?
    /// Spread of full-split paces (coefficient of variation). Low = even pacing.
    public var paceVariability: Double?

    public var secondsPerKm: Double { durationSeconds / max(distanceMeters, 1) * 1000 }
}

public enum RunAnalyzer {
    /// Zone upper bounds as a share of maximum heart rate: Z1 < 60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 ≥ 90%.
    public static let zoneBounds: [Double] = [0.60, 0.70, 0.80, 0.90]

    /// - Parameters:
    ///   - splitMeters: 1000 for kilometre splits, 1609.344 for miles.
    ///   - maxHeartRate: the athlete's maximum, for zones. Without it, zones are left out.
    public static func analyze(_ series: RunSeries, distanceMeters: Double, durationSeconds: Double,
                               splitMeters: Double = 1000, maxHeartRate: Double? = nil) -> RunAnalysis {
        let heart = series.heartRate.filter { (30...230).contains($0.v) }
        return RunAnalysis(
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            averageHeartRate: timeWeightedAverage(heart),
            maxHeartRate: heart.map(\.v).max(),
            averagePower: timeWeightedAverage(series.power.filter { $0.v > 0 }),
            averageCadence: timeWeightedAverage(series.cadence.filter { $0.v > 100 }),
            elevationGainMeters: elevationGain(series.altitude),
            splits: splits(series.distance, heartRate: heart, every: splitMeters),
            heartRateZoneSeconds: maxHeartRate.flatMap { zones(heart, maxHeartRate: $0) },
            heartRateDrift: drift(series.distance, heart),
            paceVariability: variability(splits(series.distance, heartRate: [], every: splitMeters)))
    }

    /// The time at which `meters` was reached, interpolated between samples.
    static func time(at meters: Double, in distance: [RunSeries.Point]) -> Double? {
        guard let after = distance.firstIndex(where: { $0.v >= meters }) else { return nil }
        guard after > 0 else { return distance[after].t }
        let a = distance[after - 1], b = distance[after]
        let share = b.v > a.v ? (meters - a.v) / (b.v - a.v) : 0
        return a.t + (b.t - a.t) * share
    }

    static func splits(_ distance: [RunSeries.Point], heartRate: [RunSeries.Point], every: Double) -> [RunAnalysis.Split] {
        guard let last = distance.last, last.v > 0 else { return [] }
        var result: [RunAnalysis.Split] = []
        var startMeters = 0.0, startTime = distance.first?.t ?? 0
        var index = 1
        while startMeters < last.v - 1 {
            let endMeters = min(startMeters + every, last.v)
            guard let endTime = time(at: endMeters, in: distance) else { break }
            // A trailing scrap under 100 m isn't a meaningful split.
            if endMeters - startMeters < 100 && index > 1 { break }
            let hr = heartRate.filter { $0.t >= startTime && $0.t <= endTime }
            result.append(.init(index: index, meters: endMeters - startMeters, seconds: endTime - startTime,
                                averageHeartRate: timeWeightedAverage(hr)))
            startMeters = endMeters
            startTime = endTime
            index += 1
        }
        return result
    }

    /// Average weighted by how long each sample lasted, so dense and sparse recording count the same.
    static func timeWeightedAverage(_ points: [RunSeries.Point]) -> Double? {
        guard !points.isEmpty else { return nil }
        guard points.count > 1 else { return points[0].v }
        var total = 0.0, weight = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let dt = min(max(b.t - a.t, 0), 30) // ignore pauses longer than 30 s
            total += a.v * dt
            weight += dt
        }
        return weight > 0 ? total / weight : points.map(\.v).reduce(0, +) / Double(points.count)
    }

    static func zones(_ heart: [RunSeries.Point], maxHeartRate: Double) -> [Double]? {
        guard heart.count > 1, maxHeartRate > 0 else { return nil }
        var seconds = [Double](repeating: 0, count: zoneBounds.count + 1)
        for (a, b) in zip(heart, heart.dropFirst()) {
            let dt = min(max(b.t - a.t, 0), 30)
            let share = a.v / maxHeartRate
            let zone = zoneBounds.firstIndex(where: { share < $0 }) ?? zoneBounds.count
            seconds[zone] += dt
        }
        return seconds
    }

    /// Climb only, ignoring wobbles under 2 m (barometer and GPS noise).
    static func elevationGain(_ altitude: [RunSeries.Point]) -> Double? {
        guard var base = altitude.first?.v, altitude.count > 1 else { return nil }
        var gain = 0.0
        for point in altitude.dropFirst() {
            if point.v - base >= 2 { gain += point.v - base; base = point.v }
            else if point.v < base { base = point.v }
        }
        return gain
    }

    /// Heart rate per unit of speed, second half against first half (Pa:HR decoupling).
    static func drift(_ distance: [RunSeries.Point], _ heart: [RunSeries.Point]) -> Double? {
        guard let first = distance.first, let last = distance.last, last.t - first.t >= 20 * 60,
              heart.count >= 20 else { return nil }
        let middle = (first.t + last.t) / 2
        func ratio(_ from: Double, _ to: Double) -> Double? {
            guard let d0 = value(at: from, in: distance), let d1 = value(at: to, in: distance), d1 > d0,
                  let hr = timeWeightedAverage(heart.filter { $0.t >= from && $0.t <= to }) else { return nil }
            return hr / ((d1 - d0) / (to - from))
        }
        guard let a = ratio(first.t, middle), let b = ratio(middle, last.t), a > 0 else { return nil }
        return b / a - 1
    }

    static func value(at t: Double, in points: [RunSeries.Point]) -> Double? {
        guard let after = points.firstIndex(where: { $0.t >= t }) else { return points.last?.v }
        guard after > 0 else { return points[after].v }
        let a = points[after - 1], b = points[after]
        return a.v + (b.v - a.v) * (b.t > a.t ? (t - a.t) / (b.t - a.t) : 0)
    }

    static func variability(_ splits: [RunAnalysis.Split]) -> Double? {
        let full = splits.dropLast().filter { $0.meters > 0 }
        guard full.count >= 3 else { return nil }
        let paces = full.map(\.secondsPerKm)
        let mean = paces.reduce(0, +) / Double(paces.count)
        let variance = paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count)
        return variance.squareRoot() / mean
    }

    /// Maximum heart rate for zones when the athlete hasn't set it: the age-based estimate (Tanaka, Monahan &
    /// Seals 2001: 208 − 0.7 × age) or the highest recorded, whichever is higher. Training runs rarely reach
    /// a true maximum, so recorded heart rate alone would set zones too low.
    public static func estimatedMaxHeartRate(age: Int?, runs: [RunSeries]) -> Double? {
        let fromAge = age.map { 208 - 0.7 * Double($0) }
        let recorded = highestRecordedHeartRate(runs)
        switch (fromAge, recorded) {
        case let (a?, r?): return max(a, r)
        case let (a?, nil): return a
        // Recorded alone is a lower bound; only trust it once it's high enough to be near a real maximum.
        case let (nil, r?): return r >= 175 ? r : nil
        case (nil, nil): return nil
        }
    }

    /// The highest heart rate seen in recent runs, ignoring single spikes (the second-highest per run is used).
    public static func highestRecordedHeartRate(_ runs: [RunSeries]) -> Double? {
        runs.compactMap { series -> Double? in
            let values = series.heartRate.map(\.v).filter { (100...230).contains($0) }.sorted()
            return values.count >= 2 ? values[values.count - 2] : values.last
        }.max()
    }
}

/// How a run compared with the plan.
public struct PlannedComparison: Codable, Hashable, Sendable {
    public enum Verdict: String, Codable, Sendable { case onTarget, faster, slower }
    public var targetFast: Double
    public var targetSlow: Double
    public var actualSecondsPerKm: Double
    public var verdict: Verdict

    /// For steady runs (easy, long): the whole run's pace against the target range, with a 3% margin either
    /// side because GPS pace is noisy and an easy run is a range, not a number.
    public static func compare(_ workout: Workout, _ analysis: RunAnalysis) -> PlannedComparison? {
        guard workout.kind == .easy || workout.kind == .long,
              let target = workout.blocks.flatMap(\.steps).first(where: { $0.purpose == .work })?.step.target?.range,
              analysis.distanceMeters > 0 else { return nil }
        let actual = analysis.secondsPerKm
        let verdict: Verdict = actual < target.fast * 0.97 ? .faster : actual > target.slow * 1.03 ? .slower : .onTarget
        return PlannedComparison(targetFast: target.fast, targetSlow: target.slow, actualSecondsPerKm: actual, verdict: verdict)
    }
}
