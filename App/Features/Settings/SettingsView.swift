import AVFoundation
import AuthenticationServices
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import PlanEngine

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEnd = false
    @State private var importing = false
    @State private var pendingImport: ExportBundle?
    @State private var importError: String?
    @State private var reportingBug = false

    var body: some View {
        NavigationStack {
            Form {
                if let plan = model.plan {
                    Section {
                        NavigationLink(value: RacesRoute()) {
                            HStack(spacing: 14) {
                                KindIcon(kind: .race, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Races").font(.headline).foregroundStyle(Theme.ink)
                                    Text("\(plan.inputs.goal.name) · \(max(0, model.today.days(until: plan.inputs.raceDate))) days to go")
                                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } footer: {
                        Text("Your goal race, its date and goal time, and tune-up races and results.")
                    }
                }

                Section {
                    NavigationLink {
                        ConnectionsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connections").font(.headline).foregroundStyle(Theme.ink)
                            Text(model.connectionsSummary)
                                .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    NavigationLink {
                        GearView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gear").font(.headline).foregroundStyle(Theme.ink)
                            Text(model.gearSummary)
                                .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Units") {
                    Picker("Distance", selection: Binding(get: { model.units }, set: { model.setUnits($0) })) {
                        ForEach(UnitSystem.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                RunCoachVoiceSection()

                if let plan = model.plan {
                    Section("Training") {
                        NavigationLink {
                            AvailabilityEditor(plan: plan)
                        } label: {
                            LabeledContent("Run days", value: plan.inputs.runDays.sorted().map(\.mediumName).joined(separator: ", "))
                        }
                        LabeledContent("Long run", value: plan.inputs.longRunDay.fullName)
                        NavigationLink(value: TimeOffRoute()) {
                            LabeledContent("Time off and injuries",
                                           value: model.timeOff.filter { ($0.end ?? model.today) >= model.today }.isEmpty
                                               ? String(localized: "None planned") : String(localized: "\(model.timeOff.filter { ($0.end ?? model.today) >= model.today }.count) planned"))
                        }
                        Button("End this plan", role: .destructive) { confirmEnd = true }
                    }

                    Section {
                        Toggle("Strength sessions", isOn: Binding(get: { model.strengthEnabled },
                                                                  set: { model.setStrength(enabled: $0) }))
                        if model.strengthEnabled {
                            Picker("Per week", selection: Binding(get: { model.strengthPerWeek },
                                                                  set: { model.setStrength(enabled: true, perWeek: $0) })) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                            }
                            .pickerStyle(.segmented)
                        }
                    } header: {
                        Text("Strength")
                    } footer: {
                        Text("Short bodyweight routines (10–25 minutes, no equipment) that make running injuries less likely. They're placed away from your key runs and ease off before race day. They show on Today and in your calendar; they aren't sent to your watch.")
                    }
                }

                Section {
                    NavigationLink {
                        HeartRateZonesView()
                    } label: {
                        LabeledContent("Heart-rate zones", value: zonesSourceName)
                    }
                    MaxHeartRateRow()
                    Picker("Show targets as", selection: Binding(get: { model.targetDisplay }, set: { model.setTargetDisplay($0) })) {
                        ForEach(WorkoutTargetDisplay.allCases) { Text($0.name).tag($0) }
                    }
                    Picker("Treadmill speed", selection: Binding(get: { model.treadmillUnits }, set: { model.setTreadmillUnits($0) })) {
                        Text("km/h").tag(UnitSystem.metric)
                        Text("mph").tag(UnitSystem.imperial)
                    }
                } header: {
                    Text("Heart rate and treadmill")
                } footer: {
                    Text("Workouts can show pace, heart rate or treadmill speed. You can also switch on any workout.")
                }

                Section {
                    Toggle("Show the coach", isOn: Binding(get: { model.coachEnabled }, set: { model.setCoachEnabled($0) }))
                    Text(CoachAvailability.current.message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                } header: {
                    Text("Coach")
                } footer: {
                    Text("An optional coach you can ask about your plan and runs. It uses Apple Intelligence on your iPhone, so nothing is sent anywhere. Plans are still made by the app's rules; the coach can only suggest changes.")
                }

                if model.calendarAvailable {
                    Section {
                        Toggle("Show my plan in Calendar",
                               isOn: Binding(get: { model.calendarSyncEnabled },
                                             set: { on in Task { await model.setCalendarSync(on) } }))
                    } header: {
                        Text("Calendar")
                    } footer: {
                        Text("Adds your workouts to their own calendar, at your reminder time, and keeps it up to date as the plan changes. iOS asks for full calendar access for this; only that calendar is ever changed. Turning it off removes the calendar. To add one workout without this, use Add to Calendar on the workout.")
                    }
                }

                Section {
                    Toggle("Workout reminders",
                           isOn: Binding(get: { model.remindersEnabled }, set: { on in Task { await model.setReminders(enabled: on) } }))
                    DatePicker("Time", selection: Binding(
                        get: { Calendar.current.date(bySettingHour: model.reminderMinutes / 60, minute: model.reminderMinutes % 60, second: 0, of: .now) ?? .now },
                        set: { date in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                            Task { await model.setReminderTime(minutes: (c.hour ?? 7) * 60 + (c.minute ?? 0)) }
                        }), displayedComponents: .hourAndMinute)
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A notification on workout days at this time. Workouts sent to your watch are scheduled for the same time.")
                }

                Section {
                    ShareLink(item: ExportFile(bundle: model.exportBundle()),
                              preview: SharePreview("Training data", image: Image(systemName: "doc.text"))) {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                    Button { importing = true } label: {
                        Label("Import data", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Exports are a JSON file with your plan, progress and races. Your data also stays in your own iCloud; nothing is sent to us.")
                }

                Section("About") {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("Help and how-to", systemImage: "questionmark.circle")
                    }
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Text("Free and open source under the MIT licence. No accounts, no ads, no tracking.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                    NavigationLink("How plans are built") { PlanRulesSummary() }
                    Button { reportingBug = true } label: {
                        Label("Report a bug", systemImage: "ladybug")
                    }
                }

                Section("Health and safety") {
                    DisclaimerText()
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: RacesRoute.self) { _ in RacesScreen() }
            .navigationDestination(for: TimeOffRoute.self) { _ in TimeOffView() }
            .sheet(isPresented: $reportingBug) { BugReportView() }
            .confirmationDialog("End this plan?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End plan", role: .destructive) { model.endPlan() }
            } message: {
                Text("You'll be taken back to set up a new plan. Your completed runs stay in Apple Health.")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    pendingImport = try ExportBundle.decode(Data(contentsOf: url))
                } catch {
                    importError = error.localizedDescription
                }
            }
            .confirmationDialog("Replace your data?", isPresented: Binding(get: { pendingImport != nil },
                                                                         set: { if !$0 { pendingImport = nil } }),
                                titleVisibility: .visible) {
                Button("Replace with imported data", role: .destructive) {
                    if let bundle = pendingImport { model.importBundle(bundle) }
                    pendingImport = nil
                }
            } message: {
                Text("Your current plan, progress and races will be replaced by the contents of this file. Export first if you want to keep them.")
            }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }
}

/// The export as a shareable JSON file.
nonisolated struct ExportFile: Transferable {
    let bundle: ExportBundle

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in try file.bundle.encoded() }
            .suggestedFileName("training-export.json")
    }
}

/// Maximum heart rate for zones: estimated by default, or the athlete's own (e.g. from a lab or field test).
extension SettingsView {
    fileprivate var zonesSourceName: String {
        switch model.heartRateZones?.source {
        case .imported?: String(localized: "From your watch")
        case .custom?: String(localized: "Your own")
        case .estimated?: String(localized: "Automatic")
        case nil: String(localized: "Not set")
        }
    }
}

/// The athlete's five heart-rate zones: imported from their watch platform (through Intervals.icu), typed in, or
/// estimated from maximum heart rate.
private struct HeartRateZonesView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var importMessage: String?

    private static let colors: [Color] = [Color(hex: 0xA9C6FF), Theme.green, Theme.amber, Color(hex: 0xF5894A), Theme.red]
    private static let names = [String(localized: "Recovery"), String(localized: "Easy"), String(localized: "Steady"),
                                String(localized: "Threshold"), String(localized: "Hard")]

    var body: some View {
        Form {
            if let zones = model.heartRateZones {
                Section {
                    ForEach(0..<5, id: \.self) { zone in
                        let range = zones.range(ofZone: zone)
                        HStack {
                            Circle().fill(Self.colors[zone]).frame(width: 10, height: 10)
                            Text("Zone \(zone + 1) · \(Self.names[zone])")
                            Spacer()
                            Text("\(Int(range.lowerBound))–\(Int(range.upperBound)) bpm")
                                .monospacedDigit().foregroundStyle(Theme.secondaryInk)
                        }
                    }
                } header: {
                    Text(sourceText(zones.source))
                } footer: {
                    if zones.source == .estimated, let basis = basisText { Text(basis) }
                }

                Section {
                    ForEach(0..<4, id: \.self) { index in
                        Stepper(value: limitBinding(index, zones), in: 60...230) {
                            LabeledContent("Top of zone \(index + 1)", value: "\(Int(zones.upperLimits[index])) bpm")
                        }
                    }
                    Stepper(value: maxBinding(zones), in: 120...240) {
                        LabeledContent("Maximum", value: "\(Int(zones.maxHeartRate)) bpm")
                    }
                } header: {
                    Text("Set your own")
                } footer: {
                    Text("Changing a limit makes these your own zones, which an import never overwrites.")
                }
            } else {
                Section {
                    Text("Zones need your maximum heart rate. Add your date of birth in Apple Health, record a run with heart rate, or set your maximum heart rate in Settings, under Heart rate and treadmill.")
                        .font(.subheadline)
                }
            }

            Section {
                if model.intervalsAccount != nil {
                    Button {
                        importing = true
                        Task {
                            let found = await model.importHeartRateZones()
                            importMessage = found ? String(localized: "Imported your zones.")
                                                  : String(localized: "No running zones on Intervals.icu yet. Set them on your watch or on Garmin Connect, let them sync, then try again.")
                            importing = false
                        }
                    } label: {
                        HStack {
                            Label("Import from your watch", systemImage: "arrow.down.circle")
                            Spacer()
                            if importing { ProgressView() }
                        }
                    }
                    .disabled(importing)
                } else {
                    Text("Connect Intervals.icu in Settings to bring in the zones from your Garmin, COROS, Polar or Suunto watch. They stay up to date on their own after that.")
                        .font(.subheadline).foregroundStyle(Theme.secondaryInk)
                }
                if model.storedHeartRateZones != nil {
                    Button("Use automatic zones instead") { model.setHeartRateZones(nil) }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let importMessage { Text(importMessage) }
                    Text("Apple Watch doesn't share its zones with other apps, so with Apple Watch, zones are worked out automatically from your runs unless you set your own.")
                }
            }
        }
        .navigationTitle("Heart-rate zones")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sourceText(_ source: HeartRateZones.Source) -> String {
        switch source {
        case .imported: String(localized: "From your watch, through Intervals.icu")
        case .custom: String(localized: "Your own zones")
        case .estimated: String(localized: "Automatic, from your runs")
        }
    }

    /// How the automatic maximum was found: "Your maximum is 187 bpm, the highest your heart reached in the past year
    /// (Long run, Oct 24). Zones update as you run."
    private var basisText: String? {
        if model.maxHeartRateIsSet, let bpm = model.estimatedMaxHeartRate {
            return String(localized: "Based on the maximum of \(Int(bpm.rounded())) bpm you set. Zones are 60, 70, 80 and 90% of it.")
        }
        guard let basis = model.automaticMaxHeartRate else { return nil }
        let bpm = Int(basis.bpm.rounded())
        if let run = basis.run {
            let name = model.workout(for: run)?.name ?? String(localized: "a run")
            return String(localized: "Your maximum is \(bpm) bpm, the highest your heart reached in the past year (\(name), \(run.date.formatted(.dateTime.month(.abbreviated).day()))). Zones are 60, 70, 80 and 90% of it, and update as you run.")
        }
        return String(localized: "Your maximum is about \(bpm) bpm, worked out from your age until a hard run shows a higher one. Zones are 60, 70, 80 and 90% of it, and update as you run.")
    }

    /// Edits a limit, keeping the zones in order; the result is the athlete's own.
    private func limitBinding(_ index: Int, _ zones: HeartRateZones) -> Binding<Double> {
        Binding(get: { zones.upperLimits[index] }, set: { value in
            var edited = zones
            edited.upperLimits[index] = value.rounded()
            edited.source = .custom
            if edited.isValid { model.setHeartRateZones(edited) }
        })
    }

    private func maxBinding(_ zones: HeartRateZones) -> Binding<Double> {
        Binding(get: { zones.maxHeartRate }, set: { value in
            var edited = zones
            edited.maxHeartRate = value.rounded()
            edited.source = .custom
            if edited.isValid { model.setHeartRateZones(edited) }
        })
    }
}

private struct MaxHeartRateRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let estimate = model.estimatedMaxHeartRate
        Stepper {
            LabeledContent("Max heart rate") {
                Text(estimate.map { "\(Int($0.rounded())) bpm\(model.maxHeartRateIsSet ? "" : String(localized: " (automatic)"))" }
                     ?? String(localized: "Not known yet"))
            }
        } onIncrement: {
            model.setMaxHeartRate(min((estimate ?? 180).rounded() + 1, 230))
        } onDecrement: {
            model.setMaxHeartRate(max((estimate ?? 180).rounded() - 1, 120))
        }
        if model.maxHeartRateIsSet {
            Button("Use automatic instead") { model.setMaxHeartRate(nil) }
                .font(.subheadline)
        }
    }
}

/// Change run days or long-run day; the remaining plan is re-planned.
private struct AvailabilityEditor: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var runDays: Set<Weekday> = []
    @State private var longRunDay: Weekday = .sunday
    @State private var updating: PlanChangeRequest?

    var body: some View {
        Form {
            Section {
                WeekdayChips(selection: $runDays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .onChange(of: runDays) { _, days in
                        if !days.contains(longRunDay), let fallback = days.sorted().last { longRunDay = fallback }
                    }
            } header: {
                Text("Run days")
            } footer: {
                let recommended = PlanRules.recommendedRunDays(plan.inputs.goal, goalTimeSeconds: plan.inputs.goalTimeSeconds)
                if runDays.count >= 2 && runDays.count < recommended {
                    Text("Your goal usually needs at least \(recommended) runs a week. With \(runDays.count), it's unlikely to be realistic.")
                        .foregroundStyle(Theme.amber)
                } else {
                    Text("Pick at least 2. Workouts from today onwards are re-planned onto these days.")
                }
            }
            Section("Long run day") {
                Picker("Long run day", selection: $longRunDay) {
                    ForEach(runDays.sorted(), id: \.self) { Text($0.fullName).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Training days")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Update plan") {
                    updating = .availability(runDays: runDays, longRunDay: longRunDay)
                }
                .disabled(runDays.count < 2 || !runDays.contains(longRunDay)
                          || (runDays == plan.inputs.runDays && longRunDay == plan.inputs.longRunDay))
            }
        }
        .onAppear {
            guard updating == nil else { return }
            runDays = plan.inputs.runDays
            longRunDay = plan.inputs.longRunDay
        }
        .fullScreenCover(item: $updating) { request in
            PlanUpdateView(request: request) {
                updating = nil
                dismiss()
            }
        }
    }
}

/// Plain-English summary of the training rules (the full version is docs/PLAN-RULES.md).
private struct PlanRulesSummary: View {
    var body: some View {
        List {
            rule("Paces from your fitness", "Your paces come from a recent race (or a careful estimate), using published exercise-science equations. A goal time never makes sessions harder.")
            rule("Gradual build", "Weekly distance grows by at most about 10% at a time, with an easier week every three or four weeks.")
            rule("Hard and easy", "Hard sessions and long runs are never on back-to-back days, and at most a fifth of your running is fast.")
            rule("Taper", "Distance drops in the last one to three weeks so you arrive at the start line fresh.")
            rule("Adapts to real life", "Miss runs and the plan restarts from what you actually did, never \"catching up\". Faster or slower sessions nudge your paces a little at a time.")
        }
        .navigationTitle("How plans are built")
    }

    private func rule(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryInk)
        }
        .padding(.vertical, 4)
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// The voice that talks you through guided runs, and how fast it speaks.
private struct RunCoachVoiceSection: View {
    @AppStorage(VoiceCoach.voiceKey) private var voiceID = ""
    @AppStorage(VoiceCoach.speedKey) private var speed = VoiceCoach.Speed.normal.rawValue

    var body: some View {
        Section {
            NavigationLink {
                VoicePicker()
            } label: {
                // Reads voiceID so the row updates when a new voice is picked.
                LabeledContent("Voice", value: voiceID.isEmpty ? (VoiceCoach.voice?.name ?? String(localized: "Default"))
                                                               : (VoiceCoach.voice?.name ?? String(localized: "Default")))
            }
            Picker("Speed", selection: $speed) {
                ForEach(VoiceCoach.Speed.allCases) { Text($0.name).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Run coach")
        } footer: {
            Text("The voice that talks you through runs on your phone.")
        }
    }
}

/// Every voice on the phone for its language, best first. Tap one to hear it and use it.
private struct VoicePicker: View {
    @AppStorage(VoiceCoach.voiceKey) private var voiceID = ""
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        let voices = VoiceCoach.availableVoices
        let current = VoiceCoach.voice?.identifier
        List {
            if !VoiceCoach.hasNaturalVoice {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Get a natural-sounding voice, free", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Apple's Premium voices sound much more human than these. On your iPhone, open Settings › Accessibility › Spoken Content › Voices › English, pick a voice marked Premium (like Ava, Zoe or Evan) and download it. Come back here and TrackStar uses it.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                ForEach(voices, id: \.identifier) { voice in
                    Button {
                        voiceID = voice.identifier
                        preview()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name).foregroundStyle(Theme.ink)
                                Text(detail(voice)).font(.caption).foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                            if voice.identifier == current {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            } footer: {
                Text("Tap a voice to hear it. For more natural voices, download an Enhanced or Premium one in your iPhone's Settings › Accessibility › Spoken Content › Voices, then pick it here.")
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// "English (UK) · Premium"
    private func detail(_ voice: AVSpeechSynthesisVoice) -> String {
        let region = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        switch voice.quality {
        case .premium: return String(localized: "\(region) · Premium")
        case .enhanced: return String(localized: "\(region) · Enhanced")
        default: return region
        }
    }

    private func preview() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(VoiceCoach.utterance(String(localized: "Run for 5 minutes, nice and easy. Then pick it up to threshold pace.")))
    }
}
