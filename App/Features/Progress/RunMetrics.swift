import Charts
import MapKit
import SwiftUI
import PlanEngine

/// Every number the watch recorded for a run: one card per subject (time, best efforts, heart, power, running
/// form, elevation, conditions), each with its figures as labelled tiles and, where there is one, its chart. Cards
/// and figures only appear when there's data for them.
struct RunMetricsCard: View {
    let analysis: RunAnalysis
    let units: UnitSystem
    var series: RunSeries?

    struct Row: Identifiable {
        let label: String
        let value: String
        var detail: String?
        var id: String { label }
    }

    struct Group: Identifiable {
        let title: String
        let symbol: String
        let rows: [Row]
        var footer: String?
        /// Titles of the charts (from `RunSeriesChartsCard`) that belong with these figures.
        var charts: [String] = []
        /// Shown as a table of distance, time and pace rather than tiles.
        var isTable = false
        var id: String { title }
    }

    var body: some View {
        let groups = Self.groups(analysis, units: units).filter { !$0.rows.isEmpty }
        let charts = series.map { RunSeriesChartsCard.metrics($0, units: units, set: .more) }?
            .filter { $0.samples.count > 2 } ?? []
        ForEach(groups) { group in
            GroupCard(group: group, charts: charts.filter { group.charts.contains($0.title) })
        }
    }

    private struct GroupCard: View {
        let group: Group
        let charts: [RunSeriesChartsCard.Metric]
        @State private var shownChart: String?

        var body: some View {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label {
                        Text(group.title).font(.headline).foregroundStyle(Theme.ink)
                    } icon: {
                        Image(systemName: group.symbol).foregroundStyle(Theme.ink)
                    }
                    if group.isTable { table } else { tiles }
                    if let footer = group.footer {
                        Text(footer).font(.footnote).foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    chart
                }
            }
        }

