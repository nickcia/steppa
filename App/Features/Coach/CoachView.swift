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
                            bubble(message).id(message.id)
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
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.messages.last?.text) {
                    if let last = conversation.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
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
            .task {
                conversation.prepare(model)
                if let initialPrompt, availability == .available { ask(initialPrompt) }
            }
        }
    }

    private func header(_ availability: CoachAvailability) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(StrengthStyle.gradient, in: Circle())
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

    @ViewBuilder private func bubble(_ message: CoachMessage) -> some View {
        let isAthlete = message.role == .athlete
        VStack(alignment: isAthlete ? .trailing : .leading, spacing: 8) {
            Group {
                if message.text.isEmpty {
                    ProgressView().padding(.vertical, 4)
                } else {
                    Text(LocalizedStringKey(message.text))
                        .font(.body)
                        .foregroundStyle(isAthlete ? Theme.onAccent : Theme.ink)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isAthlete ? Theme.accent : Theme.card,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            ForEach(message.suggestions) { suggestion in
                suggestionCard(suggestion)
            }
        }
        .frame(maxWidth: .infinity, alignment: isAthlete ? .trailing : .leading)
        .padding(isAthlete ? .leading : .trailing, 40)
    }

    private func suggestionCard(_ suggestion: CoachSuggestion) -> some View {
        let done = applied.contains(suggestion.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title(suggestion)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            if !suggestion.reason.isEmpty {
                Text(suggestion.reason).font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            Button(done ? String(localized: "Done") : (suggestion.action == .move ? String(localized: "Move it") : String(localized: "Skip it"))) {
                if model.apply(suggestion) { applied.insert(suggestion.id) }
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
