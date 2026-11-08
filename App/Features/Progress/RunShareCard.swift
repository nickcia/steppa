import SwiftUI
import UniformTypeIdentifiers
import PlanEngine

/// A run as a picture for Strava, Instagram or a message: the session, the key numbers, splits and heart-rate
/// zones. Made on the phone; sharing goes through the iPhone share sheet, so nothing passes through TrackStar.
struct RunShareCard: View {
    let run: CompletedRun
    let analysis: RunAnalysis
    let workout: Workout?
    let format: DisplayFormat

    /// Points; rendered at 3× for a 1080 × 1350 image (4:5, Instagram's portrait size).
    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        let kind = workout?.kind ?? .easy
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(run.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(kind.gradient, in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout?.kind.name ?? String(localized: "Run"))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let workout {
                    Text(WorkoutDescriber(format: format).summary(workout))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }

            HStack(spacing: 0) {
                stat(format.distance(analysis.distanceMeters), String(localized: "distance"))
                stat(DisplayFormat.duration(analysis.durationSeconds), String(localized: "time"))
                stat(DisplayFormat.clock(format.paceSeconds(analysis.secondsPerKm)),
                     String(localized: "pace /\(format.units.distanceUnit)"))
                if let hr = analysis.averageHeartRate {
                    stat("\(Int(hr.rounded()))", String(localized: "avg bpm"))
                }
            }

            if let workout, let comparison = PlannedComparison.compare(workout, analysis) {
                Text(verdict(comparison.verdict))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(comparison.verdict == .onTarget ? Theme.green : Theme.amber, in: Capsule())
            }

            splits
            Spacer(minLength: 0)
            zones

            HStack {
                Text("Planned and coached by TrackStar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                Spacer()
                Text("Free & open source")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(22)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Theme.background)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 19, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Up to 12 splits as bars: taller is faster.
    @ViewBuilder private var splits: some View {
        let shown = Array(analysis.splits.prefix(12))
        if shown.count >= 2 {
            let paces = shown.map(\.secondsPerKm)
            let fastest = paces.min() ?? 0, slowest = paces.max() ?? 1
            VStack(alignment: .leading, spacing: 6) {
                Text("Splits").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(shown, id: \.index) { split in
                        let share = slowest > fastest ? (slowest - split.secondsPerKm) / (slowest - fastest) : 1
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(split.secondsPerKm == fastest ? Theme.green : WorkoutKind.long.color.opacity(0.75))
                                .frame(height: 24 + 46 * share)
                            Text(DisplayFormat.clock(format.paceSeconds(split.secondsPerKm)))
                                .font(.system(size: 8, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryInk)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 86, alignment: .bottom)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder private var zones: some View {
        if let zones = analysis.heartRateZoneSeconds, zones.reduce(0, +) > 60 {
            let total = zones.reduce(0, +)
            let colors: [Color] = [Color(hex: 0xA9C6FF), Theme.green, Theme.amber, Color(hex: 0xF5894A), Theme.red]
            VStack(alignment: .leading, spacing: 6) {
                Text("Heart-rate zones").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(0..<zones.count, id: \.self) { i in
                            colors[i].frame(width: max(0, geometry.size.width * zones[i] / total - 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
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

    /// The card as a 1080 × 1350 image.
    @MainActor func image() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(Self.size)
        return renderer.uiImage
    }
}

/// The share sheet's item: the card image, named for the run.
struct RunShareImage: Transferable {
    let image: UIImage
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
            .suggestedFileName { "\($0.name).png" }
    }
}
