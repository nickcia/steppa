import Foundation
import PlanEngine

/// Everything the coach may look up, written out as short plain text on the main actor.
///
/// The on-device model has a small context window, so it doesn't get the whole plan up front. It asks for what
/// it needs through tools (see CoachTools), and each tool answers from this snapshot. Nothing here leaves the
/// phone. Pure, so it's unit-tested without the model.
nonisolated struct CoachSnapshot: Sendable, Equatable {
    var overview: String
    /// Keyed by offset from this week: -2 (two weeks ago) … +3.
    var weeks: [Int: String]
    var recentRuns: String
    /// Keyed by date (YYYY-MM-DD).
    var runDetails: [String: String]
    var today: String
    /// Today's and the next workouts not yet done, for turning a recommended skip into a button.
    var upcoming: [Upcoming] = []

    struct Upcoming: Sendable, Equatable {
        var date: LocalDate
        var isLongRun: Bool
    }

    /// When the coach recommends skipping in words but doesn't call suggestPlanChange (the small on-device model
    /// often doesn't), the app offers the button itself: for the next long run if the reply is about a long run,
    /// otherwise for the next workout from today. Nothing changes until the athlete taps it.
    func fallbackSuggestion(for reply: String) -> CoachSuggestion? {
        let text = reply.lowercased()
        if let reason = Self.timeOffReason(in: text), let today = upcoming.first?.date {
            return CoachSuggestion(action: .timeOff, date: today, newDate: nil, reason: String(localized: "Suggested by the coach"),
                                   timeOffReason: reason)
        }
        guard text.contains("skip") else { return nil }
        let target = text.contains("long run") ? upcoming.first(where: \.isLongRun) : upcoming.first
        guard let target else { return nil }
        return CoachSuggestion(action: .skip, date: target.date, newDate: nil,
                               reason: String(localized: "Suggested by the coach"))
    }
}

