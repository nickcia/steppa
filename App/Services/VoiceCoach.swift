import AVFoundation
import CoreLocation
import Foundation

/// Speaks guided-run cues over whatever's playing: music or a podcast dips while it talks, then comes back.
@MainActor
final class VoiceCoach: NSObject {
    var muted = false
    private let synthesizer = AVSpeechSynthesizer()
    private var finishObserver: SpeechDelegate?

    override init() {
        super.init()
        let delegate = SpeechDelegate { [weak self] in self?.speechFinished() }
        finishObserver = delegate
        synthesizer.delegate = delegate
    }

    func speak(_ text: String) {
        guard !muted, !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        // Voice prompts duck other audio, and pause spoken audio (podcasts) rather than talking over it.
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speechFinished()
    }

    private func speechFinished() {
        guard !synthesizer.isSpeaking else { return }
        // Give the music its full volume back.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: @MainActor () -> Void
    init(onFinish: @escaping @MainActor () -> Void) { self.onFinish = onFinish }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish() }
    }
}

/// GPS during a guided run. Keeps the app running with the screen locked (so cues and the lock-screen display carry
/// on), and adds up the distance. Only runs while a guided run is in progress.
@MainActor
final class RunLocationTracker: NSObject {
    private(set) var meters = 0.0
    var onUpdate: (() -> Void)?
    private let manager = CLLocationManager()
    private var last: CLLocation?
    private var background: AnyObject?
    private let delegate = LocationDelegate()

    override init() {
        super.init()
        manager.delegate = delegate
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        delegate.onLocations = { [weak self] in self?.received($0) }
        delegate.onAuthorization = { [weak self] in self?.startIfAllowed() }
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func start() {
        meters = 0
        last = nil
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            startIfAllowed()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        (background as? CLBackgroundActivitySession)?.invalidate()
        background = nil
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
        for location in locations {
            // Ignore poor fixes and stale ones.
            guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 25,
                  abs(location.timestamp.timeIntervalSinceNow) < 10 else { continue }
            if let last {
                let step = location.distance(from: last)
                let seconds = location.timestamp.timeIntervalSince(last.timestamp)
                // Faster than 12 m/s (a 1:23/km pace) is a GPS jump, not running.
                if seconds > 0, step / seconds < 12 { meters += step }
            }
            last = location
        }
        onUpdate?()
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
