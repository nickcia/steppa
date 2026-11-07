import Foundation
import Observation
import PlanEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the coach can run on this iPhone, in words the athlete can act on.
enum CoachAvailability: Equatable {
    case available
    /// iOS older than 26, or an iPhone that can't run Apple Intelligence.
    case unsupported
    case appleIntelligenceOff
    case downloading
    case unknown

    var message: String {
        switch self {
        case .available: String(localized: "Ready. Runs on your iPhone with Apple Intelligence.")
        case .unsupported: String(localized: "Needs an iPhone that supports Apple Intelligence, on iOS 26 or later.")
        case .appleIntelligenceOff: String(localized: "Turn on Apple Intelligence in the Settings app to use the coach.")
        case .downloading: String(localized: "Apple Intelligence is still downloading. Try again in a little while.")
        case .unknown: String(localized: "Not available right now.")
        }
    }

    static var current: CoachAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .unsupported
            case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
            case .unavailable(.modelNotReady): return .downloading
            case .unavailable: return .unknown
            }
        }
        #endif
        return .unsupported
    }
}

struct CoachMessage: Identifiable, Equatable {
    enum Role { case athlete, coach }
    let id = UUID()
    let role: Role
    var text: String
    var suggestions: [CoachSuggestion] = []
}

/// The conversation with the on-device coach.
///
/// The coach explains and advises; it never changes the plan. It reads the plan and runs through tools, and can
/// suggest moving or skipping a workout, which appears as a button the athlete taps. The app's own rules then
/// decide whether the change is allowed. Nothing is sent off the phone.
@Observable
final class CoachConversation {
    private(set) var messages: [CoachMessage] = []
    private(set) var isResponding = false
    private var snapshot: CoachSnapshot?
    private let suggestions = CoachSuggestionBox()
    #if canImport(FoundationModels)
    private var sessionStorage: Any?
    #endif

    static let instructions = """
    You are a friendly, knowledgeable running coach inside a training app. The athlete follows a plan made by \
    the app's rules; you explain it, answer questions about their runs, and give practical tips.

    Rules:
    - Look things up with the tools before answering questions about the plan or runs. Never invent workouts, \
    paces, dates or numbers. If a tool has no data, say so.
    - Keep answers short: two to five sentences, or a few bullets. Use the athlete's units as the tools give them. \
    Write dates the way people say them ("Tuesday 17 November"), never as 2026-11-17.
    - When talking about a run, mention what stands out in getRunDetails: heart-rate drift, time in hard zones, \
    uneven splits, or the app's own notes. Don't call a run steady if the data says otherwise.
    - You can't change the plan. Whenever you recommend moving or skipping a workout (tiredness, a busy day, \
    pain, illness), you must also call suggestPlanChange so the athlete gets a button; they decide. Never move a \
    workout to the day before or after another hard session or the long run.
    - You're not a doctor. For pain that changes how they run, chest pain, dizziness, fainting, or an injury, \
    tell them to stop and see a doctor or physio, and suggest skipping rather than adjusting training.
    - Don't recommend a faster goal pace or more mileage than the plan; the plan's rules set those for safety.
    - Be encouraging and honest. No emojis.
    """

    func prepare(_ model: AppModel) {
        snapshot = CoachSnapshot.make(model)
    }

    /// Starts over with a clean conversation.
    func reset() {
        messages = []
        #if canImport(FoundationModels)
        sessionStorage = nil
        #endif
    }

