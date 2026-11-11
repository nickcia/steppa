import AVFoundation
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
        synthesizer.speak(Self.utterance(text))
    }

    // MARK: Voice and speed (Settings › Run coach voice)

    static let voiceKey = "voice.identifier"
    static let speedKey = "voice.speed"

    /// How fast cues are spoken.
    enum Speed: String, CaseIterable, Identifiable {
        case slower, normal, faster
        var id: String { rawValue }
        var name: String {
            switch self {
            case .slower: String(localized: "Slower")
            case .normal: String(localized: "Normal")
            case .faster: String(localized: "Faster")
            }
        }
        var rate: Float {
            switch self {
            case .slower: AVSpeechUtteranceDefaultSpeechRate * 0.88
            case .normal: AVSpeechUtteranceDefaultSpeechRate
            case .faster: AVSpeechUtteranceDefaultSpeechRate * 1.12
            }
        }
    }

    /// The voice the athlete picked, if it's still on the phone; else the phone's own voice for its language.
    static var voice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: voiceKey), let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        return AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
    }

    static var speed: Speed {
        UserDefaults.standard.string(forKey: speedKey).flatMap(Speed.init(rawValue:)) ?? .normal
    }

    /// A cue in the chosen voice and speed (also used to preview voices in Settings).
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = speed.rate
        return utterance
    }

    /// Voices installed for the phone's language, best quality first. Enhanced and Premium voices are downloaded in
    /// the iPhone's Settings › Accessibility › Spoken Content › Voices.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
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
