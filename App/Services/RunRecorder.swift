import CoreLocation
import Foundation

/// GPS during a guided run: distance, live pace, splits and the route.
///
/// Running keeps the app awake with the screen locked (so cues and the lock-screen display carry on). Noisy fixes
/// are dropped: poor accuracy, stale points, impossible speeds (GPS jumps) and jitter while standing still. Nothing
/// is counted while the run is paused, and the gap across a pause isn't counted either.
@MainActor
final class RunRecorder: NSObject {
    /// One accepted stretch of running, for Health's distance samples.
    struct Segment: Codable, Sendable {
        var start: Date
        var end: Date
        var meters: Double
    }

    private(set) var meters = 0.0
    /// Accepted points, in order (saved to Health as the workout route).
    private(set) var route: [CLLocation] = []
    /// Distance in roughly 10-second pieces (Health's charts need more than one sample per run).
    private(set) var segments: [Segment] = []
    /// Called after new points are counted.
    var onUpdate: (() -> Void)?
    /// Called when a whole kilometre (or mile) is passed: its number, from 1.
    var onSplit: ((Int) -> Void)?
    /// Metres per split: 1000, or a mile.
    var splitMeters = 1000.0
    var isPaused = false {
        didSet { if isPaused { last = nil } }
    }

    private let manager = CLLocationManager()
    private var last: CLLocation?
    private var background: AnyObject?
    private let delegate = LocationDelegate()
    private var openSegment: Segment?

    override init() {
        super.init()
        manager.delegate = delegate
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        delegate.onLocations = { [weak self] in self?.received($0) }
        delegate.onAuthorization = { [weak self] in self?.startIfAllowed() }
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Starts a new recording, or carries on one restored after the app was closed.
    func start(resuming saved: Saved? = nil) {
        meters = saved?.meters ?? 0
        route = saved?.route.map(\.location) ?? []
        segments = saved?.segments ?? []
        last = nil
        openSegment = nil
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            startIfAllowed()
        }
    }

    func stop() {
        closeSegment()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        (background as? CLBackgroundActivitySession)?.invalidate()
        background = nil
    }

    /// Pace over roughly the last 30 seconds, in seconds per kilometre; nil until there's enough to go on.
    func currentPace(at date: Date = .now) -> Double? {
        Self.pace(of: route, window: 30, at: date)
    }

    /// Pace over the points within `window` seconds of `date`: distance over time, ignoring breaks longer than 10 s
    /// (a pause). nil with less than 25 m or 10 s of running.
    nonisolated static func pace(of route: [CLLocation], window: Double, at date: Date) -> Double? {
        let recent = route.filter { date.timeIntervalSince($0.timestamp) <= window }
        guard recent.count >= 2 else { return nil }
        var meters = 0.0, seconds = 0.0
        for (a, b) in zip(recent, recent.dropFirst()) {
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0, dt <= 10 else { continue }
            meters += b.distance(from: a)
            seconds += dt
        }
        guard meters >= 25, seconds >= 10 else { return nil }
        return seconds / meters * 1000
    }

    private func startIfAllowed() {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        // Keeps a When In Use permission working with the screen locked for the length of the run.
        if background == nil { background = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
    }

    private func received(_ locations: [CLLocation]) {
        for location in locations { accept(location) }
        onUpdate?()
    }

    private func accept(_ location: CLLocation) {
        guard !isPaused, location.horizontalAccuracy > 0, location.horizontalAccuracy <= 20,
              abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }
        guard let previous = last else {
            last = location
            route.append(location)
            return
        }
        let step = location.distance(from: previous)
        let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return }
        // Faster than 12 m/s (1:23/km) is a GPS jump. Tiny moves are jitter: wait until there's a real step (a few
        // metres, more than the fix's own uncertainty), so standing at a crossing doesn't add distance.
        if step / seconds > 12 { return }
        if step < max(3, min(location.horizontalAccuracy, 10)) { return }
        let splitsBefore = Int(meters / splitMeters)
        meters += step
        last = location
        route.append(location)
        addToSegment(from: previous.timestamp, to: location.timestamp, meters: step)
        let splitsAfter = Int(meters / splitMeters)
        if splitsAfter > splitsBefore { onSplit?(splitsAfter) }
    }

    private func addToSegment(from start: Date, to end: Date, meters: Double) {
        if var open = openSegment {
            open.end = end
            open.meters += meters
            openSegment = open
            if end.timeIntervalSince(open.start) >= 10 { closeSegment() }
        } else {
            openSegment = Segment(start: start, end: end, meters: meters)
        }
    }

    private func closeSegment() {
        if let open = openSegment, open.meters > 0 { segments.append(open) }
        openSegment = nil
    }

    // MARK: Saving across an app restart

    struct Point: Codable, Sendable {
        var latitude: Double, longitude: Double, altitude: Double
        var horizontalAccuracy: Double, verticalAccuracy: Double
        var speed: Double, course: Double, timestamp: Date

        init(_ l: CLLocation) {
            latitude = l.coordinate.latitude; longitude = l.coordinate.longitude; altitude = l.altitude
            horizontalAccuracy = l.horizontalAccuracy; verticalAccuracy = l.verticalAccuracy
            speed = l.speed; course = l.course; timestamp = l.timestamp
        }

        var location: CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: altitude,
                       horizontalAccuracy: horizontalAccuracy, verticalAccuracy: verticalAccuracy,
                       course: course, speed: speed, timestamp: timestamp)
        }
    }

    struct Saved: Codable, Sendable {
        var meters: Double
        var route: [Point]
        var segments: [Segment]
    }

    var saved: Saved {
        Saved(meters: meters, route: route.map(Point.init), segments: segments + (openSegment.map { [$0] } ?? []))
    }
}

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    var onAuthorization: (@MainActor () -> Void)?

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.onLocations?(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.onAuthorization?() }
    }
}
