import Charts
import SwiftUI
import PlanEngine

/// Bar chart of nominal weekly volume, coloured by phase.
struct WeeklyVolumeChart: View {
    let plan: TrainingPlan
    var highlight: LocalDate?
    @Environment(\.unitSystem) private var units

    private struct Bar: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let distance: Double
        let color: Color
    }

    /// Precomputed bars. Explicit x and y extents matter: on a numeric x axis `width: .ratio` gives
    /// zero-width bars, and xStart/xEnd with a single y draws a horizontal band, so bars are RectangleMarks with all four edges.
    private var bars: [Bar] {
        let currentWeek = highlight?.startOfWeek
        return plan.weeks.map { week in
            let x = Double(week.index + 1)
            let emphasised = currentWeek == nil || week.startDate == currentWeek
            return Bar(id: week.index, start: x - 0.36, end: x + 0.36,
                       distance: week.plannedMeters / units.metersPerUnit,
                       color: week.phase.color.opacity(emphasised ? 1 : 0.55))
        }
    }

    /// Label every 2nd or 4th week so the axis stays readable.
    private var weekTicks: [Int] {
        let step = plan.weeks.count > 12 ? 4 : 2
        return Array(stride(from: 1, through: plan.weeks.count, by: step))
    }

    // A little extra room on the right so the last week label isn't clipped.
    private var xDomain: ClosedRange<Double> { 0.5...(Double(plan.weeks.count) + 1) }

    var body: some View {
        Chart(bars) { bar in
            RectangleMark(xStart: .value("Week", bar.start), xEnd: .value("Week", bar.end),
                          yStart: .value("Distance", 0.0), yEnd: .value("Distance", bar.distance))
                .foregroundStyle(bar.color)
                .cornerRadius(3)
        }
        .chartXScale(domain: xDomain)
        .chartXAxis { AxisMarks(values: weekTicks) { value in AxisValueLabel { weekLabel(value) } } }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel { distanceLabel(value) }
            }
        }
        .chartYAxisLabel(units.distanceUnit)
        .frame(height: 170)
        .accessibilityLabel(Text("Weekly distance by week"))
    }

    private func weekLabel(_ value: AxisValue) -> Text {
        Text(value.as(Int.self).map { String(localized: "W\($0)") } ?? "")
    }

    private func distanceLabel(_ value: AxisValue) -> Text {
        Text(value.as(Double.self).map { String(Int($0)) } ?? "")
    }
}

struct PhaseLegend: View {
    let phases: [Phase]

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ForEach(phases, id: \.self) { phase in
                HStack(spacing: 6) {
                    Circle().fill(phase.color).frame(width: 8, height: 8)
                    Text(phase.name).font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
    }
}

/// Warm-up, blocks and cool-down, with pace ranges.
struct WorkoutStepsView: View {
    let workout: Workout
    @Environment(\.unitSystem) private var units

    var body: some View {
        let describer = WorkoutDescriber(format: DisplayFormat(units: units))
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(describer.sections(workout)) { section in
                switch section {
                case .single(let line):
                    StepRow(line: line)
                case .repeated(let times, let lines):
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("\(times) ×")
                            .font(.headline.weight(.heavy))
                            .fontDesign(.rounded)
                            .foregroundStyle(Theme.ink)
                        ForEach(lines) { StepRow(line: $0) }
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.subtle, lineWidth: 1.5))
                }
            }
        }
    }
}

private struct StepRow: View {
    let line: WorkoutDescriber.Line

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(line.zone?.color ?? Theme.subtle)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.subheadline.weight(line.isRecovery ? .regular : .semibold))
                    .foregroundStyle(line.isRecovery ? Theme.secondaryInk : Theme.ink)
                if let detail = line.detail {
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

extension PlanWarning {
    func message(_ format: DisplayFormat) -> String {
        switch self {
        case .shortPlan(let weeks, let recommended):
            String(localized: "You have \(weeks) weeks; \(recommended) is ideal for this distance. The plan is compressed, so aim to arrive healthy rather than chase a time.")
        case .lowStartingVolume(let meters):
            String(localized: "This race usually starts from at least \(format.distance(meters)) a week. The plan builds gradually from where you are; a later race or shorter distance would give you more room.")
        case .volumeLimitedByAvailability:
            String(localized: "Your available days limit how much the plan can build. Adding a run day would allow more volume.")
        case .ambitiousGoal(let predicted):
            String(localized: "Your goal is faster than your current fitness suggests (around \(DisplayFormat.clock(predicted))). Paces start from where you are now and adjust as you get fitter.")
        case .estimatedFitness:
            String(localized: "Without a recent race, your paces are an estimate. They'll adjust as you complete runs.")
        }
    }
}

/// Short reminder shown in onboarding and settings.
struct DisclaimerText: View {
    var body: some View {
        Text("This app gives general training guidance, not medical advice. Talk to a doctor before starting a new training programme, especially if you have a health condition, an injury or are returning after a long break. Stop and seek advice if you feel pain, dizziness or chest discomfort.")
            .font(.footnote)
            .foregroundStyle(Theme.secondaryInk)
    }
}
