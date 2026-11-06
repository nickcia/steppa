import SwiftUI
import PlanEngine

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEnd = false

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
                    Section("Current plan") {
                        LabeledContent("Race", value: plan.inputs.goal.name)
                        LabeledContent("Date", value: plan.inputs.raceDate.formatted(.dateTime.day().month().year()))
                        LabeledContent("Run days", value: plan.inputs.runDays.sorted().map(\.mediumName).joined(separator: ", "))
                        LabeledContent("Long run", value: plan.inputs.longRunDay.fullName)
                        Button("End this plan", role: .destructive) { confirmEnd = true }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Text("Free and open source under the MIT licence. No accounts, no servers, no tracking: your data stays on this device and in your own iCloud.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
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
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
