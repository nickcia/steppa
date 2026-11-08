import ActivityKit
import AppIntents
import Foundation

/// What the lock screen and Dynamic Island show during a guided run. Shared by the app (which starts and updates the
/// Live Activity) and the widget extension (which draws it).
nonisolated struct GuidedRunAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// "Run", "Walk", "Threshold"…
        var title: String
        /// "Run 3 of 8", "Gently, slow enough to talk", "5:10–5:20 /km"
        var detail: String
        /// When the current step ends. The countdown ticks on its own from this, without updates.
        var stepEnds: Date
        /// Time left in the step while paused (the countdown is frozen).
        var pausedRemaining: Double?
        /// "Walk 1:30", nil on the last step.
        var next: String?
        var stepNumber: Int
        var stepCount: Int
        var distanceMeters: Double
        var metric: Bool
        /// Hex colour for the current step (run, walk, threshold…).
        var tint: UInt32

        var isPaused: Bool { pausedRemaining != nil }
    }

    /// "Run/walk", "Threshold"…
    var workoutName: String
}

extension Notification.Name {
    /// Pause/resume or skip, sent from the Live Activity's buttons to the running guided run.
    nonisolated static let guidedRunCommand = Notification.Name("io.github.nickcia.runcoach.guidedRunCommand")
}

/// Pause or resume from the lock screen. Runs in the app's process, which owns the guided run.
nonisolated struct ToggleGuidedRunPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume the run"

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .guidedRunCommand, object: "pause") }
        return .result()
    }
}

/// Skip to the next step from the lock screen.
nonisolated struct SkipGuidedRunStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip to the next step"

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: .guidedRunCommand, object: "skip") }
        return .result()
    }
}
