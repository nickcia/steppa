import ActivityKit
import Foundation
import Observation
import PlanEngine

/// Runs a workout on the phone, step by step: a countdown for each step, spoken cues, distance from GPS, and a Live
/// Activity on the lock screen and in the Dynamic Island.
///
/// All timing comes from the clock (when each step started, minus pauses), so nothing drifts and the run catches up
/// correctly if iOS ever suspends the app for a moment.
@Observable
@MainActor
final class GuidedRunController {
    static let shared = GuidedRunController()

    struct Session {
        let workout: Workout
        let name: String
        let steps: [GuidedStep]
        let format: DisplayFormat
        var index = 0
        let startedAt: Date
        var stepStartedAt: Date
        /// Paused time within the current step, and in the whole run.
        var pausedInStep = 0.0
        var pausedTotal = 0.0
        var pausedAt: Date?
        var stepStartMeters = 0.0
        var spokenMidCues: Set<Int> = []
        var finishedAt: Date?

        var step: GuidedStep { steps[index] }
        var next: GuidedStep? { index + 1 < steps.count ? steps[index + 1] : nil }
        var isPaused: Bool { pausedAt != nil }
        var isFinished: Bool { finishedAt != nil }
    }

    private(set) var session: Session?
    private(set) var meters = 0.0
    var muted = false { didSet { voice.muted = muted } }
    /// Location wasn't allowed: cues only carry on while the app is open.
    private(set) var locationDenied = false

    private let voice = VoiceCoach()
    private let location = RunLocationTracker()
    private var ticker: Task<Void, Never>?
    private var activity: Activity<GuidedRunAttributes>?
    private var lastActivityMeters = 0.0

    private init() {
        location.onUpdate = { [weak self] in
            guard let self else { return }
            meters = location.meters
            tick()
        }
        NotificationCenter.default.addObserver(forName: .guidedRunCommand, object: nil, queue: .main) { note in
            let command = note.object as? String
            MainActor.assumeIsolated {
                switch command {
                case "pause": GuidedRunController.shared.togglePause()
                case "skip": GuidedRunController.shared.skip()
                default: break
                }
            }
        }
    }

    // MARK: Controls

