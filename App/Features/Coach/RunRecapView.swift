import SwiftUI
import PlanEngine

/// The coach's recap of one run: how it went, what went well, what to watch, progress against earlier runs
/// like it, and a tip for next time. Written on the phone; fills in section by section as it's written.
struct RunRecapView: View {
    let run: CompletedRun
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var writer = RunRecapWriter()
    @State private var askingCoach = false
    @State private var waitingStep = 0

    private var waitingSteps: [String] {
        [String(localized: "Reading your run"), String(localized: "Checking pace and heart rate"),
         String(localized: "Comparing with earlier runs"), String(localized: "Writing your recap")]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    let content = writer.content
                    if let failure = writer.failure {
                        Card(padding: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(failure).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                                Button("Try again") { Task { await writer.write(run, model: model, again: true) } }
                                    .buttonStyle(.chip)
                            }
                        }
                    } else if content.isEmpty {
                        ThinkingIndicator(status: waitingSteps[waitingStep])
                            .task {
                                // Steps through what the model works on while the first words are on their way.
                                while waitingStep < waitingSteps.count - 1, !Task.isCancelled {
                                    try? await Task.sleep(for: .seconds(1.6))
                                    waitingStep += 1
                                }
                            }
                    } else {
                        sections(content)
                    }
                    if !writer.isWriting, writer.failure == nil, !content.isEmpty {
                        HStack(spacing: 10) {
                            Button {
                                askingCoach = true
                            } label: {
                                Label("Ask a follow-up", systemImage: "bubble.left.and.text.bubble.right")
                            }
                            .buttonStyle(.chip)
                            Button {
                                waitingStep = 0
                                Task { await writer.write(run, model: model, again: true) }
                            } label: {
                                Label("Rewrite", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.chip)
                        }
                        .transition(.opacity)
                        Text("Written on your iPhone with Apple Intelligence from this run's data. It can make mistakes; it isn't medical advice.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
                .animation(.easeOut(duration: 0.35), value: writer.content)
                .animation(.easeOut(duration: 0.35), value: writer.isWriting)
            }
            .scrollIndicators(.hidden)
            .screenBackground()
            .navigationTitle("Run recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await writer.write(run, model: model) }
            .sheet(isPresented: $askingCoach) {
                CoachView(initialPrompt: String(localized: "About my run on \(run.date.formatted(.dateTime.day().month(.wide))): what should I take from it for the coming week?"))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CoachOrb(size: 40, animating: writer.isWriting)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                Text("\(model.workout(for: run)?.kind.name ?? String(localized: "Run")) · \(model.format.distance(run.distanceMeters))")
                    .font(.headline).foregroundStyle(Theme.ink)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder private func sections(_ content: RunRecapContent) -> some View {
        if !content.headline.isEmpty {
            PacedText(content.headline, font: .system(size: 28, weight: .semibold))
        }
        if !content.summary.isEmpty {
            PacedText(content.summary, font: .body, color: Theme.ink)
        }
        if !content.wentWell.isEmpty {
            section(String(localized: "What went well"), symbol: "checkmark.circle.fill", tint: Theme.green) {
                ForEach(Array(content.wentWell.enumerated()), id: \.offset) { _, line in
                    bullet(line, symbol: "checkmark", tint: Theme.green)
                }
            }
        }
        if !content.toWatch.isEmpty {
            section(String(localized: "To watch"), symbol: "exclamationmark.circle.fill", tint: Theme.amber) {
                ForEach(Array(content.toWatch.enumerated()), id: \.offset) { _, line in
                    bullet(line, symbol: "arrow.right", tint: Theme.amber)
                }
            }
        }
        if !content.progress.isEmpty {
            section(String(localized: "Progress"), symbol: "chart.line.uptrend.xyaxis", tint: StrengthStyle.color) {
                PacedText(content.progress, font: .subheadline)
            }
        }
        if !content.nextTime.isEmpty {
            section(String(localized: "Next time"), symbol: "lightbulb.fill", tint: Theme.ink) {
                PacedText(content.nextTime, font: .subheadline)
            }
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func bullet(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(tint)
            PacedText(text, font: .subheadline)
        }
        .transition(.opacity)
    }
}
