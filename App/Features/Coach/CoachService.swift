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
    /// What the coach is doing before its answer starts: "Thinking", or the lookup it's making.
    private(set) var status = String(localized: "Thinking")
    private var snapshot: CoachSnapshot?
    private let suggestions = CoachSuggestionBox()
    /// The time-off button is offered once per conversation, so the coach doesn't keep returning to an injury.
    private var offeredTimeOff = false
    #if canImport(FoundationModels)
    private var sessionStorage: Any?
    #endif

    static let instructions = """
    You are a friendly, knowledgeable running coach inside a training app. The athlete follows a plan made by \
    the app's rules; you explain it, answer questions about their runs, and give practical tips.

    Rules:
    - The plan overview, today and recent runs are below. Use the tools for other weeks and for a run's details \
    before answering questions about them. Never invent workouts, \
    paces, dates or numbers. If a tool has no data, say so.
    - Keep answers short: two to five sentences, or a few bullets. Use the athlete's units as the tools give them. \
    Write dates the way people say them ("Tuesday 17 November"), never as 2026-11-17.
    - When talking about a run, mention what stands out in getRunDetails: heart-rate drift, time in hard zones, \
    uneven splits, or the app's own notes. Don't call a run steady if the data says otherwise.
    - You can't change the plan. Whenever you recommend moving or skipping a workout (tiredness, a busy day, \
    pain, illness), you must also call suggestPlanChange so the athlete gets a button; they decide. Never move a \
    workout to the day before or after another hard session or the long run.
    - Questions about using the app (connecting Garmin or another watch, Apple Health, time off, heart-rate \
    zones, treadmill speed, units, run days, races, calendar, sharing…): call searchHelp and answer from what it \
    returns, in a few short steps. Never guess menu names. If it has nothing, say so and suggest Settings › About › \
    Help and how-to.
    - If the athlete is injured, sick or going away: give one or two sentences of practical advice, then call \
    suggestTimeOff. A button appears under your reply, so say "Tap Choose dates below to mark it" rather than asking \
    whether they want one. Don't keep returning to it: in later answers, only mention the injury or illness if they \
    bring it up again.
    - You're not a doctor. For pain that changes how they run, chest pain, dizziness, fainting, or an injury, \
    tell them to rest and see a doctor or physio.
    - Don't recommend a faster goal pace or more mileage than the plan; the plan's rules set those for safety.
    - Be encouraging and honest. No emojis.
    """

    func prepare(_ model: AppModel) {
        snapshot = CoachSnapshot.make(model)
    }

    /// Loads the model ahead of the first question, which makes the first answer start sooner.
    func warmUp(_ model: AppModel) {
        prepare(model)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), CoachAvailability.current == .available { session().prewarm() }
        #endif
    }

    /// Starts over with a clean conversation.
    func reset() {
        messages = []
        offeredTimeOff = false
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
        status = String(localized: "Thinking")
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
        // Tools run off the main actor; they report what they're looking up for the thinking indicator.
        let report: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in self?.status = text }
        }
        let session = LanguageModelSession(
            tools: [PlanOverviewTool(snapshot: snapshot, report: report), WeekTool(snapshot: snapshot, report: report),
                    RecentRunsTool(snapshot: snapshot, report: report), RunDetailsTool(snapshot: snapshot, report: report),
                    SuggestChangeTool(box: suggestions, report: report), HelpTool(report: report),
                    SuggestTimeOffTool(box: suggestions, today: snapshot.upcoming.first?.date ?? .today, report: report)],
            instructions: Self.instructions + "\n\nPlan overview:\n" + snapshot.overview + "\n\n" + snapshot.today
                + "\n\nRecent runs:\n" + snapshot.recentRuns)
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
            // Said they're injured, sick or away but the model didn't offer the button: offer it anyway.
            if !found.contains(where: { $0.action == .timeOff }),
               let reason = CoachSnapshot.timeOffReason(in: text) ?? CoachSnapshot.timeOffOffer(in: reply),
               let today = snapshot?.upcoming.first?.date {
                found.append(CoachSuggestion(action: .timeOff, date: today, newDate: nil, reason: "", timeOffReason: reason))
            }
            if found.isEmpty, let fallback = snapshot?.fallbackSuggestion(for: reply), fallback.action != .timeOff {
                found = [fallback]
            }
            if offeredTimeOff { found.removeAll { $0.action == .timeOff } }
            if found.contains(where: { $0.action == .timeOff }) { offeredTimeOff = true }
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
    let report: @Sendable (String) -> Void
    let name = "getPlanOverview"
    let description = "The athlete's goal race, plan length, current week and phase, run days, training paces and predicted race time."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        report(String(localized: "Checking your plan"))
        return snapshot.overview
    }
}

