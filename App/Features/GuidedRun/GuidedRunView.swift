import SwiftUI
import PlanEngine

/// The live screen during a guided run: the current step with a big countdown ring, what's next, time and distance,
/// and Pause, Skip and End. When the run finishes, a short summary with Mark as done.
struct GuidedRunView: View {
    @Environment(GuidedRunController.self) private var run
    @Environment(AppModel.self) private var model
    @State private var confirmingEnd = false

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()
            if let session = run.session {
                if session.isFinished {
                    summary(session)
                } else {
                    live(session)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("End this run?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End run", role: .destructive) { run.end() }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: Live

    private func live(_ session: GuidedRunController.Session) -> some View {
        let step = session.step
        let tint = Color(hex: step.tint)
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name).font(.headline).foregroundStyle(.white)
                    Text("Step \(session.index + 1) of \(session.steps.count)")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button {
                    run.muted.toggle()
                } label: {
                    Image(systemName: run.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .accessibilityLabel(run.muted ? "Turn voice on" : "Turn voice off")
                Button("End") { confirmingEnd = true }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.white.opacity(0.1), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)

            StepSegments(session: session)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)

            Spacer(minLength: 12)

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = run.remainingInStep(at: context.date)
                let progress = run.stepProgress(at: context.date)
                ZStack {
                    Circle().stroke(.white.opacity(0.08), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: progress)
                    VStack(spacing: 6) {
                        Text(session.isPaused ? String(localized: "Paused") : step.title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(session.isPaused ? .white : tint)
                        Text(clock(remaining))
                            .font(.system(size: 72, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                        if let target = step.meters {
                            Text(run.meters > 0 ? String(localized: "\(session.format.distance(max(0, target - run.metersInStep))) to go")
                                                : String(localized: "\(session.format.distance(target)) · about"))
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(24)
                }
                .frame(width: 290, height: 290)
                .accessibilityElement(children: .combine)
            }

            VStack(spacing: 6) {
                if let rep = step.rep {
                    Text("\(step.title) \(rep.index) of \(rep.count)").font(.headline).foregroundStyle(.white)
                }
                Text(step.detail).font(.body).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                if let next = session.next {
                    Text("Next: \(next.short(session.format))").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("Last step").font(.subheadline).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.l)

            Spacer(minLength: 12)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    stat(DisplayFormat.clock(run.elapsedTotal(at: context.date)), String(localized: "time"))
                    stat(run.meters > 0 ? session.format.distance(run.meters) : "–", String(localized: "distance"))
                }
            }
            .padding(.horizontal, Theme.Spacing.l)

            if run.locationDenied {
                Label("Location is off, so cues stop if the screen locks. Turn it on in Settings › TrackStar › Location.",
                      systemImage: "location.slash")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.s)
            }

            HStack(spacing: 28) {
                Color.clear.frame(width: 64, height: 64)
                Button { run.togglePause() } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 88, height: 88)
                        .background(.white, in: Circle())
                }
                .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
                Button { run.skip() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Skip to next step")
            }
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
            .sensoryFeedback(.impact, trigger: session.index)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Summary

    private func summary(_ session: GuidedRunController.Session) -> some View {
        let completed = session.index + 1 >= session.steps.count
        let status = model.status(of: session.workout)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: completed ? "checkmark" : "flag.checkered")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Theme.sheen, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(completed ? String(localized: "Workout complete") : String(localized: "Run ended"))
                    .font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                Text(completed ? String(localized: "Every step done. Nice work.")
                               : String(localized: "\(session.index) of \(session.steps.count) steps done."))
                    .foregroundStyle(.white.opacity(0.65))
            }
            HStack {
                stat(DisplayFormat.clock(run.elapsedTotal()), String(localized: "time"))
                stat(run.meters > 0 ? session.format.distance(run.meters) : "–", String(localized: "distance"))
            }
            .padding(.vertical, Theme.Spacing.m)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Spacer()
            if status == nil {
                Button {
                    model.setStatus(.done, for: session.workout)
                    run.close()
                } label: {
                    Text("Mark as done").frame(maxWidth: .infinity)
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(height: 56)
                .background(.white, in: Capsule())
            }
            Button { run.close() } label: {
                Text(status == nil ? String(localized: "Close without marking") : String(localized: "Close")).frame(maxWidth: .infinity)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(height: 56)
            .background(.white.opacity(0.12), in: Capsule())
        }
        .padding(Theme.Spacing.l)
        .sensoryFeedback(.success, trigger: session.isFinished)
    }
}

/// One segment per step, filled as the run goes; the current one fills live.
private struct StepSegments: View {
    let session: GuidedRunController.Session
    @Environment(GuidedRunController.self) private var run

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(Array(session.steps.enumerated()), id: \.offset) { index, step in
                        segment(step, fill: fill(index, at: context.date), width: width(step, in: proxy.size.width))
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityHidden(true)
    }

    // Split out so the type checker stays quick (older compilers timed out on the one-expression version).
    private func fill(_ index: Int, at date: Date) -> Double {
        if index < session.index { return 1 }
        if index > session.index { return 0 }
        return run.stepProgress(at: date)
    }

    private func width(_ step: GuidedStep, in available: Double) -> Double {
        let total = max(session.steps.reduce(0.0) { $0 + $1.seconds }, 1)
        let gaps = 3.0 * Double(session.steps.count - 1)
        return max(4, (available - gaps) * step.seconds / total)
    }

    private func segment(_ step: GuidedStep, fill: Double, width: Double) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .overlay(alignment: .leading) {
                Capsule().fill(Color(hex: step.tint)).scaleEffect(x: fill, anchor: .leading)
            }
            .clipShape(Capsule())
            .frame(width: width)
    }
}
