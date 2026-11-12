import Charts
import SwiftUI
import PlanEngine

/// Opens a completed run.
struct RunRoute: Hashable {
    let runID: String
}

/// One completed run: what the watch recorded, how it compared with the plan, and what it suggests.
struct RunDetailView: View {
    let runID: String
    @Environment(AppModel.self) private var model
    @State private var askingCoach = false
    @State private var sharing = false

    var body: some View {
        ScrollView {
            if let run = model.healthRuns.first(where: { $0.id == runID }) {
                content(run)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
            } else {
                Text("This run is no longer available.")
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.top, 80)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.healthRuns.contains(where: { $0.id == runID }) {
                ToolbarItem(placement: .primaryAction) {
                    Button { sharing = true } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $sharing) {
            if let run = model.healthRuns.first(where: { $0.id == runID }) { RunShareSheet(run: run) }
        }
    }

    private func content(_ run: CompletedRun) -> some View {
        let analysis = model.analysis(for: run)
        let workout = model.workout(for: run)
        let format = model.format
        let series = model.runSeries[run.id]
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                Text(workout?.name ?? String(localized: "Run"))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let garmin = model.garminAttribution(for: run) {
                    // Garmin asks for "Garmin [device]" right under the title wherever its data is shown.
                    Text(garmin)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                } else if model.dataSource(for: run) != nil {
                    Text("Data from \(model.sourceName(for: run))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .padding(.top, Theme.Spacing.s)

            // Headline numbers.
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile(format.distance(analysis.distanceMeters), String(localized: "distance"))
                    tile(DisplayFormat.duration(analysis.durationSeconds), String(localized: "time"))
                    tile(DisplayFormat.clock(format.paceSeconds(analysis.secondsPerKm)),
                         String(localized: "avg pace /\(model.units.distanceUnit)"))
                }
                if analysis.averageHeartRate != nil || analysis.averagePower != nil || analysis.averageCadence != nil {
                    GridRow {
                        tile(analysis.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "–", String(localized: "avg bpm"))
                        if let power = analysis.averagePower {
                            tile("\(Int(power.rounded())) W", String(localized: "avg power"))
                        } else {
                            tile(analysis.maxHeartRate.map { "\(Int($0.rounded()))" } ?? "–", String(localized: "max bpm"))
                        }
                        tile(analysis.averageCadence.map { "\(Int($0.rounded()))" } ?? "–", String(localized: "steps /min"))
                    }
                }
            }

            // The coach never sees data from Garmin.
            if model.showsCoach, !AppModel.isGarmin(run) {
                Button { askingCoach = true } label: {
                    HStack(spacing: 12) {
                        CoachOrb(size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analyse this run").font(.headline).foregroundStyle(.white)
                            Text("A recap and progress report from your coach")
                                .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $askingCoach) {
                    RunRecapView(run: run)
                }
            }

            if let workout {
                PlanComparisonCard(workout: workout, analysis: analysis)
            }

            RunShoesRow(run: run)

            let notes = RunNotes.make(analysis: analysis, workout: workout, format: format)
            if !notes.isEmpty {
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What this run tells you").font(.headline).foregroundStyle(Theme.ink)
                        ForEach(notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "lightbulb").foregroundStyle(Theme.amber)
                                Text(note).font(.subheadline).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if let series, !series.distance.isEmpty || !series.heartRate.isEmpty {
                RunChartsCard(series: series, units: model.units)
            }

            if !analysis.splits.isEmpty {
                SplitsCard(splits: analysis.splits, units: model.units)
            }

            if let zones = analysis.heartRateZoneSeconds, zones.reduce(0, +) > 60 {
                ZonesCard(zones: zones, heartRateZones: model.heartRateZones, maxIsSet: model.maxHeartRateIsSet)
            }


            if series == nil {
                Card(padding: 18) {
                    Label("Your watch didn't share detailed data for this run, so only the totals are shown. Apple Watch shares everything; for Garmin and others, connecting Intervals.icu in Settings brings in the full recording.",
                          systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }
}

/// Planned against actual: the target pace range and where the run landed.
private struct PlanComparisonCard: View {
    let workout: Workout
    let analysis: RunAnalysis
    @Environment(AppModel.self) private var model

    var body: some View {
        let format = model.format
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    KindIcon(kind: workout.kind, size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Planned").font(.caption).foregroundStyle(Theme.secondaryInk)
                        Text("\(workout.name) · \(WorkoutDescriber(format: format).summary(workout))")
                            .font(.headline).foregroundStyle(Theme.ink)
                    }
                }
                if let comparison = PlannedComparison.compare(workout, analysis) {
                    let range = PaceRange(fast: comparison.targetFast, slow: comparison.targetSlow)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Target \(format.paceRange(range))").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        Spacer()
                        Text(verdict(comparison.verdict))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(comparison.verdict == .onTarget ? Theme.green : Theme.amber, in: Capsule())
                    }
                    Text("You averaged \(format.pace(comparison.actualSecondsPerKm))")
                        .font(.subheadline).foregroundStyle(Theme.ink)
                } else {
                    let planned = format.distance(workout.totalMeters)
                    Text("Planned \(planned) · you ran \(format.distance(analysis.distanceMeters))")
                        .font(.subheadline).foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func verdict(_ verdict: PlannedComparison.Verdict) -> String {
        switch verdict {
        case .onTarget: String(localized: "On target")
        case .faster: String(localized: "Faster than planned")
        case .slower: String(localized: "Slower than planned")
        }
    }
}

/// Pace and heart rate over the run.
private struct RunChartsCard: View {
    let series: RunSeries
    let units: UnitSystem

    private struct Sample: Identifiable {
        let id: Int
        let minutes: Double
        let value: Double
    }

    /// Pace in seconds per display unit, smoothed over about a minute so GPS noise doesn't dominate.
    private var pace: [Sample] {
        let points = series.distance
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

    private var heart: [Sample] {
        series.heartRate.enumerated().map { Sample(id: $0.offset, minutes: $0.element.t / 60, value: $0.element.v) }
    }

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                if !pace.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pace").font(.headline).foregroundStyle(Theme.ink)
                        Chart(pace) {
                            LineMark(x: .value("Minutes", $0.minutes), y: .value("Pace", $0.value))
                                .foregroundStyle(WorkoutKind.long.color)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine()
                                AxisValueLabel { Text(value.as(Double.self).map { DisplayFormat.clock($0) } ?? "") }
                            }
                        }
                        .chartXAxisLabel("min")
                        .frame(height: 140)
                    }
                }
                if !heart.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Heart rate").font(.headline).foregroundStyle(Theme.ink)
                        Chart(heart) {
                            LineMark(x: .value("Minutes", $0.minutes), y: .value("bpm", $0.value))
                                .foregroundStyle(Theme.red)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxisLabel("min")
                        .frame(height: 120)
                    }
                }
            }
        }
    }
}

private struct SplitsCard: View {
    let splits: [RunAnalysis.Split]
    let units: UnitSystem

    var body: some View {
        let format = DisplayFormat(units: units)
        let paces = splits.map(\.secondsPerKm)
        let fastest = paces.min() ?? 0, slowest = paces.max() ?? 1
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Splits").font(.headline).foregroundStyle(Theme.ink)
                ForEach(splits, id: \.index) { split in
                    HStack(spacing: 12) {
                        Text(split.meters < units.metersPerUnit * 0.95
                             ? format.distance(split.meters) : "\(split.index)")
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .leading)
                            .foregroundStyle(Theme.secondaryInk)
                        Text(DisplayFormat.clock(format.paceSeconds(split.secondsPerKm)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .leading)
                            .foregroundStyle(Theme.ink)
                        GeometryReader { geometry in
                            // Longer bar = faster split.
                            let share = slowest > fastest ? (slowest - split.secondsPerKm) / (slowest - fastest) : 1
                            Capsule()
                                .fill(split.secondsPerKm == fastest ? Theme.green : WorkoutKind.long.color.opacity(0.7))
                                .frame(width: max(8, geometry.size.width * (0.35 + 0.65 * share)))
                        }
                        .frame(height: 8)
                        Text(split.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                            .foregroundStyle(Theme.red)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ZonesCard: View {
    let zones: [Double]
    let heartRateZones: HeartRateZones?
    let maxIsSet: Bool

    private static let colors: [Color] = [Color(hex: 0xA9C6FF), Theme.green, Theme.amber, Color(hex: 0xF5894A), Theme.red]

    var body: some View {
        let total = max(zones.reduce(0, +), 1)
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Heart-rate zones").font(.headline).foregroundStyle(Theme.ink)
                    Spacer()
                    if let heartRateZones {
                        Text("max \(Int(heartRateZones.maxHeartRate)) bpm").font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                }
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(0..<zones.count, id: \.self) { i in
                            Self.colors[i].frame(width: max(0, geometry.size.width * zones[i] / total - 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                ForEach(0..<zones.count, id: \.self) { i in
                    HStack {
                        Circle().fill(Self.colors[i]).frame(width: 8, height: 8)
                        Text(name(i)).font(.subheadline).foregroundStyle(Theme.ink)
                        if let range = heartRateZones?.range(ofZone: i) {
                            Text("\(Int(range.lowerBound))–\(Int(range.upperBound))")
                                .font(.caption).monospacedDigit().foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Text(DisplayFormat.duration(zones[i]))
                            .font(.subheadline).monospacedDigit().foregroundStyle(Theme.secondaryInk)
                    }
                }
                Text(sourceNote)
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    private var sourceNote: String {
        switch heartRateZones?.source {
        case .imported?: String(localized: "Using the zones from your watch, through Intervals.icu.")
        case .custom?: String(localized: "Using the zones you set in Settings.")
        default: maxIsSet ? String(localized: "Based on the maximum heart rate you set in Settings.")
                          : String(localized: "Automatic zones, from the highest heart rate in your runs over the past year (or your age). You can import your watch's zones or set your own in Settings.")
        }
    }

    private func name(_ zone: Int) -> String {
        switch zone {
        case 0: String(localized: "1 · Recovery")
        case 1: String(localized: "2 · Easy")
        case 2: String(localized: "3 · Steady")
        case 3: String(localized: "4 · Threshold")
        default: String(localized: "5 · Hard")
        }
    }
}

/// Plain-English observations from a run's data. Rules, not AI; each says what it's based on.
enum RunNotes {
    static func make(analysis: RunAnalysis, workout: Workout?, format: DisplayFormat) -> [String] {
        var notes: [String] = []
        let steady = workout.map { $0.kind == .easy || $0.kind == .long } ?? false

        if let workout, let comparison = PlannedComparison.compare(workout, analysis) {
            switch comparison.verdict {
            case .faster:
                notes.append(String(localized: "This was quicker than your easy pace. Easy days build fitness best when they really are easy; save the speed for session days."))
            case .slower:
                notes.append(String(localized: "Slower than planned. That's fine on a tired day or a hilly route. If it keeps happening, the plan will ease your paces."))
            case .onTarget:
                notes.append(String(localized: "Right in your target range. Nicely judged."))
            }
        }
        if let drift = analysis.heartRateDrift, steady, drift > 0.05 {
            notes.append(String(localized: "Your heart rate rose \(Int((drift * 100).rounded()))% at the same pace from the first half to the second. Heat, dehydration or a pace a little too quick for today are the usual causes."))
        } else if let drift = analysis.heartRateDrift, steady, drift < 0.03 {
            notes.append(String(localized: "Heart rate stayed steady for the whole run: a good sign of aerobic fitness."))
        }
        if let zones = analysis.heartRateZoneSeconds, steady {
            let total = max(zones.reduce(0, +), 1)
            let hard = (zones[3] + zones[4]) / total
            if hard > 0.2 {
                notes.append(String(localized: "\(Int((hard * 100).rounded()))% of this run was in zone 4 or 5. For an easy run, aim to keep almost all of it in zones 1–2."))
            }
        }
        if let variability = analysis.paceVariability {
            if variability < 0.03 {
                notes.append(String(localized: "Very even pacing from split to split."))
            } else if variability > 0.08, steady {
                notes.append(String(localized: "Your splits varied quite a bit. Hills or stops can explain it; otherwise, try settling into one rhythm."))
            }
        }
        if let cadence = analysis.averageCadence, cadence < 155 {
            notes.append(String(localized: "Your cadence averaged \(Int(cadence.rounded())) steps a minute. Slightly quicker, shorter steps often feel smoother; there's no need to force it."))
        }
        return notes
    }
}