@available(iOS 26.0, *)
nonisolated struct WeekTool: Tool {
    let snapshot: CoachSnapshot
    let report: @Sendable (String) -> Void
    let name = "getWeek"
    let description = "The planned workouts for a week, with what was done or skipped. 0 is this week, -1 last week, 1 next week."

    @Generable struct Arguments {
        @Guide(description: "Weeks from this week: -2 to 3", .range(-2...3))
        var offset: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let status = switch arguments.offset {
        case 0: String(localized: "Looking at this week")
        case 1: String(localized: "Looking at next week")
        case -1: String(localized: "Looking at last week")
        default: String(localized: "Looking through your plan")
        }
        report(status)
        return snapshot.weeks[arguments.offset] ?? "No plan for that week."
    }
}

@available(iOS 26.0, *)
nonisolated struct RecentRunsTool: Tool {
    let snapshot: CoachSnapshot
    let report: @Sendable (String) -> Void
    let name = "getRecentRuns"
    let description = "The athlete's recorded runs from the last 8 weeks, newest first, with date, distance, time, pace and heart rate."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        report(String(localized: "Going through your runs"))
        return snapshot.recentRuns
    }
}

@available(iOS 26.0, *)
nonisolated struct RunDetailsTool: Tool {
    let snapshot: CoachSnapshot
    let report: @Sendable (String) -> Void
    let name = "getRunDetails"
    let description = "Full analysis of one recorded run: planned vs actual, splits, heart rate, zones, drift, power and cadence. Use a date from getRecentRuns."

    @Generable struct Arguments {
        @Guide(description: "The run's date as YYYY-MM-DD")
        var date: String
    }

    func call(arguments: Arguments) async throws -> String {
        report(String(localized: "Reading your run"))
        return snapshot.runDetails[arguments.date] ?? "No recorded run on \(arguments.date). Check getRecentRuns for dates."
    }
}

@available(iOS 26.0, *)
nonisolated struct SuggestChangeTool: Tool {
    let box: CoachSuggestionBox
    let report: @Sendable (String) -> Void
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
        report(String(localized: "Preparing a suggestion"))
        box.add(CoachSuggestion(action: action, date: date, newDate: newDate, reason: arguments.reason))
        return "Suggestion shown to the athlete as a button. Tell them briefly what you suggested and why; they decide."
    }
}

@available(iOS 26.0, *)
nonisolated struct HelpTool: Tool {
    let report: @Sendable (String) -> Void
    let name = "searchHelp"
    let description = "How to do things in the app: connecting Garmin or other watches, Apple Health, time off and injuries, heart-rate zones, treadmill speed, units, run days, races, calendar, sharing, reminders, backups."

    @Generable struct Arguments {
        @Guide(description: "What the athlete wants to do, in their words")
        var question: String
    }

    func call(arguments: Arguments) async throws -> String {
        report(String(localized: "Looking it up"))
        let found = AppHelp.search(arguments.question, limit: 2)
        guard !found.isEmpty else { return "No help article matches that. Suggest Settings › About › Help and how-to." }
        return found.map { "\($0.title):\n\($0.body)" }.joined(separator: "\n\n")
    }
}