extension CoachSnapshot {
    /// Whether the athlete said they're injured, sick or going away, so the coach can offer to mark time off.
    nonisolated static func timeOffReason(in text: String) -> TimeOff.Reason? {
        let text = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["injur", "hurt", "pulled my", "strain", "sprain", "shin splint", "stress fracture", "physio", "pain",
                "sore", "my knee", "my ankle", "my calf", "my hamstring", "my achilles", "my hip", "my shin", "my foot"]) { return .injury }
        if has(["i'm sick", "i am sick", "got sick", "have a cold", "have the flu", "have flu", "covid", "fever", "feel ill", "i'm ill"]) { return .illness }
        if has(["vacation", "holiday", "going away", "on a trip", "travelling", "traveling"]) { return .vacation }
        return nil
    }

    /// Whether the coach's reply offers to mark time off ("…mark this as an injury and pause the plan?"), so the
    /// button appears even when the model forgot to call the tool. A passing mention ("to avoid injury") doesn't count.
    nonisolated static func timeOffOffer(in reply: String) -> TimeOff.Reason? {
        let text = reply.lowercased()
        guard ["mark", "pause", "time off"].contains(where: text.contains) else { return nil }
        if text.contains("injur") { return .injury }
        if text.contains("sick") || text.contains("illness") || text.contains("ill ") { return .illness }
        if text.contains("holiday") || text.contains("vacation") || text.contains("trip") { return .vacation }
        return text.contains("time off") ? .other : nil
    }

    @MainActor static func make(_ model: AppModel) -> CoachSnapshot {
        guard let plan = model.plan else {
            return CoachSnapshot(overview: "The athlete has no training plan yet.", weeks: [:],
                                 recentRuns: "No runs.", runDetails: [:], today: "No plan.")
        }
        let format = model.format
        let unit = model.units.distanceUnit
        let describer = WorkoutDescriber(format: format)
        let today = model.today

        func describe(_ workout: Workout) -> String {
            var text = "\(workout.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) [\(workout.date)]: \(workout.name), \(describer.summary(workout)), about \(format.distance(workout.totalMeters)) and \(DisplayFormat.duration(workout.totalSeconds))"
            if let target = workout.blocks.flatMap(\.steps).first(where: { $0.purpose == .work })?.step.target,
               !target.zone.isEffortBased, target.zone != .stride {
                text += ", target \(format.paceRange(target.range))"
            }
            switch model.status(of: workout) {
            case .done?: text += " (done)"
            case .skipped?: text += " (skipped)"
            case nil: if workout.date < today { text += " (not marked)" }
            }
            return text
        }

        // Overview.
        let current = model.week(containing: today)
        let paces = plan.paces
        var overview = """
        Goal: \(plan.inputs.goal.name) on \(plan.inputs.raceDate) (\(max(0, today.days(until: plan.inputs.raceDate))) days away).
        Plan: \(plan.weeks.count) weeks. Now in week \((current?.index ?? 0) + 1), \(current?.phase.name ?? "") phase\(current?.isStepBack == true ? " (an easier step-back week)" : "").
        Runs on \(plan.inputs.runDays.sorted().map(\.fullName).joined(separator: ", ")); long run on \(plan.inputs.longRunDay.fullName). Experience: \(plan.inputs.experience.name).
        Paces per \(unit): easy \(format.paceRange(paces.easy)), marathon \(format.pace(paces.marathon.mid)), threshold \(format.pace(paces.threshold.mid)), interval \(format.pace(paces.interval.mid)).
        Predicted \(plan.inputs.goal.name) time now: \(DisplayFormat.clock(model.prediction?.seconds ?? plan.predictedRaceSeconds)).
        """
        if let goal = plan.inputs.goalTimeSeconds { overview += " Goal time: \(DisplayFormat.clock(goal))." }
        if plan.inputs.runWalkStart != nil {
            let left = plan.weeks.filter { $0.startDate >= today.startOfWeek && RunWalk.stage(for: $0.startDate, inputs: plan.inputs) != nil }.count
            overview += left > 0
                ? "\nNew runner: the plan starts with run/walk sessions (run gently, walk briskly), building to 30 minutes non-stop; \(left) run/walk weeks left. Walking breaks are part of the plan, not a failure."
                : "\nStarted as a new runner with run/walk and now runs non-stop."
        }
        let timeOff = plan.inputs.timeOffPeriods.filter { ($0.end ?? today) >= today }
        if !timeOff.isEmpty {
            overview += "\nTime off already marked (nothing planned then): " + timeOff.map { "\($0.reason.name.lowercased()) \($0.datesText)" }.joined(separator: "; ") + "."
        }
        if let change = model.changes.first {
            overview += "\nLatest plan change (\(change.createdAt.formatted(date: .abbreviated, time: .omitted))): "
                + change.reasons.map { $0.message(format) }.joined(separator: " ")
        }

        // Weeks around now.
        var weeks: [Int: String] = [:]
        if let current {
            for offset in -2...3 {
                let index = current.index + offset
                guard plan.weeks.indices.contains(index) else { continue }
                let week = plan.weeks[index]
                var lines = ["Week \(index + 1) of \(plan.weeks.count) (\(week.phase.name)\(week.isStepBack ? ", step-back" : ""), from \(week.startDate)), planned \(format.distance(week.plannedMeters)):"]
                lines += week.workouts.map { "- " + describe($0) }
                let strength = model.strengthSessions.filter { $0.date >= week.startDate && $0.date < week.startDate.adding(days: 7) }
                lines += strength.map { "- \($0.date): strength session (\(StrengthRoutine.for($0.level).title))" }
                weeks[offset] = lines.joined(separator: "\n")
            }
        }

        // Runs from the athlete's devices.
        let runs = model.coachRuns.filter { $0.date.days(until: today) <= 56 }.sorted { $0.date > $1.date }
        var details: [String: String] = [:]
        let recentLines = runs.prefix(10).map { run -> String in
            let analysis = model.analysis(for: run)
            var line = "\(run.date): \(model.workout(for: run)?.name ?? "unplanned run"), \(format.distance(run.distanceMeters)) in \(DisplayFormat.duration(run.durationSeconds)) (\(format.pace(analysis.secondsPerKm)))"
            if let hr = analysis.averageHeartRate { line += ", avg HR \(Int(hr.rounded()))" }
            return line
        }
        for run in runs {
            details[run.date.description] = runDetail(run, model: model)
        }

        // Today.
        var todayLines = ["Today is \(today.formatted(.dateTime.weekday(.wide).day().month(.wide))) [\(today)]."]
        if let workout = model.workout(on: today) {
            todayLines.append("Today's planned run: " + describe(workout) + ". Purpose: " + workout.kind.purpose)
        } else {
            todayLines.append("Today is a rest day.")
        }
        if let strength = model.strengthSession(on: today) {
            todayLines.append("Strength session today: \(StrengthRoutine.for(strength.level).title).")
        }

        let upcoming = plan.workouts
            .filter { $0.date >= today && $0.kind != .race && model.status(of: $0) == nil }
            .prefix(7)
            .map { Upcoming(date: $0.date, isLongRun: $0.kind == .long || $0.kind == .marathonPaceLong) }
        return CoachSnapshot(overview: overview, weeks: weeks,
                             recentRuns: recentLines.isEmpty ? "No recorded runs in the last 8 weeks." : recentLines.joined(separator: "\n"),
                             runDetails: details, today: todayLines.joined(separator: "\n"), upcoming: Array(upcoming))
    }
}