        /// Two figures a row: what it is, the number, and a short note right under it.
        private var tiles: some View {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), alignment: .top)],
                      alignment: .leading, spacing: 8) {
                ForEach(group.rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.label).font(.caption.weight(.medium)).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                        FigureText(text: row.value, size: 22).foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let detail = row.detail {
                            Text(detail).font(.caption).foregroundStyle(Theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .padding(12)
                    .background(Theme.subtle.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }

        /// Distance, time and pace in columns, for best efforts.
        private var table: some View {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Distance"); Text("Time").gridColumnAlignment(.trailing); Text("Pace").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryInk)
                ForEach(group.rows) { row in
                    GridRow {
                        Text(row.label).font(.subheadline).foregroundStyle(Theme.ink)
                        Text(row.value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                        Text(row.detail ?? "").font(.subheadline).monospacedDigit().foregroundStyle(Theme.secondaryInk)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The group's chart; with several (running form), a switch picks one.
        @ViewBuilder private var chart: some View {
            if let first = charts.first {
                let selected = charts.first { $0.title == shownChart } ?? first
                VStack(alignment: .leading, spacing: 10) {
                    if charts.count > 1 {
                        Picker("Chart", selection: Binding(get: { selected.title }, set: { shownChart = $0 })) {
                            ForEach(charts) { Text(Self.shortName($0.title)).tag($0.title) }
                        }
                        .pickerStyle(.segmented)
                    }
                    RunSeriesChartsCard.MetricChart(metric: selected, showsTitle: false)
                }
                .padding(.top, 4)
            }
        }

        /// Short enough for a four-way switch.
        static func shortName(_ title: String) -> String {
            switch title {
            case String(localized: "Vertical oscillation"): String(localized: "Bounce")
            case String(localized: "Stride length"): String(localized: "Stride")
            case String(localized: "Ground contact"): String(localized: "Contact")
            default: title
            }
        }
    }

    // MARK: Building the groups (static, so it can be tested)

    static func groups(_ a: RunAnalysis, units: UnitSystem) -> [Group] {
        [time(a, units), bestEfforts(a, units), heart(a), form(a, units), power(a), elevation(a, units), conditions(a, units)]
    }

    private static func pace(_ secondsPerKm: Double, _ units: UnitSystem) -> String {
        DisplayFormat(units: units).pace(secondsPerKm)
    }

    static func time(_ a: RunAnalysis, _ units: UnitSystem) -> Group {
        var rows: [Row] = []
        if let moving = a.movingSeconds, a.durationSeconds - moving >= 30 {
            rows.append(Row(label: String(localized: "Moving time"), value: DisplayFormat.duration(moving),
                            detail: String(localized: "of \(DisplayFormat.duration(a.durationSeconds)) in all")))
            rows.append(Row(label: String(localized: "Moving pace"), value: pace(a.movingSecondsPerKm, units)))
        }
        if let fastest = a.splits.filter({ $0.meters >= units.metersPerUnit * 0.95 }).min(by: { $0.secondsPerKm < $1.secondsPerKm }),
           a.splits.count > 1 {
            rows.append(Row(label: String(localized: "Fastest split"), value: pace(fastest.secondsPerKm, units),
                            detail: String(localized: "split \(fastest.index)")))
        }
        return Group(title: String(localized: "Time and pace"), symbol: "stopwatch", rows: rows)
    }

    static func bestEfforts(_ a: RunAnalysis, _ units: UnitSystem) -> Group {
        let names: [Double: String] = [400: "400 m", 1000: "1 km", 1609.344: String(localized: "1 mile"),
                                       5000: "5K", 10000: "10K", 21097.5: String(localized: "Half marathon")]
        // A best effort the length of the whole run is just the run itself.
        let rows = a.bestEfforts.filter { $0.meters < a.distanceMeters * 0.97 }.map { effort in
            Row(label: names[effort.meters] ?? DisplayFormat(units: units).distance(effort.meters),
                value: DisplayFormat.clock(effort.seconds), detail: pace(effort.secondsPerKm, units))
        }
        return Group(title: String(localized: "Best efforts"), symbol: "bolt", rows: rows,
                     footer: rows.isEmpty ? nil : String(localized: "Your fastest stretch of each distance inside this run."),
                     isTable: true)
    }

    static func heart(_ a: RunAnalysis) -> Group {
        var rows: [Row] = []
        if let average = a.averageHeartRate { rows.append(Row(label: String(localized: "Average"), value: "\(Int(average.rounded())) bpm")) }
        if let max = a.maxHeartRate { rows.append(Row(label: String(localized: "Highest"), value: "\(Int(max.rounded())) bpm")) }
        if let recovery = a.extras?.heartRateRecovery {
            rows.append(Row(label: String(localized: "Recovery"), value: "−\(Int(recovery.rounded())) bpm",
                            detail: String(localized: "in the first minute after")))
        }
        if let drift = a.heartRateDrift {
            rows.append(Row(label: String(localized: "Drift"), value: String(format: "%+.0f%%", drift * 100).replacingOccurrences(of: "-", with: "−"),
                            detail: String(localized: "second half against first")))
        }
        if let efficiency = a.efficiency {
            rows.append(Row(label: String(localized: "Efficiency"), value: String(format: "%.2f", efficiency),
                            detail: String(localized: "metres a minute per beat")))
        }
        if let load = a.trainingLoad { rows.append(Row(label: String(localized: "Training load"), value: "\(Int(load.rounded()))")) }
        let footer = a.efficiency == nil ? nil
            : String(localized: "Efficiency rises as you get fitter: compare it between similar runs.")
        return Group(title: String(localized: "Heart"), symbol: "heart", rows: rows, footer: footer)
    }

    static func form(_ a: RunAnalysis, _ units: UnitSystem) -> Group {
        var rows: [Row] = []
        if let cadence = a.averageCadence {
            rows.append(Row(label: String(localized: "Cadence"), value: String(localized: "\(Int(cadence.rounded())) steps/min"),
                            detail: a.maxCadence.map { String(localized: "up to \(Int($0.rounded()))") }))
        }
        if let stride = a.averageStrideLength {
            let value = units == .metric ? String(format: "%.2f m", stride) : String(format: "%.1f ft", stride * 3.28084)
            rows.append(Row(label: String(localized: "Stride length"), value: value))
        }
        if let oscillation = a.averageVerticalOscillation {
            let value = units == .metric ? String(format: "%.1f cm", oscillation) : String(format: "%.1f in", oscillation / 2.54)
            rows.append(Row(label: String(localized: "Vertical oscillation"), value: value, detail: String(localized: "bounce per step")))
        }
        if let contact = a.averageGroundContactTime {
            rows.append(Row(label: String(localized: "Ground contact"), value: "\(Int(contact.rounded())) ms"))
        }
        if let ratio = a.verticalRatio {
            rows.append(Row(label: String(localized: "Vertical ratio"), value: String(format: "%.1f%%", ratio),
                            detail: String(localized: "lower is more efficient")))
        }
        return Group(title: String(localized: "Running form"), symbol: "figure.run", rows: rows,
                     charts: [String(localized: "Cadence"), String(localized: "Stride length"),
                              String(localized: "Vertical oscillation"), String(localized: "Ground contact")])
    }

    static func power(_ a: RunAnalysis) -> Group {
        var rows: [Row] = []
        if let average = a.averagePower { rows.append(Row(label: String(localized: "Average"), value: "\(Int(average.rounded())) W")) }
        if let max = a.maxPower { rows.append(Row(label: String(localized: "Highest"), value: "\(Int(max.rounded())) W")) }
        return Group(title: String(localized: "Power"), symbol: "bolt.circle", rows: rows,
                     charts: [String(localized: "Power")])
    }

    private static func height(_ meters: Double, _ units: UnitSystem) -> String {
        units == .metric ? "\(Int(meters.rounded())) m" : "\(Int((meters * 3.28084).rounded())) ft"
    }

    static func elevation(_ a: RunAnalysis, _ units: UnitSystem) -> Group {
        var rows: [Row] = []
        if let gain = a.elevationGainMeters { rows.append(Row(label: String(localized: "Climb"), value: height(gain, units))) }
        if let loss = a.elevationLossMeters { rows.append(Row(label: String(localized: "Descent"), value: height(loss, units))) }
        if let high = a.highestAltitude { rows.append(Row(label: String(localized: "Highest point"), value: height(high, units))) }
        if let low = a.lowestAltitude { rows.append(Row(label: String(localized: "Lowest point"), value: height(low, units))) }
        return Group(title: String(localized: "Elevation"), symbol: "mountain.2", rows: rows)
    }

    static func conditions(_ a: RunAnalysis, _ units: UnitSystem) -> Group {
        var rows: [Row] = []
        if let temperature = a.averageTemperature {
            let value = units == .metric ? "\(Int(temperature.rounded()))°C" : "\(Int((temperature * 9 / 5 + 32).rounded()))°F"
            rows.append(Row(label: String(localized: "Temperature"), value: value))
        }
        if let humidity = a.extras?.humidity { rows.append(Row(label: String(localized: "Humidity"), value: "\(Int(humidity.rounded()))%")) }
        if let indoor = a.extras?.indoor {
            rows.append(Row(label: String(localized: "Where"), value: indoor ? String(localized: "Indoors") : String(localized: "Outdoors")))
        }
        if let calories = a.extras?.activeCalories {
            rows.append(Row(label: String(localized: "Calories"), value: String(localized: "\(Int(calories.rounded())) kcal"),
                            detail: String(localized: "active")))
        }
        if let effort = a.extras?.effortScore {
            rows.append(Row(label: String(localized: "Effort"), value: String(localized: "\(Int(effort.rounded())) out of 10")))
        }
        return Group(title: String(localized: "Conditions and effort"), symbol: "thermometer.medium", rows: rows)
    }
}

/// A chart for each series the run has: pace, heart rate, elevation, power, cadence, and running form.
struct RunSeriesChartsCard: View {
    let series: RunSeries
    let units: UnitSystem
    /// The everyday charts (pace, heart rate, elevation), or the rest (power, cadence, running form).
    var set: ChartSet = .main

    enum ChartSet { case main, more }

    struct Sample: Identifiable {
        let id: Int
        let minutes: Double
        let value: Double
    }

    struct Metric: Identifiable {
        let title: String
        let unit: String
        let color: Color
        let samples: [Sample]
        /// Pace: lower is faster, so the axis runs the other way and labels read as times.
        var reversed = false
        var area = false
        var id: String { title }
    }

    var body: some View {
        let metrics = Self.metrics(series, units: units, set: set).filter { $0.samples.count > 2 }
        if !metrics.isEmpty {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(metrics) { MetricChart(metric: $0) }
                }
            }
        }
    }

    struct MetricChart: View {
        let metric: Metric
        var showsTitle = true

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if showsTitle { Text(metric.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
                    Spacer()
                    Text(metric.unit).font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                chart.frame(height: 110)
            }
        }

        private var chart: some View {
            Chart(metric.samples) { sample in
                if metric.area {
                    AreaMark(x: .value("Minutes", sample.minutes), y: .value(metric.title, sample.value))
                        .foregroundStyle(metric.color.opacity(0.25))
                }
                LineMark(x: .value("Minutes", sample.minutes), y: .value(metric.title, sample.value))
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: metric.reversed))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel { Text(label(value.as(Double.self))) }
                }
            }
            .chartXAxisLabel("min")
        }

        private func label(_ value: Double?) -> String {
            guard let value else { return "" }
            if metric.reversed { return DisplayFormat.clock(value) }
            // Stride (about a metre) needs two decimals to show any change; bounce in cm needs one.
            if value < 3 { return String(format: "%.2f", value) }
            return value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
        }
    }

    static func metrics(_ series: RunSeries, units: UnitSystem, set: ChartSet) -> [Metric] {
        let all = allMetrics(series, units: units)
        return set == .main ? Array(all.prefix(3)) : Array(all.dropFirst(3))
    }

    private static func allMetrics(_ series: RunSeries, units: UnitSystem) -> [Metric] {
        func samples(_ points: [RunSeries.Point], scale: Double = 1, valid: ClosedRange<Double>) -> [Sample] {
            points.enumerated().compactMap { index, point in
                valid.contains(point.v) ? Sample(id: index, minutes: point.t / 60, value: point.v * scale) : nil
            }
        }
        let feet = units == .imperial
        return [
            Metric(title: String(localized: "Pace"), unit: "/\(units.distanceUnit)", color: WorkoutKind.long.color,
                   samples: pace(series.distance, units), reversed: true),
            Metric(title: String(localized: "Heart rate"), unit: "bpm", color: Theme.red,
                   samples: samples(series.heartRate, valid: 30...230)),
            Metric(title: String(localized: "Elevation"), unit: feet ? "ft" : "m", color: WorkoutKind.hills.color,
                   samples: samples(series.altitude, scale: feet ? 3.28084 : 1, valid: -500...9000), area: true),
            Metric(title: String(localized: "Power"), unit: "W", color: WorkoutKind.tempo.color,
                   samples: samples(series.power, valid: 1...1500)),
            Metric(title: String(localized: "Cadence"), unit: String(localized: "steps/min"), color: WorkoutKind.marathonPaceLong.color,
                   samples: samples(series.cadence, valid: 100...260)),
            Metric(title: String(localized: "Stride length"), unit: feet ? "ft" : "m", color: WorkoutKind.easy.color,
                   samples: samples(series.strideLength, scale: feet ? 3.28084 : 1, valid: 0.3...3)),
            Metric(title: String(localized: "Vertical oscillation"), unit: feet ? "in" : "cm", color: WorkoutKind.custom.color,
                   samples: samples(series.verticalOscillation, scale: feet ? 1 / 2.54 : 1, valid: 2...20)),
            Metric(title: String(localized: "Ground contact"), unit: "ms", color: WorkoutKind.runWalk.color,
                   samples: samples(series.groundContactTime, valid: 100...500)),
        ]
    }

    /// Pace in seconds per display unit, smoothed over about a minute so GPS noise doesn't dominate.
    static func pace(_ points: [RunSeries.Point], _ units: UnitSystem) -> [Sample] {
        guard points.count > 2 else { return [] }
        var result: [Sample] = []
        var j = 0
        for (i, point) in points.enumerated() {
            while j < i, point.t - points[j].t > 60 { j += 1 }
            let dt = point.t - points[j].t, dd = point.v - points[j].v
            guard dt >= 20, dd > 5 else { continue }
            let secondsPerKm = dt / dd * 1000
            guard (150...900).contains(secondsPerKm) else { continue }
            result.append(Sample(id: i, minutes: point.t / 60, value: secondsPerKm * units.metersPerUnit / 1000))
        }
        return result
    }
}

