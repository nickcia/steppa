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
    /// Metres per step (Apple Watch; Garmin with a running sensor).
    public var strideLength: [Point]
    /// Centimetres of bounce per step.
    public var verticalOscillation: [Point]
    /// Milliseconds each foot spends on the ground.
    public var groundContactTime: [Point]
    /// Degrees Celsius (watches with a temperature sensor).
    public var temperature: [Point]
    /// Totals and conditions the watch saved with the run, rather than over time.
    public var extras: RunExtras?

    public struct Point: Codable, Hashable, Sendable {
        public var t: Double
        public var v: Double
        public init(_ t: Double, _ v: Double) { self.t = t; self.v = v }
    }

    public init(distance: [Point] = [], heartRate: [Point] = [], power: [Point] = [],
                cadence: [Point] = [], altitude: [Point] = [], strideLength: [Point] = [],
                verticalOscillation: [Point] = [], groundContactTime: [Point] = [], temperature: [Point] = [],
                extras: RunExtras? = nil) {
        self.distance = distance
        self.heartRate = heartRate
        self.power = power
        self.cadence = cadence
        self.altitude = altitude
        self.strideLength = strideLength
        self.verticalOscillation = verticalOscillation
        self.groundContactTime = groundContactTime
        self.temperature = temperature
        self.extras = extras
    }

    // Series added after the first release are missing from runs saved before them.
    private enum CodingKeys: String, CodingKey {
        case distance, heartRate, power, cadence, altitude, strideLength, verticalOscillation, groundContactTime,
             temperature, extras
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func series(_ key: CodingKeys) throws -> [Point] { try c.decodeIfPresent([Point].self, forKey: key) ?? [] }
        self.init(distance: try series(.distance), heartRate: try series(.heartRate), power: try series(.power),
                  cadence: try series(.cadence), altitude: try series(.altitude), strideLength: try series(.strideLength),
                  verticalOscillation: try series(.verticalOscillation), groundContactTime: try series(.groundContactTime),
                  temperature: try series(.temperature), extras: try c.decodeIfPresent(RunExtras.self, forKey: .extras))
    }

    public var isEmpty: Bool {
        distance.isEmpty && heartRate.isEmpty && power.isEmpty && cadence.isEmpty && altitude.isEmpty
            && strideLength.isEmpty && verticalOscillation.isEmpty && groundContactTime.isEmpty && temperature.isEmpty
            && (extras?.isEmpty ?? true)
    }

    /// At most `limit` points per series, keeping the shape, so stored runs stay small.
    public func downsampled(to limit: Int = 600) -> RunSeries {
        func thin(_ points: [Point]) -> [Point] {
            guard points.count > limit else { return points }
            let step = Double(points.count - 1) / Double(limit - 1)
            return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
        }
        return RunSeries(distance: thin(distance), heartRate: thin(heartRate), power: thin(power),
                         cadence: thin(cadence), altitude: thin(altitude), strideLength: thin(strideLength),
                         verticalOscillation: thin(verticalOscillation), groundContactTime: thin(groundContactTime),
                         temperature: thin(temperature), extras: extras)
    }
}

/// Single numbers a watch saves with a run (Apple Health's workout totals and metadata, for example).
public struct RunExtras: Codable, Hashable, Sendable {
    /// Active calories (kcal).
    public var activeCalories: Double?
    /// The watch's own climb and descent, used when there's no altitude recording.
    public var elevationGainMeters: Double?
    public var elevationLossMeters: Double?
    public var temperatureCelsius: Double?
    /// Relative humidity, 0–100.
    public var humidity: Double?
    /// Treadmill or indoor track.
    public var indoor: Bool?
    /// How far heart rate fell in the minute after stopping, in bpm (Apple Watch).
    public var heartRateRecovery: Double?
    /// The athlete's (or Apple's estimated) effort, 1–10.
    public var effortScore: Double?

