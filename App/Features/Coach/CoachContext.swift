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
        guard text.contains("skip") else { return nil }
        let target = text.contains("long run") ? upcoming.first(where: \.isLongRun) : upcoming.first
        guard let target else { return nil }
        return CoachSuggestion(action: .skip, date: target.date, newDate: nil,
                               reason: String(localized: "Suggested by the coach"))
    }
}

extension CoachSnapshot {
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
            var text = "\(workout.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) [\(workout.date)]: \(workout.kind.name), \(describer.summary(workout)), about \(format.distance(workout.totalMeters)) and \(DisplayFormat.duration(workout.totalSeconds))"
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
        let runs = model.healthRuns.filter { $0.date.days(until: today) <= 56 }.sorted { $0.date > $1.date }
        var details: [String: String] = [:]
        let recentLines = runs.prefix(10).map { run -> String in
            let analysis = model.analysis(for: run)
            var line = "\(run.date): \(model.workout(for: run)?.kind.name ?? "unplanned run"), \(format.distance(run.distanceMeters)) in \(DisplayFormat.duration(run.durationSeconds)) (\(format.pace(analysis.secondsPerKm)))"
            if let hr = analysis.averageHeartRate { line += ", avg HR \(Int(hr.rounded()))" }
            return line
        }
        for run in runs {
            let analysis = model.analysis(for: run)
            let workout = model.workout(for: run)
            var lines = ["Run on \(run.date): \(format.distance(run.distanceMeters)) in \(DisplayFormat.duration(run.durationSeconds)), average \(format.pace(analysis.secondsPerKm))."]
            if let workout { lines.append("Planned: " + describe(workout)) }
            if let workout, let comparison = PlannedComparison.compare(workout, analysis) {
                lines.append("Pace against target: \(comparison.verdict.rawValue).")
            }
            if let hr = analysis.averageHeartRate {
                lines.append("Heart rate: average \(Int(hr.rounded())), max \(Int((analysis.maxHeartRate ?? hr).rounded())).")
            }
            if let drift = analysis.heartRateDrift {
                lines.append("Heart-rate drift (second half vs first, same pace): \(Int((drift * 100).rounded()))%.")
            }
            if let zones = analysis.heartRateZoneSeconds {
                let total = max(zones.reduce(0, +), 1)
                lines.append("Time in heart-rate zones 1–5: " + zones.map { "\(Int(($0 / total * 100).rounded()))%" }.joined(separator: ", ") + ".")
            }
            if !analysis.splits.isEmpty {
                lines.append("Splits per \(unit): " + analysis.splits.prefix(30).map {
                    DisplayFormat.clock(format.paceSeconds($0.secondsPerKm)) + ($0.averageHeartRate.map { " @\(Int($0.rounded()))" } ?? "")
                }.joined(separator: ", ") + ".")
            }
            if let power = analysis.averagePower { lines.append("Average power \(Int(power.rounded())) W.") }
            if let cadence = analysis.averageCadence { lines.append("Average cadence \(Int(cadence.rounded())) steps/min.") }
            let notes = RunNotes.make(analysis: analysis, workout: workout, format: format)
            if !notes.isEmpty { lines.append("App's own notes: " + notes.joined(separator: " ")) }
            details[run.date.description] = lines.joined(separator: "\n")
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

/// A plan change the coach suggested. It's only a suggestion: the athlete taps to apply it, and the app's own
/// rules decide whether it's allowed.
nonisolated struct CoachSuggestion: Sendable, Hashable, Identifiable {
    enum Action: String, Sendable { case move, skip }
    var action: Action
    var date: LocalDate
    var newDate: LocalDate?
    var reason: String
    var id: String { "\(action)-\(date)-\(newDate?.description ?? "")" }
}

/// Collects suggestions from the coach's tool calls (which run off the main actor).
nonisolated final class CoachSuggestionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CoachSuggestion] = []

    func add(_ suggestion: CoachSuggestion) { lock.withLock { if !items.contains(suggestion) { items.append(suggestion) } } }
    func take() -> [CoachSuggestion] { lock.withLock { defer { items = [] }; return items } }
}