    func send(_ text: String, model: AppModel) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        prepare(model)
        messages.append(CoachMessage(role: .athlete, text: text))
        messages.append(CoachMessage(role: .coach, text: ""))
        isResponding = true
        defer { isResponding = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            await respond(to: text)
            return
        }
        #endif
        replaceLast(String(localized: "The coach needs Apple Intelligence on iOS 26 or later."))
    }

    private func replaceLast(_ text: String, suggestions: [CoachSuggestion] = []) {
        guard let index = messages.indices.last else { return }
        messages[index].text = text
        messages[index].suggestions = suggestions
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func session() -> LanguageModelSession {
        if let existing = sessionStorage as? LanguageModelSession { return existing }
        let snapshot = snapshot ?? CoachSnapshot(overview: "", weeks: [:], recentRuns: "", runDetails: [:], today: "")
        let session = LanguageModelSession(
            tools: [PlanOverviewTool(snapshot: snapshot), WeekTool(snapshot: snapshot),
                    RecentRunsTool(snapshot: snapshot), RunDetailsTool(snapshot: snapshot),
                    SuggestChangeTool(box: suggestions)],
            instructions: Self.instructions + "\n\n" + snapshot.today)
        sessionStorage = session
        return session
    }

    @available(iOS 26.0, *)
    private func respond(to text: String) async {
        do {
            let stream = session().streamResponse(to: text)
            for try await partial in stream {
                replaceLast(partial.content)
            }
            let reply = messages.last?.text ?? ""
            var found = suggestions.take()
            if found.isEmpty, let fallback = snapshot?.fallbackSuggestion(for: reply) { found = [fallback] }
            replaceLast(reply, suggestions: found)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // The on-device model's memory is short: start a fresh conversation and say so.
            sessionStorage = nil
            replaceLast(String(localized: "That conversation got too long for the on-device model, so I've started fresh. Ask again and I'll look it up."))
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            replaceLast(String(localized: "I can't help with that one. Try asking about your training or runs."))
        } catch {
            // Usually Apple Intelligence being busy or still setting up. The detail is only useful to developers.
            print("Coach error: \(error)")
            sessionStorage = nil
            replaceLast(String(localized: "The coach couldn't answer just now. Try again in a moment."))
        }
    }
    #endif
}

#if canImport(FoundationModels)
// MARK: - Tools (read-only lookups, plus one that only suggests)

@available(iOS 26.0, *)
nonisolated struct PlanOverviewTool: Tool {
    let snapshot: CoachSnapshot
    let name = "getPlanOverview"
    let description = "The athlete's goal race, plan length, current week and phase, run days, training paces and predicted race time."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String { snapshot.overview }
}

@available(iOS 26.0, *)
nonisolated struct WeekTool: Tool {
    let snapshot: CoachSnapshot
    let name = "getWeek"
    let description = "The planned workouts for a week, with what was done or skipped. 0 is this week, -1 last week, 1 next week."

    @Generable struct Arguments {
        @Guide(description: "Weeks from this week: -2 to 3", .range(-2...3))
        var offset: Int
    }

    func call(arguments: Arguments) async throws -> String {
        snapshot.weeks[arguments.offset] ?? "No plan for that week."
    }
}

@available(iOS 26.0, *)
nonisolated struct RecentRunsTool: Tool {
    let snapshot: CoachSnapshot
    let name = "getRecentRuns"
    let description = "The athlete's recorded runs from the last 8 weeks, newest first, with date, distance, time, pace and heart rate."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String { snapshot.recentRuns }
}

@available(iOS 26.0, *)
nonisolated struct RunDetailsTool: Tool {
    let snapshot: CoachSnapshot
    let name = "getRunDetails"
    let description = "Full analysis of one recorded run: planned vs actual, splits, heart rate, zones, drift, power and cadence. Use a date from getRecentRuns."

    @Generable struct Arguments {
        @Guide(description: "The run's date as YYYY-MM-DD")
        var date: String
    }

    func call(arguments: Arguments) async throws -> String {
        snapshot.runDetails[arguments.date] ?? "No recorded run on \(arguments.date). Check getRecentRuns for dates."
    }
}

@available(iOS 26.0, *)
nonisolated struct SuggestChangeTool: Tool {
    let box: CoachSuggestionBox
    let name = "suggestPlanChange"
    let description = "Suggest moving or skipping one planned workout. The athlete sees a button and decides; nothing changes until they tap it."

    @Generable struct Arguments {
        @Guide(description: "move or skip", .anyOf(["move", "skip"]))
        var action: String
        @Guide(description: "The workout's current date as YYYY-MM-DD")
        var date: String
        @Guide(description: "For move: the new date as YYYY-MM-DD, in the same week. Empty for skip.")
        var newDate: String
        @Guide(description: "One short sentence on why")
        var reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let action = CoachSuggestion.Action(rawValue: arguments.action), let date = LocalDate(iso: arguments.date) else {
            return "Not suggested: the action or date wasn't valid."
        }
        let newDate = LocalDate(iso: arguments.newDate)
        if action == .move && newDate == nil { return "Not suggested: a move needs a new date." }
        box.add(CoachSuggestion(action: action, date: date, newDate: newDate, reason: arguments.reason))
        return "Suggestion shown to the athlete as a button. Tell them briefly what you suggested and why; they decide."
    }
}
#endif