    public init(activeCalories: Double? = nil, elevationGainMeters: Double? = nil, elevationLossMeters: Double? = nil,
                temperatureCelsius: Double? = nil, humidity: Double? = nil, indoor: Bool? = nil,
                heartRateRecovery: Double? = nil, effortScore: Double? = nil) {
        self.activeCalories = activeCalories
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.temperatureCelsius = temperatureCelsius
        self.humidity = humidity
        self.indoor = indoor
        self.heartRateRecovery = heartRateRecovery
        self.effortScore = effortScore
    }

    public var isEmpty: Bool { self == RunExtras() }
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

    // Everything else the watch recorded. nil when it wasn't.
    /// Time spent moving (stops at crossings and pauses left out).
    public var movingSeconds: Double?
    public var maxPower: Double?
    public var maxCadence: Double?
    /// Metres per step.
    public var averageStrideLength: Double?
    /// Centimetres.
    public var averageVerticalOscillation: Double?
    /// Milliseconds.
    public var averageGroundContactTime: Double?
    /// Vertical oscillation as a share of stride length, in percent. Lower is more efficient.
    public var verticalRatio: Double?
    public var elevationLossMeters: Double?
    public var highestAltitude: Double?
    public var lowestAltitude: Double?
    public var averageTemperature: Double?
    /// Fastest stretches inside the run (e.g. the quickest kilometre), shortest first.
    public var bestEfforts: [BestEffort] = []
    /// Metres a minute per heartbeat while moving. Rises as aerobic fitness improves (compare like with like).
    public var efficiency: Double?
    /// Training load: minutes in each heart-rate zone weighted by the zone (1–5) (Edwards' TRIMP).
    public var trainingLoad: Double?
    public var extras: RunExtras?

    public struct BestEffort: Codable, Hashable, Sendable {
        public var meters: Double
        public var seconds: Double
        public var secondsPerKm: Double { seconds / meters * 1000 }
    }

    /// Moving time when known, else the whole time.
    public var movingSecondsPerKm: Double { (movingSeconds ?? durationSeconds) / max(distanceMeters, 1) * 1000 }

    public var secondsPerKm: Double { durationSeconds / max(distanceMeters, 1) * 1000 }
}

public enum RunAnalyzer {
    /// Zone upper bounds as a share of maximum heart rate, when no zones are set (see `HeartRateZones.fromMax`).
    public static let zoneBounds: [Double] = HeartRateZones.maxShares

    /// - Parameters:
    ///   - splitMeters: 1000 for kilometre splits, 1609.344 for miles.
    ///   - maxHeartRate: the athlete's maximum, for zones when `zones` isn't given. Without either, zones are left out.
    ///   - zones: the athlete's heart-rate zones (imported or set), which take precedence over `maxHeartRate`.
    public static func analyze(_ series: RunSeries, distanceMeters: Double, durationSeconds: Double,
                               splitMeters: Double = 1000, maxHeartRate: Double? = nil,
                               zones: HeartRateZones? = nil) -> RunAnalysis {
        let zones = zones ?? maxHeartRate.map { HeartRateZones.fromMax($0) }
        let heart = series.heartRate.filter { (30...230).contains($0.v) }
        var analysis = RunAnalysis(
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            averageHeartRate: timeWeightedAverage(heart),
            maxHeartRate: heart.map(\.v).max(),
            averagePower: timeWeightedAverage(series.power.filter { $0.v > 0 }),
            averageCadence: timeWeightedAverage(series.cadence.filter { $0.v > 100 }),
            elevationGainMeters: elevationGain(series.altitude),
            splits: splits(series.distance, heartRate: heart, every: splitMeters),
            heartRateZoneSeconds: zones.flatMap { timeInZones(heart, zones: $0) },
            heartRateDrift: drift(series.distance, heart),
            paceVariability: variability(splits(series.distance, heartRate: [], every: splitMeters)))
        addEverythingElse(to: &analysis, series: series, heart: heart)
        return analysis
    }

