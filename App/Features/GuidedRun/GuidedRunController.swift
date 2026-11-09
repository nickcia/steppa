import ActivityKit
import AVFoundation
import CoreLocation
import Foundation
import Observation
import PlanEngine

/// Runs a workout on the phone, step by step: a countdown for each step, spoken cues (steps, pace, splits), distance
/// and pace from GPS, and a Live Activity on the lock screen and in the Dynamic Island. At the end it hands over a
/// recording to save to Apple Health.
///
/// All timing comes from the clock (when each step started, minus pauses), so nothing drifts and the run catches up
/// correctly if iOS suspends the app for a moment. The run is saved as it goes, so if iOS closes the app mid-run it
/// picks up where it was when reopened.
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
        /// Finished pauses, for Health.
        var pauses: [DateInterval] = []
        var stepStartMeters = 0.0
        var spokenMidCues: Set<Int> = []
        var lastPaceCheck: Date?
        var confirmedPaceThisStep = false
        var lastSplitElapsed = 0.0
        var finishedAt: Date?

        var step: GuidedStep { steps[index] }
        var next: GuidedStep? { index + 1 < steps.count ? steps[index + 1] : nil }
        var isPaused: Bool { pausedAt != nil }
        var isFinished: Bool { finishedAt != nil }
        var completedAllSteps: Bool { isFinished && index + 1 >= steps.count && finishedNormally }
        var finishedNormally = false
    }

    private(set) var session: Session?
    private(set) var meters = 0.0
    var muted = false { didSet { voice.muted = muted } }
    /// Location wasn't allowed: cues only carry on while the app is open.
    private(set) var locationDenied = false
    /// Set when a run was picked up again after the app was closed.
    private(set) var resumedAfterRestart = false

    private let voice = VoiceCoach()
    private let recorder = RunRecorder()
    private var ticker: Task<Void, Never>?
    private var activity: Activity<GuidedRunAttributes>?
    private var lastActivityMeters = 0.0
    private var lastSaved = Date.distantPast

    private init() {
        recorder.onUpdate = { [weak self] in
            guard let self else { return }
            meters = recorder.meters
            tick()
        }
        recorder.onSplit = { [weak self] number in self?.split(number) }
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
        // A phone call or Siri cuts the voice off; the run itself carries on (most runners keep moving).
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .began
            MainActor.assumeIsolated {
                if began { GuidedRunController.shared.voice.stop() }
            }
        }
    }

    // MARK: Controls

    func start(_ workout: Workout, describer: WorkoutDescriber) {
        let steps = GuidedTimeline.steps(for: workout, describer: describer)
        guard !steps.isEmpty else { return }
        let now = Date()
        session = Session(workout: workout, name: workout.name, steps: steps, format: describer.format,
                          startedAt: now, stepStartedAt: now)
        meters = 0
        resumedAfterRestart = false
        recorder.splitMeters = describer.format.units.metersPerUnit
        recorder.isPaused = false
        recorder.start()
        locationDenied = recorder.isDenied
        voice.speak(GuidedTimeline.startCue(steps, index: 0))
        startActivity()
        startTicker()
        save()
    }

    func togglePause() {
        guard var s = session, !s.isFinished else { return }
        let now = Date()
        if let pausedAt = s.pausedAt {
            let paused = now.timeIntervalSince(pausedAt)
            s.pausedInStep += paused
            s.pausedTotal += paused
            s.pauses.append(DateInterval(start: pausedAt, end: now))
            s.pausedAt = nil
            s.lastPaceCheck = now
            session = s
            recorder.isPaused = false
            voice.speak(String(localized: "Resuming."))
        } else {
            s.pausedAt = now
            session = s
            recorder.isPaused = true
            voice.speak(String(localized: "Paused."))
        }
        updateActivity()
        save()
    }

    func skip() {
        guard let s = session, !s.isFinished else { return }
        advance(from: s.index)
    }

    /// Ends the run early, or closes it after it's finished.
    func end() {
        guard var s = session else { return }
        if !s.isFinished {
            finishPause(&s, at: Date())
            s.finishedAt = Date()
            session = s
        }
        stopTracking()
    }

    /// Closes the summary.
    func close() {
        end()
        session = nil
        Self.clearSaved()
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

    /// Pace over the last 30 seconds or so, in seconds per kilometre.
    func currentPace(at date: Date = .now) -> Double? {
        guard session?.isPaused == false else { return nil }
        return recorder.currentPace(at: date)
    }

    /// Average pace for the run so far.
    func averagePace(at date: Date = .now) -> Double? {
        guard meters >= 100 else { return nil }
        return elapsedTotal(at: date) / meters * 1000
    }

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
            return
        }
        checkPace(elapsed: elapsed)
        if abs(meters - lastActivityMeters) >= 50 { updateActivity() }
        if Date().timeIntervalSince(lastSaved) >= 20 { save() }
    }

    /// On steps with a pace target: after the first 40 seconds, a check every 45 seconds. Says something only when the
    /// pace is off, plus one "right on pace" on longer steps, so it isn't chatty.
    private func checkPace(elapsed: Double) {
        guard let s = session, let target = s.step.target, elapsed >= 40, remainingInStep() >= 20,
              let pace = recorder.currentPace() else { return }
        let now = Date()
        if let last = s.lastPaceCheck, now.timeIntervalSince(last) < 45 { return }
        session?.lastPaceCheck = now
        let verdict = GuidedTimeline.paceVerdict(current: pace, target: target)
        if verdict == .onPace {
            guard !s.confirmedPaceThisStep, s.step.seconds >= 180 else { return }
            session?.confirmedPaceThisStep = true
        }
        voice.speak(GuidedTimeline.paceCue(verdict, target: target, units: s.format.units))
    }

    private func split(_ number: Int) {
        guard let s = session, !s.isFinished else { return }
        let elapsed = elapsedTotal()
        session?.lastSplitElapsed = elapsed
        voice.speak(GuidedTimeline.splitCue(number: number, seconds: elapsed - s.lastSplitElapsed, units: s.format.units))
    }

    private func advance(from index: Int, silently: Bool = false) {
        guard var s = session, s.index == index else { return }
        let now = Date()
        if index + 1 >= s.steps.count {
            finishPause(&s, at: now)
            s.finishedAt = now
            s.finishedNormally = true
            session = s
            if !silently { voice.speak(GuidedTimeline.finishCue) }
            stopTracking()
            save()
            return
        }
        // A step finished on time starts the next one exactly when it ended, so a late tick doesn't drift.
        let planned = s.stepStartedAt.addingTimeInterval(s.step.seconds + s.pausedInStep)
        let finishedOnTime = s.step.meters == nil && planned <= now && (silently || now.timeIntervalSince(planned) < 5)
        s.index += 1
        s.stepStartedAt = finishedOnTime ? planned : now
        if let pausedAt = s.pausedAt {
            // Skipped while paused: the new step starts paused.
            s.pausedTotal += now.timeIntervalSince(pausedAt)
            s.pauses.append(DateInterval(start: pausedAt, end: now))
            s.pausedAt = now
            s.stepStartedAt = now
        }
        s.pausedInStep = 0
        s.stepStartMeters = meters
        s.spokenMidCues = []
        s.lastPaceCheck = nil
        s.confirmedPaceThisStep = false
        session = s
        if !silently {
            voice.speak(GuidedTimeline.startCue(s.steps, index: s.index))
            updateActivity()
            save()
        }
    }

    private func finishPause(_ s: inout Session, at date: Date) {
        guard let pausedAt = s.pausedAt else { return }
        s.pausedTotal += date.timeIntervalSince(pausedAt)
        s.pauses.append(DateInterval(start: pausedAt, end: date))
        s.pausedAt = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stopTracking() {
        ticker?.cancel()
        ticker = nil
        recorder.stop()
        endActivity()
    }

    // MARK: Saving to Health

    /// What to save to Apple Health once the run is over; nil while running, or for a run too short to keep (under
    /// two minutes and 200 m).
    var recording: GuidedRunRecording? {
        guard let s = session, let end = s.finishedAt else { return nil }
        let moving = elapsedTotal()
        guard moving >= 120 || meters >= 200 else { return nil }
        return GuidedRunRecording(workoutID: s.workout.id, start: s.startedAt, end: end, pauses: s.pauses,
                                  meters: meters, segments: recorder.segments, route: recorder.route)
    }

    // MARK: Picking up after the app was closed

    private struct Saved: Codable {
        var workout: Workout
        var startedAt: Date
        var stepStartedAt: Date
        var index: Int
        var pausedInStep: Double
        var pausedTotal: Double
        var pausedAt: Date?
        var pauses: [DateInterval]
        var stepStartMeters: Double
        var lastSplitElapsed: Double
        var finishedAt: Date?
        var finishedNormally: Bool
        var units: UnitSystem
        var recorder: RunRecorder.Saved
    }

    private static var savedURL: URL {
        URL.applicationSupportDirectory.appending(path: "guided-run.json")
    }

    private func save() {
        guard let s = session else { return }
        lastSaved = Date()
        let saved = Saved(workout: s.workout, startedAt: s.startedAt, stepStartedAt: s.stepStartedAt, index: s.index,
                          pausedInStep: s.pausedInStep, pausedTotal: s.pausedTotal, pausedAt: s.pausedAt, pauses: s.pauses,
                          stepStartMeters: s.stepStartMeters, lastSplitElapsed: s.lastSplitElapsed,
                          finishedAt: s.finishedAt, finishedNormally: s.finishedNormally, units: s.format.units,
                          recorder: recorder.saved)
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: Self.savedURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Not being able to save only loses the ability to pick up after a restart; the run carries on.
        }
    }

    /// After the run is in Health: forget the saved copy, so reopening the app can't save it twice.
    func forgetSavedRun() { Self.clearSaved() }

    private static func clearSaved() {
        try? FileManager.default.removeItem(at: savedURL)
    }

    /// At launch: if iOS closed the app during a run (in the last four hours), carry on from where it was. Steps
    /// that ran out while the app was closed are passed silently, then the current one is announced.
    func restoreIfNeeded(describer: WorkoutDescriber) {
        guard session == nil, let data = try? Data(contentsOf: Self.savedURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              Date().timeIntervalSince(saved.startedAt) < 4 * 3600 else {
            Self.clearSaved()
            return
        }
        let format = DisplayFormat(units: saved.units)
        let steps = GuidedTimeline.steps(for: saved.workout, describer: describer)
        guard saved.index < steps.count else { Self.clearSaved(); return }
        var s = Session(workout: saved.workout, name: saved.workout.name, steps: steps, format: format,
                        index: saved.index, startedAt: saved.startedAt, stepStartedAt: saved.stepStartedAt)
        s.pausedInStep = saved.pausedInStep
        s.pausedTotal = saved.pausedTotal
        s.pausedAt = saved.pausedAt
        s.pauses = saved.pauses
        s.stepStartMeters = saved.stepStartMeters
        s.lastSplitElapsed = saved.lastSplitElapsed
        s.finishedAt = saved.finishedAt
        s.finishedNormally = saved.finishedNormally
        session = s
        meters = saved.recorder.meters
        resumedAfterRestart = true
        guard !s.isFinished else { return } // Show the summary, so the run can still be saved.
        recorder.splitMeters = saved.units.metersPerUnit
        recorder.isPaused = s.isPaused
        recorder.start(resuming: saved.recorder)
        locationDenied = recorder.isDenied
        // Time-based steps that ran out while the app was closed; distance steps wait for GPS to catch up.
        while let current = session, !current.isPaused, current.step.meters == nil,
              elapsedInStep() >= current.step.seconds, current.index + 1 < current.steps.count {
            advance(from: current.index, silently: true)
        }
        if let current = session {
            voice.speak(String(localized: "Picking up your run. \(GuidedTimeline.startCue(current.steps, index: current.index))"))
        }
        startActivity()
        startTicker()
        save()
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
        // One at a time (a restored run may find the old one still showing).
        for old in Activity<GuidedRunAttributes>.activities {
            nonisolated(unsafe) let stale = old
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
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

/// A finished guided run, ready to save to Apple Health.
struct GuidedRunRecording {
    var workoutID: String
    var start: Date
    var end: Date
    var pauses: [DateInterval]
    var meters: Double
    var segments: [RunRecorder.Segment]
    var route: [CLLocation]
}
