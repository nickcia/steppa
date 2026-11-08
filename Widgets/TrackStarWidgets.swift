import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct TrackStarWidgets: WidgetBundle {
    var body: some Widget {
        GuidedRunLiveActivity()
    }
}

/// A guided run on the lock screen and in the Dynamic Island: the current step, a live countdown, what's next, and
/// Pause and Skip buttons that work without unlocking.
struct GuidedRunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidedRunAttributes.self) { context in
            LockScreenView(name: context.attributes.workoutName, state: context.state)
                .activityBackgroundTint(Color(white: 0.11))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.title3.weight(.bold)).foregroundStyle(stepColor(state))
                        Text(state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state).font(.title2.weight(.semibold)).monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if let next = state.next {
                            Text("Next: \(next)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Controls(state: state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(state.title).font(.caption.weight(.bold)).foregroundStyle(stepColor(state)).lineLimit(1)
            } compactTrailing: {
                Countdown(state: state).font(.caption.weight(.semibold)).monospacedDigit().frame(maxWidth: 46)
            } minimal: {
                Image(systemName: state.isPaused ? "pause.fill" : "figure.run").foregroundStyle(stepColor(state))
            }
        }
    }
}

private func stepColor(_ state: GuidedRunAttributes.ContentState) -> Color {
    Color(red: Double((state.tint >> 16) & 0xFF) / 255, green: Double((state.tint >> 8) & 0xFF) / 255,
          blue: Double(state.tint & 0xFF) / 255)
}

/// Counts down to the end of the step by itself; frozen while paused.
private struct Countdown: View {
    let state: GuidedRunAttributes.ContentState

    var body: some View {
        if let remaining = state.pausedRemaining {
            Text(clock(remaining))
        } else {
            Text(timerInterval: Date.now...max(state.stepEnds, .now), countsDown: true)
        }
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct Controls: View {
    let state: GuidedRunAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleGuidedRunPauseIntent()) {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.18), in: Circle())
            .accessibilityLabel(state.isPaused ? "Resume" : "Pause")
            Button(intent: SkipGuidedRunStepIntent()) {
                Image(systemName: "forward.end.fill")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.18), in: Circle())
            .accessibilityLabel("Skip step")
        }
        .foregroundStyle(.white)
        .font(.system(size: 14, weight: .bold))
    }
}

private struct LockScreenView: View {
    let name: String
    let state: GuidedRunAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("Step \(state.stepNumber) of \(state.stepCount)").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isPaused ? "Paused" : state.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(state.isPaused ? Color.white : stepColor(state))
                    Text(state.detail).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer()
                Countdown(state: state)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            HStack {
                if let next = state.next {
                    Text("Next: \(next)").font(.footnote).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                } else {
                    Text("Last step").font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
                if state.distanceMeters >= 10 {
                    Text("· \(distance)").font(.footnote).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Controls(state: state)
            }
        }
        .padding(16)
    }

    private var distance: String {
        let value = state.metric ? state.distanceMeters / 1000 : state.distanceMeters / 1609.344
        return String(format: "%.2f %@", value, state.metric ? "km" : "mi")
    }
}