@available(iOS 26.0, *)
nonisolated struct SuggestTimeOffTool: Tool {
    let box: CoachSuggestionBox
    let today: LocalDate
    let report: @Sendable (String) -> Void
    let name = "suggestTimeOff"
    let description = "Offer a button to mark time off (injured, sick, holiday or busy). The athlete picks the dates; the plan then pauses or works around it and eases them back in."

    @Generable struct Arguments {
        @Guide(description: "Why", .anyOf(["injury", "illness", "vacation", "busy"]))
        var reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let reason = TimeOff.Reason(rawValue: arguments.reason) else { return "Not suggested: unknown reason." }
        report(String(localized: "Preparing a suggestion"))
        box.add(CoachSuggestion(action: .timeOff, date: today, newDate: nil, reason: "", timeOffReason: reason))
        return "A button to mark time off is shown. Mention it in one short sentence, then move on."
    }
}

// MARK: - Run recap

/// A recap of one run, generated as structured fields so the screen can lay it out as it streams in.
@available(iOS 26.0, *)
@Generable
struct RunRecap {
    @Guide(description: "A short, specific title for the run, at most 6 words, no date")
    var headline: String
    @Guide(description: "Two sentences: how the run went overall, against the plan if there was one")
    var summary: String
    @Guide(description: "Things that went well, each one short sentence with a number from the data", .count(2...3))
    var wentWell: [String]
    @Guide(description: "Things to watch or improve, each one short sentence. Empty if nothing stands out", .maximumCount(2))
    var toWatch: [String]
    @Guide(description: "One or two sentences comparing this run with the earlier similar runs: pace, heart rate, distance. If there are none, say this run sets the baseline")
    var progress: String
    @Guide(description: "One practical tip for the next run like this")
    var nextTime: String
}
#endif

/// The recap as plain values the screen shows while it streams; fields fill in as they arrive.
struct RunRecapContent: Equatable {
    var headline = ""
    var summary = ""
    var wentWell: [String] = []
    var toWatch: [String] = []
    var progress = ""
    var nextTime = ""
    var isEmpty: Bool { headline.isEmpty && summary.isEmpty }
}

/// Writes a recap of one run with the on-device model. All the data goes in the prompt, so there are no tool
/// calls and the recap starts quickly.
@Observable
final class RunRecapWriter {
    private(set) var content = RunRecapContent()
    private(set) var isWriting = false
    private(set) var failure: String?

    /// Recaps already written this session, so reopening a run doesn't wait again.
    private static var cache: [String: RunRecapContent] = [:]

    static let instructions = """
    You are a friendly, knowledgeable running coach. Write a short recap of one run for the athlete, like a \
    progress report: how it went, what went well, what to watch, how it compares with earlier similar runs, and \
    a tip for next time.

    Rules:
    - Use only the numbers in the data. Never invent paces, heart rates, dates or distances. Use the units given.
    - Easy and long runs are meant to be slow: running them at or below the target pace is good, not a weakness.
    - Rising heart-rate drift, lots of time in zones 4–5 on an easy run, or fading splits are worth mentioning.
    - Faster pace at the same or lower heart rate than earlier runs is a sign of improving fitness.
    - You're not a doctor. If something looks off (a very high heart rate), suggest it may be the watch reading.
    - Be encouraging and honest. Write dates the way people say them. No emojis.
    """

    func write(_ run: CompletedRun, model: AppModel, again: Bool = false) async {
        if !again, let cached = Self.cache[run.id] {
            content = cached
            return
        }
        guard !isWriting else { return }
        let context = CoachSnapshot.recapContext(run, model: model)
        content = RunRecapContent()
        failure = nil
        isWriting = true
        defer { isWriting = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                let stream = session.streamResponse(to: "Write the recap of this run.\n\n" + context, generating: RunRecap.self)
                for try await snapshot in stream {
                    let partial = snapshot.content
                    content = RunRecapContent(headline: partial.headline ?? "", summary: partial.summary ?? "",
                                              wentWell: partial.wentWell ?? [], toWatch: partial.toWatch ?? [],
                                              progress: partial.progress ?? "", nextTime: partial.nextTime ?? "")
                }
                Self.cache[run.id] = content
            } catch {
                print("Recap error: \(error)")
                failure = String(localized: "The coach couldn't write a recap just now. Try again in a moment.")
            }
            return
        }
        #endif
        failure = CoachAvailability.unsupported.message
    }
}