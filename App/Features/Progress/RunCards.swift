import MapKit
import SwiftUI
import PlanEngine

/// One run as a row, like the plan's rows: its route as the icon, name, a one-line summary, and distance.
struct RunCard: View {
    let run: CompletedRun
    @Environment(AppModel.self) private var model

    var body: some View {
        let workout = model.workout(for: run)
        HStack(spacing: 12) {
            RouteThumbnail(run: run, kind: workout?.kind ?? .easy)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout?.name ?? String(localized: "Run"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                // Garmin asks for its credit beneath the title wherever its data is shown.
                if let garmin = model.garminAttribution(for: run) {
                    Text(garmin).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                PlaceName(run: run)
            }
            Spacer(minLength: 8)
            ValuePill(text: model.format.distance(run.distanceMeters))
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Tue, Nov 10 · 36 min · 6:39 /km".
    private var summary: String {
        [run.date.shortDayMonth, DisplayFormat.duration(run.durationSeconds), model.format.pace(run.paceSecondsPerKm)]
            .joined(separator: " · ")
    }
}

/// The run's route drawn on a small, quiet map. Runs without a route (treadmill, or from Garmin or Intervals.icu)
/// show their workout icon instead.
struct RouteThumbnail: View {
    let run: CompletedRun
    let kind: WorkoutKind
    /// The same size and corners as a workout icon, so a map sits where an icon would.
    var size: CGFloat = 44
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                    .transition(.opacity)
            } else {
                KindIcon(kind: kind, size: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: run.id) {
            guard let route = await model.route(for: run) else { return }
            let drawn = await RouteSnapshots.image(for: run.id, route: route, size: CGSize(width: size, height: size),
                                                   scale: scale, color: UIColor(kind.color))
            withAnimation(.easeOut(duration: 0.2)) { image = drawn }
        }
        .accessibilityHidden(true)
    }
}

/// Map pictures of routes, made once each and kept while the app runs.
@MainActor
enum RouteSnapshots {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for id: String, route: [CLLocationCoordinate2D], size: CGSize, scale: CGFloat,
                      color: UIColor) async -> UIImage? {
        let key = "\(id)-\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        // Drawn at 2.5× the size and half the scale, then shown small: map labels come out small enough not to
        // crowd a thumbnail, at the same sharpness.
        let zoom = 2.5
        let canvas = CGSize(width: size.width * zoom, height: size.height * zoom)
        let options = MKMapSnapshotter.Options()
        options.region = region(fitting: route)
        options.size = canvas
        options.traitCollection = UITraitCollection(traitsFrom: [UITraitCollection(displayScale: max(1, scale / zoom * 1.5)),
                                                                UITraitCollection(userInterfaceStyle: .light)])
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = UIGraphicsImageRenderer(size: canvas, format: .init(for: options.traitCollection)).image { context in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (index, coordinate) in route.enumerated() {
                let point = snapshot.point(for: coordinate)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            UIColor.white.setStroke()
            path.lineWidth = 5 * zoom
            path.stroke()
            color.setStroke()
            path.lineWidth = 3 * zoom
            path.stroke()
        }
        cache.setObject(image, forKey: key)
        return image
    }

    /// The route's bounds, squared up and with a margin so the line doesn't touch the edges.
    static func region(fitting route: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let latSpan = (lats.max()! - lats.min()!) * 1.35
        let lonSpan = (lons.max()! - lons.min()!) * 1.35
        // Longitude degrees shrink towards the poles; square the region in metres, not degrees.
        let squash = cos(center.latitude * .pi / 180)
        let side = max(latSpan, lonSpan * squash, 0.004)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: side, longitudeDelta: side / max(squash, 0.1)))
    }
}

/// The city where a run started ("Toronto, ON"), looked up once from its route.
private struct PlaceName: View {
    let run: CompletedRun
    @Environment(AppModel.self) private var model
    @State private var name: String?

    var body: some View {
        Group {
            if let name {
                Text(name).font(.caption).foregroundStyle(Theme.secondaryInk).lineLimit(1)
            }
        }
        .task(id: run.id) {
            guard let start = await model.route(for: run)?.first else { return }
            name = await PlaceNames.name(for: run.id, at: start)
        }
    }
}

@MainActor
enum PlaceNames {
    private static var names: [String: String] = [:]

    static func name(for id: String, at coordinate: CLLocationCoordinate2D) async -> String? {
        if let known = names[id] { return known }
        // Place names use MapKit's newer geocoding; older iOS shows the card without one.
        guard #available(iOS 26.0, *) else { return nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first,
              let name = item.addressRepresentations?.cityWithContext ?? item.addressRepresentations?.cityName
        else { return nil }
        names[id] = name
        return name
    }
}

/// Every run, newest first, grouped by week.
struct AllRunsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let weeks = Dictionary(grouping: model.healthRuns) { $0.date.startOfWeek }
            .sorted { $0.key > $1.key }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if model.routeAccessNeeded { RouteAccessPrompt() }
                ForEach(weeks, id: \.key) { start, runs in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weekTitle(start)).font(.headline).foregroundStyle(Theme.ink)
                        Text((runs.count == 1 ? String(localized: "1 run") : String(localized: "\(runs.count) runs"))
                             + " · " + model.format.distance(runs.reduce(0) { $0 + $1.distanceMeters }))
                            .font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(.top, Theme.Spacing.m)
                    ForEach(runs.sorted { ($0.start ?? $0.date.date()) > ($1.start ?? $1.date.date()) }) { run in
                        NavigationLink(value: RunRoute(runID: run.id)) { RunCard(run: run) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .screenBackground()
        .navigationTitle("All runs")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "9 Nov – 15 Nov", as the plan's weeks are written.
    private func weekTitle(_ start: LocalDate) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(start.formatted(style)) – \(start.adding(days: 6).formatted(style))"
    }
}

struct AllRunsRoute: Hashable {}

/// Asks once for route access, for people who connected Health before TrackStar showed maps.
struct RouteAccessPrompt: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { Task { await model.allowRoutes() } } label: {
            Label("Show your routes on a map", systemImage: "map")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.secondary)
    }
}