/// The run's route across the top of the run page, when it has one (runs from Health with a route). Still, so the
/// page scrolls past it easily.
struct RunRouteMap: View {
    let run: CompletedRun
    @Environment(AppModel.self) private var model
    @State private var route: [CLLocationCoordinate2D] = []

    var body: some View {
        Group {
            if route.count > 1 {
                Map(initialPosition: .rect(Self.rect(fitting: route)), interactionModes: []) {
                    MapPolyline(coordinates: route)
                        .stroke(WorkoutKind.long.color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let start = route.first {
                        Annotation("", coordinate: start) { Circle().fill(Theme.green).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2)) }
                    }
                    if let end = route.last {
                        Annotation("", coordinate: end) { Circle().fill(Theme.red).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2)) }
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel("Map of the route")
            } else {
                // Something to hang the loading on: an empty view never runs its task.
                Color.clear.frame(height: 0)
            }
        }
        .task(id: run.id) { route = await model.route(for: run) ?? [] }
    }

    /// The route with a margin around it.
    static func rect(fitting route: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = route.map(MKMapPoint.init)
        let xs = points.map(\.x), ys = points.map(\.y)
        let rect = MKMapRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0),
                             height: (ys.max() ?? 0) - (ys.min() ?? 0))
        let margin = max(rect.width, rect.height) * 0.15 + 200
        return rect.insetBy(dx: -margin, dy: -margin)
    }
}
