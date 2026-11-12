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
    /// "Garmin Forerunner 265" for a Garmin run: Garmin asks for it on every image of its data.
    var attribution: String? = nil
    var shape: Shape = .square

    /// The image's proportions. Strava's feed shows an activity's photo as a square and cuts the sides off portrait
    /// ones, so square is the default; portrait suits Instagram and messages.
    enum Shape: String, CaseIterable, Identifiable {
        case square, portrait
        var id: Self { self }

        /// Points; rendered at 3×: 1080 × 1080, or 1080 × 1350 (4:5).
        var size: CGSize {
            switch self {
            case .square: CGSize(width: 360, height: 360)
            case .portrait: CGSize(width: 360, height: 450)
            }
        }

        var name: String {
            switch self {
            case .square: String(localized: "Square, for Strava")
            case .portrait: String(localized: "Portrait")
            }
        }
    }

    private var compact: Bool { shape == .square }

    var body: some View {
        let kind = workout?.kind ?? .easy
        VStack(alignment: .leading, spacing: compact ? 11 : 14) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondaryInk)
                    if let attribution {
                        Text(attribution)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Spacer()
                KindIcon(kind: kind, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout?.name ?? String(localized: "Run"))
                    .font(.system(size: compact ? 26 : 30, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.ink)
                if let workout {
                    Text(WorkoutDescriber(format: format).summary(workout))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(1)
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
            if !compact { zones }

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
        .padding(compact ? 20 : 22)
        .frame(width: shape.size.width, height: shape.size.height, alignment: .topLeading)
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
                                .frame(height: (compact ? 16 : 24) + (compact ? 34 : 46) * share)
                            Text(DisplayFormat.clock(format.paceSeconds(split.secondsPerKm)))
                                .font(.system(size: 8, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondaryInk)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: compact ? 64 : 86, alignment: .bottom)
            }
            .padding(compact ? 12 : 14)
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

    /// The card as a 1080-pixel-wide image.
    @MainActor func image() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(shape.size)
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

/// Preview a run's image, pick its shape, then save it to Photos or share it (Strava, Instagram, a message).
struct RunShareSheet: View {
    let run: CompletedRun
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var shape: RunShareCard.Shape = .square
    @State private var saved: Bool?

    private var card: RunShareCard {
        RunShareCard(run: run, analysis: model.analysis(for: run), workout: model.workout(for: run),
                     format: model.format, attribution: model.garminAttribution(for: run), shape: shape)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                Picker("Shape", selection: $shape) {
                    ForEach(RunShareCard.Shape.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                card
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .animation(.snappy, value: shape)
                Spacer(minLength: 0)
                if let image = card.image() {
                    VStack(spacing: 10) {
                        Button {
                            PhotoSaver.save(image) { saved = $0 }
                        } label: {
                            Label(saved == true ? String(localized: "Saved to Photos") : String(localized: "Save to Photos"),
                                  systemImage: saved == true ? "checkmark" : "square.and.arrow.down")
                        }
                        .buttonStyle(.primary)
                        ShareLink(item: RunShareImage(image: image, name: "Run \(run.date)"),
                                  preview: SharePreview(model.workout(for: run)?.name ?? String(localized: "Run"),
                                                        image: Image(uiImage: image))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.secondary)
                    }
                }
                Text(saved == false
                     ? String(localized: "TrackStar isn't allowed to add to Photos. You can allow it in Settings › TrackStar › Photos, or use Share › Save Image.")
                     : String(localized: "On Strava, open the activity, tap Edit, then add the photo from your library."))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Spacing.m)
            .screenBackground()
            .navigationTitle("Share image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: shape) { saved = nil }
        }
    }
}

/// Adds an image to the photo library (add-only access: TrackStar never sees the athlete's photos).
@MainActor
enum PhotoSaver {
    static func save(_ image: UIImage, completion: @escaping @MainActor (Bool) -> Void) {
        let target = Completion(completion)
        UIImageWriteToSavedPhotosAlbum(image, target, #selector(Completion.done(_:error:context:)), nil)
        // UIKit holds the target only weakly; keep it until it calls back.
        pending.insert(target)
    }

    fileprivate static var pending: Set<Completion> = []

    fileprivate final class Completion: NSObject {
        let completion: @MainActor (Bool) -> Void
        init(_ completion: @escaping @MainActor (Bool) -> Void) { self.completion = completion }

        @objc func done(_ image: UIImage, error: Error?, context: UnsafeMutableRawPointer?) {
            let ok = error == nil
            MainActor.assumeIsolated {
                completion(ok)
                PhotoSaver.pending.remove(self)
            }
        }
    }
}