extension CoachSnapshot {
    /// Everything about one recorded run, as plain text.
    @MainActor static func runDetail(_ run: CompletedRun, model: AppModel) -> String {
        let format = model.format
        let unit = model.units.distanceUnit
        let describer = WorkoutDescriber(format: format)
        let analysis = model.analysis(for: run)
        let workout = model.workout(for: run)
        var lines = ["Run on \(run.date.formatted(.dateTime.weekday(.wide).day().month(.wide))): \(format.distance(run.distanceMeters)) in \(DisplayFormat.duration(run.durationSeconds)), average \(format.pace(analysis.secondsPerKm))."]
        if let workout {
            var planned = "Planned: \(workout.name), \(describer.summary(workout)), about \(format.distance(workout.totalMeters))"
            if let target = workout.blocks.flatMap(\.steps).first(where: { $0.purpose == .work })?.step.target,
               !target.zone.isEffortBased, target.zone != .stride {
                planned += ", target \(format.paceRange(target.range))"
            }
            lines.append(planned + ". Purpose: " + workout.kind.purpose)
            if let comparison = PlannedComparison.compare(workout, analysis) {
                lines.append("Pace against target: \(comparison.verdict.rawValue).")
            }
        } else {
            lines.append("Not a planned workout.")
        }
        if let hr = analysis.averageHeartRate {
            lines.append("Heart rate: average \(Int(hr.rounded())), max \(Int((analysis.maxHeartRate ?? hr).rounded())).")
        }
        if let drift = analysis.heartRateDrift {
            lines.append("Heart-rate drift (second half vs first, same pace): \(Int((drift * 100).rounded()))%.")
        }
        if let zones = analysis.heartRateZoneSeconds, zones.reduce(0, +) > 0 {
            lines.append(zoneLine(zones))
        }
        if !analysis.splits.isEmpty {
            lines.append("Splits per \(unit): " + analysis.splits.prefix(30).map {
                DisplayFormat.clock(format.paceSeconds($0.secondsPerKm)) + ($0.averageHeartRate.map { " @\(Int($0.rounded()))" } ?? "")
            }.joined(separator: ", ") + ".")
        }
        if let elevation = analysis.elevationGainMeters, elevation > 0 { lines.append("Climb: \(Int(elevation.rounded())) m.") }
        if let power = analysis.averagePower { lines.append("Average power \(Int(power.rounded())) W.") }
        if let cadence = analysis.averageCadence { lines.append("Average cadence \(Int(cadence.rounded())) steps/min.") }
        let notes = RunNotes.make(analysis: analysis, workout: workout, format: format)
        if !notes.isEmpty { lines.append("App's own notes: " + notes.joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }

    /// Time in each heart-rate zone, named, leaving out empty ones (bare lists of percentages confuse the model).
    nonisolated static func zoneLine(_ zones: [Double]) -> String {
        let names = ["zone 1 (very easy)", "zone 2 (easy)", "zone 3 (moderate)", "zone 4 (hard)", "zone 5 (very hard)"]
        let total = max(zones.reduce(0, +), 1)
        let parts = zones.enumerated().compactMap { index, seconds -> String? in
            let share = Int((seconds / total * 100).rounded())
            return share > 0 && index < names.count ? "\(share)% in \(names[index])" : nil
        }
        return "Heart-rate zones: " + parts.joined(separator: ", ") + ". Easy and long runs should be mostly in zones 1–2."
    }

    /// What the run recap needs: the run itself, earlier runs like it, and where it sits in the plan.
    @MainActor static func recapContext(_ run: CompletedRun, model: AppModel) -> String {
        let format = model.format
        var sections = [runDetail(run, model: model)]

        // Earlier runs of the same kind (or, for an unplanned run, of a similar distance), up to 8 weeks back.
        let kind = model.workout(for: run)?.kind
        let earlier = model.coachRuns
            .filter { $0.id != run.id && $0.date < run.date && $0.date.days(until: run.date) <= 56 }
            .filter { other in
                if let kind { return model.workout(for: other)?.kind == kind }
                return abs(other.distanceMeters - run.distanceMeters) <= run.distanceMeters * 0.3
            }
            .sorted { $0.date > $1.date }
            .prefix(6)
        if earlier.isEmpty {
            sections.append("Earlier similar runs: none in the last 8 weeks, so there's nothing to compare yet.")
        } else {
            sections.append("Earlier similar runs (newest first):\n" + earlier.map { other in
                let analysis = model.analysis(for: other)
                var line = "- \(other.date.formatted(.dateTime.day().month(.abbreviated))): \(format.distance(other.distanceMeters)) at \(format.pace(analysis.secondsPerKm))"
                if let hr = analysis.averageHeartRate { line += ", avg HR \(Int(hr.rounded()))" }
                if let drift = analysis.heartRateDrift { line += ", drift \(Int((drift * 100).rounded()))%" }
                return line
            }.joined(separator: "\n"))
        }

        // Volume over the last four weeks, and the plan around the run.
        if let plan = model.plan, let week = model.week(containing: run.date) {
            let weekStart = week.startDate
            let done = model.coachRuns.filter { $0.date >= weekStart && $0.date < weekStart.adding(days: 7) }
                .reduce(0) { $0 + $1.distanceMeters }
            var context = "Plan: \(plan.inputs.goal.name) on \(plan.inputs.raceDate.formatted(.dateTime.day().month(.wide))). This run was in week \(week.index + 1) of \(plan.weeks.count), \(week.phase.name) phase\(week.isStepBack ? " (step-back week)" : ""). That week: \(format.distance(done)) run of \(format.distance(week.plannedMeters)) planned."
            let totals = (1...4).map { back -> Double in
                let start = weekStart.adding(days: -7 * back)
                return model.coachRuns.filter { $0.date >= start && $0.date < start.adding(days: 7) }.reduce(0) { $0 + $1.distanceMeters }
            }
            if totals.contains(where: { $0 > 0 }) {
                context += " The 4 weeks before (oldest first): " + totals.reversed().map { format.distance($0) }.joined(separator: ", ") + "."
            }
            sections.append(context)
        }
        return sections.joined(separator: "\n\n")
    }
}

/// A plan change the coach suggested. It's only a suggestion: the athlete taps to apply it, and the app's own
/// rules decide whether it's allowed.
nonisolated struct CoachSuggestion: Sendable, Hashable, Identifiable {
    enum Action: String, Sendable { case move, skip, timeOff }
    var action: Action
    var date: LocalDate
    var newDate: LocalDate?
    var reason: String
    /// For `.timeOff`: why (injured, sick, holiday…). The button opens time off with this filled in.
    var timeOffReason: TimeOff.Reason?
    var id: String { "\(action)-\(date)-\(newDate?.description ?? "")-\(timeOffReason?.rawValue ?? "")" }
}

/// Collects suggestions from the coach's tool calls (which run off the main actor).
nonisolated final class CoachSuggestionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CoachSuggestion] = []

    func add(_ suggestion: CoachSuggestion) { lock.withLock { if !items.contains(suggestion) { items.append(suggestion) } } }
    func take() -> [CoachSuggestion] { lock.withLock { defer { items = [] }; return items } }
}
