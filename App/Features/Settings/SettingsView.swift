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

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: Binding(get: { model.units }, set: { model.setUnits($0) })) {
                        ForEach(UnitSystem.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let plan = model.plan {
                    Section("Training") {
                        NavigationLink {
                            AvailabilityEditor(plan: plan)
                        } label: {
                            LabeledContent("Run days", value: plan.inputs.runDays.sorted().map(\.mediumName).joined(separator: ", "))
                        }
                        LabeledContent("Long run", value: plan.inputs.longRunDay.fullName)
                        LabeledContent("Goal race", value: "\(plan.inputs.goal.name), \(plan.inputs.raceDate.formatted(.dateTime.day().month()))")
                        Button("End this plan", role: .destructive) { confirmEnd = true }
                    }
                }

                Section {
                    if model.healthConnected {
                        LabeledContent("Apple Health", value: String(localized: "\(model.healthRuns.count) runs found"))
                        Button("Refresh runs") { Task { await model.refreshHealth() } }
                    } else {
                        Button {
                            Task { await model.connectHealth() }
                        } label: {
                            Label("Connect Apple Health", systemImage: "heart.text.square")
                        }
                        .disabled(!model.healthAvailable)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Runs from Apple Watch, Garmin, Coros and other apps that save to Health tick off your workouts automatically. Manage access in the Health app under Sharing › Apps.")
                }

                Section {
                    Toggle("Send the next 7 days automatically",
                           isOn: Binding(get: { model.watchAutoSync }, set: { on in Task { await model.setWatchAutoSync(on) } }))
                    if let plan = model.plan {
                        Button("Send this week now") {
                            Task {
                                await model.sendToWatch(plan.workouts.filter {
                                    $0.date >= model.today && model.today.days(until: $0.date) < 7
                                })
                            }
                        }
                    }
                } header: {
                    Text("Apple Watch")
                } footer: {
                    Text("Workouts appear in the Workout app on your watch with each step and pace alerts, ready to start.")
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
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Text("Free and open source under the MIT licence. No accounts, no servers, no tracking.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                    NavigationLink("How plans are built") { PlanRulesSummary() }
                }

                Section("Health and safety") {
                    DisclaimerText()
                }
            }
            .navigationTitle("Settings")
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

/// Change run days or long-run day; the remaining plan is re-planned.
private struct AvailabilityEditor: View {
    let plan: TrainingPlan
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var runDays: Set<Weekday> = []
    @State private var longRunDay: Weekday = .sunday

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
                Text("Pick at least 2. Workouts from today onwards are re-planned onto these days.")
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
                    model.changeAvailability(runDays: runDays, longRunDay: longRunDay)
                    dismiss()
                }
                .disabled(runDays.count < 2 || !runDays.contains(longRunDay)
                          || (runDays == plan.inputs.runDays && longRunDay == plan.inputs.longRunDay))
            }
        }
        .onAppear {
            runDays = plan.inputs.runDays
            longRunDay = plan.inputs.longRunDay
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