    /// The fuller picture: moving time, best efforts, running form, power, elevation, conditions and load.
    static func addEverythingElse(to analysis: inout RunAnalysis, series: RunSeries, heart: [RunSeries.Point]) {
        let extras = series.extras
        analysis.extras = extras
        analysis.movingSeconds = movingTime(series.distance)
        analysis.maxPower = series.power.map(\.v).filter { $0 > 0 }.max()
        analysis.maxCadence = series.cadence.map(\.v).filter { (100...260).contains($0) }.max()
        analysis.averageStrideLength = timeWeightedAverage(series.strideLength.filter { (0.3...3).contains($0.v) })
        analysis.averageVerticalOscillation = timeWeightedAverage(series.verticalOscillation.filter { (2...20).contains($0.v) })
        analysis.averageGroundContactTime = timeWeightedAverage(series.groundContactTime.filter { (100...500).contains($0.v) })
        if let oscillation = analysis.averageVerticalOscillation, let stride = analysis.averageStrideLength, stride > 0 {
            analysis.verticalRatio = oscillation / (stride * 100) * 100
        }
        if analysis.elevationGainMeters == nil { analysis.elevationGainMeters = extras?.elevationGainMeters }
        analysis.elevationLossMeters = elevationGain(series.altitude.map { .init($0.t, -$0.v) }) ?? extras?.elevationLossMeters
        analysis.highestAltitude = series.altitude.map(\.v).max()
        analysis.lowestAltitude = series.altitude.map(\.v).min()
        analysis.averageTemperature = timeWeightedAverage(series.temperature) ?? extras?.temperatureCelsius
        analysis.bestEfforts = bestEfforts(series.distance)
        if let hr = analysis.averageHeartRate, hr > 0, analysis.distanceMeters > 0 {
            let minutes = (analysis.movingSeconds ?? analysis.durationSeconds) / 60
            if minutes > 0 { analysis.efficiency = analysis.distanceMeters / minutes / hr }
        }
        if let zones = analysis.heartRateZoneSeconds {
            analysis.trainingLoad = zones.enumerated().reduce(0) { $0 + Double($1.offset + 1) * $1.element / 60 }
        }
    }

    /// Time when moving faster than a slow walk (0.5 m/s); pauses longer than 30 s between samples don't count.
    static func movingTime(_ distance: [RunSeries.Point]) -> Double? {
        guard distance.count > 2 else { return nil }
        var moving = 0.0
        for (a, b) in zip(distance, distance.dropFirst()) {
            let dt = b.t - a.t
            guard dt > 0, dt <= 30, (b.v - a.v) / dt >= 0.5 else { continue }
            moving += dt
        }
        return moving > 0 ? moving : nil
    }

    /// Distances worth knowing a best for, shortest first.
    public static let bestEffortDistances: [Double] = [400, 1000, 1609.344, 5000, 10000, 21097.5]

    /// The fastest time for each distance anywhere inside the run, from the distance recording.
    static func bestEfforts(_ distance: [RunSeries.Point]) -> [RunAnalysis.BestEffort] {
        guard let total = distance.last?.v, distance.count > 2 else { return [] }
        return bestEffortDistances.filter { $0 <= total + 1 }.compactMap { meters in
            var best: Double?
            for start in distance where start.v + meters <= total + 1 {
                // The whole run can be a hair short of a round distance; count it as reaching it.
                guard let end = time(at: min(start.v + meters, total), in: distance) else { break }
                let seconds = end - start.t
                if seconds > 0, seconds < (best ?? .infinity) { best = seconds }
            }
            // Faster than world-record pace means GPS trouble, not a best.
            guard let best, meters / best < 7 else { return nil }
            return RunAnalysis.BestEffort(meters: meters, seconds: best)
        }
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

    static func timeInZones(_ heart: [RunSeries.Point], zones: HeartRateZones) -> [Double]? {
        guard heart.count > 1, zones.maxHeartRate > 0 else { return nil }
        var seconds = [Double](repeating: 0, count: zones.upperLimits.count + 1)
        for (a, b) in zip(heart, heart.dropFirst()) {
            let dt = min(max(b.t - a.t, 0), 30)
            seconds[zones.zone(for: a.v)] += dt
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