    func start(_ workout: Workout, describer: WorkoutDescriber) {
        let steps = GuidedTimeline.steps(for: workout, describer: describer)
        guard !steps.isEmpty else { return }
        let now = Date()
        session = Session(workout: workout, name: workout.kind.name, steps: steps, format: describer.format,
                          startedAt: now, stepStartedAt: now)
        meters = 0
        location.start()
        locationDenied = location.isDenied
        voice.speak(GuidedTimeline.startCue(steps, index: 0))
        startActivity()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func togglePause() {
        guard var s = session, !s.isFinished else { return }
        let now = Date()
        if let pausedAt = s.pausedAt {
            let paused = now.timeIntervalSince(pausedAt)
            s.pausedInStep += paused
            s.pausedTotal += paused
            s.pausedAt = nil
            session = s
            voice.speak(String(localized: "Resuming."))
        } else {
            s.pausedAt = now
            session = s
            voice.speak(String(localized: "Paused."))
        }
        updateActivity()
    }

    func skip() {
        guard let s = session, !s.isFinished else { return }
        advance(from: s.index)
    }

    /// Ends the run early, or closes it after it's finished.
    func end() {
        guard var s = session else { return }
        if !s.isFinished {
            s.finishedAt = Date()
            session = s
        }
        stopTracking()
    }

    /// Closes the summary.
    func close() {
        end()
        session = nil
    }

    // MARK: Progress

    /// Seconds into the current step, not counting pauses.
    func elapsedInStep(at date: Date = .now) -> Double {
        guard let s = session else { return 0 }
        let end = s.finishedAt ?? s.pausedAt ?? date
        return max(0, end.timeIntervalSince(s.stepStartedAt) - s.pausedInStep)
    }

    /// Whole run so far, not counting pauses.
    func elapsedTotal(at date: Date = .now) -> Double {
        guard let s = session else { return 0 }
        let end = s.finishedAt ?? date
        let pausedNow = s.pausedAt.map { end.timeIntervalSince($0) } ?? 0
        return max(0, end.timeIntervalSince(s.startedAt) - s.pausedTotal - pausedNow)
    }

    /// Distance into the current step, when GPS is measuring it.
    var metersInStep: Double { max(0, meters - (session?.stepStartMeters ?? 0)) }

    /// Distance steps follow GPS once it has measured something; otherwise (no permission, no fix yet) the estimated time.
    private var usesGPSForStep: Bool { !locationDenied && meters > 0 }

    /// Seconds left in the step (estimated for a distance step followed by GPS).
    func remainingInStep(at date: Date = .now) -> Double {
        guard let s = session else { return 0 }
        let step = s.step
        if let target = step.meters, usesGPSForStep {
            let left = max(0, target - metersInStep)
            return left / target * step.seconds
        }
        return max(0, step.seconds - elapsedInStep(at: date))
    }

    /// 0…1 through the current step.
    func stepProgress(at date: Date = .now) -> Double {
        guard let s = session, s.step.seconds > 0 else { return 0 }
        if let target = s.step.meters, usesGPSForStep { return min(1, metersInStep / target) }
        return min(1, elapsedInStep(at: date) / s.step.seconds)
    }

    private func tick() {
        guard let s = session, !s.isFinished, !s.isPaused else { return }
        let elapsed = elapsedInStep()
        for (i, cue) in GuidedTimeline.midCues(s.steps, index: s.index).enumerated()
            where elapsed >= cue.at && !s.spokenMidCues.contains(i) {
            session?.spokenMidCues.insert(i)
            voice.speak(cue.text)
        }
        let done: Bool = if let target = s.step.meters, usesGPSForStep { metersInStep >= target } else { elapsed >= s.step.seconds }
        if done {
            advance(from: s.index)
        } else if abs(meters - lastActivityMeters) >= 50 {
            updateActivity()
        }
    }

    private func advance(from index: Int) {
        guard var s = session, s.index == index else { return }
        let now = Date()
        if index + 1 >= s.steps.count {
            s.finishedAt = now
            session = s
            voice.speak(GuidedTimeline.finishCue)
            stopTracking()
            return
        }
        // A step finished on time starts the next one exactly when it ended, so a late tick doesn't drift.
        let planned = s.stepStartedAt.addingTimeInterval(s.step.seconds + s.pausedInStep)
        let finishedOnTime = s.step.meters == nil && planned <= now && now.timeIntervalSince(planned) < 5
        s.index += 1
        s.stepStartedAt = finishedOnTime ? planned : now
        if let pausedAt = s.pausedAt {
            // Skipped while paused: the new step starts paused.
            s.pausedTotal += now.timeIntervalSince(pausedAt)
            s.pausedAt = now
            s.stepStartedAt = now
        }
        s.pausedInStep = 0
        s.stepStartMeters = meters
        s.spokenMidCues = []
        session = s
        voice.speak(GuidedTimeline.startCue(s.steps, index: s.index))
        updateActivity()
    }

    private func stopTracking() {
        ticker?.cancel()
        ticker = nil
        location.stop()
        endActivity()
    }

    // MARK: Live Activity

    private func content() -> GuidedRunAttributes.ContentState? {
        guard let s = session else { return nil }
        let step = s.step
        let remaining = remainingInStep()
        let detail = step.rep.map { String(localized: "\(step.title) \($0.index) of \($0.count)") } ?? step.detail
        return .init(title: step.title, detail: detail,
                     stepEnds: Date().addingTimeInterval(remaining),
                     pausedRemaining: s.isPaused ? remaining : nil,
                     next: s.next?.short(s.format), stepNumber: s.index + 1, stepCount: s.steps.count,
                     distanceMeters: meters, metric: s.format.units == .metric, tint: step.tint)
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let state = content(), let s = session else { return }
        activity = try? Activity.request(attributes: GuidedRunAttributes(workoutName: s.name),
                                         content: .init(state: state, staleDate: nil))
    }

    private func updateActivity() {
        guard let current = activity, let state = content() else { return }
        lastActivityMeters = meters
        // ActivityKit's Activity isn't marked Sendable, but updating it from any thread is safe.
        nonisolated(unsafe) let activity = current
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let current = activity else { return }
        self.activity = nil
        let state = content()
        nonisolated(unsafe) let activity = current
        Task {
            await activity.end(state.map { .init(state: $0, staleDate: nil) }, dismissalPolicy: .immediate)
        }
    }
}
