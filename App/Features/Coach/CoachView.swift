import SwiftUI
import PlanEngine

/// Chat with the on-device coach.
struct CoachView: View {
    /// A question to ask straight away (e.g. from a run's screen).
    var initialPrompt: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var conversation = CoachConversation()
    @State private var draft = ""
    @State private var applied: Set<String> = []
    @State private var timeOffPrefill: TimeOffPrefill?
    @State private var updating: PlanChangeRequest?

    private struct TimeOffPrefill: Identifiable {
        let suggestionID: String
        let reason: TimeOff.Reason
        var id: String { suggestionID }
    }
    @FocusState private var typing: Bool

    private let starters = [
        String(localized: "Why this workout today?"),
        String(localized: "How did my last run go?"),
        String(localized: "I'm tired today. What should I do?"),
        String(localized: "Tips for my next long run"),
    ]

    var body: some View {
        let availability = CoachAvailability.current
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header(availability)
                        ForEach(conversation.messages) { message in
                            bubble(message) { proxy.scrollTo("bottom", anchor: .bottom) }.id(message.id)
                        }
                        if conversation.messages.isEmpty, availability == .available {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(starters, id: \.self) { starter in
                                    Button(starter) { ask(starter) }
                                        .buttonStyle(.chip)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.m)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.messages.count) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: conversation.messages.last?.suggestions.count) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if availability == .available { inputBar }
            }
            .screenBackground()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !conversation.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New chat") { conversation.reset() }
                    }
                }
            }
            .sheet(item: $timeOffPrefill) { prefill in
                TimeOffEditor(period: nil, prefill: prefill.reason) { saved in
                    applied.insert(prefill.suggestionID)
                    updating = .timeOff(model.timeOff + [saved])
                }
            }
            .fullScreenCover(item: $updating) { request in
                PlanUpdateView(request: request) { updating = nil }
            }
            .task {
                conversation.warmUp(model)
                if let initialPrompt, availability == .available { ask(initialPrompt) }
            }
        }
    }

    private func header(_ availability: CoachAvailability) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CoachOrb(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(availability == .available ? "Ask about your plan and runs" : "Coach unavailable")
                    .font(.headline).foregroundStyle(Theme.ink)
                Text(availability == .available
                     ? "Runs on your iPhone with Apple Intelligence; nothing leaves your phone. It can suggest changes, but only you can make them. Not medical advice."
                     : availability.message)
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder private func bubble(_ message: CoachMessage, onStep: @escaping () -> Void) -> some View {
        let isAthlete = message.role == .athlete
        VStack(alignment: isAthlete ? .trailing : .leading, spacing: 8) {
            if isAthlete {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Theme.onAccent)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else if message.text.isEmpty {
                ThinkingIndicator(status: conversation.status)
                    .transition(.opacity)
            } else {
                // The coach's answer sits on the page rather than in a bubble, and types out smoothly.
                PacedText(message.text, onStep: onStep)
                    .padding(.vertical, 4)
                    .transition(.opacity)
            }
            ForEach(message.suggestions) { suggestion in
                suggestionCard(suggestion)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: message.text.isEmpty)
        .animation(.easeOut(duration: 0.3), value: message.suggestions)
        .frame(maxWidth: .infinity, alignment: isAthlete ? .trailing : .leading)
        .padding(isAthlete ? .leading : .trailing, isAthlete ? 40 : 8)
    }

    private func suggestionCard(_ suggestion: CoachSuggestion) -> some View {
        let done = applied.contains(suggestion.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title(suggestion)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            if !suggestion.reason.isEmpty {
                Text(suggestion.reason).font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            Button(done ? String(localized: "Done") : buttonTitle(suggestion)) {
                if suggestion.action == .timeOff, let reason = suggestion.timeOffReason {
                    timeOffPrefill = TimeOffPrefill(suggestionID: suggestion.id, reason: reason)
                } else if model.apply(suggestion) {
                    applied.insert(suggestion.id)
                }
            }
            .buttonStyle(.chip)
            .disabled(done)
        }
        .padding(12)
        .background(Theme.subtle.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func title(_ suggestion: CoachSuggestion) -> String {
        let name = model.workout(on: suggestion.date)?.kind.name ?? String(localized: "Workout")
        let day = suggestion.date.formatted(.dateTime.weekday(.wide))
        switch suggestion.action {
        case .move:
            return String(localized: "Move \(name) from \(day) to \(suggestion.newDate?.formatted(.dateTime.weekday(.wide)) ?? "")")
        case .skip:
            return String(localized: "Skip \(day)'s \(name.lowercased())")
        case .timeOff:
            return switch suggestion.timeOffReason {
            case .injury?: String(localized: "Mark yourself as injured")
            case .illness?: String(localized: "Mark yourself as sick")
            case .vacation?: String(localized: "Add your holiday")
            default: String(localized: "Add time off")
            }
        }
    }

    private func buttonTitle(_ suggestion: CoachSuggestion) -> String {
        switch suggestion.action {
        case .move: String(localized: "Move it")
        case .skip: String(localized: "Skip it")
        case .timeOff: String(localized: "Choose dates")
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask your coach", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onSubmit { ask(draft) }
            Button {
                ask(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || conversation.isResponding)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    private func ask(_ text: String) {
        draft = ""
        Task { await conversation.send(text, model: model) }
    }
}
