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
